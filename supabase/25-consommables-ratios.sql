-- MAJ25 : après MAJ24. Réexécutable. Aucun changement des droits des signalements.
begin;
update public.workshop_order_requests o set items=(select coalesce(jsonb_agg(x || jsonb_build_object('id',coalesce(x->>'id',gen_random_uuid()::text),'out_of_stock',coalesce((x->>'out_of_stock')::boolean,false)) order by n),'[]'::jsonb) from jsonb_array_elements(o.items) with ordinality t(x,n)),version=version+1 where exists(select 1 from jsonb_array_elements(o.items) x where not (x ? 'id'));
create or replace function public.workshop_list_orders(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; can_manage boolean;
begin
 a:=workshop_private.order_actor();can_manage:=coalesce((a->>'manager')::boolean,false);perform workshop_private.ensure_weekly_order();
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',can_manage,'total',(select count(*) from public.workshop_order_requests where deleted_at is null),'items',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_edit',can_manage or r.status='pending','week_number',extract(week from coalesce(r.week_start,(r.created_at at time zone 'Europe/Paris')::date)),'week_year',extract(isoyear from coalesce(r.week_start,(r.created_at at time zone 'Europe/Paris')::date))) order by r.created_at desc,r.id),'[]') from (select * from public.workshop_order_requests where deleted_at is null order by created_at desc,id limit 30 offset p_offset) r));
end $$;
create or replace function public.workshop_save_order(p_id uuid,p_version integer,p_items jsonb,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; item jsonb; clean jsonb:='[]'; person text; item_id uuid; old_item jsonb; manager boolean; out_stock boolean;
begin
 a:=workshop_private.order_actor();manager:=coalesce((a->>'manager')::boolean,false);
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found or r.deleted_at is not null then raise exception 'Commande introuvable.';end if;
 if r.status='validated' and not manager then raise exception 'Cette commande est validée. Seuls l’administrateur et les modérateurs peuvent la modifier.' using errcode='42501';end if;
 if p_id is null or p_version is null then raise exception 'Demande invalide.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Liste d’articles invalide.';end if;
 if jsonb_array_length(p_items) not between 0 and 100 then raise exception 'Maximum 100 articles.';end if;
 if p_notes is null or length(p_notes)>2000 then raise exception 'Commentaire limité à 2000 caractères.';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item)<>'object' or length(trim(coalesce(item->>'label',''))) not between 1 and 200 or length(coalesce(item->>'reference',''))>120 or length(coalesce(item->>'supplier',''))>150 then raise exception 'Renseigne un article valide (200 caractères maximum).';end if;
  if jsonb_typeof(item->'quantity') is distinct from 'number' or coalesce(item->>'quantity','') !~ '^[0-9]{1,3}$' or (item->>'quantity')::integer not between 1 and 999 then raise exception 'Quantité entière de 1 à 999 attendue.';end if;
  item_id:=coalesce(nullif(item->>'id','')::uuid,gen_random_uuid());
  if exists(select 1 from jsonb_array_elements(clean) x where x->>'id'=item_id::text) then raise exception 'Article en double.';end if;
  select x into old_item from jsonb_array_elements(r.items) x where x->>'id'=item_id::text;
  if item ? 'out_of_stock' and jsonb_typeof(item->'out_of_stock')<>'boolean' then raise exception 'État de rupture invalide.';end if;
  out_stock:=coalesce((item->>'out_of_stock')::boolean,false);
  if not manager and out_stock is distinct from coalesce((old_item->>'out_of_stock')::boolean,false) then raise exception 'Seuls l’administrateur et les modérateurs renseignent les ruptures.' using errcode='42501';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('id',item_id,'label',trim(item->>'label'),'quantity',(item->>'quantity')::integer,'out_of_stock',out_stock));
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if found then
  if r.deleted_at is not null then raise exception 'Cette commande a été supprimée.';end if;
  if p_version is distinct from r.version then raise exception 'La demande a changé entre-temps. Ferme puis rouvre-la.';end if;
  update public.workshop_order_requests set items=clean,version=version+1,updated_at=now(),status='pending',validated_at=null,validated_by=null,validated_name=null where id=p_id;
 else
  raise exception 'Commande introuvable. Les nouvelles commandes sont créées automatiquement chaque semaine.';
 end if;
 return (select to_jsonb(o) from public.workshop_order_requests o where id=p_id);
end $$;

create table if not exists public.workshop_daily_ratios(date date primary key,ratio numeric(12,2) not null check(ratio>=0),updated_at timestamptz not null default now());
alter table public.workshop_daily_ratios enable row level security;
revoke all on public.workshop_daily_ratios from public,anon,authenticated;
-- Conserver les fonctions précédentes sans perdre les horaires manuels et autres évolutions.
do $$ begin
 if to_regprocedure('public.workshop_load_before25(date)') is null then alter function public.workshop_load(date) rename to workshop_load_before25;end if;
 if to_regprocedure('public.workshop_import_planning_before25(jsonb,jsonb,boolean)') is null then alter function public.workshop_import_planning(jsonb,jsonb,boolean) rename to workshop_import_planning_before25;end if;
end $$;
revoke all on function public.workshop_load_before25(date),public.workshop_import_planning_before25(jsonb,jsonb,boolean) from public,anon,authenticated;
create or replace function public.workshop_load(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; allowed boolean;
begin
 result:=public.workshop_load_before25(p_date);
 allowed:=exists(select 1 from public.workshop_staff where id=result->>'self' and active and team='Encadrants');
 return result||jsonb_build_object('can_view_ratio',allowed)||case when allowed then jsonb_build_object('selected_ratio',(select ratio from public.workshop_daily_ratios where date=p_date)) else '{}'::jsonb end;
end $$;
create or replace function public.workshop_import_planning(p_rows jsonb,p_targets jsonb,p_replace boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb; t jsonb; v numeric; saved integer:=0;
begin
 -- La fonction existante contrôle l’administrateur et importe objectifs/horaires atomiquement.
 result:=public.workshop_import_planning_before25(p_rows,p_targets,p_replace);
 for t in select value from jsonb_array_elements(p_targets) loop
  if t ? 'ratio' and t->'ratio'<>'null'::jsonb then
   if jsonb_typeof(t->'ratio')<>'number' then raise exception 'Ratio invalide.';end if;
   v:=(t->>'ratio')::numeric;
   if v<0 or v>99999999 or round(v,2)<>v then raise exception 'Ratio invalide.';end if;
   insert into public.workshop_daily_ratios(date,ratio) values((t->>'date')::date,v) on conflict(date) do update set ratio=excluded.ratio,updated_at=now() where coalesce(p_replace,false);
   if found then saved:=saved+1;end if;
  end if;
 end loop;
 return result||jsonb_build_object('ratios_saved',saved);
end $$;
revoke all on function public.workshop_save_order(uuid,integer,jsonb,text),public.workshop_list_orders(integer),public.workshop_load(date),public.workshop_import_planning(jsonb,jsonb,boolean) from public,anon,authenticated;
grant execute on function public.workshop_save_order(uuid,integer,jsonb,text),public.workshop_list_orders(integer),public.workshop_load(date),public.workshop_import_planning(jsonb,jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
