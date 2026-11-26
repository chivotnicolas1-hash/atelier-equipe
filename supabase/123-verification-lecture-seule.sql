-- Contrôles de métadonnées uniquement ; aucune vente ni fiche contact créée.
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'routage_recap122_present',to_regprocedure('workshop_private.recap_recipient122(date,text,timestamptz)')is not null,
 'table_contacts_presente',to_regclass('workshop_private.waste_contacts123')is not null,
 'rls_contacts_active',coalesce((select relrowsecurity from pg_class where oid=to_regclass('workshop_private.waste_contacts123')),false),
 'fiches_contact_enregistrees',(select count(*)from workshop_private.waste_contacts123),
 'contacts_interdits_anonymes',not has_function_privilege('anon','public.workshop_waste_contact123(text)','EXECUTE')
  and not has_function_privilege('anon','public.workshop_waste_contact_save123(text,integer,text,text,text,text)','EXECUTE'),
 'detail_ecran_interdit_anonyme_sans_jeton',not has_function_privilege('anon','public.workshop_screen_sales123(date)','EXECUTE'),
 'lecture_ecran_par_jeton_active',has_function_privilege('anon','public.workshop_screen_read123(text,date)','EXECUTE'),
 'agregation_privee_verrouillee',not has_function_privilege('anon','workshop_private.screen_sales123(date)','EXECUTE')
  and not has_function_privilege('authenticated','workshop_private.screen_sales123(date)','EXECUTE'),
 'detail_ecran_du_jour',(select jsonb_build_object('categories',coalesce((select count(*)from jsonb_object_keys(r->'contributors123')),0),
  'derniere_vente',r->'last_sale_at123')from(select workshop_private.screen_sales123((now()at time zone'Europe/Paris')::date)r)x)
)as verification123;
