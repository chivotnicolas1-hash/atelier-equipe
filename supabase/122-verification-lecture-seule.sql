-- Métadonnées et choix indicatifs selon les horaires actuels. Aucune notification n'est envoyée.
with clock as(select(now()at time zone'Europe/Paris')::date as plan_day,now()as at_time)
select jsonb_build_object(
 'heure_paris',c.at_time at time zone'Europe/Paris',
 'routine_recap_installee',coalesce((select position('recap_send122' in prosrc)>0 from pg_proc where oid=to_regprocedure('workshop_private.schedule_messages_before49(timestamptz)')),false),
 'sauvegardes_definitions',(select count(*)from workshop_private.code_backup122),
 'horaires_notifications',jsonb_build_object('matin','07:30','soir','18:30','zone','Europe/Paris'),
 'matin_aujourdhui',(select jsonb_build_object('nom',r.name,'debut',r.starts,'fin',r.ends)from workshop_private.recap_recipient122(c.plan_day,'morning',c.at_time)r),
 'soir_aujourdhui',(select jsonb_build_object('nom',r.name,'debut',r.starts,'fin',r.ends)from workshop_private.recap_recipient122(c.plan_day,'evening',c.at_time)r),
 'matin_demain',(select jsonb_build_object('nom',r.name,'debut',r.starts,'fin',r.ends)from workshop_private.recap_recipient122(c.plan_day+1,'morning',((c.plan_day+1)+time'07:30')at time zone'Europe/Paris')r),
 'decisions_recentes',(select coalesce(jsonb_agg(to_jsonb(x)order by x.decided_at desc),'[]')from(
  select d.day,d.phase,d.recap_date,s.name,d.outcome,d.decided_at
  from workshop_private.recap_dispatch122 d left join public.workshop_staff s on s.id=d.staff_id order by d.decided_at desc limit 6)x),
 'dechets_validation_conservee',coalesce((select position('validated_at=null' in regexp_replace(lower(prosrc),'[[:space:]]','','g'))=0 from pg_proc where oid=to_regprocedure('public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date)')),false),
 'fonctions_privees_verrouillees',not has_function_privilege('authenticated','workshop_private.recap_send122(date,text,date,timestamptz)','EXECUTE')
  and not has_function_privilege('anon','workshop_private.recap_send122(date,text,date,timestamptz)','EXECUTE')
)as verification122 from clock c;
