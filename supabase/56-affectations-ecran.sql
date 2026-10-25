-- MAJ56 : après MAJ55. Réexécutable.
begin;
create table if not exists public.workshop_staff_birthdays(staff_id text primary key references public.workshop_staff(id),birth_date date,version integer not null default 1,updated_at timestamptz not null default now());
alter table public.workshop_staff_birthdays enable row level security;
revoke all on public.workshop_staff_birthdays from public,anon,authenticated;
insert into public.workshop_staff_birthdays(staff_id,birth_date) select s.id,b.birth_date from public.workshop_birthdays b join auth.users u on u.id=b.user_id join public.workshop_staff s on s.email=lower(u.email) on conflict do nothing;
delete from public.workshop_birthdays b using auth.users u,public.workshop_staff s where u.id=b.user_id and s.email=lower(u.email);
create or replace function public.workshop_birthday_get() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;b date;begin a:=workshop_private.actor();select birth_date into b from public.workshop_staff_birthdays where staff_id=a->>'self';return jsonb_build_object('birthday_today',coalesce(to_char(b,'MM-DD')=to_char(now() at time zone 'Europe/Paris','MM-DD'),false));end $$;
-- Ancien formulaire rendu inopérant, y compris sur un client non actualisé.
create or replace function public.workshop_birthday_save(p_date date) returns void language plpgsql security definer set search_path='' as $$ begin raise exception 'La date de naissance se renseigne désormais par l’administrateur dans Équipes.' using errcode='42501';end $$;
revoke all on function public.workshop_birthday_save(date) from public,anon,authenticated;
create or replace function public.workshop_admin_birthday(p_staff text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_staff_birthdays%rowtype;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if not exists(select 1 from public.workshop_staff where id=p_staff and active and role<>'guest') then raise exception 'Collaborateur invalide.';end if;
 select * into r from public.workshop_staff_birthdays where staff_id=p_staff;return jsonb_build_object('birth_date',r.birth_date,'version',coalesce(r.version,0));end $$;
create or replace function public.workshop_admin_birthday_save(p_staff text,p_date date,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_staff_birthdays%rowtype;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if not exists(select 1 from public.workshop_staff where id=p_staff and active and role<>'guest') or (p_date is not null and (p_date<'1900-01-01' or p_date>(now() at time zone 'Europe/Paris')::date)) then raise exception 'Collaborateur ou date invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('birthday:'||p_staff,0));select * into r from public.workshop_staff_birthdays where staff_id=p_staff for update;
 if coalesce(r.version,0) is distinct from p_version then raise exception 'Date modifiée entre-temps. Ferme et rouvre la fiche.';end if;
 insert into public.workshop_staff_birthdays(staff_id,birth_date) values(p_staff,p_date) on conflict(staff_id) do update set birth_date=excluded.birth_date,version=workshop_staff_birthdays.version+1,updated_at=now();end $$;

create table if not exists public.workshop_screen_settings(id integer primary key check(id=1),title text not null default 'Écran d’atelier',message text not null default '',show_objective boolean not null default true,show_roster boolean not null default true,show_birthdays boolean not null default true,compact boolean not null default true,version integer not null default 1);
insert into public.workshop_screen_settings(id) values(1) on conflict do nothing;
alter table public.workshop_screen_settings enable row level security;
revoke all on public.workshop_screen_settings from public,anon,authenticated;
create or replace function public.workshop_screen_info() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;
 return jsonb_build_object('settings',(select to_jsonb(s)-'id' from public.workshop_screen_settings s where id=1),'birthdays',(select coalesce(jsonb_agg(jsonb_build_object('name',s.name,'id',s.id) order by s.name),'[]') from public.workshop_staff_birthdays b join public.workshop_staff s on s.id=b.staff_id where s.active and s.role<>'guest' and to_char(b.birth_date,'MM-DD')=to_char(now() at time zone 'Europe/Paris','MM-DD')));end $$;
create or replace function public.workshop_screen_save(p_settings jsonb,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;v integer;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_settings is null or jsonb_typeof(p_settings)<>'object' or length(trim(coalesce(p_settings->>'title',''))) not between 1 and 80 or length(coalesce(p_settings->>'message',''))>2000 or jsonb_typeof(p_settings->'show_objective') is distinct from 'boolean' or jsonb_typeof(p_settings->'show_roster') is distinct from 'boolean' or jsonb_typeof(p_settings->'show_birthdays') is distinct from 'boolean' or jsonb_typeof(p_settings->'compact') is distinct from 'boolean' then raise exception 'Paramètres d’écran invalides.';end if;
 select version into v from public.workshop_screen_settings where id=1 for update;if v is distinct from p_version then raise exception 'Écran modifié entre-temps. Ferme puis rouvre les paramètres.';end if;
 update public.workshop_screen_settings set title=trim(p_settings->>'title'),message=trim(coalesce(p_settings->>'message','')),show_objective=(p_settings->>'show_objective')::boolean,show_roster=(p_settings->>'show_roster')::boolean,show_birthdays=(p_settings->>'show_birthdays')::boolean,compact=(p_settings->>'compact')::boolean,version=version+1 where id=1;end $$;

-- Toutes les voies d’affectation utilisent la même règle de compétence et de métier.
create or replace function workshop_private.staff_can_work(p_staff text,p_station text) returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from public.workshop_staff s join public.workshop_stations st on st.id=p_station join public.workshop_skills k on k.staff_id=s.id and k.station_id=st.id and k.level='autonomous' where s.id=p_staff and s.active and s.role<>'guest' and st.active and (st.office=(lower(trim(coalesce(s.team,'')))='encadrants')))
$$;
create or replace function workshop_private.assignment_allowed(p_staff text,p_date date,p_station text) returns boolean language sql stable set search_path='' as $$
 select workshop_private.staff_can_work(p_staff,p_station) and exists(select 1 from public.workshop_days d join public.workshop_stations st on st.id=p_station where d.staff_id=p_staff and d.date=p_date and d.presence='present' and (st.office or jsonb_array_length(d.slots)>0) and not exists(select 1 from public.workshop_station_status ss where ss.station_id=st.id and ss.status='broken'))
$$;
create or replace function workshop_private.check_active_station() returns trigger language plpgsql security definer set search_path='' as $$
declare prev_station text;prev_geometry boolean:=false;effective_slots jsonb;office boolean;begin
 effective_slots:=coalesce(new.slots,'[]');
 if tg_op='INSERT' then
  select d.station,d.geometry,case when jsonb_array_length(effective_slots)=0 then d.slots else effective_slots end into prev_station,prev_geometry,effective_slots from public.workshop_days d where d.date=new.date and d.staff_id=new.staff_id;
  effective_slots:=coalesce(effective_slots,new.slots,'[]');
 else prev_station:=old.station;prev_geometry:=old.geometry;end if;
 if new.station is not null and new.station is distinct from prev_station then
  if not workshop_private.staff_can_work(new.staff_id,new.station) then raise exception 'Affectation interdite : compétence Autonome requise et encadrants limités aux espaces de gestion.';end if;
  if exists(select 1 from public.workshop_station_status where station_id=new.station and status='broken') then raise exception 'Pont en panne : nouvelle affectation impossible.';end if;
  select s.office into office from public.workshop_stations s where s.id=new.station and s.active;
  if new.presence<>'present' or (not office and jsonb_array_length(effective_slots)=0) then raise exception 'Présence et horaires nécessaires pour cette affectation.';end if;
 end if;
 if new.geometry and not coalesce(prev_geometry,false) then
  if not workshop_private.staff_can_work(new.staff_id,'geometrie') then raise exception 'Compétence Autonome requise en géométrie ; encadrants non autorisés.';end if;
  if exists(select 1 from public.workshop_station_status where station_id='geometrie' and status='broken') then raise exception 'Pont géométrie en panne.';end if;
  if new.presence<>'present' or jsonb_array_length(effective_slots)=0 then raise exception 'Présence et horaires nécessaires pour la géométrie.';end if;
 end if;return new;end $$;

-- Exception ciblée à la protection historique contre les doubles postes principaux.
create or replace function workshop_private.protect_station_move() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.station is not null and new.station is not null and old.station is distinct from new.station and not (old.station='geometrie' and new.geometry) then raise exception 'Retire d’abord le collaborateur de son poste actuel avant de l’affecter à un autre poste.';end if;
 return new;
end $$;

-- Affectation du jour : géométrie cumulable dans les deux sens, modification atomique.
create or replace function public.workshop_assign(p_date date,p_staff text,p_station text,p_enabled boolean,p_expected_station text,p_expected_geometry boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_days%rowtype;dest text;geo boolean;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;
 if p_date is null or p_date>(now() at time zone 'Europe/Paris')::date or p_station is null or p_enabled is null then raise exception 'Utilise la préparation pour une journée future.';end if;
 lock table public.workshop_days in share row exclusive mode;lock table public.workshop_skills in share mode;lock table public.workshop_station_status in share mode;
 select * into r from public.workshop_days where date=p_date and staff_id=p_staff for update;
 if not found or r.station is distinct from p_expected_station or r.geometry is distinct from p_expected_geometry then raise exception 'Affectation modifiée entre-temps. Actualise.';end if;
 dest:=r.station;geo:=r.geometry;
 if p_enabled then
  if not workshop_private.assignment_allowed(p_staff,p_date,p_station) then raise exception 'Affectation interdite : vérifie compétence Autonome, équipe, présence, horaires et état du pont.';end if;
  if p_station='geometrie' then
   if dest is null then dest:='geometrie';geo:=false;elsif dest<>'geometrie' then geo:=true;end if;
  else
   if dest is not null and dest not in ('geometrie',p_station) then raise exception 'Retire d’abord le poste principal actuel.';end if;
   geo:=geo or dest='geometrie';dest:=p_station;
  end if;
 else
  if p_station='geometrie' then if dest='geometrie' then dest:=null;end if;geo:=false;
  elsif dest=p_station then dest:=null;else raise exception 'La personne n’est pas affectée à ce poste.';end if;
 end if;
 update public.workshop_days set station=dest,geometry=coalesce(geo,false) where date=p_date and staff_id=p_staff;
end $$;

create or replace function public.workshop_plan_edit(p_date date,p_action text,p_version integer,p_staff text default null,p_station text default null,p_geometry boolean default false) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_plan_drafts%rowtype;e jsonb;current_base jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;
 if p_date is null or p_date<(now() at time zone 'Europe/Paris')::date then raise exception 'Choisis aujourd’hui ou une date à venir.';end if;
 if p_action is null or p_action not in ('start','save','publish','discard') then raise exception 'Action de préparation invalide.';end if;
 lock table public.workshop_days in share row exclusive mode;lock table public.workshop_skills in share mode;lock table public.workshop_station_status in share mode;
 perform pg_advisory_xact_lock(hashtextextended('plan:'||p_date::text,0));
 select * into r from public.workshop_plan_drafts where date=p_date for update;
 if p_action='start' then
  if found then return;end if;
  insert into public.workshop_plan_drafts(date,entries,baseline,updated_by) values(p_date,(select coalesce(jsonb_agg(jsonb_build_object('staff_id',d.staff_id,'station',d.station,'geometry',d.geometry) order by d.staff_id),'[]') from public.workshop_days d where date=p_date),workshop_private.plan_baseline(p_date),auth.uid());return;
 end if;
 if r.date is null or r.version is distinct from p_version then raise exception 'Préparation modifiée entre-temps. Actualise le plan.';end if;
 if p_action='discard' then delete from public.workshop_plan_drafts where date=p_date;return;end if;
 if p_action='save' then
  if not exists(select 1 from public.workshop_staff where id=p_staff and active and role<>'guest') or p_geometry is null then raise exception 'Collaborateur invalide.';end if;
  select x into e from jsonb_array_elements(r.entries)x where x->>'staff_id'=p_staff;
  if e->>'station'='geometrie' and p_station is not null and p_station<>'geometrie' then p_geometry:=true;
  elsif e->>'station' is not null and p_station is not null and p_station is distinct from e->>'station' then raise exception 'Retire d’abord le poste principal actuel.';end if;
  if p_station is not null and p_station is distinct from e->>'station' and not workshop_private.assignment_allowed(p_staff,p_date,p_station) then raise exception 'Affectation non autorisée : vérifie compétence Autonome, présence, horaires, équipe et pont.';end if;
  if p_geometry and not coalesce((e->>'geometry')::boolean,false) and not workshop_private.assignment_allowed(p_staff,p_date,'geometrie') then raise exception 'Géométrie non autorisée pour ce collaborateur.';end if;
  update public.workshop_plan_drafts set entries=(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(r.entries)x where x->>'staff_id'<>p_staff)||jsonb_build_array(jsonb_build_object('staff_id',p_staff,'station',p_station,'geometry',p_geometry)),version=version+1,updated_at=now(),updated_by=auth.uid() where date=p_date;return;
 end if;
 if p_action<>'publish' then raise exception 'Action inconnue.';end if;
 current_base:=workshop_private.plan_baseline(p_date);
 if current_base is distinct from r.baseline then raise exception 'Les horaires, présences ou affectations ont changé pendant la préparation. Annule le brouillon puis recommence depuis le plan à jour.';end if;
 for e in select * from jsonb_array_elements(r.entries) loop
  if e->>'station' is not null and not workshop_private.assignment_allowed(e->>'staff_id',p_date,e->>'station') then raise exception 'Une affectation n’est plus possible. Corrige le brouillon avant publication.';end if;
  if (e->>'geometry')::boolean and not workshop_private.assignment_allowed(e->>'staff_id',p_date,'geometrie') then raise exception 'Une affectation géométrie n’est plus possible.';end if;
  update public.workshop_days set station=e->>'station',geometry=(e->>'geometry')::boolean where date=p_date and staff_id=e->>'staff_id';
 end loop;
 delete from public.workshop_plan_drafts where date=p_date;
end $$;

do $$begin if to_regprocedure('public.workshop_load_before56(date)') is null then alter function public.workshop_load(date) rename to workshop_load_before56;end if;end $$;
revoke all on function public.workshop_load_before56(date) from public,anon,authenticated;
create or replace function public.workshop_load(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;begin a:=workshop_private.actor_before30();r:=public.workshop_load_before56(p_date);return r||case when coalesce((a->>'manager')::boolean,false) then jsonb_build_object('skills',public.workshop_skills_list()) else '{}'::jsonb end;end $$;
revoke all on function public.workshop_admin_birthday(text),public.workshop_admin_birthday_save(text,date,integer),public.workshop_screen_info(),public.workshop_screen_save(jsonb,integer),public.workshop_assign(date,text,text,boolean,text,boolean),workshop_private.staff_can_work(text,text) from public,anon,authenticated;
grant execute on function public.workshop_admin_birthday(text),public.workshop_admin_birthday_save(text,date,integer),public.workshop_screen_info(),public.workshop_screen_save(jsonb,integer),public.workshop_assign(date,text,text,boolean,text,boolean) to authenticated;
notify pgrst,'reload schema';commit;
