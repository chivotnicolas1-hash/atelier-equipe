begin;
create table if not exists public.workshop_task_series (
 id uuid primary key default gen_random_uuid(), title text not null check(length(trim(title)) between 1 and 200), details text not null default '' check(length(details)<=4000),
 staff_id text not null references public.workshop_staff(id),priority text not null check(priority in ('normal','high','urgent')),
 starts_on date not null, unit text not null check(unit in ('day','week','month')), every integer not null check(every between 1 and 365),
 ends_on date, next_index integer not null default 1 check(next_index>=1),next_due date not null,active boolean not null default true,created_at timestamptz not null default now(),
 check(ends_on is null or ends_on>=starts_on)
);
alter table public.workshop_task_series enable row level security;
revoke all on public.workshop_task_series from public,anon,authenticated;
alter table public.workshop_tasks add column if not exists recurrence_id uuid references public.workshop_task_series(id);
alter table public.workshop_tasks add column if not exists occurrence_date date;
create unique index if not exists workshop_task_occurrence on public.workshop_tasks(recurrence_id,occurrence_date) where recurrence_id is not null;
create or replace function workshop_private.recurrence_date(p_start date,p_unit text,p_every integer,p_index integer) returns date language sql immutable set search_path='' as $$
 select case p_unit when 'month' then (p_start+make_interval(months=>p_every*p_index))::date when 'week' then p_start+(7*p_every*p_index) else p_start+(p_every*p_index) end;
$$;
revoke all on function workshop_private.recurrence_date(date,text,integer,integer) from public,anon,authenticated;
create or replace function public.workshop_create_recurring_task(p jsonb,p_unit text,p_every integer,p_until date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; first_day date; next_day date; series_id uuid; task_id uuid;
begin
 lock table public.workshop_staff in share mode;
 a:=workshop_private.actor();if (a->>'manager')::boolean is not true then raise exception 'Récurrences réservées aux administrateurs et modérateurs.' using errcode='42501';end if;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Tâche invalide.';end if;
 if p_unit is null or p_unit not in ('day','week','month') or p_every is null or p_every<1 or p_every>365 then raise exception 'Fréquence invalide (1 à 365).';end if;
 if not exists(select 1 from public.workshop_staff where id=p->>'staffId' and active) then raise exception 'Choisis un collaborateur actif.';end if;
 first_day:=(p->>'due')::date;
 if first_day is null or first_day<(now() at time zone 'Europe/Paris')::date then raise exception 'La première échéance récurrente doit être aujourd’hui ou plus tard.';end if;
 if p_until<first_day then raise exception 'La date de fin doit suivre la première échéance.';end if;
 lock table public.workshop_task_series in share row exclusive mode;
 if (select count(*) from public.workshop_task_series where active)>=500 then raise exception 'Maximum 500 récurrences actives.';end if;
 next_day:=workshop_private.recurrence_date(first_day,p_unit,p_every,1);
 insert into public.workshop_task_series(title,details,staff_id,priority,starts_on,unit,every,ends_on,next_due,active)
 values(trim(p->>'title'),coalesce(p->>'details',''),p->>'staffId',p->>'priority',first_day,p_unit,p_every,p_until,next_day,p_until is null or next_day<=p_until) returning id into series_id;
 insert into public.workshop_tasks(title,details,staff_id,due,priority,recurrence_id,occurrence_date)
 values(trim(p->>'title'),coalesce(p->>'details',''),p->>'staffId',first_day,p->>'priority',series_id,first_day) returning id into task_id;
 return jsonb_build_object('id',task_id,'recurrence_id',series_id);
end $$;
create or replace function public.workshop_list_recurring_tasks() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin a:=workshop_private.actor();if (a->>'manager')::boolean is not true then raise exception 'Accès réservé aux gestionnaires.' using errcode='42501';end if;
 return (select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('staff_name',s.name) order by r.active desc,r.next_due,r.title),'[]') from public.workshop_task_series r join public.workshop_staff s on s.id=r.staff_id where s.active);
end $$;
create or replace function public.workshop_stop_recurring_task(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin a:=workshop_private.actor();if (a->>'manager')::boolean is not true then raise exception 'Accès réservé aux gestionnaires.' using errcode='42501';end if;
 update public.workshop_task_series set active=false where id=p_id;
 if not found then raise exception 'Récurrence introuvable.';end if;
end $$;
create or replace function workshop_private.generate_recurring_tasks(p_today date default (now() at time zone 'Europe/Paris')::date)
returns integer language plpgsql security definer set search_path='' as $$
declare r public.workshop_task_series%rowtype; n integer:=0; next_day date;
begin
 lock table public.workshop_staff in share mode;
 for r in select series.* from public.workshop_task_series series join public.workshop_staff s on s.id=series.staff_id where series.active and s.active and series.next_due<=p_today order by series.next_due for update of series skip locked loop
  while r.next_due<=p_today and (r.ends_on is null or r.next_due<=r.ends_on) and n<500 loop
   insert into public.workshop_tasks(title,details,staff_id,due,priority,recurrence_id,occurrence_date)
   values(r.title,r.details,r.staff_id,r.next_due,r.priority,r.id,r.next_due) on conflict do nothing;
   n:=n+1;r.next_index:=r.next_index+1;
   r.next_due:=workshop_private.recurrence_date(r.starts_on,r.unit,r.every,r.next_index);
  end loop;
  update public.workshop_task_series set next_index=r.next_index,next_due=r.next_due,active=(r.ends_on is null or r.next_due<=r.ends_on) where id=r.id;
  exit when n>=500;
 end loop;
 return n;
end $$;
revoke all on function workshop_private.generate_recurring_tasks(date) from public,anon,authenticated;
revoke all on function public.workshop_create_recurring_task(jsonb,text,integer,date),public.workshop_list_recurring_tasks(),public.workshop_stop_recurring_task(uuid) from public,anon,authenticated;
grant execute on function public.workshop_create_recurring_task(jsonb,text,integer,date),public.workshop_list_recurring_tasks(),public.workshop_stop_recurring_task(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
