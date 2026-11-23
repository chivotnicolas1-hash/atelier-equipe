-- Vérification finale uniquement : aucune écriture ni appel de génération.
select jsonb_build_object(
 'heure_paris',now() at time zone 'Europe/Paris',
 'regle_annulation_installee',coalesce((select position('plan_retry_allowed120' in p.prosrc)>0
  from pg_proc p where p.oid=to_regprocedure('workshop_private.plan_automatic118(timestamptz)')),false),
 'sauvegardes_definitions',(select count(*)from workshop_private.plan_code_backup120),
 'ancien_acces_client_verrouille',not has_function_privilege('authenticated',
  'public.workshop_plan_edit_before120(date,text,integer,text,text,boolean)','EXECUTE'),
 'fonctions_admin',(select jsonb_agg(jsonb_build_object('fonction',p.oid::regprocedure::text,
  'appel_anonyme',has_function_privilege('anon',p.oid,'EXECUTE'),
  'appel_connecte',has_function_privilege('authenticated',p.oid,'EXECUTE')))
  from pg_proc p where p.oid in(to_regprocedure('public.workshop_catalog_code88(text,uuid,text,text,text)'),to_regprocedure('public.workshop_monthly82(date)'))),
 'programme',(select coalesce(jsonb_agg(jsonb_build_object('active',active,'schedule',schedule,
  'commande_attendue',btrim(command)='select workshop_private.plan_tick120();')),'[]'::jsonb)
  from cron.job where jobname='atelier-plan-brouillon-118'),
 'dernier_controle',(select jsonb_build_object('checked_at',checked_at,'state',state,'error_code',error_code) from workshop_private.plan_checks120 where date=(now() at time zone 'Europe/Paris')::date),
 'jour_actuel',(select jsonb_build_object('kind',r.kind,'created_at',r.created_at,'finished_at',r.finished_at)
  from workshop_private.plan_runs118 r where r.date=(now() at time zone 'Europe/Paris')::date),
 'relance_possible_aujourdhui',workshop_private.plan_retry_allowed120((now() at time zone 'Europe/Paris')::date,now()),
 'brouillon_actuel',exists(select 1 from public.workshop_plan_drafts where date=(now() at time zone 'Europe/Paris')::date)
)as verification120;
