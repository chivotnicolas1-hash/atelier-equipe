begin;
create index if not exists workshop_waste_collected117 on public.workshop_waste(collected_at desc) where collected_at is not null;

-- Une ligne d’historique par famille et par ramassage effectif.
-- Les enlèvements partiels sont inclus, même si le solde reste en attente.
create or replace function public.workshop_waste_history117(p_year integer default null,p_family text default null,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;result jsonb;
begin
 a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if p_offset is null or p_offset<0 or p_offset>1000000 or (p_year is not null and p_year not between 2000 and 2200) or length(coalesce(p_family,''))>100 then raise exception 'Filtre d’historique invalide.';end if;
 if a->>'role'='guest' then return jsonb_build_object('years','[]'::jsonb,'families','[]'::jsonb,'items','[]'::jsonb,'total',0);end if;
 with events as (
  select w.id request_id,w.collected_at at,w.collected_name by_name,
   (select coalesce(jsonb_object_agg(c.key,case when c.key='pneus' then '1'::jsonb else w.bin_counts->c.key end),'{}') from jsonb_array_elements_text(w.categories)c(key)) amounts,
   w.notes,w.author_name,w.created_at requested_at,'final'::text event_key,true completed,
   case when coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false) then to_jsonb(w)-'author_id'-'validated_by'-'collected_by' else null end request_snapshot
  from public.workshop_waste w where w.collected_at is not null
  union all
  select w.id,(x.item->>'at')::timestamptz,x.item->>'by',x.item->'amounts',w.notes,w.author_name,w.created_at,'partial-'||x.ord::text,false,
   case when coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false) then to_jsonb(w)-'author_id'-'validated_by'-'collected_by' else null end
  from public.workshop_waste w cross join lateral jsonb_array_elements(coalesce(w.pickups72,'[]'::jsonb)) with ordinality x(item,ord)
  where x.item->>'at' is not null and jsonb_typeof(x.item->'amounts')='object'
 ), lines as (
  select e.request_id,e.at,e.by_name,e.notes,e.author_name,e.requested_at,e.event_key,e.completed,e.request_snapshot,
   extract(year from e.at at time zone 'Europe/Paris')::integer as "year",
   q.key family,coalesce(t.label,q.key) label,coalesce(t.unit,'piece') unit,q.value quantity
  from events e cross join lateral jsonb_each(e.amounts) q
  left join workshop_private.waste_types112 t on t.key=q.key
  where (jsonb_typeof(q.value)='number' and (q.value#>>'{}')::numeric>0) or jsonb_typeof(q.value)='null'
 ), filtered as (
  select * from lines where (p_year is null or "year"=p_year) and (p_family is null or family=p_family)
 ), page as (
  select * from filtered order by at desc,request_id,event_key,family limit 50 offset p_offset
 )
 select jsonb_build_object(
  'years',(select coalesce(jsonb_agg(y."year" order by y."year" desc),'[]') from (select distinct "year" from lines)y),
  'families',(select coalesce(jsonb_agg(jsonb_build_object('key',f.family,'label',f.label) order by f.label,f.family),'[]') from (select distinct family,label from lines)f),
  'total',(select count(*) from filtered),
  'items',(select coalesce(jsonb_agg(to_jsonb(p) order by p.at desc,p.request_id,p.event_key,p.family),'[]') from page p)
 ) into result;
 return result;
end $$;
revoke all on function public.workshop_waste_history117(integer,text,integer) from public,anon,authenticated;
grant execute on function public.workshop_waste_history117(integer,text,integer) to authenticated;
notify pgrst,'reload schema';
commit;
