-- MAJ119 sur base MAJ118 corrigée. Réexécutable, aucun plan supprimé.
begin;
create table if not exists workshop_private.move_permits119(
 tx bigint not null,date date not null,staff_id text not null,from_station text,to_station text not null,
 geometry boolean not null,primary key(tx,date,staff_id)
);
alter table workshop_private.move_permits119 enable row level security;
revoke all on workshop_private.move_permits119 from public,anon,authenticated;
create table if not exists workshop_private.move_guard_backup119(id integer primary key check(id=1),definition text not null);
alter table workshop_private.move_guard_backup119 enable row level security;
revoke all on workshop_private.move_guard_backup119 from public,anon,authenticated;
-- Exception transactionnelle très limitée. Le corps du garde existant est conservé
-- intégralement dans un bloc imbriqué et s'applique à tous les autres changements.
do $migration$
declare body text;original text;wrapped text;
begin
 select p.prosrc,pg_get_functiondef(p.oid) into body,original from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
 where n.nspname='workshop_private' and p.proname='protect_station_move' and p.pronargs=0 and l.lanname='plpgsql';
 if body is null then raise exception 'Garde des affectations introuvable : ne pas continuer avant vérification du schéma.';end if;
 if position('move_permits119' in body)>0 then return;end if;
 if exists(select 1 from workshop_private.move_guard_backup119) then raise exception 'Le garde a changé depuis la MAJ119. Une vérification est nécessaire.';end if;
 insert into workshop_private.move_guard_backup119 values(1,original);
 wrapped:=$guard$
begin
 if tg_op='UPDATE' and new.date=old.date and new.staff_id=old.staff_id
 and new.presence is not distinct from old.presence and new.slots is not distinct from old.slots and new.confirmed is not distinct from old.confirmed
 and exists(select 1 from workshop_private.move_permits119 p where p.tx=txid_current() and p.date=new.date and p.staff_id=new.staff_id
 and p.from_station is not distinct from old.station and p.to_station=new.station and p.geometry is not distinct from new.geometry)
 then return new;end if;
 <<original_guard119>>
$guard$||rtrim(body,E' \r\n\t;')||E';\nend';
 execute format('create or replace function workshop_private.protect_station_move() returns trigger language plpgsql security definer set search_path='''' as %L',wrapped);
end $migration$;

-- La publication habituelle reste le seul moyen de rendre un brouillon visible.
-- Elle réutilise toutes les vérifications existantes et autorise uniquement les
-- transferts exacts du brouillon pendant la transaction de publication.
do $$begin
 if to_regprocedure('public.workshop_plan_edit_before119(date,text,integer,text,text,boolean)') is null then
  alter function public.workshop_plan_edit(date,text,integer,text,text,boolean) rename to workshop_plan_edit_before119;
 end if;
end $$;
revoke all on function public.workshop_plan_edit_before119(date,text,integer,text,text,boolean) from public,anon,authenticated;
create or replace function public.workshop_plan_edit(p_date date,p_action text,p_version integer,p_staff text default null,p_station text default null,p_geometry boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_plan_drafts%rowtype;begin
 a:=workshop_private.actor();if not (coalesce((a->>'manager')::boolean,false) or coalesce((a->>'admin')::boolean,false)) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_action='publish' then
  lock table public.workshop_days in share row exclusive mode;lock table public.workshop_skills in share mode;lock table public.workshop_station_status in share mode;
  perform pg_advisory_xact_lock(hashtextextended('plan:'||p_date::text,0));
  select * into r from public.workshop_plan_drafts where date=p_date for update;
  if r.date is null or r.version is distinct from p_version or r.baseline is distinct from workshop_private.plan_baseline(p_date) then raise exception 'Le brouillon ou les horaires ont changé. Vérifie le plan avant publication.';end if;
  insert into workshop_private.move_permits119(tx,date,staff_id,from_station,to_station,geometry)
   select txid_current(),d.date,d.staff_id,d.station,x->>'station',coalesce((x->>'geometry')::boolean,false)
   from public.workshop_days d join jsonb_array_elements(r.entries)x on x->>'staff_id'=d.staff_id
   where d.date=p_date and x->>'station' is not null and d.station is distinct from x->>'station';
 end if;
 perform public.workshop_plan_edit_before119(p_date,p_action,p_version,p_staff,p_station,p_geometry);
 delete from workshop_private.move_permits119 where tx=txid_current() and date=p_date;
end $$;

create or replace function public.workshop_move119(p_date date,p_staff text,p_from text,p_to text,p_expected_station text,p_expected_geometry boolean,p_draft_version integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_days%rowtype;draft public.workshop_plan_drafts%rowtype;e jsonb;src text;geo boolean;dest text;new_geo boolean;begin
 a:=workshop_private.actor();if not (coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Réservé à l’administration et à la modération.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_date is null or p_staff is null or p_from is null or p_to is null or p_expected_geometry is null then raise exception 'Déplacement incomplet.';end if;
 lock table public.workshop_days in share row exclusive mode;lock table public.workshop_skills in share mode;lock table public.workshop_station_status in share mode;
 perform pg_advisory_xact_lock(hashtextextended('plan:'||p_date::text,0));
 select * into r from public.workshop_days where date=p_date and staff_id=p_staff for update;
 if not found then raise exception 'Présence introuvable pour cette journée.';end if;
 select * into draft from public.workshop_plan_drafts where date=p_date for update;
 if draft.date is not null then
  if p_draft_version is null or draft.version is distinct from p_draft_version or draft.baseline is distinct from workshop_private.plan_baseline(p_date) then raise exception 'Le brouillon ou les horaires ont changé. Actualise le plan.';end if;
  select x into e from jsonb_array_elements(draft.entries)x where x->>'staff_id'=p_staff;
  if e is null then raise exception 'Collaborateur absent du brouillon. Actualise le plan.';end if;
  src:=e->>'station';geo:=coalesce((e->>'geometry')::boolean,false);
 else
  if p_draft_version is not null or p_date>(now() at time zone 'Europe/Paris')::date then raise exception 'Prépare un brouillon pour cette journée.';end if;
  src:=r.station;geo:=coalesce(r.geometry,false);
 end if;
 if src is distinct from p_expected_station or geo is distinct from p_expected_geometry or src is distinct from p_from then raise exception 'Affectation modifiée entre-temps. Actualise puis recommence depuis le poste principal.';end if;
 if src=p_to then return jsonb_build_object('changed',false,'draft',draft.date is not null);end if;
 if not exists(select 1 from public.workshop_staff s where s.id=p_staff and s.active and s.role not in ('guest','director') and coalesce(to_jsonb(s)->>'suspended','false')<>'true')
 or r.presence<>'present' or workshop_private.scheduled_minutes118(r.slots)<=0
 or exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods)x where l.staff_id=p_staff and l.status='accepted' and p_date between (x->>'start')::date and (x->>'end')::date)
 then raise exception 'Ce collaborateur doit être prévu présent avec des horaires pour cette journée, hors congé accepté.';end if;
 if not workshop_private.assignment_allowed(p_staff,p_date,p_to) then raise exception 'Destination interdite : vérifie compétence Autonome, équipe, présence, horaires et état du pont.';end if;
 -- Exception géométrie conservée : elle peut se cumuler avec le poste principal.
 if p_to='geometrie' then dest:=src;new_geo:=true;
 else dest:=p_to;new_geo:=geo or src='geometrie';end if;
 if draft.date is not null then
  update public.workshop_plan_drafts set entries=(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(draft.entries)x where x->>'staff_id'<>p_staff)
   ||jsonb_build_array(jsonb_build_object('staff_id',p_staff,'station',dest,'geometry',new_geo)),version=version+1,updated_at=now(),updated_by=auth.uid() where date=p_date;
 else
  insert into workshop_private.move_permits119 values(txid_current(),p_date,p_staff,src,dest,new_geo);
  update public.workshop_days set station=dest,geometry=new_geo where date=p_date and staff_id=p_staff;
  delete from workshop_private.move_permits119 where tx=txid_current() and date=p_date and staff_id=p_staff;
 end if;
 return jsonb_build_object('changed',true,'draft',draft.date is not null,'station',dest,'geometry',new_geo);
end $$;
revoke all on function workshop_private.protect_station_move(),public.workshop_move119(date,text,text,text,text,boolean,integer),public.workshop_plan_edit(date,text,integer,text,text,boolean) from public,anon,authenticated;
grant execute on function public.workshop_move119(date,text,text,text,text,boolean,integer),public.workshop_plan_edit(date,text,integer,text,text,boolean) to authenticated;
notify pgrst,'reload schema';commit;
