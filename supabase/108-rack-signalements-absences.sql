begin;
alter table workshop_private.waste_rack94 add column if not exists drum_states108 jsonb not null default '[]'::jsonb;
create or replace function workshop_private.drum_count108(p_text text) returns integer language sql immutable set search_path='' as $$
 select case when translate(lower(coalesce(p_text,'')),'û','u') ~ '\mfuts?\M' and translate(lower(coalesce(p_text,'')),'û','u') !~ '\mtonnelets?\M' then
 coalesce((select least(99,greatest(1,(m[1])::numeric))::integer from regexp_match(translate(lower(p_text),'û','u'),'\m([0-9]+)\s*futs?\M') m),1) else 0 end
$$;
-- Reprise des états communs existants, sans toucher à la version ni au contenu.
update workshop_private.waste_rack94 r set drum_states108=(select coalesce(jsonb_agg(coalesce(r.fill_state100,'unknown') order by i),'[]'::jsonb) from generate_series(1,workshop_private.drum_count108(r.contents)) i)
where drum_states108='[]'::jsonb and workshop_private.drum_count108(contents)>0;
create or replace function public.workshop_rack_save108(p_id integer,p_version integer,p_contents text,p_fill text,p_states jsonb default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare n integer;v jsonb;common text;begin
 if p_contents is null or length(p_contents)>500 then raise exception 'Contenu requis, limité à 500 caractères.';end if;
 n:=workshop_private.drum_count108(p_contents);
 if p_fill is null or p_fill not in ('unknown','full','empty') then raise exception 'État invalide.';end if;
 if n>0 then
  v:=coalesce(p_states,(select jsonb_agg(p_fill order by i) from generate_series(1,n) i));
  if jsonb_typeof(v) is distinct from 'array' or jsonb_array_length(v)<>n or exists(select 1 from jsonb_array_elements(v) x where jsonb_typeof(x) is distinct from 'string' or x#>>'{}' not in ('unknown','full','empty')) then raise exception 'Précise un état valide pour chaque fût.';end if;
  select case when count(distinct x)=1 then min(x) else 'unknown' end into common from jsonb_array_elements_text(v) x;
 else v:='[]';common:=p_fill;end if;
 -- Le moteur existant vérifie identité, lecture seule, verrou et version.
 perform public.workshop_rack_save100(p_id,p_version,p_contents,common);
 update workshop_private.waste_rack94 set drum_states108=v where id=p_id;
 return (select to_jsonb(r) from workshop_private.waste_rack94 r where id=p_id);
end $$;
revoke all on function workshop_private.drum_count108(text) from public,anon,authenticated;
revoke all on function public.workshop_rack_save108(integer,integer,text,text,jsonb) from public,anon;
grant execute on function public.workshop_rack_save108(integer,integer,text,text,jsonb) to authenticated;
-- Le filtre s'applique avant le comptage et la pagination.
create or replace function public.workshop_list_reports108(p_offset integer default 0,p_own boolean default true,p_search text default '') returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;q text;total bigint;items jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('reports');
 if p_own is distinct from false or a->>'role'='guest' then return public.workshop_list_reports(p_offset,p_own,p_search);end if;
 if not(coalesce((a->>'admin')::boolean,false) or coalesce((a->>'manager')::boolean,false)) then raise exception 'Consultation de l’équipe réservée à l’administration et la modération.' using errcode='42501';end if;
 if p_offset is null or p_offset<0 or p_search is null or length(p_search)>30 then raise exception 'Recherche ou page invalide.';end if;
 q:=regexp_replace(upper(p_search),'[^A-Z0-9]','','g');
 select count(*) into total from public.workshop_reports where author_id<>auth.uid() and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0;
 select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id desc),'[]') into items from (select id,author_name,registration,notes,created_at,(select count(*) from public.workshop_report_photos where report_id=x.id) photo_count from public.workshop_reports x where author_id<>auth.uid() and strpos(regexp_replace(upper(registration),'[^A-Z0-9]','','g'),q)>0 order by created_at desc,id desc limit 30 offset p_offset) r;
 return jsonb_build_object('items',items,'total',total);
end $$;
revoke all on function public.workshop_list_reports108(integer,boolean,text) from public,anon;
grant execute on function public.workshop_list_reports108(integer,boolean,text) to authenticated;
-- Adapter les libellés dans les définitions actuellement installées, sans remplacer
-- les modifications d'identité ou de droits des mises à jour précédentes.
do $patch$
declare n text;d text;old text;replacement text;periods text;oid oid;begin
 foreach n in array array['workshop_leave_save_before59','workshop_leave_decide_before59','workshop_leave_admin_edit_before59'] loop
  select p.oid into strict oid from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=n;
  d:=pg_get_functiondef(oid);
  if strpos(d,'absence exceptionnelle')>0 then continue;end if;
  if n='workshop_leave_admin_edit_before59' then
   old:=quote_literal('Ta demande de congé a été modifiée. Vérifie les informations et signe-la à nouveau.');
   replacement:=quote_literal('Ta demande d’absence exceptionnelle a été modifiée. Vérifie les informations et signe-la à nouveau.');periods:='p_periods';
  else old:=quote_literal('Demande de congé : ');replacement:=quote_literal('Demande d’absence exceptionnelle : ');periods:=case when n='workshop_leave_save_before59' then 'p_periods' else 'r.periods' end;end if;
  if strpos(d,old)=0 then raise exception 'Libellé de notification inattendu dans %. Transmets sa définition avant de poursuivre.',n;end if;
  d:=replace(d,old,'(case when exists(select 1 from jsonb_array_elements('||periods||') p where p->>''exceptional103''=''true'') then '||replacement||' else '||old||' end)');
  execute d;
 end loop;
end $patch$;
notify pgrst,'reload schema';commit;
