-- Après la version 108/109 : contenus et anciens états conservés.
begin;
alter table workshop_private.waste_rack94 add column if not exists rack_items110 jsonb not null default '[]'::jsonb;
create or replace function workshop_private.rack_parse110(p_contents text) returns jsonb language plpgsql immutable set search_path='' as $$
declare output jsonb:='[]';counts jsonb:='{}';line record;norm text;m text[];n integer;word text;kind text;serial integer;i integer;pos text;begin
 if p_contents is null or length(p_contents)>500 then raise exception 'Contenu requis, limité à 500 caractères.';end if;
 for line in select value,ord from unnest(string_to_array(replace(p_contents,E'\r',''),E'\n')) with ordinality q(value,ord) loop
  norm:=translate(lower(line.value),'éèêëàâäîïôöùûüç','eeeeaaaiioouuuc');
  for m in select regexp_matches(norm,'(?:\m([0-9]+)\s*)?\m(tonnelets?|futs?|bacs?|palettes?)\M','g') loop
   if coalesce(m[1],'1')::numeric>99 then raise exception 'Maximum 99 contenants par case.';end if;n:=coalesce(m[1],'1')::int;
   if jsonb_array_length(output)+n>99 then raise exception 'Maximum 99 contenants par case.';end if;
   word:=m[2];kind:=case when word like 'tonnelet%' then 'small' when word like 'fut%' then 'drum' when word like 'bac%' then case when norm ~ '\mchiffons?\M' then 'cloth' else 'bin' end when norm ~ '\mplastiques?\M' then 'plastic' else 'pallet' end;
   for i in 1..n loop
    serial:=coalesce((counts->>kind)::int,0)+1;counts:=jsonb_set(counts,array[kind],to_jsonb(serial));
    pos:=case when norm ~ '\m(derriere|arriere)\M' then 'back' when norm ~ '\m(devant|facade|avant)\M' then 'front' when jsonb_array_length(output)%4<2 then 'front' else 'back' end;
    output:=output||jsonb_build_array(jsonb_build_object('key',kind||':'||serial,'kind',kind,'line',line.ord-1,'label',btrim(line.value),'position',pos,'fill','unknown'));
   end loop;
  end loop;
 end loop;return output;
end $$;
create or replace function workshop_private.rack_reconcile110(p_contents text,p_items jsonb,p_fill text,p_drums jsonb) returns jsonb language plpgsql immutable set search_path='' as $$
declare output jsonb:='[]';item jsonb;old jsonb;state text;pos text;d integer:=0;begin
 for item in select value from jsonb_array_elements(workshop_private.rack_parse110(p_contents)) loop
  old:=null;if jsonb_typeof(p_items)='array' then select x into old from jsonb_array_elements(p_items) x where x->>'key'=item->>'key' and x->>'kind'=item->>'kind' limit 1;end if;
  state:=p_fill;if item->>'kind'='drum' then state:=coalesce(p_drums->>d,p_fill);d:=d+1;end if;
  if old->>'fill' in ('full','empty','unknown') then state:=old->>'fill';end if;
  if state is null or state not in ('full','empty','unknown') then state:='unknown';end if;
  pos:=case when old->>'position' in ('front','back') then old->>'position' else item->>'position' end;
  output:=output||jsonb_build_array(item||jsonb_build_object('fill',state,'position',pos));
 end loop;return output;
end $$;
-- Lecture protégée existante, puis complément des objets ligne par ligne.
create or replace function public.workshop_rack_read110() returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;items jsonb:='[]';item jsonb;objects jsonb;begin
 r:=public.workshop_rack94();
 for item in select value from jsonb_array_elements(r->'items') loop
  begin objects:=workshop_private.rack_reconcile110(item->>'contents',item->'rack_items110',item->>'fill_state100',item->'drum_states108');item:=item||jsonb_build_object('rack_items110',objects);
  exception when others then item:=item||jsonb_build_object('rack_items110','[]'::jsonb,'parse_error110','Précise les quantités et utilise un type de contenant par ligne.');end;
  items:=items||jsonb_build_array(item);
 end loop;return r||jsonb_build_object('items',items);
end $$;
create or replace function public.workshop_rack_save110(p_id integer,p_version integer,p_contents text,p_items jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare expected jsonb;result jsonb:='[]';item jsonb;given jsonb;i integer:=0;common text;drums jsonb;begin
 expected:=workshop_private.rack_parse110(p_contents);
 if jsonb_typeof(p_items) is distinct from 'array' or jsonb_array_length(p_items)<>jsonb_array_length(expected) then raise exception 'Le nombre de contenants doit correspondre aux lignes saisies.';end if;
 for item in select value from jsonb_array_elements(expected) loop
  given:=p_items->i;i:=i+1;
  if given->>'key' is distinct from item->>'key' or given->>'kind' is distinct from item->>'kind' or coalesce(given->>'fill','') not in ('unknown','full','empty') or coalesce(given->>'position','') not in ('front','back') then raise exception 'Contenant, état ou position invalide.';end if;
  result:=result||jsonb_build_array(item||jsonb_build_object('fill',given->>'fill','position',given->>'position'));
 end loop;
 -- Identité, autorisations, verrouillage de case et version contrôlés ici.
 perform public.workshop_rack_save94(p_id,p_version,p_contents,null);
 select case when count(distinct x->>'fill')=1 then min(x->>'fill') else 'unknown' end into common from jsonb_array_elements(result) x;
 select coalesce(jsonb_agg(x->'fill' order by ord),'[]') into drums from jsonb_array_elements(result) with ordinality q(x,ord) where x->>'kind'='drum';
 update workshop_private.waste_rack94 set rack_items110=result,fill_state100=coalesce(common,'unknown'),drum_states108=drums where id=p_id;
 return(select to_jsonb(r) from workshop_private.waste_rack94 r where id=p_id);
end $$;
revoke all on function workshop_private.rack_parse110(text),workshop_private.rack_reconcile110(text,jsonb,text,jsonb) from public,anon,authenticated;
revoke all on function public.workshop_rack_read110(),public.workshop_rack_save110(integer,integer,text,jsonb) from public,anon;
grant execute on function public.workshop_rack_read110(),public.workshop_rack_save110(integer,integer,text,jsonb) to authenticated;
notify pgrst,'reload schema';commit;
