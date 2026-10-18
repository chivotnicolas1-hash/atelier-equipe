-- MAJ46 : nécessite MAJ45. Réexécutable.
begin;
alter table public.workshop_target_sales add column if not exists deleted_at timestamptz;
alter table public.workshop_target_sales add column if not exists deleted_by uuid references auth.users(id) on delete set null;
-- Trace interne conservée pour le délai anti-doublon et les nouvelles tentatives.
create or replace function public.workshop_target_sales_status(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;t timestamptz:=clock_timestamp();next_at timestamptz;
begin
 a:=workshop_private.actor_before30();
 manager:=coalesce((a->>'manager')::boolean,false);
 if p_date is null then raise exception 'Date requise.';end if;
 if not manager then select max(created_at)+interval '10 minutes' into next_at from public.workshop_target_sales where user_id=auth.uid();end if;
 return jsonb_build_object(
  'targets',public.workshop_service_targets(p_date),
  'totals',(select coalesce(jsonb_object_agg(category,total),'{}'::jsonb) from (select category,sum(quantity) total from public.workshop_target_sales where date=p_date and deleted_at is null group by category)s),
  'manager',manager,'guest',a->>'role'='guest',
  'can_add',a->>'role'<>'guest' and (manager or p_date=(t at time zone 'Europe/Paris')::date),
  'server_now',t,'next_allowed_at',next_at);
end $$;

create or replace function public.workshop_add_target_sale(p_id uuid,p_date date,p_category text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;r public.workshop_target_sales%rowtype;last_at timestamptz;t timestamptz;person text;
begin
 a:=workshop_private.actor();manager:=coalesce((a->>'manager')::boolean,false);
 if p_id is null or p_date is null or p_category is null or p_category not in ('purge','batteries','beg','geometry','clim') then raise exception 'Vente invalide.';end if;
 -- Sérialise aussi les requêtes provenant de plusieurs téléphones/onglets.
 perform pg_advisory_xact_lock(hashtextextended('target-sale:'||auth.uid()::text,0));
 select * into r from public.workshop_target_sales where id=p_id;
 if found then
  if r.deleted_at is not null then raise exception 'Cette vente a été supprimée.';end if;
  if r.user_id is distinct from auth.uid() or r.date is distinct from p_date or r.category is distinct from p_category then raise exception 'Identifiant déjà utilisé.';end if;
  return public.workshop_target_sales_status(p_date);
 end if;
 t:=clock_timestamp();
 if not manager then
  if p_date<>(t at time zone 'Europe/Paris')::date then raise exception 'Les ventes se saisissent uniquement pour aujourd’hui.';end if;
  select max(created_at) into last_at from public.workshop_target_sales where user_id=auth.uid();
  if last_at+interval '10 minutes'>t then raise exception 'Patiente 10 minutes entre deux ventes, toutes catégories confondues.' using errcode='P0001';end if;
 end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_target_sales(id,date,category,user_id,author_name,created_at)
 values(p_id,p_date,p_category,auth.uid(),coalesce(person,'Utilisateur'),t);
 return public.workshop_target_sales_status(p_date);
end $$;

create or replace function public.workshop_target_sales_history(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Historique réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null then raise exception 'Date requise.';end if;
 return coalesce((select jsonb_agg(jsonb_build_object(
  'id',s.id,'category',s.category,'author_name',s.author_name,'quantity',s.quantity,'created_at',s.created_at,
  'version',s.version,'updated_at',s.updated_at,'updated_name',s.updated_name,
  'edits',(select coalesce(jsonb_agg(jsonb_build_object('old_quantity',e.old_quantity,'new_quantity',e.new_quantity,'editor_name',e.editor_name,'created_at',e.created_at) order by e.created_at desc,e.id desc),'[]'::jsonb) from public.workshop_target_sale_edits e where e.sale_id=s.id)
 ) order by s.created_at desc,s.id) from public.workshop_target_sales s where s.date=p_date and s.deleted_at is null),'[]'::jsonb);
end $$;

create or replace function public.workshop_update_target_sale(p_id uuid,p_quantity integer,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_target_sales%rowtype;person text;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Correction réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_quantity is null or p_quantity not between 0 and 10000 then raise exception 'Quantité entière comprise entre 0 et 10000 requise.';end if;
 select * into r from public.workshop_target_sales where id=p_id for update;
 if not found or r.deleted_at is not null then raise exception 'Vente introuvable ou supprimée.';end if;
 if p_version is distinct from r.version then raise exception 'Cette vente a été modifiée ailleurs. Actualise l’historique.';end if;
 if p_quantity=r.quantity then return;end if;
 select name into person from public.workshop_staff where id=a->>'self';
 person:=coalesce(person,'Gestionnaire');
 insert into public.workshop_target_sale_edits(sale_id,old_quantity,new_quantity,editor_id,editor_name)
 values(p_id,r.quantity,p_quantity,auth.uid(),person);
 update public.workshop_target_sales set quantity=p_quantity,version=version+1,updated_at=clock_timestamp(),updated_name=person where id=p_id;
end $$;

create or replace function public.workshop_delete_target_sale(p_id uuid,p_version integer)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_target_sales%rowtype;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Suppression réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_target_sales where id=p_id for update;
 if not found then raise exception 'Vente introuvable.';end if;
 if r.deleted_at is not null then return;end if;
 if p_version is distinct from r.version then raise exception 'Cette vente a été modifiée ailleurs. Actualise l’historique.';end if;
 update public.workshop_target_sales set deleted_at=clock_timestamp(),deleted_by=auth.uid(),version=version+1 where id=p_id;
end $$;
revoke all on function public.workshop_delete_target_sale(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_delete_target_sale(uuid,integer) to authenticated;

create or replace function workshop_private.handover_release(p_date date)
returns timestamptz language sql immutable set search_path='' as $$
 select ((p_date+case when extract(isodow from p_date)=6 then 2 else 1 end)::timestamp+interval '7 hours 30 minutes') at time zone 'Europe/Paris'
$$;
revoke all on function workshop_private.handover_release(date) from public,anon,authenticated;
create or replace function public.workshop_save_handover(p_date date,p_version integer,p_vehicles text,p_anomalies text,p_missing_parts text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_handover%rowtype; release_time timestamptz; todo jsonb; person text;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Préparation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null or p_version is null or p_date>(now() at time zone 'Europe/Paris')::date or p_vehicles is null or p_anomalies is null or p_missing_parts is null or greatest(length(p_vehicles),length(p_anomalies),length(p_missing_parts))>6000 then raise exception 'Date ou contenu invalide (6000 caractères par rubrique).';end if;
 if extract(isodow from p_date)=7 then raise exception 'Pas de récapitulatif le dimanche. Celui du samedi est destiné au lundi.';end if;
 release_time:=workshop_private.handover_release(p_date);
 if release_time<=now() then raise exception 'Ce récapitulatif est déjà publié : il ne peut plus être modifié.';end if;
 perform pg_advisory_xact_lock(hashtextextended('handover:'||p_date::text,0));
 select * into r from public.workshop_handover where date=p_date for update;
 if (found and r.version is distinct from p_version) or (not found and p_version<>0) then raise exception 'Récapitulatif modifié entre-temps. Ferme puis actualise la liste.';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'title',t.title,'details',t.details,'due',t.due,'priority',t.priority,'name',s.name) order by t.due,t.created_at),'[]') into todo from public.workshop_tasks t join public.workshop_staff s on s.id=t.staff_id and s.active where t.done=0 and t.due<=p_date;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_handover(date,vehicles,anomalies,missing_parts,tasks,author_name,release_at) values(p_date,trim(p_vehicles),trim(p_anomalies),trim(p_missing_parts),todo,coalesce(person,a->>'user'),release_time)
 on conflict(date) do update set vehicles=excluded.vehicles,anomalies=excluded.anomalies,missing_parts=excluded.missing_parts,tasks=excluded.tasks,author_name=excluded.author_name,updated_at=now(),release_at=excluded.release_at,version=workshop_handover.version+1;
 return (select to_jsonb(h) from public.workshop_handover h where date=p_date);
end $$;

-- Reprogramme le samedi en cours, y compris si la mise à jour est appliquée
-- le dimanche. Les récapitulatifs anciens restent dans l’historique.
with moved as (
 update public.workshop_handover set release_at=workshop_private.handover_release(date),version=version+1
 where extract(isodow from date)=6 and workshop_private.handover_release(date)>now()
 and release_at is distinct from workshop_private.handover_release(date)
 returning date
)
update public.workshop_recap_reads r set last_date=m.date-1 from moved m where r.last_date=m.date;

create or replace function workshop_private.schedule_messages(p_now timestamptz)
returns void language plpgsql security definer set search_path='' as $$
declare d date:=(p_now at time zone 'Europe/Paris')::date;t time:=(p_now at time zone 'Europe/Paris')::time;recipient record;recap record;key text;
begin
 if p_now is null or extract(isodow from d)=7 then return;end if;
 for recipient in select distinct a.id from auth.users a left join public.workshop_staff s on s.email=lower(a.email) and s.active where lower(a.email)='nchivot@norauto.fr' or s.role='moderator' loop
 for recap in select date,release_at from public.workshop_handover
 where release_at<=p_now and (release_at at time zone 'Europe/Paris')::date=d and extract(isodow from date)<>7 loop
 key:='recap:'||recap.date::text;
 -- Clé spécifique au lundi : une ancienne notification du dimanche ne doit
 -- pas empêcher la nouvelle notification après reprogrammation.
 if extract(isodow from recap.date)=6 then key:=key||':lundi';end if;
 perform workshop_private.message(recipient.id,case when extract(isodow from recap.date)=6 then 'Le récapitulatif du samedi est disponible' else 'Le récapitulatif de la veille est disponible' end,'/?notifications=recap',key);
 end loop;
 if t>=time '18:30' and not exists(select 1 from public.workshop_handover where date=d) then
 perform workshop_private.message(recipient.id,'Pense à faire ton récapitulatif','/?notifications=recap','reminder:'||d::text);
 end if;
 end loop;
end $$;
revoke all on function workshop_private.schedule_messages(timestamptz) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
