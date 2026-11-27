begin read only;
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'fonction_non_affectes_presente',to_regprocedure('public.workshop_move127(date,text,text,text,text,boolean,integer)')is not null,
 'appel_anonyme_interdit',not has_function_privilege('anon','public.workshop_move127(date,text,text,text,text,boolean,integer)','EXECUTE'),
 'appel_connecte_autorise',has_function_privilege('authenticated','public.workshop_move127(date,text,text,text,text,boolean,integer)','EXECUTE'),
 'moteur_deplacement_conserve',to_regprocedure('public.workshop_move119(date,text,text,text,text,boolean,integer)')is not null,
 'moteur_brouillon_conserve',to_regprocedure('public.workshop_plan_edit(date,text,integer,text,text,boolean)')is not null
)as verification127;
commit;
