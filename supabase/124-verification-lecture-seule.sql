-- À exécuter après 124-habilitation-clim.sql. Aucune donnée personnelle affichée.
begin read only;
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'table_habilitations_presente',to_regclass('workshop_private.staff_aircon124')is not null,
 'rls_habilitations_active',coalesce((select relrowsecurity from pg_class where oid=to_regclass('workshop_private.staff_aircon124')),false),
 'gestion_interdite_anonymes',not has_function_privilege('anon','public.workshop_staff_aircon124(text,boolean,integer)','EXECUTE'),
 'detail_ecran_interdit_anonymes_sans_jeton',not has_function_privilege('anon','public.workshop_screen_aircon124()','EXECUTE'),
 'lecture_ecran_par_jeton_active',has_function_privilege('anon','public.workshop_screen_read124(text,date)','EXECUTE'),
 'agregation_privee_verrouillee',not has_function_privilege('anon','workshop_private.screen_aircon124()','EXECUTE')
  and not has_function_privilege('authenticated','workshop_private.screen_aircon124()','EXECUTE'),
 'habilitations_actives',(select count(*)from workshop_private.staff_aircon124 where enabled)
)as verification124;
commit;
