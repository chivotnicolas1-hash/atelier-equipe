begin;
CREATE OR REPLACE FUNCTION workshop_private.guard_order76()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x jsonb;prior jsonb:='[]';n numeric;begin if auth.uid() is null or workshop_private.catalog_manager90() then return new;end if; if tg_op='UPDATE' then prior:=old.items;end if;
for x in select value from jsonb_array_elements(new.items) loop
select coalesce(sum((v->>'quantity')::numeric),0) into n from jsonb_array_elements(prior) v where v->>'id'=x->>'id' and v->>'label'=x->>'label';
if (x->>'quantity')::numeric>n and (exists(select 1 from workshop_private.catalog75 c where c.unavailable and (c.id::text=x->>'id' or lower(trim(c.name))=lower(trim(x->>'label')))) or exists(select 1 from workshop_private.oil_catalog72 o cross join lateral jsonb_array_elements(o.items) t where t->>'unavailable'='true' and (lower(x->>'label')=lower((t->>'name')||case when coalesce(t->>'pack','')='' then '' else ' ('||(t->>'pack')||')' end) or (t->>'kind'='tank' and starts_with(lower(x->>'label'),lower((t->>'name')||' — livraison en cuve de ')))))) then raise exception 'Produit en rupture : ajout à la commande impossible.';end if;end loop;
return new;end $function$
;
alter table public.workshop_waste add column if not exists collection_expected100 date;
alter table public.workshop_waste add column if not exists collection_events100 jsonb not null default '[]';
create or replace function public.workshop_waste_date100(p_id uuid,p_version integer,p_date date) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;n text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');
 if not (coalesce((a->>'manager')::boolean,false) or workshop_private.has_right('waste_progress')) then raise exception 'Droit de suivi des déchets requis.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(930093);
 select * into r from public.workshop_waste where id=p_id for update;
 if not found or r.collected_at is not null or r.version is distinct from p_version then raise exception 'Cette demande a changé ou a été clôturée. Rouvre son suivi.';end if;
 if p_date is not null and p_date<(now() at time zone 'Europe/Paris')::date then raise exception 'Choisis une date de collecte à venir ou aujourd’hui.';end if;
 if r.collection_expected100 is not distinct from p_date then return;end if;
 select name into n from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set collection_expected100=p_date,collection_events100=collection_events100||jsonb_build_array(jsonb_build_object('at',now(),'by',coalesce(n,a->>'user'),'date',p_date)),version=version+1 where id=p_id;
 if p_date is not null then
  update workshop_private.waste_followups93 set closed_at=now(),closed_reason='Date de collecte communiquée',version=version+1 where waste_id=p_id and closed_at is null;
  delete from public.workshop_push_queue q using public.workshop_push_subscriptions s,public.workshop_messages m,workshop_private.waste_followups93 f where f.waste_id=p_id and m.event_key='waste93:'||f.id::text and q.subscription_id=s.id and s.user_id=m.user_id and q.sent_at is null and q.kind='message' and q.body=m.body and q.url=m.url and not exists(select 1 from public.workshop_messages other where other.user_id=m.user_id and other.body=m.body and other.url=m.url and other.event_key<>m.event_key and other.deleted_at is null);
  update public.workshop_messages m set deleted_at=now() from workshop_private.waste_followups93 f where f.waste_id=p_id and m.event_key='waste93:'||f.id::text and m.deleted_at is null;
 else
  update workshop_private.waste_followups93 set closed_at=null,closed_reason=null,version=version+1 where waste_id=p_id and validation_at=r.validated_at and closed_reason='Date de collecte communiquée';
 end if;
end $$;
revoke all on function public.workshop_waste_date100(uuid,integer,date) from public,anon;grant execute on function public.workshop_waste_date100(uuid,integer,date) to authenticated;
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
 where s.active and coalesce(s.role,'employee') not in ('guest','director') and (lower(s.email)=workshop_private.admin_email100() or s.role in ('admin','moderator') or lower(btrim(s.team))='encadrants') loop
 perform workshop_private.message(recipient,'Ramassage en retard · '||request_row.provider||' : relance le prestataire. Une tâche commune est disponible dans les tâches. Réf. '||left(request_row.id::text,8),'/?notifications=tasks','waste93:'||t::text);
 end loop;
 end if;
 end loop;
end $function$
;
CREATE OR REPLACE FUNCTION public.workshop_waste_tracking93()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if a->>'role'='guest' then return '[]'::jsonb;end if;
 return(select coalesce(jsonb_agg(jsonb_build_object('id',w.id,'due_at',case when d.days is not null then workshop_private.waste_due93(w.validated_at,d.days) end,'overdue',w.collection_expected100 is null and d.days is not null and workshop_private.waste_due93(w.validated_at,d.days)<=now(),'followup_created',f.id is not null and f.closed_at is null,'collection_expected',w.collection_expected100,'done_at',f.done_at,'done_name',f.done_name)),'[]')
 from public.workshop_waste w join workshop_private.waste_delays93 d using(provider)
 left join workshop_private.waste_followups93 f on f.waste_id=w.id and f.validation_at=w.validated_at
 where w.validated_at is not null and w.collected_at is null);
end $function$
;
alter table workshop_private.waste_rack94 add column if not exists fill_state100 text not null default 'unknown' check(fill_state100 in ('unknown','full','empty'));
create or replace function public.workshop_rack_save100(p_id integer,p_version integer,p_contents text,p_fill text) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if p_fill is null or p_fill not in ('unknown','full','empty') then raise exception 'État du bac invalide.';end if;
 result:=public.workshop_rack_save94(p_id,p_version,p_contents,null);
 update workshop_private.waste_rack94 set fill_state100=case when p_contents ~* '\mbacs?\M' then p_fill else 'unknown' end where id=p_id;
 return (select to_jsonb(r) from workshop_private.waste_rack94 r where id=p_id);
end $$;
revoke all on function public.workshop_rack_save100(integer,integer,text,text) from public,anon;grant execute on function public.workshop_rack_save100(integer,integer,text,text) to authenticated;
notify pgrst,'reload schema';commit;
