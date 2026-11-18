-- MAJ102 — Après MAJ100/101. Aucun historique supprimé.
begin;
CREATE OR REPLACE FUNCTION workshop_private.waste_schedule93(p_now timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare request_row record;t uuid;recipient uuid;due timestamptz;begin
 perform pg_advisory_xact_lock(930093);
 update workshop_private.waste_followups93 f set closed_at=p_now,closed_reason=case when w.collected_at is not null then 'Ramassage terminé' else 'Demande modifiée : nouvelle validation nécessaire' end,version=f.version+1
 from public.workshop_waste w where w.id=f.waste_id and f.closed_at is null and (w.collected_at is not null or w.validated_at is distinct from f.validation_at);
 for request_row in select w.*,d.days from public.workshop_waste w join workshop_private.waste_delays93 d using(provider)
 where w.validated_at is not null and w.collected_at is null and w.collection_expected100 is null and d.days is not null
 and workshop_private.waste_due93(w.validated_at,d.days)<p_now
 and extract(isodow from p_now at time zone 'Europe/Paris') between 1 and 5
 and not workshop_private.waste_holiday93((p_now at time zone 'Europe/Paris')::date)
 and (p_now at time zone 'Europe/Paris')::time>=time '08:00'
 order by w.id for update of w loop
 due:=workshop_private.waste_due93(request_row.validated_at,request_row.days);
 t:=null;
 insert into workshop_private.waste_followups93(waste_id,validation_at,due_at,created_at)
 values(request_row.id,request_row.validated_at,due,p_now) on conflict(waste_id,validation_at) do nothing returning id into t;
 if t is not null then
 for recipient in select distinct u.id from public.workshop_staff s join auth.users u on lower(u.email)=lower(s.email)
 where s.active and coalesce(s.role,'employee') not in ('guest','director') and (lower(s.email)=workshop_private.admin_email100() or s.role in ('admin','moderator')) loop
 perform workshop_private.message(recipient,'Ramassage en retard · '||request_row.provider||' : relance le prestataire. Une tâche commune est disponible dans les tâches. Réf. '||left(request_row.id::text,8),'/?notifications=tasks','waste93:'||t::text);
 end loop;
 end if;
 end loop;
end $function$;
CREATE OR REPLACE FUNCTION public.workshop_waste_tracking93()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if a->>'role'='guest' then return '[]'::jsonb;end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'delay_days',d.days,'provider',w.provider,'due_at',case when d.days is not null then workshop_private.waste_due93(w.validated_at,d.days) end,'overdue',w.collection_expected100 is null and d.days is not null and workshop_private.waste_due93(w.validated_at,d.days)<=now(),'followup_created',f.id is not null and f.closed_at is null,'collection_expected',w.collection_expected100,'done_at',f.done_at,'done_name',f.done_name)),'[]')
 from public.workshop_waste w join workshop_private.waste_delays93 d using(provider)
 left join workshop_private.waste_followups93 f on f.waste_id=w.id and f.validation_at=w.validated_at
 where w.validated_at is not null and w.collected_at is null);
end $function$;
create or replace function public.workshop_rack_save100(p_id integer,p_version integer,p_contents text,p_fill text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if p_fill is null or p_fill not in ('unknown','full','empty') then raise exception 'État du contenant invalide.';end if;
 result:=public.workshop_rack_save94(p_id,p_version,p_contents,null);
 update workshop_private.waste_rack94 set fill_state100=case when p_contents ~* '\m(bacs?|f[ûu]ts?|tonnelets?)\M' then p_fill else 'unknown' end where id=p_id;
 return (select to_jsonb(r) from workshop_private.waste_rack94 r where id=p_id);
end $$;
notify pgrst,'reload schema';
commit;
