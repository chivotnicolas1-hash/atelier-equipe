-- MAJ122 — après MAJ121. À examiner avant exécution.
-- Aucun message envoyé par l'installation ; le programme existant utilisera la règle au prochain passage.
-- Seul le routage du récapitulatif est remplacé. Autres notifications et horaires conservés.
begin;
do $$declare source text;begin
 if to_regclass('workshop_private.accounts100') is null
 or to_regclass('workshop_private.code_backup121') is null
 or to_regprocedure('workshop_private.schedule_messages_before49(timestamptz)') is null
 or to_regprocedure('workshop_private.message(uuid,text,text,text)') is null then
  raise exception 'Prérequis MAJ121 et moteur de notifications absent. Arrêter et vérifier la version installée.';
 end if;
 select prosrc into source from pg_proc where oid=to_regprocedure('public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)');
 if source is null or position('validated_at=null' in regexp_replace(lower(source),'[[:space:]]','','g'))>0 then
  raise exception 'Le correctif déchets MAJ121 doit être installé avant MAJ122.';
 end if;
end $$;
create table if not exists workshop_private.code_backup122(signature text primary key,definition text not null,saved_at timestamptz not null default now());
alter table workshop_private.code_backup122 enable row level security;
revoke all on workshop_private.code_backup122 from public,anon,authenticated;
insert into workshop_private.code_backup122(signature,definition)
select 'workshop_private.schedule_messages_before49(timestamptz)',pg_get_functiondef('workshop_private.schedule_messages_before49(timestamptz)'::regprocedure)
on conflict(signature)do nothing;

-- Une décision par journée et par notification. Elle reste conservée même si les horaires changent ensuite.
create table if not exists workshop_private.recap_dispatch122(
 day date not null,phase text not null check(phase in('morning','evening')),
 recap_date date,user_id uuid,staff_id text,event_key text not null,
 outcome text not null check(outcome in('queued','already_recorded')),
 decided_at timestamptz not null,primary key(day,phase)
);
alter table workshop_private.recap_dispatch122 enable row level security;
revoke all on workshop_private.recap_dispatch122 from public,anon,authenticated;

create or replace function workshop_private.recap_recipient122(p_day date,p_phase text,p_now timestamptz)
returns table(staff_id text,user_id uuid,name text,starts time,ends time)
language sql stable security definer set search_path='' as $$
 select s.id,a.user_id,s.name,h.starts,h.ends
 from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id
 join workshop_private.accounts100 a on a.staff_id=s.id join auth.users u on u.id=a.user_id
 cross join lateral(
  select min(case when valid then(slot->>'start')::time end)starts,
         max(case when valid then(slot->>'end')::time end)ends
  from(
   select slot,coalesce(jsonb_typeof(slot)='object' and slot->>'start'~'^([01][0-9]|2[0-3]):[0-5][0-9]$'
    and slot->>'end'~'^([01][0-9]|2[0-3]):[0-5][0-9]$' and slot->>'start'<slot->>'end',false)valid
   from jsonb_array_elements(case when jsonb_typeof(dy.slots)='array' then dy.slots else '[]'::jsonb end)slot
  )slots
 )h
 where p_day is not null and p_now is not null and p_phase in('morning','evening') and extract(isodow from p_day)<>7
 and dy.date=p_day and dy.presence='present' and s.active
 and coalesce(to_jsonb(s)->>'suspended','false')<>'true'
 and lower(btrim(coalesce(s.team,'')))='encadrants'
 and coalesce(s.role,'employee')not in('guest','director')
 and(coalesce(a.is_admin,false)or s.role='moderator')
 and u.email_confirmed_at is not null and(u.banned_until is null or u.banned_until<=p_now)
 and h.starts is not null and h.ends is not null
 and not exists(select 1 from public.workshop_leave_requests l
  cross join lateral jsonb_array_elements(case when jsonb_typeof(l.periods)='array' then l.periods else '[]'::jsonb end)period
  where l.staff_id=s.id and l.status='accepted' and p_day between(period->>'start')::date and(period->>'end')::date)
 order by case when p_phase='morning' then h.starts end asc,
          case when p_phase='evening' then h.ends end desc,lower(s.name),s.id,a.user_id
 limit 1;
$$;
revoke all on function workshop_private.recap_recipient122(date,text,timestamptz) from public,anon,authenticated;

create or replace function workshop_private.recap_send122(p_day date,p_phase text,p_recap date,p_now timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare target record;key text;body text;
begin
 if p_day is null or p_now is null or p_day<>(p_now at time zone'Europe/Paris')::date
 or p_phase is null or p_phase not in('morning','evening') then raise exception 'Routage incorrect.';end if;
 if p_phase='morning' then
  if p_recap is null or p_recap>=p_day then raise exception 'Récapitulatif incorrect.';end if;
  key:='recap:'||p_recap::text;
  if extract(isodow from p_recap)=6 then key:=key||':lundi';end if;
  body:=case when extract(isodow from p_recap)=6 then'Le récapitulatif du samedi est disponible'else'Le récapitulatif de la veille est disponible'end;
 else key:='reminder:'||p_day::text;body:='Pense à faire ton récapitulatif';end if;
 perform pg_advisory_xact_lock(hashtextextended('recap-dispatch122:'||p_day::text||':'||p_phase,0));
 if exists(select 1 from workshop_private.recap_dispatch122 d where d.day=p_day and d.phase=p_phase)then return;end if;
 -- Ne pas réémettre une notification déjà produite avant l'installation ou avant un changement d'horaire.
 if exists(select 1 from public.workshop_messages where event_key=key)then
  insert into workshop_private.recap_dispatch122(day,phase,recap_date,event_key,outcome,decided_at)
  values(p_day,p_phase,p_recap,key,'already_recorded',p_now);return;
 end if;
 select * into target from workshop_private.recap_recipient122(p_day,p_phase,p_now);
 if not found then return;end if; -- Horaires tardifs : réessai au prochain passage, aucune personne sans horaire choisie.
 perform workshop_private.message(target.user_id,body,'/?notifications=recap',key);
 insert into workshop_private.recap_dispatch122(day,phase,recap_date,user_id,staff_id,event_key,outcome,decided_at)
 values(p_day,p_phase,p_recap,target.user_id,target.staff_id,key,'queued',p_now);
end $$;
revoke all on function workshop_private.recap_send122(date,text,date,timestamptz) from public,anon,authenticated;

-- Point d'entrée récapitulatif existant : la chaîne des autres programmations n'est pas modifiée.
create or replace function workshop_private.schedule_messages_before49(p_now timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone'Europe/Paris')::date;t time:=(p_now at time zone'Europe/Paris')::time;r record;
begin
 if p_now is null or extract(isodow from d)=7 then return;end if;
 if t>=time'07:30'then
  select h.date into r from public.workshop_handover h
  where h.date<d and extract(isodow from h.date)<>7 and h.release_at<=p_now
   and(h.release_at at time zone'Europe/Paris')::date=d
  order by h.date desc limit 1;
  if found then perform workshop_private.recap_send122(d,'morning',r.date,p_now);end if;
 end if;
 if t>=time'18:30'and not exists(select 1 from public.workshop_handover where date=d)then
  perform workshop_private.recap_send122(d,'evening',null,p_now);
 end if;
end $$;
revoke all on function workshop_private.schedule_messages_before49(timestamptz) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
