begin read only;
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'colonne_type_presente',exists(select 1 from pg_attribute where attrelid='public.workshop_stations'::regclass and attname='lift_kind'and not attisdropped),
 'contrainte_type_presente',exists(select 1 from pg_constraint where conrelid='public.workshop_stations'::regclass and conname='workshop_stations_lift_kind126_check'),
 'modification_interdite_anonyme',not has_function_privilege('anon','public.workshop_save_station126(text,integer,text,text,integer,integer,boolean,boolean,boolean,text)','EXECUTE'),
 'lecture_ecran_par_jeton_active',has_function_privilege('anon','public.workshop_screen_read126(text,date)','EXECUTE'),
 'types_renseignes',(select count(*)from public.workshop_stations where active and not office and lift_kind<>'unknown'),
 'types_a_preciser',(select count(*)from public.workshop_stations where active and not office and lift_kind='unknown')
)as verification126;
commit;
