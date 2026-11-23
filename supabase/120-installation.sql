-- ATELIER FAYET 33 — MAJ120 — installation à relire avant exécution.
-- Production NON modifiée par la préparation de cette archive.
-- Exécuter le fichier entier dans SQL Editor (rôle propriétaire habituel).
-- Une transaction unique : échec d'installation = aucune modification conservée.
-- Le passage final peut préparer un brouillon réel après 5 h ; jamais le publier.
begin;
do $$begin
 if to_regclass('cron.job') is null
 or to_regprocedure('cron.schedule(text,text,text)') is null then
  raise exception 'pg_cron doit déjà être installé et disponible. Arrêter et vérifier le projet.';
 end if;
 if to_regprocedure('workshop_private.plan_finished118()') is null
 or to_regprocedure('public.workshop_plan_edit(date,text,integer,text,text,boolean)') is null then
  raise exception 'Version du plan incompatible : arrêter et vérifier la version installée.';
 end if;
end $$;
-- Ne publie aucun plan et ne supprime aucune affectation.

do $$begin
 if to_regprocedure('workshop_private.plan_automatic118(timestamp with time zone)') is null
 or to_regclass('workshop_private.plan_runs118') is null then
  raise exception 'Moteur 118 absent : arrêter et vérifier la version installée. Ne pas réinstaller un ancien script au hasard.';
 end if;
end $$;
create table if not exists workshop_private.plan_checks120(
 date date primary key,checked_at timestamptz not null,state text not null,error_code text
);
alter table workshop_private.plan_checks120 enable row level security;
revoke all on workshop_private.plan_checks120 from public,anon,authenticated;

create or replace function workshop_private.plan_check120() returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare d date:=(now() at time zone 'Europe/Paris')::date;r jsonb;code text;
begin
 -- Sous-transaction : une erreur annule la génération avant d'enregistrer son diagnostic.
 begin r:=workshop_private.plan_automatic118(now());
 exception when others then code:=sqlstate;r:=jsonb_build_object('state','failed');end;
 insert into workshop_private.plan_checks120(date,checked_at,state,error_code)
 values(d,clock_timestamp(),coalesce(r->>'state','unknown'),code)
 on conflict(date) do update set checked_at=excluded.checked_at,state=excluded.state,error_code=excluded.error_code;
 delete from workshop_private.plan_checks120 where date<d-90;
 return r||jsonb_build_object('error_code',code);
end $$;
revoke all on function workshop_private.plan_check120() from public,anon,authenticated;

create or replace function workshop_private.plan_tick120() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.plan_check120();
 -- Le nettoyage technique ne peut jamais annuler la génération déjà effectuée.
 if to_regclass('cron.job_run_details') is not null and to_regclass('cron.job') is not null then
  begin execute 'delete from cron.job_run_details where jobid in(select jobid from cron.job where jobname=$1) and end_time<now()-interval ''7 days''' using 'atelier-plan-brouillon-118';
  exception when others then null;end;
 end if;
end $$;
revoke all on function workshop_private.plan_tick120() from public,anon,authenticated;

create or replace function public.workshop_plan_automatic_status120(p_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;check_row jsonb;scheduled boolean:=false;known boolean:=false;retry_planned boolean:=false;last_closure jsonb;last_retry timestamptz;
begin
 a:=workshop_private.actor();
 if not(coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Réservé à l’administration et à la modération.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_date is null then raise exception 'Date requise';end if;
 -- Seul notre programme est examiné ; aucune commande SQL ni autre tâche n'est exposée.
 if to_regclass('cron.job') is not null then
  begin
   execute 'select exists(select 1 from cron.job where jobname=$1 and active and btrim(command) in ($2,$3))'
    into scheduled using 'atelier-plan-brouillon-118','select workshop_private.plan_tick120();','select workshop_private.plan_tick118();';
   known:=true;
  exception when insufficient_privilege then known:=false;end;
 end if;
 select jsonb_build_object('kind',kind,'created_at',created_at,'finished',finished_at is not null,'finished_at',finished_at,'summary',summary) into r
 from workshop_private.plan_runs118 where date=p_date;
 select jsonb_build_object('checked_at',checked_at,'state',state,'error_code',error_code) into check_row
 from workshop_private.plan_checks120 where date=p_date;
 if to_regprocedure('workshop_private.plan_retry_allowed120(date,timestamptz)') is not null then
  retry_planned:=workshop_private.plan_retry_allowed120(p_date,now());
 end if;
 if to_regclass('workshop_private.plan_events120') is not null then
  select jsonb_build_object('action',action,'created_at',created_at) into last_closure from workshop_private.plan_events120
   where date=p_date and action in('publish','discard','unknown') order by id desc limit 1;
  select created_at into last_retry from workshop_private.plan_events120 where date=p_date and action='auto_retry' order by id desc limit 1;
 end if;
 return coalesce(r,'{}'::jsonb)||jsonb_build_object('version',120,'date',p_date,
 'draft_exists',exists(select 1 from public.workshop_plan_drafts where date=p_date),
 'retry_planned',retry_planned,'retry_after',case when retry_planned then(p_date+time '05:00')at time zone 'Europe/Paris' end,
 'last_closure',last_closure,'last_retry_at',last_retry,
 'automation',jsonb_build_object('scheduler_known',known,'scheduled',scheduled,'last_check',check_row));
end $$;
revoke all on function public.workshop_plan_automatic_status120(date) from public,anon,authenticated;
grant execute on function public.workshop_plan_automatic_status120(date) to authenticated;

create or replace function public.workshop_plan_ensure120(p_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if not(coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Réservé à l’administration et à la modération.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_date is null then raise exception 'Date requise';end if;
 -- Pas d'horloge contrôlée par le navigateur et pas de préparation automatique d'une autre date.
 if p_date<>(now() at time zone 'Europe/Paris')::date then return jsonb_build_object('state','other_date');end if;
 return workshop_private.plan_check120();
end $$;
revoke all on function public.workshop_plan_ensure120(date) from public,anon,authenticated;
grant execute on function public.workshop_plan_ensure120(date) to authenticated;

-- Corrige l'annulation d'essai avant 5 h ; ne publie ni ne modifie les affectations.

do $$begin
 if to_regprocedure('workshop_private.plan_check120()') is null
 or to_regprocedure('public.workshop_plan_edit(date,text,integer,text,text,boolean)') is null then
  raise exception 'Préparation habituelle absente : arrêter et vérifier la version installée.';
 end if;
end $$;
-- Sauvegarde privée des trois définitions antérieures, une seule fois.
create table if not exists workshop_private.plan_code_backup120(
 signature text primary key,definition text not null,saved_at timestamptz not null default now()
);
alter table workshop_private.plan_code_backup120 enable row level security;
revoke all on workshop_private.plan_code_backup120 from public,anon,authenticated;
insert into workshop_private.plan_code_backup120(signature,definition)
select signature,pg_get_functiondef(to_regprocedure(signature)) from unnest(array[
 'workshop_private.plan_automatic118(timestamptz)',
 'workshop_private.plan_finished118()',
 'public.workshop_plan_edit(date,text,integer,text,text,boolean)'
])signature on conflict(signature)do nothing;

create table if not exists workshop_private.plan_events120(
 id bigint generated always as identity primary key,
 date date not null,action text not null check(action in('publish','discard','unknown','auto_retry')),
 created_at timestamptz not null,actor uuid,previous_run jsonb
);
create index if not exists plan_events_day120 on workshop_private.plan_events120(date,id desc);
alter table workshop_private.plan_events120 enable row level security;
revoke all on workshop_private.plan_events120 from public,anon,authenticated;
revoke all on sequence workshop_private.plan_events120_id_seq from public,anon,authenticated;

create or replace function workshop_private.plan_retry_allowed120(p_date date,p_now timestamptz) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare r workshop_private.plan_runs118%rowtype;last_action text;cutoff timestamptz;
begin
 if p_date is null or p_now is null or p_date<(p_now at time zone 'Europe/Paris')::date then return false;end if;
 cutoff:=(p_date+time '05:00') at time zone 'Europe/Paris';
 select * into r from workshop_private.plan_runs118 where date=p_date;
 if not found or r.finished_at is null or r.finished_at>=cutoff then return false;end if;
 if exists(select 1 from public.workshop_plan_drafts where date=p_date)
 or exists(select 1 from public.workshop_days where date=p_date and(station is not null or geometry)) then return false;end if;
 -- Une publication tracée reste protégée, même si son plan était volontairement vide.
 if exists(select 1 from workshop_private.plan_events120 where date=p_date and action='publish') then return false;end if;
 select action into last_action from workshop_private.plan_events120 where date=p_date
  and action in('publish','discard','unknown') order by id desc limit 1;
 if last_action is not null then return last_action='discard';end if;
 -- Ancien historique sans motif : uniquement la clôture précoce, sans plan ni brouillon.
 return r.kind='closed' and r.created_at<cutoff and r.finished_at>=r.created_at;
end $$;
revoke all on function workshop_private.plan_retry_allowed120(date,timestamptz) from public,anon,authenticated;

-- Distinguer désormais annulation et publication, en déléguant toutes les règles
-- de gestion et de glisser-déposer à la fonction existante, inchangée.
do $$begin
 if to_regprocedure('public.workshop_plan_edit_before120(date,text,integer,text,text,boolean)') is null then
  alter function public.workshop_plan_edit(date,text,integer,text,text,boolean) rename to workshop_plan_edit_before120;
 end if;
end $$;
revoke all on function public.workshop_plan_edit_before120(date,text,integer,text,text,boolean) from public,anon,authenticated;
create or replace function public.workshop_plan_edit(p_date date,p_action text,p_version integer,p_staff text default null,p_station text default null,p_geometry boolean default false)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;previous_context text:=current_setting('workshop.plan_action120',true);
begin
 a:=workshop_private.actor();
 if not(coalesce((a->>'admin')::boolean,false)or coalesce((a->>'manager')::boolean,false))then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 perform set_config('workshop.plan_action120',jsonb_build_object('date',p_date,'action',p_action)::text,true);
 begin
  perform public.workshop_plan_edit_before120(p_date,p_action,p_version,p_staff,p_station,p_geometry);
 exception when others then
  perform set_config('workshop.plan_action120',coalesce(previous_context,''),true);raise;
 end;
 perform set_config('workshop.plan_action120',coalesce(previous_context,''),true);
end $$;
revoke all on function public.workshop_plan_edit(date,text,integer,text,text,boolean) from public,anon,authenticated;
grant execute on function public.workshop_plan_edit(date,text,integer,text,text,boolean) to authenticated;

create or replace function workshop_private.plan_finished118() returns trigger
language plpgsql security definer set search_path='' as $$
declare context jsonb;kind text:='unknown';at_time timestamptz:=clock_timestamp();
begin
 begin context:=nullif(current_setting('workshop.plan_action120',true),'')::jsonb;
 exception when others then context:=null;end;
 if context->>'date'=old.date::text and context->>'action' in('publish','discard') then kind:=context->>'action';end if;
 insert into workshop_private.plan_events120(date,action,created_at,actor)values(old.date,kind,at_time,auth.uid());
 insert into workshop_private.plan_runs118(date,kind,created_at,finished_at)values(old.date,'closed',at_time,at_time)
 on conflict(date)do update set finished_at=excluded.finished_at;
 return old;
end $$;
revoke all on function workshop_private.plan_finished118() from public,anon,authenticated;
create or replace trigger workshop_plan_finished118 after delete on public.workshop_plan_drafts for each row execute function workshop_private.plan_finished118();

-- Moteur fourni conservé, seules les gardes de relance et son historique évoluent.
CREATE OR REPLACE FUNCTION workshop_private.plan_automatic118(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET lock_timeout TO '3s'
AS $function$
declare d date;local_time timestamp;st record;person text;proposal jsonb;used text[]:='{}';
 added integer:=0;uncovered jsonb:='[]';summary jsonb;previous_run jsonb;
begin
 if p_now is null then raise exception 'Date requise';end if;
 local_time:=p_now at time zone 'Europe/Paris';d:=local_time::date;
 if local_time::time<time '05:00' then return jsonb_build_object('state','before_5');end if;
 if exists(select 1 from workshop_private.plan_runs118 where date=d) and not workshop_private.plan_retry_allowed120(d,p_now) then return jsonb_build_object('state','already_processed');end if;
 -- Même ordre que le moteur de préparation existant. Sérialise avec publication/import.
 lock table public.workshop_days in share row exclusive mode;
 lock table public.workshop_station_status in share mode;
 lock table public.workshop_skills in share mode;
 perform pg_advisory_xact_lock(hashtextextended('plan:'||d::text,0));
 select to_jsonb(r) into previous_run from workshop_private.plan_runs118 r where r.date=d for update;
 if previous_run is not null and not workshop_private.plan_retry_allowed120(d,p_now) then return jsonb_build_object('state','already_processed');end if;
 if exists(select 1 from public.workshop_plan_drafts where date=d) then
  insert into workshop_private.plan_runs118(date,kind) values(d,'existing_draft');return jsonb_build_object('state','existing_draft');
 end if;
 if exists(select 1 from public.workshop_days where date=d and (station is not null or geometry)) then
  insert into workshop_private.plan_runs118(date,kind) values(d,'existing_plan');return jsonb_build_object('state','existing_plan');
 end if;
 -- Pas de brouillon vide si le planning n'a pas encore été chargé : réessai au prochain passage.
 if not exists(select 1 from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id
  where dy.date=d and s.active and s.role not in ('guest','director') and dy.presence='present'
  and coalesce(to_jsonb(s)->>'suspended','false')<>'true' and workshop_private.scheduled_minutes118(dy.slots)>0
  and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods)p
    where l.staff_id=s.id and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date))
 then return jsonb_build_object('state','waiting_schedule');end if;
 select coalesce(jsonb_agg(jsonb_build_object('staff_id',dy.staff_id,'station',null,'geometry',false) order by dy.staff_id),'[]')
 into proposal from public.workshop_days dy where dy.date=d;
 -- Couvrir d'abord les postes dont les compétences sont les plus rares.
 for st in select s.*,(select count(*) from public.workshop_days dy where dy.date=d
   and workshop_private.plan_candidate118(dy.staff_id,d,s.id)) candidates
 from public.workshop_stations s where s.active
 and not exists(select 1 from public.workshop_station_status ss where ss.station_id=s.id and ss.status<>'available')
 order by candidates,s.office desc,s.id loop
  person:=null;
  select dy.staff_id into person from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id
  where dy.date=d and not dy.staff_id=any(used) and workshop_private.plan_candidate118(dy.staff_id,d,st.id)
  order by (select count(*) from public.workshop_skills k join public.workshop_stations ss on ss.id=k.station_id and ss.active where k.staff_id=dy.staff_id and k.level='autonomous' and workshop_private.plan_candidate118(dy.staff_id,d,ss.id) and not exists(select 1 from jsonb_array_elements(proposal)e where e->>'station'=ss.id)),
    workshop_private.scheduled_minutes118(dy.slots) desc,s.name,dy.staff_id limit 1;
  if person is null then uncovered:=uncovered||jsonb_build_array(st.name);continue;end if;
  proposal:=(select coalesce(jsonb_agg(x),'[]') from jsonb_array_elements(proposal)x where x->>'staff_id'<>person)
   ||jsonb_build_array(jsonb_build_object('staff_id',person,'station',st.id,'geometry',false));
  used:=array_append(used,person);added:=added+1;
 end loop;
 summary:=jsonb_build_object('added',added,'uncovered',uncovered,'unassigned',(
 select coalesce(jsonb_agg(s.name order by s.name),'[]') from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id
 where dy.date=d and s.active and s.role not in ('guest','director') and coalesce(to_jsonb(s)->>'suspended','false')<>'true'
 and dy.presence='present' and workshop_private.scheduled_minutes118(dy.slots)>0 and not s.id=any(used)
 and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods)p where l.staff_id=s.id and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date)));
 insert into public.workshop_plan_drafts(date,entries,baseline,updated_by)
 values(d,proposal,workshop_private.plan_baseline(d),null);
 if previous_run is not null then
  insert into workshop_private.plan_events120(date,action,created_at,actor,previous_run)
  values(d,'auto_retry',p_now,auth.uid(),previous_run);
 end if;
 insert into workshop_private.plan_runs118 as target(date,kind,created_at,summary)
 values(d,'generated',p_now,summary)
 on conflict(date)do update set kind=excluded.kind,created_at=excluded.created_at,finished_at=null,summary=excluded.summary
 where previous_run is not null and to_jsonb(target)=previous_run;
 if not found then raise exception 'La préparation a changé pendant le traitement. Réessai au prochain passage.' using errcode='40001';end if;
 return summary||jsonb_build_object('state','generated','retried_after_early_cancel',previous_run is not null);
end $function$;

revoke all on function workshop_private.plan_automatic118(timestamptz) from public,anon,authenticated;

-- Retire l'appel anonyme de deux fonctions réservées à l'administrateur.
-- Ne change aucun corps de fonction, rôle applicatif ou donnée métier.

do $$
declare signature text;fn regprocedure;keep_authenticated boolean;keep_service boolean;
begin
 foreach signature in array array[
  'public.workshop_catalog_code88(text,uuid,text,text,text)',
  'public.workshop_monthly82(date)'
 ] loop
  fn:=to_regprocedure(signature);
  if fn is null then raise exception 'Fonction attendue absente : %. Aucun changement ne sera conservé.',signature;end if;
  -- Conserver les droits effectifs existants, sans en donner de nouveaux.
  keep_authenticated:=has_function_privilege('authenticated',fn,'EXECUTE');
  keep_service:=has_function_privilege('service_role',fn,'EXECUTE');
  execute format('revoke execute on function %s from public,anon',fn);
  if keep_authenticated then execute format('grant execute on function %s to authenticated',fn);end if;
  if keep_service then execute format('grant execute on function %s to service_role',fn);end if;
 end loop;
end $$;

-- Met à jour la tâche quotidienne existante, ne crée pas une seconde tâche nommée autrement.


select cron.alter_job(job_id:=cron.schedule('atelier-plan-brouillon-118','*/10 * * * *','select workshop_private.plan_tick120();'),active:=true);
-- Passage initial réel : peut créer le brouillon du jour après 5 h, jamais le publier.
select workshop_private.plan_check120();
notify pgrst,'reload schema';
commit;
