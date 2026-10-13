begin;
create table if not exists public.workshop_push_subscriptions (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 endpoint text unique not null, p256dh text not null, auth text not null, updated_at timestamptz not null default now()
);
create table if not exists public.workshop_push_queue (
 id uuid primary key default gen_random_uuid(), subscription_id uuid not null references public.workshop_push_subscriptions(id) on delete cascade,
 task_id uuid references public.workshop_tasks(id) on delete cascade,
 kind text not null, created_at timestamptz not null default now(), attempts integer not null default 0,
 next_at timestamptz not null default now(), sent_at timestamptz, last_error text
);
alter table public.workshop_push_subscriptions enable row level security;
alter table public.workshop_push_queue enable row level security;
revoke all on public.workshop_push_subscriptions,public.workshop_push_queue from public,anon,authenticated;
grant all on public.workshop_push_subscriptions,public.workshop_push_queue to service_role;
create or replace function public.workshop_push_register(p_subscription jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb; ep text:=p_subscription->>'endpoint'; k text:=p_subscription->'keys'->>'p256dh'; h text:=p_subscription->'keys'->>'auth';
begin
 a:=workshop_private.actor();
 if ep is null or length(ep)>2048 or ep !~ '^https://(fcm[.]googleapis[.]com|updates[.]push[.]services[.]mozilla[.]com|[a-z0-9-]+[.]notify[.]windows[.]com|[a-z0-9.-]*push[.]apple[.]com)/[^[:space:]]+$' or k is null or k !~ '^[A-Za-z0-9_-]{87}$' or h is null or h !~ '^[A-Za-z0-9_-]{22}$' then raise exception 'Abonnement de notification invalide.'; end if;
 if (select count(*) from public.workshop_push_subscriptions where user_id=auth.uid() and endpoint<>ep)>=10 then raise exception 'Dix appareils maximum. Désactive les anciens appareils.';end if;
 -- Un navigateur partagé appartient au dernier compte qui active les notifications.
 delete from public.workshop_push_subscriptions where endpoint=ep and user_id<>auth.uid();
 insert into public.workshop_push_subscriptions(user_id,endpoint,p256dh,auth) values(auth.uid(),ep,k,h)
 on conflict(endpoint) do update set p256dh=excluded.p256dh,auth=excluded.auth,updated_at=now();
end $$;
create or replace function public.workshop_push_remove(p_endpoint text) returns void language plpgsql security definer set search_path='' as $$
begin delete from public.workshop_push_subscriptions where user_id=auth.uid() and endpoint=p_endpoint;end $$;
create or replace function public.workshop_push_status() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin a:=workshop_private.actor();
 return jsonb_build_object('endpoints',(select coalesce(jsonb_agg(endpoint),'[]') from public.workshop_push_subscriptions where user_id=auth.uid()),'team',case when (a->>'admin')::boolean then
 (select coalesce(jsonb_agg(jsonb_build_object('name',s.name,'devices',(select count(*) from public.workshop_push_subscriptions p join auth.users u on u.id=p.user_id where lower(u.email)=s.email)) order by s.name),'[]') from public.workshop_staff s where s.active) else '[]'::jsonb end);
end $$;
create or replace function workshop_private.enqueue_push() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_NAME='workshop_announcement' then
  if not new.enabled then return new; end if;
  if TG_OP='UPDATE' then if old.enabled and (new.message,new.link_url,new.link_label) is not distinct from (old.message,old.link_url,old.link_label) then return new; end if;end if;
  insert into public.workshop_push_queue(subscription_id,kind)
   select p.id,'announcement' from public.workshop_push_subscriptions p join auth.users u on u.id=p.user_id
   where lower(u.email)='nchivot@norauto.fr' or exists(select 1 from public.workshop_staff s where s.active and s.email=lower(u.email));
 else
  if new.done=1 then return new;end if;
  if TG_OP='UPDATE' then if (new.title,new.details,new.staff_id,new.due,new.priority,new.done) is not distinct from (old.title,old.details,old.staff_id,old.due,old.priority,old.done) then return new;end if;end if;
  insert into public.workshop_push_queue(subscription_id,kind,task_id)
   select p.id,'task',new.id from public.workshop_push_subscriptions p join auth.users u on u.id=p.user_id join public.workshop_staff s on s.email=lower(u.email)
   where s.active and s.id=new.staff_id;
 end if;
 return new;
end $$;
revoke all on function workshop_private.enqueue_push() from public,anon,authenticated;
drop trigger if exists workshop_announcement_push on public.workshop_announcement;
create trigger workshop_announcement_push after insert or update on public.workshop_announcement for each row execute function workshop_private.enqueue_push();
drop trigger if exists workshop_task_push on public.workshop_tasks;
create trigger workshop_task_push after insert or update on public.workshop_tasks for each row execute function workshop_private.enqueue_push();
create or replace function public.workshop_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 delete from public.workshop_push_queue where created_at<now()-interval '7 days';
 with candidates as (
 select q.id from public.workshop_push_queue q join public.workshop_push_subscriptions p on p.id=q.subscription_id join auth.users u on u.id=p.user_id
 where q.sent_at is null and q.attempts<5 and q.next_at<=now() and q.created_at>now()-interval '1 day'
 and (lower(u.email)='nchivot@norauto.fr' or exists(select 1 from public.workshop_staff s where s.active and s.email=lower(u.email)))
 and (q.kind='announcement' or exists(select 1 from public.workshop_tasks t join public.workshop_staff s on s.id=t.staff_id where t.id=q.task_id and t.done=0 and s.active and s.email=lower(u.email)))
 order by q.created_at limit 50 for update of q skip locked
 ), claimed as (update public.workshop_push_queue q set attempts=attempts+1,next_at=now()+interval '5 minutes' from candidates c where q.id=c.id returning q.*)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('endpoint',p.endpoint,'p256dh',p.p256dh,'auth',p.auth)),'[]') into result from claimed c join public.workshop_push_subscriptions p on p.id=c.subscription_id;
 return result;
end $$;
revoke all on function public.workshop_push_claim() from public,anon,authenticated;
grant execute on function public.workshop_push_claim() to service_role;
revoke all on function public.workshop_push_register(jsonb),public.workshop_push_remove(text),public.workshop_push_status() from public,anon,authenticated;
grant execute on function public.workshop_push_register(jsonb),public.workshop_push_remove(text),public.workshop_push_status() to authenticated;
notify pgrst,'reload schema';
commit;
