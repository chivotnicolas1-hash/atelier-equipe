BEGIN;
-- MAJ88 : les lignes en rupture ne comptent pas parmi les commandes honorées.
-- Ne change ni les commandes existantes ni les droits d'accès.
CREATE OR REPLACE FUNCTION workshop_private.popular79()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
with matches as (
 select r.id order_id,m.kind,m.id
 from public.workshop_order_requests r
 cross join lateral jsonb_array_elements(r.items) l
 cross join lateral workshop_private.match_product79(l) m
 where r.status='validated' and r.deleted_at is null
   and coalesce((l->>'out_of_stock')::boolean,false)=false
   and (select count(*) from workshop_private.match_product79(l))=1
),counts as (
 select kind,id,count(distinct order_id) orders from matches group by kind,id
),products as (
 select 'catalog' kind,c.id::text id,c.name,c.section,
 case when c.photo is null then null else 'data:image/webp;base64,'||replace(encode(c.photo,'base64'),E'\n','') end photo,c.unavailable
 from workshop_private.catalog75 c
 union all
 select 'oil',o->>'id',(o->>'name')||case when coalesce(o->>'pack','')<>'' then ' ('||(o->>'pack')||')' else '' end,
 'Divers liquides',o->>'photo',coalesce((o->>'unavailable')::boolean,false)
 from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) o
)
select coalesce(jsonb_agg(jsonb_build_object('id',p.kind||':'||p.id,'name',p.name,'section',p.section,'photo',p.photo,'unavailable',p.unavailable,'orders',c.orders) order by c.orders desc,p.name,p.id),'[]')
from products p join counts c on p.kind=c.kind and p.id=c.id
$function$;

REVOKE ALL ON FUNCTION workshop_private.popular79() FROM PUBLIC,anon,authenticated;
COMMIT;
