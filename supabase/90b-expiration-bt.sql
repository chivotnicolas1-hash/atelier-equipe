-- Le rappel « Véhicule à faire reprendre ? » expire après une heure sans fiche envoyée.
-- Les notifications portant sur un BT réellement transmis ne sont pas supprimées.
begin;
create or replace function workshop_private.expire_lunch90(p_now timestamptz) returns integer language plpgsql security definer set search_path='' as $$
declare n integer;begin
 if p_now is null then return 0;end if;
 with expired as (
 select m.id,m.user_id,m.body,m.url from public.workshop_messages m
 where m.event_key like 'lunch:%' and m.body='Véhicule à faire reprendre ?'
 and m.created_at+interval '1 hour'<=p_now
 and not exists(select 1 from public.workshop_lunch_handoffs h where h.user_id=m.user_id
 and h.date::text=substring(m.event_key from 7) and h.created_at<=m.created_at+interval '1 hour')
 ), queued as (
 delete from public.workshop_push_queue q using public.workshop_push_subscriptions s,expired e
 where q.subscription_id=s.id and s.user_id=e.user_id and q.kind='message' and q.body=e.body and q.url=e.url returning q.id
 ) delete from public.workshop_messages m using expired e where m.id=e.id;
 get diagnostics n=row_count;return n;
end $$;
do $$begin if to_regprocedure('public.workshop_message_status_before90(uuid)') is null then alter function public.workshop_message_status(uuid) rename to workshop_message_status_before90;end if;end $$;
create or replace function public.workshop_message_status(p_read uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor_before30();perform workshop_private.expire_lunch90(now());return public.workshop_message_status_before90(p_read);end $$;
revoke all on function workshop_private.expire_lunch90(timestamptz),public.workshop_message_status_before90(uuid),public.workshop_message_status(uuid) from public,anon,authenticated;
grant execute on function public.workshop_message_status(uuid) to authenticated;
-- Le planificateur déjà utilisé pour les notifications est conservé.
create extension if not exists pg_cron;
do $$declare j record;begin for j in select jobid from cron.job where jobname='atelier-expiration-bt90' loop perform cron.unschedule(j.jobid);end loop;perform cron.schedule('atelier-expiration-bt90','* * * * *','select workshop_private.expire_lunch90(now());');end $$;
select workshop_private.expire_lunch90(now());
notify pgrst,'reload schema';commit;
