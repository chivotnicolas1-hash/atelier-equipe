-- MAJ128 : contrôle d'usage des notifications et alertes sur les futurs signalements.
-- Pas d'envoi rétroactif, pas de modification des anciennes fiches.
begin;
do $$begin
 if to_regprocedure('workshop_private.message(uuid,text,text,text)')is null
 or to_regprocedure('workshop_private.actor_before30()')is null
 or to_regprocedure('workshop_private.scheduled_minutes118(jsonb)')is null
 or to_regclass('workshop_private.accounts100')is null
 or to_regclass('public.workshop_reports')is null or to_regclass('public.workshop_messages')is null
 or to_regclass('public.workshop_push_subscriptions')is null or to_regclass('public.workshop_push_queue')is null then
  raise exception 'Prérequis notifications, comptes par ID ou horaires absents.';
 end if;
end $$;
create or replace function public.workshop_notification_access128()
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();
 if not exists(select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self'and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now()))then
  raise exception 'Compte suspendu ou accès indisponible.' using errcode='42501';
 end if;
 return jsonb_build_object('required',coalesce(a->>'role','employee')<>'guest','endpoints',case when a->>'role'='guest'then'[]'::jsonb else
  (select coalesce(jsonb_agg(endpoint),'[]')from public.workshop_push_subscriptions where user_id=auth.uid())end);
end $$;
revoke all on function public.workshop_notification_access128()from public,anon,authenticated;
grant execute on function public.workshop_notification_access128()to authenticated;

create or replace function workshop_private.report_created128()
returns trigger language plpgsql security definer set search_path='' as $$
declare recipient record;d date:=(new.created_at at time zone'Europe/Paris')::date;begin
 -- Un seul événement par utilisateur et par nouvelle fiche. Le moteur message existant
 -- remplit à la fois la boîte Mes notifications et la file mobile.
 for recipient in
  select distinct a.user_id
  from public.workshop_days dy join public.workshop_staff s on s.id=dy.staff_id
  join workshop_private.accounts100 a on a.staff_id=s.id join auth.users u on u.id=a.user_id
  where dy.date=d and dy.presence='present'and workshop_private.scheduled_minutes118(dy.slots)>0
  and s.active and not coalesce(s.suspended,false)and s.role not in('guest','director')
  and lower(btrim(coalesce(s.team,'')))='encadrants'
  and u.email_confirmed_at is not null and(u.banned_until is null or u.banned_until<=now())
  and not exists(select 1 from public.workshop_leave_requests l
   cross join lateral jsonb_array_elements(case when jsonb_typeof(l.periods)='array'then l.periods else'[]'::jsonb end)p
   where l.staff_id=s.id and l.status='accepted'and d between(p->>'start')::date and(p->>'end')::date)
 loop
  perform workshop_private.message(recipient.user_id,
   'Un nouveau signalement véhicule a été créé par '||coalesce(nullif(btrim(new.author_name),''),'un collaborateur')||'.',
   '/?notifications=reports','report-created128:'||new.id::text);
 end loop;
 return new;
end $$;
revoke all on function workshop_private.report_created128()from public,anon,authenticated;
drop trigger if exists workshop_report_created128 on public.workshop_reports;
create trigger workshop_report_created128 after insert on public.workshop_reports for each row execute function workshop_private.report_created128();
notify pgrst,'reload schema';
commit;
