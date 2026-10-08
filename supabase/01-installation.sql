-- Atelier Équipe — installation sur le nouveau projet Supabase.
-- Administrateur : nchivot@norauto.fr. Exécuter tout le fichier dans SQL Editor.
-- Relançable : les collaborateurs et les données existantes sont conservés.
begin;
create schema if not exists workshop_private;
revoke all on schema workshop_private from public, anon, authenticated;

create table if not exists public.workshop_staff (
 id text primary key check (id ~ '^[0-9]{2}$'),
 name text not null check (length(trim(name)) between 1 and 100),
 email text unique check (email is null or (email = lower(trim(email)) and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'))
);
create table if not exists public.workshop_days (
 date date not null,
 staff_id text not null references public.workshop_staff(id),
 presence text not null default 'unknown' check (presence in ('unknown','present','absent','leave')),
 station text check (station in ('pneus1','attelage','vidange1','vidange2','mecalegere','mecalourde','distribution','pneus2','geometrie','elec','clim','organisation','devis')),
 confirmed timestamptz,
 primary key(date,staff_id),
 check(station is null or presence='present'),
 check(confirmed is null or (presence='present' and station is not null))
);
create table if not exists public.workshop_tasks (
 id uuid primary key default gen_random_uuid(),
 title text not null check (length(trim(title)) between 1 and 200),
 details text not null default '' check(length(details)<=4000),
 staff_id text not null references public.workshop_staff(id),
 due date not null,
 priority text not null check (priority in ('normal','high','urgent')),
 done integer not null default 0 check(done in (0,1)),
 completed_at timestamptz,
 created_at timestamptz not null default now(),
 check ((done=0 and completed_at is null) or (done=1 and completed_at is not null))
);
create index if not exists workshop_tasks_staff_due on public.workshop_tasks(staff_id,due);
alter table public.workshop_staff enable row level security;
alter table public.workshop_days enable row level security;
alter table public.workshop_tasks enable row level security;
-- Aucune lecture/écriture directe depuis le navigateur : les fonctions contrôlent chaque action.
revoke all on public.workshop_staff, public.workshop_days, public.workshop_tasks from public, anon, authenticated;
insert into public.workshop_staff(id,name)
select lpad(i::text,2,'0'), 'Collaborateur '||i from generate_series(1,13) i
on conflict(id) do nothing;

create or replace function workshop_private.actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_staff text; v_admin boolean;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501'; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','') <> 'email' or not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) m where m->>'method'='password') then
  raise exception 'Connecte-toi avec les identifiants fournis par ton administrateur.' using errcode='42501';
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Une adresse e-mail vérifiée est nécessaire.' using errcode='42501'; end if;
 v_admin := v_email='nchivot@norauto.fr';
 select id into v_staff from public.workshop_staff where email=v_email;
 if not v_admin and v_staff is null then
  raise exception 'Cette adresse n’est pas autorisée. Demande à l’administrateur de renseigner ton adresse e-mail dans Équipe.' using errcode='42501';
 end if;
 return jsonb_build_object('admin',v_admin,'self',v_staff,'user',v_email);
end $$;
revoke all on function workshop_private.actor() from public, anon, authenticated;

create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s) else jsonb_build_object('id',s.id,'name',s.name) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where v_admin or t.staff_id=a->>'self';
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date);
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

create or replace function public.workshop_mutate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; act text; v_id text; v_email text; v_task public.workshop_tasks%rowtype; v_count integer; v_done boolean;
begin
 a:=workshop_private.actor();v_admin:=(a->>'admin')::boolean;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Action invalide.'; end if;
 act:=p->>'action';v_id:=p->>'id';
 if act in ('staff','day','task','editTask') and not v_admin then
  raise exception 'Action réservée à l’administration.' using errcode='42501';
 end if;
 if act='staff' then
  if nullif(trim(p->>'name'),'') is null then raise exception 'Renseigne un nom.'; end if;
  v_email:=nullif(lower(trim(p->>'email')),'');
  update public.workshop_staff set name=trim(p->>'name'),email=v_email where id=v_id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Collaborateur introuvable.';end if;
 elsif act='day' then
  insert into public.workshop_days as existing(date,staff_id,presence,station,confirmed)
  values((p->>'date')::date,v_id,p->>'presence',nullif(p->>'station',''),null)
  on conflict(date,staff_id) do update set
    presence=excluded.presence,station=excluded.station,
    confirmed=case when existing.presence=excluded.presence and existing.station is not distinct from excluded.station then existing.confirmed else null end;
 elsif act='task' then
  insert into public.workshop_tasks(title,details,staff_id,due,priority)
  values(trim(p->>'title'),coalesce(p->>'details',''),p->>'staffId',(p->>'due')::date,p->>'priority');
 elsif act='editTask' then
  update public.workshop_tasks set title=trim(p->>'title'),details=coalesce(p->>'details',''),staff_id=p->>'staffId',due=(p->>'due')::date,priority=p->>'priority' where id=v_id::uuid;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Tâche introuvable.';end if;
 elsif act='complete' then
  if jsonb_typeof(p->'done') is distinct from 'boolean' then raise exception 'Statut invalide.';end if;
  select * into v_task from public.workshop_tasks where id=v_id::uuid for update;
  if not found then raise exception 'Tâche introuvable.'; end if;
  if not v_admin and v_task.staff_id is distinct from a->>'self' then
   raise exception 'Cette tâche n’est pas la tienne.' using errcode='42501';
  end if;
  v_done:=(p->>'done')::boolean;
  update public.workshop_tasks set done=case when v_done then 1 else 0 end,
    completed_at=case when v_done then coalesce(completed_at,now()) else null end where id=v_task.id;
 elsif act='confirm' then
  if a->>'self' is null then raise exception 'Associe ton adresse e-mail à ta fiche dans Équipe.';end if;
  update public.workshop_days set confirmed=coalesce(confirmed,now())
   where date=(now() at time zone 'Europe/Paris')::date and staff_id=a->>'self' and presence='present' and station is not null;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Aucun poste ne t’est affecté aujourd’hui.';end if;
 else raise exception 'Action inconnue.';
 end if;
 return jsonb_build_object('ok',true);
exception
 when unique_violation then raise exception 'Cette adresse e-mail est déjà utilisée par un autre collaborateur.';
 when check_violation then raise exception 'Vérifie les informations saisies : nom, e-mail, présence, poste ou tâche invalide.';
 when foreign_key_violation then raise exception 'Collaborateur introuvable.';
 when not_null_violation then raise exception 'Il manque une information obligatoire.';
end $$;
revoke all on function public.workshop_mutate(jsonb) from public, anon, authenticated;
grant execute on function public.workshop_mutate(jsonb) to authenticated;

-- Fonction réservée au serveur de création des comptes, jamais au navigateur.
create or replace function public.workshop_account_id(p_staff_id text)
returns uuid language sql security definer set search_path = '' as $$
 select u.id from auth.users u join public.workshop_staff s on s.email=lower(u.email) where s.id=p_staff_id limit 1;
$$;
revoke all on function public.workshop_account_id(text) from public,anon,authenticated;
grant execute on function public.workshop_account_id(text) to service_role;

notify pgrst, 'reload schema';
commit;
