-- MAJ48 : nécessite MAJ47. Réexécutable.
begin;
-- Les saisies supprimées restent prises en compte pour le délai de leur cible.
create or replace function public.workshop_target_sales_status(p_date date)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;manager boolean;t timestamptz:=clock_timestamp();next_by_category jsonb:='{}'::jsonb;
begin
 a:=workshop_private.actor_before30();
 manager:=coalesce((a->>'manager')::boolean,false);
 if p_date is null then raise exception 'Date requise.';end if;
 if not manager then
 select coalesce(jsonb_object_agg(category,next_at),'{}'::jsonb) into next_by_category from
 (select category,max(created_at)+interval '5 minutes' next_at from public.workshop_target_sales where user_id=auth.uid() group by category)s;
 end if;
 return jsonb_build_object(
  'targets',public.workshop_service_targets(p_date),
  'totals',(select coalesce(jsonb_object_agg(category,total),'{}'::jsonb) from (select category,sum(quantity) total from public.workshop_target_sales where date=p_date and deleted_at is null group by category)s),
  'manager',manager,'guest',a->>'role'='guest',
  'can_add',a->>'role'<>'guest' and (manager or p_date=(t at time zone 'Europe/Paris')::date),
  'server_now',t,'next_allowed_at',null,'next_allowed_by_category',next_by_category);
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
  select max(created_at) into last_at from public.workshop_target_sales where user_id=auth.uid() and category=p_category;
  if last_at+interval '5 minutes'>t then raise exception 'Patiente 5 minutes avant une nouvelle vente pour cette cible.' using errcode='P0001';end if;
 end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_target_sales(id,date,category,user_id,author_name,created_at)
 values(p_id,p_date,p_category,auth.uid(),coalesce(person,'Utilisateur'),t);
 return public.workshop_target_sales_status(p_date);
end $$;


create or replace function public.workshop_save_service_targets(p_date date,p_targets jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;k text;current_targets jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Modification des cibles réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null or p_targets is null or jsonb_typeof(p_targets)<>'object' then raise exception 'Cibles invalides.';end if;
 if p_targets-array['purge','batteries','beg','geometry','clim']<>'{}'::jsonb then raise exception 'Catégorie inconnue.';end if;
 foreach k in array array['purge','batteries','beg','geometry','clim'] loop
  if not(p_targets ? k) or jsonb_typeof(p_targets->k)<>'number' or (p_targets->>k)!~ '^(0|[1-9][0-9]*)$' then raise exception 'Chaque cible doit être un entier entre 0 et 100000.';end if;
  if (p_targets->>k)::numeric>100000 then raise exception 'Chaque cible doit être un entier entre 0 et 100000.';end if;
 end loop;
 -- Même verrou que l’import PDF : aucun écrasement silencieux entre les deux.
 perform pg_advisory_xact_lock(hashtextextended('daily-targets-import',0));
 current_targets:=public.workshop_service_targets(p_date);
 if current_targets is distinct from p_expected then raise exception 'Les cibles ont été modifiées ailleurs. Actualise-les avant de recommencer.';end if;
 insert into public.workshop_service_targets(date,purge,batteries,beg,geometry,clim,updated_at,updated_by)
 values(p_date,(p_targets->>'purge')::integer,(p_targets->>'batteries')::integer,(p_targets->>'beg')::integer,(p_targets->>'geometry')::integer,(p_targets->>'clim')::integer,clock_timestamp(),auth.uid())
 on conflict(date) do update set purge=excluded.purge,batteries=excluded.batteries,beg=excluded.beg,geometry=excluded.geometry,clim=excluded.clim,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.workshop_target_sales_status(p_date);
end $$;
revoke all on function public.workshop_save_service_targets(date,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.workshop_save_service_targets(date,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
