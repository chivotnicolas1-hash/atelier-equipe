-- MAJ93 — Après MAJ92. Réexécutable ; aucune donnée existante supprimée.
begin;
create table if not exists workshop_private.waste_delays93(
 provider text primary key check(provider in ('Grandidier','Chimirec','Gurdebeke')),
 days integer check(days between 1 and 365),version integer not null default 0
);
insert into workshop_private.waste_delays93(provider) values('Grandidier'),('Chimirec'),('Gurdebeke') on conflict do nothing;
create table if not exists workshop_private.waste_followups93(
 id uuid primary key default gen_random_uuid(),
 waste_id uuid not null references public.workshop_waste(id) on delete cascade,
 validation_at timestamptz not null, due_at timestamptz not null,
 created_at timestamptz not null default now(),done_at timestamptz,done_name text,
 closed_at timestamptz,closed_reason text,version integer not null default 0,
 unique(waste_id,validation_at)
);
alter table workshop_private.waste_delays93 enable row level security;
alter table workshop_private.waste_followups93 enable row level security;
revoke all on workshop_private.waste_delays93,workshop_private.waste_followups93 from public,anon,authenticated;
create or replace function workshop_private.waste_audience93(a jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select coalesce((a->>'admin')::boolean,false) or a->>'role'='moderator' or exists(
 select 1 from public.workshop_staff where id=a->>'self' and active and coalesce(role,'employee') not in ('guest','director') and lower(btrim(team))='encadrants')
$$;
-- Jours fériés nationaux applicables à Fayet (métropole).
create or replace function workshop_private.waste_holiday93(p_date date) returns boolean language plpgsql immutable set search_path='' as $$
declare y int:=extract(year from p_date);a int;b int;c int;d int;e int;f int;g int;h int;i int;k int;l int;m int;easter date;
begin
 if to_char(p_date,'MM-DD')=any(array['01-01','05-01','05-08','07-14','08-15','11-01','11-11','12-25']) then return true;end if;
 a:=y%19;b:=y/100;c:=y%100;d:=b/4;e:=b%4;f:=(b+8)/25;g:=(b-f+1)/3;h:=(19*a+b-d-g+15)%30;i:=c/4;k:=c%4;l:=(32+2*e+2*i-h-k)%7;m:=(a+11*h+22*l)/451;
 easter:=make_date(y,(h+l-7*m+114)/31,(h+l-7*m+114)%31+1);
 return p_date in(easter+1,easter+39,easter+50);
end $$;
create or replace function workshop_private.waste_due93(p_validated timestamptz,p_days integer) returns timestamptz language plpgsql immutable set search_path='' as $$
declare d date:=(p_validated at time zone 'Europe/Paris')::date;n int:=0;
begin
 if p_validated is null or p_days is null then return null;end if;
 if p_days not between 1 and 365 then raise exception 'Délai invalide';end if;
 while n<p_days loop
 d:=d+1;
 if extract(isodow from d) between 1 and 5 and not workshop_private.waste_holiday93(d) then n:=n+1;end if;
 end loop;
 -- Le prestataire dispose de toute la dernière journée ouvrée ; alerte le lendemain à 8 h.
 return (d+time '23:59:59') at time zone 'Europe/Paris';
end $$;
create or replace function public.workshop_waste_delays93(p_provider text default null,p_days integer default null,p_version integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réglage réservé à l’administrateur.' using errcode='42501';end if;
 if p_provider is not null then
 if p_days is not null and p_days not between 1 and 365 then raise exception 'Choisis un délai entre 1 et 365 jours.';end if;
 update workshop_private.waste_delays93 set days=p_days,version=version+1 where provider=p_provider and version=p_version;
 if not found then raise exception 'Ce délai a changé. Ferme puis rouvre les réglages.';end if;
 end if;
 return(select jsonb_agg(to_jsonb(d) order by provider) from workshop_private.waste_delays93 d);
end $$;
-- Le traitement reste actif même lorsque toutes les applications sont fermées.
create or replace function workshop_private.waste_schedule93(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare request_row record;t uuid;recipient uuid;due timestamptz;begin
 perform pg_advisory_xact_lock(930093);
 update workshop_private.waste_followups93 f set closed_at=p_now,closed_reason=case when w.collected_at is not null then 'Ramassage terminé' else 'Demande modifiée : nouvelle validation nécessaire' end,version=f.version+1
 from public.workshop_waste w where w.id=f.waste_id and f.closed_at is null and (w.collected_at is not null or w.validated_at is distinct from f.validation_at);
 for request_row in select w.*,d.days from public.workshop_waste w join workshop_private.waste_delays93 d using(provider)
 where w.validated_at is not null and w.collected_at is null and d.days is not null
 and workshop_private.waste_due93(w.validated_at,d.days)<p_now
 and extract(isodow from p_now at time zone 'Europe/Paris') between 1 and 5
 and not workshop_private.waste_holiday93((p_now at time zone 'Europe/Paris')::date)
 and (p_now at time zone 'Europe/Paris')::time>=time '08:00'
 order by w.id for update of w loop
 due:=workshop_private.waste_due93(request_row.validated_at,request_row.days);
 t:=null;
 insert into workshop_private.waste_followups93(waste_id,validation_at,due_at,created_at)
 values(request_row.id,request_row.validated_at,due,p_now) on conflict(waste_id,validation_at) do nothing returning id into t;
 if t is not null then
 for recipient in select distinct u.id from public.workshop_staff s join auth.users u on lower(u.email)=lower(s.email)
 where s.active and coalesce(s.role,'employee') not in ('guest','director') and (lower(s.email)='nchivot@norauto.fr' or s.role in ('admin','moderator') or lower(btrim(s.team))='encadrants') loop
 perform workshop_private.message(recipient,'Ramassage en retard · '||request_row.provider||' : relance le prestataire. Une tâche commune est disponible dans les tâches.','/?notifications=tasks','waste93:'||t::text);
 end loop;
 end if;
 end loop;
end $$;
create or replace function public.workshop_waste_tracking93() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if a->>'role'='guest' then return '[]'::jsonb;end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'due_at',case when d.days is not null then workshop_private.waste_due93(w.validated_at,d.days) end,'overdue',d.days is not null and workshop_private.waste_due93(w.validated_at,d.days)<=now(),'followup_created',f.id is not null,'done_at',f.done_at,'done_name',f.done_name)),'[]')
 from public.workshop_waste w join workshop_private.waste_delays93 d using(provider)
 left join workshop_private.waste_followups93 f on f.waste_id=w.id and f.validation_at=w.validated_at
 where w.validated_at is not null and w.collected_at is null);
end $$;
create or replace function public.workshop_waste_tasks93() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('tasks');
 if not coalesce(workshop_private.waste_audience93(a),false) then return '[]'::jsonb;end if;
 return(select coalesce(jsonb_agg(to_jsonb(r) order by r.done_at nulls first,r.due_at),'[]') from(
 select f.id,f.due_at,f.done_at,f.done_name,f.version,w.provider,w.categories,w.bin_counts,w.author_name,w.created_at as requested_at
 from workshop_private.waste_followups93 f join public.workshop_waste w on w.id=f.waste_id
 where f.closed_at is null and w.collected_at is null and w.validated_at=f.validation_at
 )r);
end $$;
create or replace function public.workshop_waste_task_done93(p_id uuid,p_version integer,p_done boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;n text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('tasks');
 if not coalesce(workshop_private.waste_audience93(a),false) then raise exception 'Relance réservée aux encadrants, administrateur et modérateurs.' using errcode='42501';end if;
 if p_done is null then raise exception 'État requis.';end if;
 select name into n from public.workshop_staff where id=a->>'self';
 update workshop_private.waste_followups93 f set done_at=case when p_done then now() end,done_name=case when p_done then coalesce(n,a->>'user') end,version=f.version+1
 where f.id=p_id and f.version=p_version and f.closed_at is null and exists(select 1 from public.workshop_waste w where w.id=f.waste_id and w.collected_at is null and w.validated_at=f.validation_at);
 if not found then raise exception 'Cette relance a changé ou le ramassage est terminé. Rouvre les tâches.';end if;
end $$;
revoke all on function workshop_private.waste_holiday93(date),workshop_private.waste_audience93(jsonb),workshop_private.waste_due93(timestamptz,integer),workshop_private.waste_schedule93(timestamptz) from public,anon,authenticated;
revoke all on function public.workshop_waste_delays93(text,integer,integer),public.workshop_waste_tracking93(),public.workshop_waste_tasks93(),public.workshop_waste_task_done93(uuid,integer,boolean) from public,anon;
grant execute on function public.workshop_waste_delays93(text,integer,integer),public.workshop_waste_tracking93(),public.workshop_waste_tasks93(),public.workshop_waste_task_done93(uuid,integer,boolean) to authenticated;
-- Même nom lors d’une réexécution : pas de second programme.
create extension if not exists pg_cron;
select cron.schedule('atelier-relances-dechets93','* * * * *','select workshop_private.waste_schedule93(now());');
notify pgrst,'reload schema';
commit;
