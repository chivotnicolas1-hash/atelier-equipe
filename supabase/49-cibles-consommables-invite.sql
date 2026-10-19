-- MAJ49 : appliquer après MAJ48. Réexécutable.
begin;
create or replace function workshop_private.next_order(w date,created timestamptz)
returns void language sql security definer set search_path='' as $$
 insert into public.workshop_order_requests(id,author_name,items,week_start)
 values(gen_random_uuid(),'Commande commune','[]',coalesce(w,date_trunc('week',created at time zone 'Europe/Paris')::date)+7)
 on conflict(week_start) do update set deleted_at=null,items='[]',notes='',status='pending',
 validated_at=null,validated_by=null,validated_name=null,version=workshop_order_requests.version+1,updated_at=now()
 where workshop_order_requests.deleted_at is not null;
$$;
revoke all on function workshop_private.next_order(date,timestamptz) from public,anon,authenticated;
create or replace function public.workshop_validate_order(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; person text;
begin
 a:=workshop_private.order_actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Validation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found or r.deleted_at is not null then raise exception 'Demande introuvable.';end if;
 if jsonb_array_length(r.items)=0 then raise exception 'Ajoute au moins un article avant validation.';end if;
 if r.status='validated' then perform workshop_private.next_order(r.week_start,r.created_at);return to_jsonb(r);end if;
 if p_version is distinct from r.version then raise exception 'Cette demande a été modifiée. Actualise-la avant validation.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_order_requests set status='validated',version=version+1,updated_at=now(),validated_at=now(),validated_by=auth.uid(),validated_name=coalesce(person,a->>'user') where id=p_id returning * into r;
 perform workshop_private.next_order(r.week_start,r.created_at);return to_jsonb(r);
end $$;

revoke all on function public.workshop_validate_order(uuid,integer) from public,anon;
grant execute on function public.workshop_validate_order(uuid,integer) to authenticated;
create or replace function workshop_private.ensure_weekly_order() returns void
language plpgsql security definer set search_path='' as $$
declare monday date:=date_trunc('week',now() at time zone 'Europe/Paris')::date;
begin
 -- Ne rétablit pas une liste volontairement supprimée à chaque ouverture.
 insert into public.workshop_order_requests(id,author_name,items,week_start)
 values(gen_random_uuid(),'Commande commune','[]',monday) on conflict(week_start) do nothing;
 if exists(select 1 from public.workshop_order_requests where week_start=monday and status='validated' and deleted_at is null) and not exists(select 1 from public.workshop_order_requests where week_start=monday+7) then
 perform workshop_private.next_order(monday,now());end if;
end $$;
revoke all on function workshop_private.ensure_weekly_order() from public,anon,authenticated;
select workshop_private.ensure_weekly_order();
-- Conserve la planification des récapitulatifs de MAJ46.
do $$ begin
 if to_regprocedure('workshop_private.schedule_messages_before49(timestamptz)') is null then
 alter function workshop_private.schedule_messages(timestamptz) rename to schedule_messages_before49;
 end if;
end $$;
create or replace function workshop_private.schedule_messages(p_now timestamptz) returns void
language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone 'Europe/Paris')::date;recipient record; monday date;
begin
 if p_now is null then return;end if;
 perform workshop_private.schedule_messages_before49(p_now);
 perform workshop_private.ensure_weekly_order();
 if extract(isodow from d)<>2 or (p_now at time zone 'Europe/Paris')::time<time '09:00' then return;end if;
 monday:=date_trunc('week',d::timestamp)::date;
 for recipient in select distinct u.id from auth.users u left join public.workshop_staff s
 on s.email=lower(u.email) and s.active
 where lower(u.email)='nchivot@norauto.fr' or s.role in ('admin','moderator') loop
 perform workshop_private.message(recipient.id,'Pense à passer la commande de consommables de la semaine '||extract(week from d)::integer||'.',
 '/?notifications=orders','consumables-order:'||monday::text);
 end loop;
end $$;
revoke all on function workshop_private.schedule_messages(timestamptz),workshop_private.schedule_messages_before49(timestamptz) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
