-- MAJ34 : appliquer après MAJ33. Réexécutable.
begin;
alter table public.workshop_push_queue add column if not exists body text;
alter table public.workshop_push_queue add column if not exists url text;
create table if not exists public.workshop_messages(id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,body text not null,url text not null default '/',event_key text,created_at timestamptz not null default now(),read_at timestamptz,unique(user_id,event_key));
create table if not exists public.workshop_recap_reads(user_id uuid primary key references auth.users(id) on delete cascade,last_date date not null);
create table if not exists public.workshop_password_requests(id uuid primary key default gen_random_uuid(),staff_id text not null references public.workshop_staff(id),recipients uuid[] not null,created_at timestamptz not null default now(),resolved_at timestamptz,resolved_by uuid references auth.users(id) on delete set null);
alter table public.workshop_messages enable row level security;
alter table public.workshop_recap_reads enable row level security;
alter table public.workshop_password_requests enable row level security;
revoke all on public.workshop_messages,public.workshop_recap_reads,public.workshop_password_requests from public,anon,authenticated;
create or replace function workshop_private.message(p_user uuid,p_body text,p_url text,p_key text) returns void language plpgsql security definer set search_path='' as $$
declare v_id uuid;
begin
 insert into public.workshop_messages(user_id,body,url,event_key) values(p_user,p_body,p_url,p_key) on conflict(user_id,event_key) do nothing returning id into v_id;
 if v_id is not null then insert into public.workshop_push_queue(subscription_id,kind,body,url) select id,'message',p_body,p_url from public.workshop_push_subscriptions where user_id=p_user;end if;
end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone 'Europe/Paris')::date; t time:=(p_now at time zone 'Europe/Paris')::time; recipient record;
begin
 for recipient in select distinct a.id from auth.users a left join public.workshop_staff s on s.email=lower(a.email) and s.active where lower(a.email)='nchivot@norauto.fr' or s.role='moderator' loop
 if t>=time '07:30' and exists(select 1 from public.workshop_handover where date=d-1 and release_at<=p_now) then perform workshop_private.message(recipient.id,'Le récapitulatif de la veille est disponible','/?notifications=recap','recap:'||(d-1)::text);end if;
 if t>=time '18:30' and not exists(select 1 from public.workshop_handover where date=d) then perform workshop_private.message(recipient.id,'Pense à faire ton récapitulatif','/?notifications=recap','reminder:'||d::text);end if;
 end loop;
end $$;
create or replace function public.workshop_message_status(p_read uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;latest date;
begin
 a:=workshop_private.actor_before30();
 if p_read is not null then update public.workshop_messages set read_at=coalesce(read_at,now()) where id=p_read and user_id=auth.uid();end if;
 if coalesce((a->>'manager')::boolean,false) then select max(date) into latest from public.workshop_handover where release_at<=now();end if;
 return jsonb_build_object('recap_date',latest,'recap_unread',coalesce(latest>(select last_date from public.workshop_recap_reads where user_id=auth.uid()),latest is not null),'items',(select coalesce(jsonb_agg(to_jsonb(m) order by created_at desc),'[]') from (select id,body,url,created_at,read_at from public.workshop_messages where user_id=auth.uid() order by created_at desc limit 100)m));
end $$;
create or replace function public.workshop_recap_read(p_date date) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé.';end if;
 if not exists(select 1 from public.workshop_handover where date=p_date and release_at<=now()) then raise exception 'Récapitulatif indisponible.';end if;
 insert into public.workshop_recap_reads values(auth.uid(),p_date) on conflict(user_id) do update set last_date=greatest(workshop_recap_reads.last_date,excluded.last_date);
end $$;
create or replace function public.workshop_send_message(p_staff text[],p_body text,p_id uuid) returns integer language plpgsql security definer set search_path='' as $$
declare a jsonb;recipient record;n integer:=0;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Envoi réservé aux gestionnaires.' using errcode='42501';end if;
 if p_id is null or p_body is null or length(trim(p_body)) not between 1 and 500 or p_staff is null or cardinality(p_staff) not between 1 and 200 then raise exception 'Sélectionne les destinataires et un message (500 caractères maximum).';end if;
 if exists(select 1 from unnest(p_staff) x where not exists(select 1 from public.workshop_staff s where s.id=x and s.active)) then raise exception 'Un destinataire n’est plus actif.';end if;
 for recipient in select distinct u.id from public.workshop_staff s join auth.users u on lower(u.email)=s.email where s.active and s.id=any(p_staff) loop
 perform workshop_private.message(recipient.id,trim(p_body),'/?notifications=inbox','manual:'||auth.uid()::text||':'||p_id::text);n:=n+1;end loop;if n=0 then raise exception 'Aucun destinataire n’a encore de compte de connexion.';end if;return n;
end $$;
-- Demande sans session : réponse uniforme, un envoi par compte par heure,
-- pas de nouveau doublon tant que la demande reste ouverte ; plafond global.
create or replace function public.workshop_request_password(p_email text) returns void language plpgsql security definer set search_path='' as $$
declare s public.workshop_staff%rowtype;recipients uuid[];v_id uuid;u uuid;
begin
 if p_email is null or length(p_email)>254 then return;end if;
 perform pg_advisory_xact_lock(hashtextextended('password-requests',0));
 select * into s from public.workshop_staff where active and email=lower(trim(p_email)) limit 1;
 if not found or not exists(select 1 from auth.users where lower(email)=s.email) then return;end if;
 if exists(select 1 from public.workshop_password_requests where staff_id=s.id and (resolved_at is null or created_at>now()-interval '1 hour')) or (select count(*) from public.workshop_password_requests where created_at>now()-interval '1 hour')>=30 then return;end if;
 if exists(select 1 from public.workshop_staff a join public.workshop_days d on d.staff_id=a.id where a.email='nchivot@norauto.fr' and a.active and d.date=(now() at time zone 'Europe/Paris')::date and jsonb_array_length(d.slots)>0) then
 select array_agg(id) into recipients from auth.users where lower(email)='nchivot@norauto.fr';
 else select array_agg(u.id) into recipients from auth.users u join public.workshop_staff x on x.email=lower(u.email) where x.active and x.role='moderator' and x.email<>'nchivot@norauto.fr';end if;
 if coalesce(cardinality(recipients),0)=0 then select array_agg(id) into recipients from auth.users where lower(email)='nchivot@norauto.fr';end if;
 insert into public.workshop_password_requests(staff_id,recipients) values(s.id,coalesce(recipients,'{}')) returning id into v_id;
 foreach u in array coalesce(recipients,'{}'::uuid[]) loop perform workshop_private.message(u,'Une demande de nouveau mot de passe est à traiter.','/?notifications=inbox','password:'||v_id::text);end loop;
end $$;
create or replace function public.workshop_password_requests() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé.';end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',s.name,'email',s.email,'created_at',r.created_at) order by r.created_at),'[]') from public.workshop_password_requests r join public.workshop_staff s on s.id=r.staff_id and s.active where r.resolved_at is null and ((a->>'admin')::boolean or (auth.uid()=any(r.recipients) and s.email<>'nchivot@norauto.fr')));
end $$;
create or replace function public.workshop_password_authorize(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_password_requests%rowtype;s public.workshop_staff%rowtype;
begin a:=workshop_private.actor();select * into r from public.workshop_password_requests where id=p_id;select * into s from public.workshop_staff where id=r.staff_id and active;
 if r.id is null or r.resolved_at is not null or s.id is null or not(coalesce((a->>'admin')::boolean,false) or (coalesce((a->>'manager')::boolean,false) and auth.uid()=any(r.recipients) and s.email<>'nchivot@norauto.fr')) then raise exception 'Demande inaccessible.' using errcode='42501';end if;
 return jsonb_build_object('staffId',s.id,'email',s.email);
end $$;
create or replace function public.workshop_password_resolved(p_id uuid,p_actor uuid) returns void language sql security definer set search_path='' as $$update public.workshop_password_requests set resolved_at=now(),resolved_by=p_actor where id=p_id and resolved_at is null$$;
revoke all on function workshop_private.message(uuid,text,text,text),workshop_private.schedule_messages(timestamptz),public.workshop_password_resolved(uuid,uuid) from public,anon,authenticated;
grant execute on function public.workshop_password_resolved(uuid,uuid) to service_role;
revoke all on function public.workshop_message_status(uuid),public.workshop_recap_read(date),public.workshop_send_message(text[],text,uuid),public.workshop_password_requests(),public.workshop_password_authorize(uuid),public.workshop_request_password(text) from public,anon,authenticated;
grant execute on function public.workshop_message_status(uuid),public.workshop_recap_read(date),public.workshop_send_message(text[],text,uuid),public.workshop_password_requests(),public.workshop_password_authorize(uuid) to authenticated;
grant execute on function public.workshop_request_password(text) to anon,authenticated;
create or replace function public.workshop_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 perform workshop_private.schedule_messages(now());
 delete from public.workshop_push_queue where created_at<now()-interval '7 days';
 with candidates as (
 select q.id from public.workshop_push_queue q join public.workshop_push_subscriptions p on p.id=q.subscription_id join auth.users u on u.id=p.user_id
 where q.sent_at is null and q.attempts<5 and q.next_at<=now() and q.created_at>now()-interval '1 day'
 and (lower(u.email)='nchivot@norauto.fr' or exists(select 1 from public.workshop_staff s where s.active and s.email=lower(u.email)))
 and (q.kind in ('announcement','message') or exists(select 1 from public.workshop_tasks t join public.workshop_staff s on s.id=t.staff_id where t.id=q.task_id and t.done=0 and s.active and s.email=lower(u.email)))
 order by q.created_at limit 50 for update of q skip locked
 ), claimed as (update public.workshop_push_queue q set attempts=attempts+1,next_at=now()+interval '5 minutes' from candidates c where q.id=c.id returning q.*)
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('endpoint',p.endpoint,'p256dh',p.p256dh,'auth',p.auth)),'[]') into result from claimed c join public.workshop_push_subscriptions p on p.id=c.subscription_id;
 return result;
end $$;

notify pgrst,'reload schema';
commit;
