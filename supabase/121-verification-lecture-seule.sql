-- Après installation : métadonnées et compteurs, aucune création de présence ni de demande.
select jsonb_build_object(
 'heure_paris',now()at time zone'Europe/Paris',
 'correction_dates_dechets',coalesce((select position('validated_at=null' in replace(p.prosrc,' ',''))=0
  from pg_proc p where p.oid=to_regprocedure('public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)')),false),
 'sauvegarde',(select count(*)from workshop_private.code_backup121),
 'fonction_dechets_anonyme',has_function_privilege('anon','public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)','EXECUTE'),
 'fonction_dechets_connectee',has_function_privilege('authenticated','public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)','EXECUTE'),
 'compteurs_du_jour',(select jsonb_build_object(
  'prevus_avec_horaires',count(*),
  'confirmes',count(*)filter(where d.confirmed is not null),
  'sans_affectation_confirmes',count(*)filter(where d.confirmed is not null and d.station is null and not d.geometry)
 )from public.workshop_days d join public.workshop_staff s on s.id=d.staff_id
 where d.date=(now()at time zone'Europe/Paris')::date and d.presence='present' and s.active
 and coalesce(s.role,'employee')not in('guest','director')and coalesce(to_jsonb(s)->>'suspended','false')<>'true'
 and exists(select 1 from jsonb_array_elements(coalesce(d.slots,'[]'))slot
  where slot->>'start'~'^([01][0-9]|2[0-3]):[0-5][0-9]$' and slot->>'end'~'^([01][0-9]|2[0-3]):[0-5][0-9]$' and slot->>'start'<slot->>'end'))
)as verification121;
