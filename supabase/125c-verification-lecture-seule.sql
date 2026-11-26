begin read only;
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'table_essai_prive_presente',to_regclass('workshop_private.plan_preview125')is not null,
 'rls_essai_prive_active',coalesce((select relrowsecurity from pg_class where oid=to_regclass('workshop_private.plan_preview125')),false),
 'essai_interdit_anonyme',not has_function_privilege('anon','public.workshop_plan_preview125(jsonb,integer)','EXECUTE'),
 'horaires_interdits_anonymes',not has_function_privilege('anon','public.workshop_save_schedule125(text,date,text,jsonb,jsonb)','EXECUTE'),
 'statut_formation_autorise',exists(select 1 from pg_constraint where conrelid='public.workshop_days'::regclass
  and conname='workshop_days_presence_check'and position('''training'''in pg_get_expr(conbin,conrelid))>0),
 'journees_en_formation',(select count(*)from public.workshop_days where presence='training')
)as verification125;
commit;
