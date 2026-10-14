-- MAJ30 complément : après 30-dechets-suivi.sql. Réexécutable.
begin;
alter table public.workshop_staff drop constraint if exists workshop_staff_role_check;
alter table public.workshop_staff add constraint workshop_staff_role_check check(role in ('employee','moderator','guest'));
do $$ declare c record;begin for c in select conname from pg_constraint where conrelid='public.workshop_days'::regclass and contype='c' and pg_get_constraintdef(oid) like '%confirmed%' loop execute format('alter table public.workshop_days drop constraint %I',c.conname);end loop;end $$;
alter table public.workshop_days add constraint workshop_confirmation_present check(confirmed is null or presence='present');
alter table public.workshop_days add column if not exists geometry boolean not null default false;
alter table public.workshop_reports add column if not exists location text;
create table if not exists public.workshop_guest_settings(id integer primary key check(id=1),report_id uuid references public.workshop_reports(id) on delete set null);
insert into public.workshop_guest_settings(id) values(1) on conflict do nothing;
alter table public.workshop_guest_settings enable row level security;
revoke all on public.workshop_guest_settings from public,anon,authenticated;

do $$ begin
 if to_regprocedure('workshop_private.actor_before30()') is null then alter function workshop_private.actor() rename to actor_before30;end if;
 if to_regprocedure('public.workshop_load_before30(date)') is null then alter function public.workshop_load(date) rename to workshop_load_before30;end if;
 if to_regprocedure('public.workshop_list_orders_before30(integer)') is null then alter function public.workshop_list_orders(integer) rename to workshop_list_orders_before30;end if;
 if to_regprocedure('public.workshop_list_waste_before30(integer)') is null then alter function public.workshop_list_waste(integer) rename to workshop_list_waste_before30;end if;
 if to_regprocedure('public.workshop_get_report_before30(uuid)') is null then alter function public.workshop_get_report(uuid) rename to workshop_get_report_before30;end if;
 if to_regprocedure('public.workshop_list_reports_before30(integer,boolean,text)') is null then alter function public.workshop_list_reports(integer,boolean,text) rename to workshop_list_reports_before30;end if;
end $$;
revoke all on function workshop_private.actor_before30(),public.workshop_load_before30(date),public.workshop_list_orders_before30(integer),public.workshop_list_waste_before30(integer),public.workshop_get_report_before30(uuid),public.workshop_list_reports_before30(integer,boolean,text) from public,anon,authenticated;
create or replace function workshop_private.actor() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();if a->>'role'='guest' then raise exception 'Compte invité : consultation uniquement.' using errcode='42501';end if;return a;end $$;
revoke all on function workshop_private.actor() from public,anon,authenticated;
revoke all on function public.workshop_preview(text,date) from public,anon,authenticated;

create or replace function public.workshop_mutate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; act text; v_id text; v_email text; v_task public.workshop_tasks%rowtype; v_count integer; v_done boolean; v_manager boolean; person public.workshop_staff%rowtype; current_day public.workshop_days%rowtype;
begin
 a:=workshop_private.actor();v_admin:=(a->>'admin')::boolean;v_manager:=(a->>'manager')::boolean;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Action invalide.'; end if;
 act:=p->>'action';v_id:=p->>'id';
 if act in ('staff','createStaff') and p->>'role'='guest' then p:=p||jsonb_build_object('team',null,'can_manage_schedule',false);end if;
 if act in ('day','task','editTask') and exists(select 1 from public.workshop_staff where id=coalesce(p->>'staffId',v_id) and role='guest') then raise exception 'Un invité ne peut recevoir ni horaires ni tâches réelles.';end if;
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
 if act in ('staff','createStaff') and p ? 'can_manage_schedule' and jsonb_typeof(p->'can_manage_schedule') is distinct from 'boolean' then raise exception 'Permission horaires invalide.';end if;
 if act='createStaff' then
  if p->>'role' is not null and p->>'role' not in ('employee','moderator','guest') then raise exception 'Rôle invalide.';end if;
  select lpad((coalesce(max(id::integer),0)+1)::text,greatest(2,length((coalesce(max(id::integer),0)+1)::text)),'0') into v_id from public.workshop_staff;
  insert into public.workshop_staff(id,name,email,team,role,can_manage_schedule)
  values(v_id,trim(p->>'name'),nullif(lower(trim(p->>'email')),''),nullif(p->>'team',''),coalesce(p->>'role','employee'),coalesce(p->>'role','employee')='moderator' and coalesce((p->>'can_manage_schedule')::boolean,false));
 elsif act='deleteStaff' then
  if person.email='nchivot@norauto.fr' or v_id=a->>'self' then raise exception 'Ton compte administrateur ne peut pas être supprimé.';end if;
  update public.workshop_staff set active=false,role='employee',can_manage_schedule=false where id=v_id;
 elsif act='deleteTask' then
  delete from public.workshop_tasks where id=v_id::uuid;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Tâche introuvable.';end if;
 elsif act='staff' then
  if nullif(trim(p->>'name'),'') is null then raise exception 'Renseigne un nom.'; end if;
  v_email:=nullif(lower(trim(p->>'email')),'');
  if person.email='nchivot@norauto.fr' and v_email is distinct from person.email then raise exception 'L’adresse du compte administrateur doit être conservée.';end if;
  if p ? 'role' and (p->>'role' is null or p->>'role' not in ('employee','moderator','guest')) then raise exception 'Rôle invalide.';end if;
  update public.workshop_staff set can_manage_schedule=case when coalesce(p->>'role',role)='moderator' then coalesce((p->>'can_manage_schedule')::boolean,can_manage_schedule) else false end,role=case when p ? 'role' then p->>'role' else role end,name=trim(p->>'name'),email=v_email,team=case when p ? 'team' then nullif(p->>'team','') else team end where id=v_id;
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
   where date=(now() at time zone 'Europe/Paris')::date and staff_id=a->>'self' and presence='present' and jsonb_array_length(slots)>0;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Aucun horaire de travail ne t’est affecté aujourd’hui.';end if;
 else raise exception 'Action inconnue.';
 end if;
 if act in ('staff','createStaff') and p->>'role'='guest' then delete from public.workshop_push_subscriptions where user_id in (select u.id from auth.users u join public.workshop_staff s on lower(u.email)=s.email where s.id=v_id);end if;
 return jsonb_build_object('ok',true);
exception
 when unique_violation then raise exception 'Cette adresse e-mail est déjà utilisée par un autre collaborateur.';
 when check_violation then raise exception 'Vérifie les informations saisies : nom, e-mail, équipe, présence, poste ou tâche invalide.';
 when foreign_key_violation then raise exception 'Collaborateur introuvable.';
 when not_null_violation then raise exception 'Il manque une information obligatoire.';
end $$;

create or replace function public.workshop_geometry(p_staff text,p_date date,p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();if not (a->>'manager')::boolean then raise exception 'Réservé à la gestion.' using errcode='42501';end if;
 if p_enabled is null then raise exception 'État invalide.';end if;
 update public.workshop_days d set geometry=p_enabled where d.staff_id=p_staff and date=p_date and presence='present' and exists(select 1 from public.workshop_staff s where s.id=p_staff and s.active and s.role<>'guest');
 if not found then raise exception 'Choisis un collaborateur présent ce jour.';end if;
end $$;
create or replace function public.workshop_load(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;people jsonb;allowed boolean;
begin
 a:=workshop_private.actor_before30();if p_date is null then raise exception 'Date requise.';end if;
 if a->>'role'='guest' then
 result:=a||jsonb_build_object('guest',true,'reports_all',false,'days',(select coalesce(jsonb_agg(to_jsonb(d)),'[]') from public.workshop_days d join public.workshop_staff s on s.id=d.staff_id where d.date=p_date and s.active and s.role<>'guest'),
 'tasks',jsonb_build_array(jsonb_build_object('id','guest-demo','title','Démonstration : contrôler un véhicule prioritaire','details','Exemple fictif en lecture seule. Cette tâche ne figure pas dans les tâches de l’équipe.','staff_id',a->>'self','due',p_date,'priority','urgent','done',0,'completed_at',null)),
 'profile',jsonb_build_object('photo',null),'selected_target',jsonb_build_object('date',p_date,'amount',(select amount from public.workshop_daily_targets where date=p_date)),
 'announcement',(select to_jsonb(x)-'updated_by' from public.workshop_announcement x where id=1),
 'custom_buttons',(select coalesce(jsonb_agg(to_jsonb(b) order by position),'[]') from public.workshop_custom_buttons b where enabled and audience='all'));
 else result:=public.workshop_load_before30(p_date);end if;
 select coalesce(jsonb_agg(case when (a->>'admin')::boolean then to_jsonb(s) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team,'role',s.role) end ||jsonb_build_object('photo',(select p.photo from public.workshop_profiles p join auth.users u on u.id=p.user_id where lower(u.email)=s.email limit 1)) order by s.id),'[]') into people from public.workshop_staff s where s.active and ((a->>'admin')::boolean or s.role<>'guest' or s.id=a->>'self');
 allowed:=(a->>'manager')::boolean or a->>'role'='guest' or (a->>'reports_all')::boolean;
 return result||jsonb_build_object('staff',people,'days',(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(result->'days') x where exists(select 1 from public.workshop_staff s where s.id=x->>'staff_id' and s.role<>'guest')),'tasks',case when a->>'role'='guest' then result->'tasks' else (select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(result->'tasks') x where exists(select 1 from public.workshop_staff s where s.id=x->>'staff_id' and s.role<>'guest')) end,'can_view_ratio',allowed)||case when allowed then jsonb_build_object('selected_ratio',(select ratio from public.workshop_daily_ratios where date=p_date)) else '{}'::jsonb end;
end $$;
create or replace function public.workshop_list_orders(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();
 if a->>'role'<>'guest' then return public.workshop_list_orders_before30(p_offset);end if;
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',false,'total',(select count(*) from public.workshop_order_requests where deleted_at is null),'items',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_edit',false,'week_number',extract(week from coalesce(r.week_start,(r.created_at at time zone 'Europe/Paris')::date)),'week_year',extract(isoyear from coalesce(r.week_start,(r.created_at at time zone 'Europe/Paris')::date)))),'[]') from (select * from public.workshop_order_requests where deleted_at is null order by created_at desc,id limit 30 offset p_offset) r));
end $$;
create or replace function public.workshop_list_waste(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();
 if a->>'role'<>'guest' then return public.workshop_list_waste_before30(p_offset);end if;
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',false,'total',(select count(*) from public.workshop_waste),'items',(select coalesce(jsonb_agg(to_jsonb(r)),'[]') from (select * from public.workshop_waste order by created_at desc,id limit 30 offset p_offset) r));
end $$;

create or replace function workshop_private.next_order(w date,created timestamptz) returns void language sql security definer set search_path='' as $$
 insert into public.workshop_order_requests(id,author_name,items,week_start) values(gen_random_uuid(),'Commande commune','[]',coalesce(w,date_trunc('week',created at time zone 'Europe/Paris')::date)+7) on conflict(week_start) do nothing;
$$;
revoke all on function workshop_private.next_order(date,timestamptz) from public,anon,authenticated;
create or replace function public.workshop_validate_order(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; person text;
begin
 a:=workshop_private.order_actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Validation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found or r.deleted_at is not null then raise exception 'Demande introuvable.';end if;
 if jsonb_array_length(r.items)=0 then raise exception 'Ajoute au moins un article avant validation.';end if;
 if r.status='validated' then perform workshop_private.next_order(r.week_start,r.created_at);return to_jsonb(r);end if;
 if p_version is distinct from r.version then raise exception 'Cette demande a été modifiée. Actualise-la avant validation.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_order_requests set status='validated',version=version+1,updated_at=now(),validated_at=now(),validated_by=auth.uid(),validated_name=coalesce(person,a->>'user') where id=p_id returning * into r;
 perform workshop_private.next_order(r.week_start,r.created_at);return to_jsonb(r);
end $$;

alter table public.workshop_design_history add column if not exists principal boolean not null default false;
create unique index if not exists workshop_one_principal on public.workshop_design_history(principal) where principal;
do $$ begin if not exists(select 1 from public.workshop_design_history where principal) then
 delete from public.workshop_design_history;
 insert into public.workshop_design_history(name,settings,principal) select 'Thème principal','{"appName":"ATELIER FAYET 33","subtitle":"ÉQUIPE & ORGANISATION","loginTitle":"Ta journée commence ici.","loginDescription":"Retrouve ton poste, confirme ta présence et consulte les tâches qui te sont confiées.","loginNote":"Utilise les identifiants transmis par ton administrateur. Pour obtenir un accès ou réinitialiser ton mot de passe, contacte-le.","signature":"Par Nicolas CHIVOT","light":{"background":"#f3f8fe","surface":"#ffffff","text":"#244460","primary":"#0866b6","header":"#142b43"},"dark":{"background":"#101f30","surface":"#192f46","text":"#e2edf8","primary":"#237dc7","header":"#142b43"},"fontSize":16,"radius":12,"spacing":20,"stations":{}}'::jsonb||settings||jsonb_build_object('light','{"background":"#f3f8fe","surface":"#ffffff","text":"#244460","primary":"#0866b6","header":"#142b43"}'::jsonb||coalesce(settings->'light','{}'),'dark','{"background":"#101f30","surface":"#192f46","text":"#e2edf8","primary":"#237dc7","header":"#142b43"}'::jsonb||coalesce(settings->'dark','{}')),true from public.workshop_design where id=1;
 end if;end $$;
create or replace function workshop_private.protect_principal() returns trigger language plpgsql set search_path='' as $$ begin if old.principal then raise exception 'Le thème principal est protégé.';end if;return old;end $$;
drop trigger if exists workshop_principal_guard on public.workshop_design_history;
create trigger workshop_principal_guard before update or delete on public.workshop_design_history for each row execute function workshop_private.protect_principal();
revoke all on function workshop_private.protect_principal() from public,anon,authenticated;

create or replace function workshop_private.check_report_location(p_location text) returns void language plpgsql set search_path='' as $$ begin
 if p_location is null or p_location not in ('pneus1','attelage','vidange1','vidange2','mecalegere','mecalourde','distribution','pneus2','geometrie','elec','organisation','devis','exterieur') then raise exception 'Choisis un pôle ou Extérieur.';end if;
end $$;
revoke all on function workshop_private.check_report_location(text) from public,anon,authenticated;
create or replace function public.workshop_create_report(p_id uuid,p_registration text,p_notes text,p_photos jsonb,p_location text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();perform workshop_private.check_report_location(p_location);
 perform pg_advisory_xact_lock(hashtextextended('report-location:'||p_id::text,0));
 if exists(select 1 from public.workshop_reports where id=p_id and location is distinct from p_location) then raise exception 'Signalement déjà enregistré avec un autre pôle.';end if;
 result:=public.workshop_create_report(p_id,p_registration,p_notes,p_photos);
 update public.workshop_reports set location=p_location where id=p_id;
 return result;end $$;
create or replace function public.workshop_update_report(p_id uuid,p_version integer,p_registration text,p_notes text,p_photos jsonb,p_location text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();perform workshop_private.check_report_location(p_location);result:=public.workshop_update_report(p_id,p_version,p_registration,p_notes,p_photos);update public.workshop_reports set location=p_location where id=p_id;return result;end $$;
revoke all on function public.workshop_create_report(uuid,text,text,jsonb),public.workshop_update_report(uuid,integer,text,text,jsonb) from public,anon,authenticated;
create or replace function public.workshop_guest_report(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not (a->>'admin')::boolean then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_id is not null and not exists(select 1 from public.workshop_reports rr join auth.users u on u.id=rr.author_id where rr.id=p_id and lower(u.email)='nchivot@norauto.fr') then raise exception 'Choisis un signalement créé par l’administrateur.';end if;
 update public.workshop_guest_settings set report_id=p_id where id=1;
end $$;
create or replace function public.workshop_get_report(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;r public.workshop_reports%rowtype;begin
 a:=workshop_private.actor_before30();
 if a->>'role'='guest' then
 select x.* into r from public.workshop_reports x join public.workshop_guest_settings g on g.report_id=x.id join auth.users u on u.id=x.author_id where x.id=p_id and lower(u.email)='nchivot@norauto.fr';
 if not found then raise exception 'Signalement non autorisé.' using errcode='42501';end if;
 result:=jsonb_build_object('id',r.id,'registration',r.registration,'author_name',r.author_name,'notes',r.notes,'created_at',r.created_at,'photos',(select coalesce(jsonb_agg(photo order by position),'[]') from public.workshop_report_photos where report_id=p_id),'can_edit',false,'can_delete',false);
 else result:=public.workshop_get_report_before30(p_id);end if;
 return result||jsonb_build_object('location',(select location from public.workshop_reports where id=p_id),'guest_example',(select report_id=p_id from public.workshop_guest_settings where id=1),'can_share_guest',(a->>'admin')::boolean and exists(select 1 from public.workshop_reports rr join auth.users u on u.id=rr.author_id where rr.id=p_id and lower(u.email)='nchivot@norauto.fr'));
end $$;
create or replace function public.workshop_list_reports(p_offset integer default 0,p_own boolean default true,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;q text;begin
 a:=workshop_private.actor_before30();if a->>'role'<>'guest' then return public.workshop_list_reports_before30(p_offset,p_own,p_search);end if;
 if p_offset is null or p_offset<0 or p_search is null or length(p_search)>30 then raise exception 'Recherche invalide.';end if;
 q:=regexp_replace(upper(p_search),'[^A-Z0-9]','','g');
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'registration',r.registration,'author_name',r.author_name,'notes',r.notes,'created_at',r.created_at,'photo_count',(select count(*) from public.workshop_report_photos where report_id=r.id))),'[]') into result from public.workshop_reports r join public.workshop_guest_settings g on g.report_id=r.id join auth.users u on u.id=r.author_id where lower(u.email)='nchivot@norauto.fr' and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0;
 return jsonb_build_object('total',jsonb_array_length(result),'items',case when p_offset=0 then result else '[]'::jsonb end);
end $$;

create or replace function public.workshop_list_handovers(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; manage boolean;
begin
 a:=workshop_private.actor();manage:=coalesce((a->>'manager')::boolean,false);
 if not manage then raise exception 'Récapitulatifs réservés à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',manage,'total',(select count(*) from public.workshop_handover where manage or release_at<=now()),'items',(select coalesce(jsonb_agg(to_jsonb(h)||jsonb_build_object('published',h.release_at<=now(),'can_edit',manage and h.release_at>now()) order by date desc),'[]') from (select * from public.workshop_handover where manage or release_at<=now() order by date desc limit 30 offset p_offset) h));
end $$;

revoke all on function public.workshop_geometry(text,date,boolean),public.workshop_load(date),public.workshop_list_orders(integer),public.workshop_list_waste(integer),public.workshop_create_report(uuid,text,text,jsonb,text),public.workshop_update_report(uuid,integer,text,text,jsonb,text),public.workshop_guest_report(uuid),public.workshop_get_report(uuid),public.workshop_list_reports(integer,boolean,text) from public,anon,authenticated;
grant execute on function public.workshop_geometry(text,date,boolean),public.workshop_load(date),public.workshop_list_orders(integer),public.workshop_list_waste(integer),public.workshop_create_report(uuid,text,text,jsonb,text),public.workshop_update_report(uuid,integer,text,text,jsonb,text),public.workshop_guest_report(uuid),public.workshop_get_report(uuid),public.workshop_list_reports(integer,boolean,text) to authenticated;
create or replace function public.workshop_push_remove(p_endpoint text) returns void language plpgsql security definer set search_path='' as $$ begin perform workshop_private.actor();delete from public.workshop_push_subscriptions where user_id=auth.uid() and endpoint=p_endpoint;end $$;
create or replace function public.workshop_design_history_list() returns jsonb language plpgsql security definer set search_path='' as $$ declare a jsonb;begin a:=workshop_private.actor();if not (a->>'admin')::boolean then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;return (select coalesce(jsonb_agg(to_jsonb(h) order by principal desc,id desc),'[]') from (select * from public.workshop_design_history order by principal desc,id desc limit 100) h);end $$;
notify pgrst,'reload schema';commit;
