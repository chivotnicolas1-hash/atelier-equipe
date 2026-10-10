-- Mise à jour 06 : appliquer après 05. Aucune donnée historique supprimée.
begin;
alter table public.workshop_staff add column if not exists role text not null default 'employee' check(role in ('employee','moderator'));
alter table public.workshop_staff add column if not exists active boolean not null default true;
alter table public.workshop_staff drop constraint if exists workshop_staff_id_check;
alter table public.workshop_staff add constraint workshop_staff_id_check check(id ~ '^[0-9]{2,9}$');
-- Retirer le poste clim sans effacer les journées ni les horaires.
update public.workshop_days set station=null,confirmed=null where station='clim';
alter table public.workshop_days drop constraint if exists workshop_days_station_check;
alter table public.workshop_days add constraint workshop_days_station_check check(station in ('pneus1','attelage','vidange1','vidange2','mecalegere','mecalourde','distribution','pneus2','geometrie','elec','organisation','devis'));
create or replace function workshop_private.actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_staff text; v_admin boolean; v_role text;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501'; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','') <> 'email' or not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) m where m->>'method'='password') then
  raise exception 'Connecte-toi avec les identifiants fournis par ton administrateur.' using errcode='42501';
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Une adresse e-mail vérifiée est nécessaire.' using errcode='42501'; end if;
 v_admin := v_email='nchivot@norauto.fr';
 select id,role into v_staff,v_role from public.workshop_staff where email=v_email and active;
 if not v_admin and v_staff is null then
  raise exception 'Cette adresse n’est pas autorisée. Demande à l’administrateur de renseigner ton adresse e-mail dans Équipe.' using errcode='42501';
 end if;
 return jsonb_build_object('admin',v_admin,'role',case when v_admin then 'admin' else coalesce(v_role,'employee') end,'manager',v_admin or coalesce(v_role='moderator',false),'self',v_staff,'user',v_email);
end $$;
revoke all on function workshop_private.actor() from public, anon, authenticated;


create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s where s.active;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date and exists(select 1 from public.workshop_staff s where s.id=d.staff_id and s.active);
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where exists(select 1 from public.workshop_staff s where s.id=t.staff_id and s.active) and ((a->>'manager')::boolean or t.staff_id=a->>'self');
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date);
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

create or replace function public.workshop_mutate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; act text; v_id text; v_email text; v_task public.workshop_tasks%rowtype; v_count integer; v_done boolean; v_manager boolean; person public.workshop_staff%rowtype; current_day public.workshop_days%rowtype;
begin
 a:=workshop_private.actor();v_admin:=(a->>'admin')::boolean;v_manager:=(a->>'manager')::boolean;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Action invalide.'; end if;
 act:=p->>'action';v_id:=p->>'id';
 if act in ('staff','createStaff','deleteStaff') and not v_admin then
  raise exception 'Action réservée à l’administration.' using errcode='42501';
 end if;
 if act in ('day','task','editTask','deleteTask') and not v_manager then
  raise exception 'Action réservée à l’administration ou aux modérateurs.' using errcode='42501';
 end if;
 -- Verrou partagé : aucune affectation/import ne peut viser une fiche retirée entre deux contrôles.
 if act in ('staff','createStaff','deleteStaff') then
  lock table public.workshop_staff in share row exclusive mode;
 else
  lock table public.workshop_staff in share mode;
 end if;
 if act in ('staff','deleteStaff','day') then
  select * into person from public.workshop_staff where id=v_id and active for share;
  if not found then raise exception 'Collaborateur introuvable.';end if;
 end if;
 if act in ('task','editTask') and not exists(select 1 from public.workshop_staff where id=p->>'staffId' and active) then
  raise exception 'Choisis un collaborateur actif.';
 end if;
 if act='createStaff' then
  if p->>'role' is not null and p->>'role' not in ('employee','moderator') then raise exception 'Rôle invalide.';end if;
  select lpad((coalesce(max(id::integer),0)+1)::text,greatest(2,length((coalesce(max(id::integer),0)+1)::text)),'0') into v_id from public.workshop_staff;
  insert into public.workshop_staff(id,name,email,team,role)
  values(v_id,trim(p->>'name'),nullif(lower(trim(p->>'email')),''),nullif(p->>'team',''),coalesce(p->>'role','employee'));
 elsif act='deleteStaff' then
  if person.email='nchivot@norauto.fr' or v_id=a->>'self' then raise exception 'Ton compte administrateur ne peut pas être supprimé.';end if;
  update public.workshop_staff set active=false,role='employee' where id=v_id;
 elsif act='deleteTask' then
  delete from public.workshop_tasks where id=v_id::uuid;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Tâche introuvable.';end if;
 elsif act='staff' then
  if nullif(trim(p->>'name'),'') is null then raise exception 'Renseigne un nom.'; end if;
  v_email:=nullif(lower(trim(p->>'email')),'');
  if person.email='nchivot@norauto.fr' and v_email is distinct from person.email then raise exception 'L’adresse du compte administrateur doit être conservée.';end if;
  if p ? 'role' and (p->>'role' is null or p->>'role' not in ('employee','moderator')) then raise exception 'Rôle invalide.';end if;
  update public.workshop_staff set role=case when p ? 'role' then p->>'role' else role end,name=trim(p->>'name'),email=v_email,team=case when p ? 'team' then nullif(p->>'team','') else team end where id=v_id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Collaborateur introuvable.';end if;
 elsif act='day' then
  lock table public.workshop_days in row exclusive mode;
  if not v_admin then
   select * into current_day from public.workshop_days where date=(p->>'date')::date and staff_id=v_id for update;
   if not found or current_day.presence<>'present' or p->>'presence' is distinct from current_day.presence then
    raise exception 'Le modérateur peut déplacer uniquement les collaborateurs prévus présents.' using errcode='42501';
   end if;
  end if;
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
  select * into v_task from public.workshop_tasks where id=v_id::uuid and exists(select 1 from public.workshop_staff s where s.id=staff_id and s.active) for update;
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
 when check_violation then raise exception 'Vérifie les informations saisies : nom, e-mail, équipe, présence, poste ou tâche invalide.';
 when foreign_key_violation then raise exception 'Collaborateur introuvable.';
 when not_null_violation then raise exception 'Il manque une information obligatoire.';
end $$;
revoke all on function public.workshop_mutate(jsonb) from public, anon, authenticated;
grant execute on function public.workshop_mutate(jsonb) to authenticated;


create or replace function public.workshop_import_schedule(p_rows jsonb,p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r jsonb; slot jsonb; v_slots jsonb; v_staff text; v_date date; v_presence text;
 v_previous_end text; existing public.workshop_days%rowtype; saved integer:=0; skipped integer:=0;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Import réservé à l’administrateur.' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Liste de journées invalide.';end if;
 if jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>1200 then raise exception 'Import limité à 1200 journées.';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) x group by x->>'staff_id',x->>'date' having count(*)>1) then raise exception 'Doublons de personne et date dans cet import.';end if;
 -- L’import et les changements manuels ne peuvent pas se superposer.
 lock table public.workshop_staff in share mode;
 lock table public.workshop_days in share row exclusive mode;
 for r in select value from jsonb_array_elements(p_rows) loop
  if coalesce(r->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Date ISO attendue.';end if;
  v_staff:=r->>'staff_id';v_date:=(r->>'date')::date;v_presence:=r->>'presence';v_slots:=r->'slots';
  if v_date is null or not exists(select 1 from public.workshop_staff where id=v_staff and active) then raise exception 'Date ou collaborateur invalide.';end if;
  if v_presence is null or v_presence not in ('present','rest','absent','leave') then raise exception 'Vérifie le statut de chaque journée.';end if;
  if v_slots is null or jsonb_typeof(v_slots)<>'array' then raise exception 'Créneaux invalides.';end if;
  if jsonb_array_length(v_slots)>4 or (v_presence='present' and jsonb_array_length(v_slots)=0) or (v_presence<>'present' and jsonb_array_length(v_slots)<>0) then raise exception 'Créneaux incompatibles avec le statut.';end if;
  v_previous_end:=null;
  for slot in select value from jsonb_array_elements(v_slots) loop
   if coalesce(slot->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(slot->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Horaire invalide : utiliser HH:MM.';end if;
   if (slot->>'start') >= (slot->>'end') or (v_previous_end is not null and (slot->>'start')<v_previous_end) then raise exception 'Les créneaux doivent être ordonnés, sans chevauchement et dans la même journée.';end if;
   v_previous_end:=slot->>'end';
  end loop;
  select * into existing from public.workshop_days where date=v_date and staff_id=v_staff;
  if found then
   if existing.confirmed is not null or not coalesce(p_replace,false) then skipped:=skipped+1;continue;end if;
   if existing.presence=v_presence and existing.slots=v_slots then skipped:=skipped+1;continue;end if;
   update public.workshop_days set presence=v_presence,slots=v_slots,
     station=case when v_presence='present' then station else null end,confirmed=null
    where date=v_date and staff_id=v_staff;
  else
   insert into public.workshop_days(date,staff_id,presence,station,confirmed,slots) values(v_date,v_staff,v_presence,null,null,v_slots);
  end if;
  saved:=saved+1;
 end loop;
 return jsonb_build_object('saved',saved,'skipped',skipped);
end $$;
revoke all on function public.workshop_import_schedule(jsonb,boolean) from public,anon,authenticated;
grant execute on function public.workshop_import_schedule(jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
