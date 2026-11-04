begin;
-- Résout un produit par son identifiant, puis par une désignation exacte non ambiguë.
create or replace function workshop_private.match_product79(line jsonb)
returns table(kind text,id text,section text) language plpgsql stable security definer set search_path='' as $$
begin
 if exists(select 1 from workshop_private.catalog75 c where c.id::text=line->>'id') then
  return query select 'catalog'::text,c.id::text,c.section from workshop_private.catalog75 c where c.id::text=line->>'id';return;
 end if;
 return query
 select 'catalog'::text,c.id::text,c.section from workshop_private.catalog75 c where lower(trim(c.name))=lower(trim(line->>'label'))
 union all
 select 'oil'::text,o->>'id','Divers liquides'::text from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) o
 where lower(trim(line->>'label'))=lower(trim((o->>'name')||case when coalesce(o->>'pack','')<>'' then ' ('||(o->>'pack')||')' else '' end))
 or (o->>'kind'='tank' and lower(split_part(line->>'label',' — livraison en cuve de ',1))=lower(o->>'name') and position(' — livraison en cuve de ' in line->>'label')>0);
end $$;
create or replace function workshop_private.order_stock79() returns trigger language plpgsql security definer set search_path='' as $$
declare a jsonb;l jsonb;m record;count_matches int;sections text[]:=array[]::text[];oil_ids text[]:=array[]::text[];begin
 if not exists(select 1 from jsonb_array_elements(coalesce(new.items,'[]')) x where x->>'out_of_stock'='true') then return new;end if;
 a:=workshop_private.actor();if not (coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then return new;end if;
 for l in select value from jsonb_array_elements(new.items) where value->>'out_of_stock'='true' loop
  -- Réagit aux nouvelles ruptures et à la validation de la commande.
  if TG_OP='UPDATE' then
   if new.status is not distinct from old.status and exists(select 1 from jsonb_array_elements(old.items) x where x->>'id'=l->>'id' and x->>'label'=l->>'label' and x->>'out_of_stock'='true') then continue;end if;
  end if;
  select count(*) into count_matches from workshop_private.match_product79(l);
  if count_matches>1 then raise exception 'Plusieurs produits correspondent à %. Renomme les références ambiguës avant de déclarer la rupture.',l->>'label';end if;
  for m in select * from workshop_private.match_product79(l) loop
   if m.kind='catalog' then
    update workshop_private.catalog75 set unavailable=true where id::text=m.id and unavailable is distinct from true;
    if found then sections:=array_append(sections,m.section);end if;
   else oil_ids:=array_append(oil_ids,m.id);end if;
  end loop;
 end loop;
 update workshop_private.catalog75_rev set rev=rev+1 where section=any(sections);
 if cardinality(oil_ids)>0 then
  update workshop_private.oil_catalog72 t set items=(select jsonb_agg(case when o->>'id'=any(oil_ids) then o||'{"unavailable":true}'::jsonb else o end order by ord) from jsonb_array_elements(t.items) with ordinality e(o,ord)),version=version+1
  where exists(select 1 from jsonb_array_elements(t.items) o where o->>'id'=any(oil_ids) and coalesce(o->>'unavailable','false')<>'true');
 end if;
 return new;
end $$;
drop trigger if exists workshop_order_stock79 on public.workshop_order_requests;
create trigger workshop_order_stock79 after insert or update of items,status on public.workshop_order_requests for each row execute function workshop_private.order_stock79();
-- Classement unique : aucune commande en attente ou supprimée ne compte.
create or replace function workshop_private.popular79() returns jsonb language sql stable security definer set search_path='' as $$
with matches as (
 select r.id order_id,m.kind,m.id from public.workshop_order_requests r cross join lateral jsonb_array_elements(r.items) l cross join lateral workshop_private.match_product79(l) m
 where r.status='validated' and r.deleted_at is null and (select count(*) from workshop_private.match_product79(l))=1
),counts as(select kind,id,count(distinct order_id) orders from matches group by kind,id), products as(
 select 'catalog' kind,c.id::text id,c.name,c.section,case when c.photo is null then null else 'data:image/webp;base64,'||replace(encode(c.photo,'base64'),E'\n','') end photo,c.unavailable from workshop_private.catalog75 c
 union all select 'oil',o->>'id',(o->>'name')||case when coalesce(o->>'pack','')<>'' then ' ('||(o->>'pack')||')' else '' end,'Divers liquides',o->>'photo',coalesce((o->>'unavailable')::boolean,false) from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) o
)
select coalesce(jsonb_agg(jsonb_build_object('id',p.kind||':'||p.id,'name',p.name,'section',p.section,'photo',p.photo,'unavailable',p.unavailable,'orders',c.orders) order by c.orders desc,p.name,p.id),'[]') from products p join counts c on p.kind=c.kind and p.id=c.id
$$;
create or replace function public.workshop_popular79() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not (coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Réservé à l’administrateur et aux modérateurs' using errcode='42501';end if;return workshop_private.popular79();end $$;
revoke all on function workshop_private.match_product79(jsonb),workshop_private.order_stock79(),workshop_private.popular79() from public,anon,authenticated;
revoke all on function public.workshop_popular79() from public,anon;
grant execute on function public.workshop_popular79() to authenticated;
notify pgrst,'reload schema';commit;
