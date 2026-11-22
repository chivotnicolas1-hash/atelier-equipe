-- MAJ118 : génération serveur d'un brouillon, jamais du plan publié.
-- Conserve les règles métier existantes : assignment_allowed + staff_can_work.
begin;
create table if not exists workshop_private.plan_runs118(
 date date primary key,kind text not null check(kind in ('generated','existing_draft','existing_plan','closed')),
 created_at timestamptz not null default now(),finished_at timestamptz,summary jsonb not null default '{}'
);
alter table workshop_private.plan_runs118 enable row level security;
revoke all on workshop_private.plan_runs118 from public,anon,authenticated;
-- Annulation OU publication manuelle : ne jamais recréer le brouillon ce jour-là.
create or replace function workshop_private.plan_finished118() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 insert into workshop_private.plan_runs118(date,kind,finished_at) values(old.date,'closed',now())
 on conflict(date) do update set finished_at=now();
 return old;
end $$;
drop trigger if exists workshop_plan_finished118 on public.workshop_plan_drafts;
create trigger workshop_plan_finished118 after delete on public.workshop_plan_drafts
 for each row execute function workshop_private.plan_finished118();

create or replace function workshop_private.scheduled_minutes118(p_slots jsonb) returns numeric
language sql immutable set search_path='' as $$
 select coalesce(sum(case when x->>'start' ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$'
 and x->>'end' ~ '^([01][0-9]|2[0-3]):[0-5][0-9](:00)?$'
 then greatest(0,extract(epoch from ((x->>'end')::time-(x->>'start')::time))/60) else 0 end),0)
 from jsonb_array_elements(case when jsonb_typeof(p_slots)='array' then p_slots else '[]'::jsonb end)x
$$;
create or replace function workshop_private.plan_candidate118(p_staff text,p_date date,p_station text) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.workshop_staff s join public.workshop_days d on d.staff_id=s.id and d.date=p_date
 join public.workshop_stations st on st.id=p_station
 join public.workshop_skills k on k.staff_id=s.id and k.station_id=st.id and k.level='autonomous'
 where s.id=p_staff and s.active and s.role not in ('guest','director')
 and coalesce(to_jsonb(s)->>'suspended','false')<>'true'
 and d.presence='present' and workshop_private.scheduled_minutes118(d.slots)>0
 and st.active and st.office=(lower(trim(coalesce(s.team,'')))='encadrants')
 and not exists(select 1 from public.workshop_station_status ss where ss.station_id=st.id and ss.status<>'available')
 and workshop_private.assignment_allowed(s.id,p_date,st.id)
 and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods)p
 where l.staff_id=s.id and l.status='accepted' and p_date between (p->>'start')::date and (p->>'end')::date))
$$;

create or replace function workshop_private.plan_automatic118(p_now timestamptz default now()) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='3s' as $$
declare d date;local_time timestamp;st record;person text;proposal jsonb;used text[]:='{}';
 added integer:=0;uncovered jsonb:='[]';summary jsonb;
begin
 if p_now is null then raise exception 'Date requise';end if;
 local_time:=p_now at time zone 'Europe/Paris';d:=local_time::date;
 if local_time::time<time '05:00' then return jsonb_build_object('state','before_5');end if;
 if exists(select 1 from workshop_private.plan_runs118 where date=d) then return jsonb_build_object('state','already_processed');end if;
 -- Même ordre que le moteur de préparation existant. Sérialise avec publication/import.
 lock table public.workshop_days in share row exclusive mode;
 lock table public.workshop_station_status in share mode;
 lock table public.workshop_skills in share mode;
 perform pg_advisory_xact_lock(hashtextextended('plan:'||d::text,0));
 if exists(select 1 from workshop_private.plan_runs118 where date=d) then return jsonb_build_object('state','already_processed');end if;
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
 insert into workshop_private.plan_runs118(date,kind,summary) values(d,'generated',summary);
 return summary||jsonb_build_object('state','generated');
end $$;

create or replace function public.workshop_plan_automatic_status118(p_date date) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();
 if not (coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Réservé à l’administration et à la modération.' using errcode='42501';end if;
 perform workshop_private.assert_section('plan');
 if p_date is null then raise exception 'Date requise';end if;
 return (select jsonb_build_object('kind',r.kind,'created_at',r.created_at,'finished',r.finished_at is not null,'summary',r.summary) from workshop_private.plan_runs118 r where date=p_date);
end $$;
revoke all on function workshop_private.plan_finished118(),workshop_private.scheduled_minutes118(jsonb),workshop_private.plan_candidate118(text,date,text),workshop_private.plan_automatic118(timestamptz),public.workshop_plan_automatic_status118(date) from public,anon,authenticated;
grant execute on function public.workshop_plan_automatic_status118(date) to authenticated;
notify pgrst,'reload schema';
commit;
