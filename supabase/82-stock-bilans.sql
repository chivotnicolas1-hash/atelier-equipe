begin;
-- Un état de stock porte sur un produit, jamais sur la version du classement.
create or replace function public.workshop_stock82(p_kind text,p_id text,p_state boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;s text;v int;old_v int;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 if p_state is null then raise exception 'État du stock requis.';end if;
 if p_kind='catalog' then
  select section into s from workshop_private.catalog75 where id::text=p_id;
  if not found then raise exception 'Cet article a été retiré du catalogue.';end if;
  perform 1 from workshop_private.catalog75_rev where section=s for update;
  update workshop_private.catalog75 set unavailable=p_state where id::text=p_id;
  if not found then raise exception 'Cet article a été retiré du catalogue.';end if;
  update workshop_private.catalog75_rev set rev=rev+1 where section=s;
  return jsonb_build_object('unavailable',p_state);
 elsif p_kind='oil' then
  select version into old_v from workshop_private.oil_catalog72 where id=1 for update;
  if not exists(select 1 from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) o where o->>'id'=p_id) then raise exception 'Enregistre d’abord cette référence dans le plan.';end if;
  update workshop_private.oil_catalog72 t set items=(select jsonb_agg(case when o->>'id'=p_id then o||jsonb_build_object('unavailable',p_state) else o end order by ord) from jsonb_array_elements(t.items) with ordinality x(o,ord)),version=version+1 where id=1 returning version into v;
  return jsonb_build_object('unavailable',p_state,'version',v,'previous_version',old_v);
 end if;raise exception 'Catalogue inconnu.';
end $$;
create or replace function public.workshop_stock76(p_id uuid,p_state boolean,p_rev integer) returns void language plpgsql security definer set search_path='' as $$begin perform public.workshop_stock82('catalog',p_id::text,p_state);end $$;
revoke all on function public.workshop_stock82(text,text,boolean),public.workshop_stock76(uuid,boolean,integer) from public,anon;
grant execute on function public.workshop_stock82(text,text,boolean),public.workshop_stock76(uuid,boolean,integer) to authenticated;

create or replace function workshop_private.working_day82(p_date date) returns boolean language plpgsql immutable set search_path='' as $$
declare y int:=extract(year from p_date);a int;b int;c int;d int;e int;f int;g int;h int;i int;k int;l int;m int;easter date;begin
 if extract(isodow from p_date)=7 or to_char(p_date,'MM-DD')=any(array['01-01','05-01','05-08','07-14','08-15','11-01','11-11','12-25']) then return false;end if;
 a:=y%19;b:=y/100;c:=y%100;d:=b/4;e:=b%4;f:=(b+8)/25;g:=(b-f+1)/3;h:=(19*a+b-d-g+15)%30;i:=c/4;k:=c%4;l:=(32+2*e+2*i-h-k)%7;m:=(a+11*h+22*l)/451;
 easter:=make_date(y,(h+l-7*m+114)/31,(h+l-7*m+114)%31+1);
 return p_date<>all(array[easter+1,easter+39,easter+50]);
end $$;
create or replace function workshop_private.first_workday82(p_month date) returns date language plpgsql immutable set search_path='' as $$declare d date:=date_trunc('month',p_month)::date;begin while not workshop_private.working_day82(d) loop d:=d+1;end loop;return d;end $$;

create or replace function public.workshop_monthly82(p_month date default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;m date:=date_trunc('month',coalesce(p_month,(now() at time zone 'Europe/Paris')::date-interval '1 month'))::date;n date;d date;q jsonb:='[]';begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Bilan réservé à l’administrateur.' using errcode='42501';end if;
 n:=(m+interval '1 month')::date;
 if m<date '2020-01-01' or (now() at time zone 'Europe/Paris')::date<workshop_private.first_workday82(n) then raise exception 'Ce mois n’est pas encore disponible.';end if;
 d:=m;while d<n loop q:=q||coalesce(public.workshop_quality_history(d),'[]');d:=d+1;end loop;
 return jsonb_build_object('month',m,'generated_at',now(),
 'staff',(select coalesce(jsonb_agg(jsonb_build_object('id',u.id,'name',s.name) order by s.name),'[]') from public.workshop_staff s left join auth.users u on lower(u.email)=lower(s.email) where s.active and coalesce(s.role,'employee') not in ('guest','director')),
 'sales',(select coalesce(jsonb_agg(to_jsonb(x) order by x.author_name,x.category),'[]') from (select user_id,max(author_name) author_name,category,sum(quantity) quantity from public.workshop_target_sales where date>=m and date<n and deleted_at is null and category in ('purge','batteries','geometry','clim') group by user_id,category) x),
 'quality',(select coalesce(jsonb_agg(to_jsonb(x) order by x.author_name),'[]') from (select coalesce(v->>'user_id',v->>'author_id',v->>'author_name','Inconnu') person,max(coalesce(v->>'author_name','Non renseigné')) author_name,count(*) quantity from jsonb_array_elements(q) v group by coalesce(v->>'user_id',v->>'author_id',v->>'author_name','Inconnu')) x),
 'reports',(select count(*) from public.workshop_reports r where r.created_at>=m::timestamp at time zone 'Europe/Paris' and r.created_at<n::timestamp at time zone 'Europe/Paris' and to_jsonb(r)->>'deleted_at' is null),
 'waste',(select coalesce(jsonb_agg(to_jsonb(w) order by provider,created_at),'[]') from public.workshop_waste w where collected_at is null));
end $$;
revoke all on function public.workshop_monthly82(date) from public,anon;
grant execute on function public.workshop_monthly82(date) to authenticated;

do $$begin if to_regprocedure('workshop_private.schedule_messages_before82(timestamp with time zone)') is null then alter function workshop_private.schedule_messages(timestamptz) rename to schedule_messages_before82;end if;end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone 'Europe/Paris')::date;m date;u record;begin
 perform workshop_private.schedule_messages_before82(p_now);m:=date_trunc('month',d)::date;
 if d>=workshop_private.first_workday82(m) and (p_now at time zone 'Europe/Paris')::time>=time '08:30' then
  for u in select id from auth.users where lower(email)='nchivot@norauto.fr' loop
   perform workshop_private.message(u.id,'Le bilan mensuel de l’atelier est disponible','/?notifications=recap&monthly='||to_char(m-interval '1 month','YYYY-MM'),'monthly82:'||m::text);
  end loop;
 end if;
end $$;

create table if not exists workshop_private.morning_seen82(user_id uuid not null,day date not null,recap_date date not null,seen_at timestamptz not null default now(),primary key(user_id,day));
alter table workshop_private.morning_seen82 enable row level security;revoke all on workshop_private.morning_seen82 from public,anon,authenticated;
create or replace function workshop_private.morning82(p_now timestamptz,p_ack date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;d date:=(p_now at time zone 'Europe/Paris')::date;t time:=(p_now at time zone 'Europe/Paris')::time;first_time time;mine time;r public.workshop_handover%rowtype;begin
 a:=workshop_private.actor_before30();
 if not exists(select 1 from public.workshop_staff s where s.id=a->>'self' and s.active and lower(trim(s.team))='encadrants') then return null;end if;
 select min((slot->>'start')::time) into first_time from public.workshop_days day join public.workshop_staff s on s.id=day.staff_id cross join lateral jsonb_array_elements(day.slots) slot where day.date=d and day.presence='present' and s.active and lower(trim(s.team))='encadrants' and not exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods) p where l.staff_id=s.id and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date);
 select min((slot->>'start')::time) into mine from public.workshop_days day cross join lateral jsonb_array_elements(day.slots) slot where day.date=d and day.staff_id=a->>'self' and day.presence='present';
 if mine is null or mine is distinct from first_time or exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods) p where l.staff_id=a->>'self' and l.status='accepted' and d between (p->>'start')::date and (p->>'end')::date) then return null;end if;
 select * into r from public.workshop_handover where (release_at at time zone 'Europe/Paris')::date=d and release_at<=p_now and date<d order by date desc limit 1;
 if not found then return null;end if;
 if p_ack is not null then
  if p_ack<>r.date then raise exception 'Récapitulatif incorrect.';end if;
  insert into workshop_private.morning_seen82(user_id,day,recap_date) values(auth.uid(),d,r.date) on conflict(user_id,day) do nothing;return null;
 end if;
 if exists(select 1 from workshop_private.morning_seen82 where user_id=auth.uid() and day=d) then return null;end if;
 if not exists(select 1 from public.workshop_days day cross join lateral jsonb_array_elements(day.slots) slot where day.date=d and day.staff_id=a->>'self' and day.presence='present' and t>=(slot->>'start')::time and t<(slot->>'end')::time) then return null;end if;
 return jsonb_build_object('date',r.date,'vehicles',r.vehicles,'missing_parts',r.missing_parts,'tasks',r.tasks,'author_name',r.author_name,'day',d);
end $$;
create or replace function public.workshop_morning82(p_ack date default null) returns jsonb language sql security definer set search_path='' as $$select workshop_private.morning82(now(),p_ack)$$;
revoke all on function public.workshop_morning82(date) from public,anon;
grant execute on function public.workshop_morning82(date) to authenticated;
revoke all on function workshop_private.morning82(timestamptz,date),workshop_private.working_day82(date),workshop_private.first_workday82(date),workshop_private.schedule_messages(timestamptz),workshop_private.schedule_messages_before82(timestamptz) from public,anon,authenticated;
notify pgrst,'reload schema';commit;
