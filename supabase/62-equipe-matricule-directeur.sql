-- MAJ62 après MAJ61. Réexécutable. Aucun mot de passe stocké ici.
begin;
alter table public.workshop_staff drop constraint if exists workshop_staff_role_check;
alter table public.workshop_staff add constraint workshop_staff_role_check check(role in ('employee','moderator','guest','director'));
-- Étendre seulement la validation des rôles des anciennes fonctions.
do $$declare r record;b text;begin
 for r in select p.oid from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'workshop_mutate%' loop
 b:=pg_get_functiondef(r.oid);if position('not in (''employee'',''moderator'',''guest'')' in b)>0 then execute replace(b,'not in (''employee'',''moderator'',''guest'')','not in (''employee'',''moderator'',''guest'',''director'')');end if;end loop;end $$;
create table if not exists public.workshop_staff_logins(staff_id text primary key references public.workshop_staff(id) on delete cascade,matricule text not null unique check(matricule ~ '^[A-Z0-9_-]{1,32}$'));
alter table public.workshop_staff_logins enable row level security;
revoke all on public.workshop_staff_logins from public,anon,authenticated;
do $$begin
 if to_regprocedure('public.workshop_mutate_before62(jsonb)') is null then alter function public.workshop_mutate(jsonb) rename to workshop_mutate_before62;end if;
 if to_regprocedure('public.workshop_load_before62(date)') is null then alter function public.workshop_load(date) rename to workshop_load_before62;end if;
end $$;
create or replace function public.workshop_mutate(p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;sid text;m text;begin
 if p->>'action' in ('staff','createStaff') then
  a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Action réservée à l’administration.' using errcode='42501';end if;
  lock table public.workshop_staff in share row exclusive mode;m:=nullif(upper(trim(p->>'matricule')),'');
  if p ? 'matricule' and m is not null and (m !~ '^[A-Z0-9_-]{1,32}$' or nullif(trim(p->>'email'),'') is null) then raise exception 'Matricule invalide ou adresse e-mail manquante.';end if;
  r:=public.workshop_mutate_before62(p);
  if p ? 'matricule' then
   if p->>'action'='staff' then sid:=p->>'id';else select id into sid from public.workshop_staff where email=lower(trim(p->>'email')) and active;end if;
   if m is null then delete from public.workshop_staff_logins where staff_id=sid;
   else
    if exists(select 1 from public.workshop_staff_logins where matricule=m and staff_id<>sid) then raise exception 'Ce matricule est déjà utilisé.';end if;
    insert into public.workshop_staff_logins values(sid,m) on conflict(staff_id) do update set matricule=excluded.matricule;
   end if;
  end if;return r;
 end if;return public.workshop_mutate_before62(p);end $$;
create or replace function public.workshop_load(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin r:=public.workshop_load_before62(p_date);
 if coalesce((r->>'admin')::boolean,false) then r:=jsonb_set(r,'{staff}',(select coalesce(jsonb_agg(s.value||jsonb_build_object('matricule',l.matricule) order by s.ord),'[]') from jsonb_array_elements(r->'staff') with ordinality s(value,ord) left join public.workshop_staff_logins l on l.staff_id=s.value->>'id'));end if;return r;end $$;
-- Fonction automatique, sans altération des signatures dessinées ni des PDF passés.
create or replace function workshop_private.sync_staff_job() returns trigger language plpgsql security definer set search_path='' as $$
begin if new.role='employee' and new.email is distinct from 'nchivot@norauto.fr' then
 update public.workshop_signatures sig set job_title=coalesce(new.team,''),version=sig.version+1,updated_at=now() from auth.users u where u.id=sig.user_id and lower(u.email)=new.email and sig.job_title is distinct from coalesce(new.team,'');end if;return new;end $$;
drop trigger if exists staff_job62 on public.workshop_staff;
create trigger staff_job62 after insert or update of team,role,email on public.workshop_staff for each row execute function workshop_private.sync_staff_job();
create or replace function workshop_private.enforce_staff_job() returns trigger language plpgsql security definer set search_path='' as $$
declare s public.workshop_staff%rowtype;begin select st.* into s from public.workshop_staff st join auth.users u on lower(u.email)=st.email where u.id=new.user_id and st.active;
 if found and s.role='employee' and s.email is distinct from 'nchivot@norauto.fr' then new.job_title:=coalesce(s.team,'');end if;return new;end $$;
drop trigger if exists signature_job62 on public.workshop_signatures;
create trigger signature_job62 before insert or update on public.workshop_signatures for each row execute function workshop_private.enforce_staff_job();
update public.workshop_signatures sig set job_title=coalesce(st.team,''),version=sig.version+1,updated_at=now() from public.workshop_staff st join auth.users u on lower(u.email)=st.email where sig.user_id=u.id and st.role='employee' and st.email is distinct from 'nchivot@norauto.fr' and sig.job_title is distinct from coalesce(st.team,'');
create or replace function public.workshop_staff_save(p jsonb,p_job text,p_birth date,p_job_version integer,p_birth_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;s public.workshop_staff%rowtype;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p->>'action' is distinct from 'staff' or p->>'id' is null then raise exception 'Fiche existante requise.';end if;
 perform public.workshop_mutate(p);select * into s from public.workshop_staff where id=p->>'id';
 if s.role<>'employee' or s.email='nchivot@norauto.fr' then
  if p_job_version>=0 then perform public.workshop_admin_job(p->>'id',p_job,p_job_version);
  elsif p_job_version is distinct from -1 or exists(select 1 from auth.users u where lower(u.email)=s.email) then raise exception 'Recharge la fiche pour modifier la fonction.';end if;
 end if;perform public.workshop_admin_birthday_save(p->>'id',p_birth,p_birth_version);end $$;
-- Résolution accessible seulement au serveur, après contrôle du format et avec
-- limite persistante par matricule. Le mot de passe est vérifié par Supabase Auth.
create table if not exists public.workshop_login_limits(key text primary key,started_at timestamptz not null,attempts integer not null);
alter table public.workshop_login_limits enable row level security;
revoke all on public.workshop_login_limits from public,anon,authenticated;
create or replace function public.workshop_login_lookup(p_matricule text) returns jsonb language plpgsql security definer set search_path='' as $$
declare k text;m text;e text;n integer;begin
 m:=upper(trim(p_matricule));if m is null or m !~ '^[A-Z0-9_-]{1,32}$' then return jsonb_build_object('email',null);end if;
 k:=md5(m);perform pg_advisory_xact_lock(hashtextextended('login62:'||k,0));delete from public.workshop_login_limits where started_at<now()-interval '1 day';
 insert into public.workshop_login_limits values(k,now(),1) on conflict(key) do update set attempts=case when workshop_login_limits.started_at<now()-interval '15 minutes' then 1 else workshop_login_limits.attempts+1 end,started_at=case when workshop_login_limits.started_at<now()-interval '15 minutes' then now() else workshop_login_limits.started_at end returning attempts into n;
 if n>10 then return jsonb_build_object('limited',true);end if;
 select s.email into e from public.workshop_staff_logins l join public.workshop_staff s on s.id=l.staff_id join auth.users u on lower(u.email)=s.email where l.matricule=m and s.active and u.email_confirmed_at is not null;return jsonb_build_object('email',e);end $$;
revoke all on function public.workshop_mutate_before62(jsonb),public.workshop_load_before62(date),workshop_private.sync_staff_job(),workshop_private.enforce_staff_job(),public.workshop_login_lookup(text) from public,anon,authenticated;
grant execute on function public.workshop_login_lookup(text) to service_role;
revoke all on function public.workshop_mutate(jsonb),public.workshop_load(date),public.workshop_staff_save(jsonb,text,date,integer,integer) from public,anon;
grant execute on function public.workshop_mutate(jsonb),public.workshop_load(date),public.workshop_staff_save(jsonb,text,date,integer,integer) to authenticated;
notify pgrst,'reload schema';commit;
