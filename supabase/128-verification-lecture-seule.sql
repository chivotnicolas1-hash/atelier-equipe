begin read only;
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'controle_notifications_present',to_regprocedure('public.workshop_notification_access128()')is not null,
 'controle_interdit_anonyme',not has_function_privilege('anon','public.workshop_notification_access128()','EXECUTE'),
 'declencheur_signalement_present',exists(select 1 from pg_trigger where tgrelid='public.workshop_reports'::regclass and tgname='workshop_report_created128'and not tgisinternal),
 'declencheur_prive_verrouille',not has_function_privilege('authenticated','workshop_private.report_created128()','EXECUTE')and not has_function_privilege('anon','workshop_private.report_created128()','EXECUTE'),
 'messages_signalement_enregistres',(select count(*)from public.workshop_messages where event_key like'report-created128:%')
)as verification128;
commit;
