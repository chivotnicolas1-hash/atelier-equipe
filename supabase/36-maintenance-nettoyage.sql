-- MAJ36 : après MAJ34/35. Réexécutable.
begin;
create table if not exists public.workshop_maintenance(id integer primary key check(id=1),enabled boolean not null default false,updated_at timestamptz not null default now());
insert into public.workshop_maintenance(id) values(1) on conflict do nothing;
alter table public.workshop_maintenance enable row level security;
revoke all on public.workshop_maintenance from public,anon,authenticated;
do $$begin if to_regprocedure('workshop_private.actor_before36()') is null then alter function workshop_private.actor_before30() rename to actor_before36;end if;end $$;
revoke all on function workshop_private.actor_before36() from public,anon,authenticated;
create or replace function workshop_private.actor_before30() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before36();
 if not coalesce((a->>'admin')::boolean,false) and (select enabled from public.workshop_maintenance where id=1) then raise exception 'Application en maintenance. Réessaie dans quelques instants.' using errcode='42501';end if;return a;end $$;
revoke all on function workshop_private.actor_before30() from public,anon,authenticated;
create or replace function public.workshop_maintenance_status() returns jsonb language sql security definer set search_path='' as $$
 select jsonb_build_object('enabled',enabled,'admin',exists(select 1 from auth.users where id=auth.uid() and lower(email)='nchivot@norauto.fr' and email_confirmed_at is not null)) from public.workshop_maintenance where id=1
$$;
create or replace function public.workshop_set_maintenance(p_enabled boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before36();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Maintenance réservée à l’administrateur.' using errcode='42501';end if;if p_enabled is null then raise exception 'Choix requis.';end if;update public.workshop_maintenance set enabled=p_enabled,updated_at=now() where id=1;end $$;
create or replace function public.workshop_purge_old_reports(p_confirm boolean default false,p_before timestamptz default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;cutoff timestamptz:=coalesce(p_before,now()-interval '720 hours');reports integer;photos integer;
begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Suppression groupée réservée à l’administrateur.' using errcode='42501';end if;
 if p_confirm is null or cutoff>now()-interval '720 hours' or (p_confirm and p_before is null) then raise exception 'La limite doit être antérieure à 30 jours.';end if;
 if p_confirm then perform id from public.workshop_reports where created_at<cutoff for update;end if;
 select count(*) into reports from public.workshop_reports where created_at<cutoff;
 select count(*) into photos from public.workshop_report_photos p join public.workshop_reports r on r.id=p.report_id where r.created_at<cutoff;
 if p_confirm then delete from public.workshop_reports where created_at<cutoff;end if;
 -- workshop_report_photos : ON DELETE CASCADE ; exemple invité : ON DELETE SET NULL.
 return jsonb_build_object('before',cutoff,'reports',reports,'photos',photos,'deleted',p_confirm);
end $$;
revoke all on function public.workshop_maintenance_status(),public.workshop_set_maintenance(boolean),public.workshop_purge_old_reports(boolean,timestamptz) from public,anon,authenticated;
grant execute on function public.workshop_maintenance_status() to anon,authenticated;
grant execute on function public.workshop_set_maintenance(boolean),public.workshop_purge_old_reports(boolean,timestamptz) to authenticated;
create or replace function public.workshop_request_password(p_email text) returns void language plpgsql security definer set search_path='' as $$
declare s public.workshop_staff%rowtype;recipients uuid[];v_id uuid;u uuid;
begin
 if (select enabled from public.workshop_maintenance where id=1) then return;end if;
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
create or replace function public.workshop_push_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 if (select enabled from public.workshop_maintenance where id=1) then return '[]'::jsonb;end if;
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
