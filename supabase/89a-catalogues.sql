begin;
CREATE OR REPLACE FUNCTION public.workshop_settings81(p_settings jsonb DEFAULT NULL::jsonb, p_version integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;r jsonb;k text;v jsonb;begin
 a:=workshop_private.actor_before30();
 if p_settings is not null then
  a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
  if jsonb_typeof(p_settings->'sections') is distinct from 'object' or jsonb_typeof(p_settings->'reminders') is distinct from 'object' or octet_length(p_settings::text)>30000 then raise exception 'Réglages invalides.';end if;
  for k,v in select * from jsonb_each(p_settings->'sections') loop
   if not k=any(array['journee','plan','tasks','reports','team','orders','waste','polls','recap','quality','disputes','settings','inbox','leave','lunch','skills','catalog.oil','catalog.pneus','catalog.gaz','catalog.freins','catalog.hygiene','waste.Grandidier','waste.Chimirec','waste.Gurdebeke']) then raise exception 'Section inconnue.';end if;
   if jsonb_typeof(v->'title') is distinct from 'string' or length(trim(v->>'title')) not between 1 and 90 or jsonb_typeof(v->'description') is distinct from 'string' or length(v->>'description')>300 then raise exception 'Nom ou description invalide.';end if;
  end loop;
  foreach k in array array['orders','waste'] loop
   r:=p_settings->'reminders'->k;
   if jsonb_typeof(r->'enabled') is distinct from 'boolean' or coalesce(r->>'mode','') not in ('weekly','once') or coalesce(r->>'time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(r->>'weekday','') !~ '^[1-7]$' then raise exception 'Jour, heure ou fréquence invalide.';end if;
   if r->>'mode'='once' and (r->>'enabled')::boolean then
    if coalesce(r->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' or (r->>'date')::date<(now() at time zone 'Europe/Paris')::date then raise exception 'Choisis aujourd’hui ou une date future.';end if;
   end if;
  end loop;
  update workshop_private.settings81 set settings=p_settings,version=version+1 where id=1 and version=p_version;
  if not found then raise exception 'Ces réglages ont changé. Ferme puis rouvre la configuration.';end if;
 end if;
 return (select jsonb_build_object('settings',settings,'version',version) from workshop_private.settings81 where id=1);
end $function$
;
insert into workshop_private.catalog75_rev(section,rev) values('Hygiène, protection et nettoyage',0) on conflict(section) do nothing;
create or replace function public.workshop_catalog89(p_section text,p_known integer default -1) returns jsonb language plpgsql security definer set search_path='' as $$
declare v integer;r jsonb;begin
 perform workshop_private.actor_before30();perform workshop_private.assert_section('orders');
 select rev into v from workshop_private.catalog75_rev where section=p_section for share;
 if not found then raise exception 'Section introuvable';end if;
 if v=p_known then return jsonb_build_object('rev',v);end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'unavailable',unavailable,'photo',case when photo is null then null else 'data:image/webp;base64,'||replace(encode(photo,'base64'),E'\n','') end) order by position,id),'[]') into r from workshop_private.catalog75 where section=p_section;
 return jsonb_build_object('rev',v,'items',r);end $$;
create or replace function public.workshop_catalog_editor89(p_section text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 r:=public.workshop_catalog89(p_section,-1);
 return r||jsonb_build_object('codes',public.workshop_catalog_codes88(p_section),'token',workshop_private.catalog_token78(p_section));end $$;
create or replace function public.workshop_catalog_save89(p_section text,p_id uuid,p_revision integer,p_name text,p_code text,p_photo text default null,p_clear_photo boolean default false,p_unavailable boolean default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;v integer;n text;ph bytea;code text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 n:=btrim(regexp_replace(coalesce(p_name,''),'[[:space:]]+',' ','g'));code:=btrim(coalesce(p_code,''));
 if length(n) not between 1 and 200 or length(code)>100 then raise exception 'Nom ou code produit invalide';end if;
 select rev into v from workshop_private.catalog75_rev where section=p_section for update;
 if not found then raise exception 'Section introuvable';end if;
 if v is distinct from p_revision then raise exception 'Le catalogue a changé. Ferme puis rouvre la fiche avant de réessayer.';end if;
 perform 1 from workshop_private.catalog75 where section=p_section and id=p_id for update;
 if not found then raise exception 'Cet article a été retiré du catalogue.';end if;
 if p_photo is not null then
  if p_clear_photo or p_photo !~ '^data:image/webp;base64,[A-Za-z0-9+/=]+$' or length(p_photo)>500000 then raise exception 'Photo WebP invalide ou trop volumineuse';end if;
  ph:=decode(split_part(p_photo,',',2),'base64');
  if octet_length(ph)<12 or substring(ph from 1 for 4)<>decode('52494646','hex') or substring(ph from 9 for 4)<>decode('57454250','hex') then raise exception 'Photo WebP illisible';end if;
 end if;
 update workshop_private.catalog75 set name=n,unavailable=coalesce(p_unavailable,unavailable),photo=case when p_clear_photo then null when p_photo is not null then ph else photo end where id=p_id and section=p_section;
 insert into workshop_private.product_codes83(product_id,code) values(p_id,code) on conflict(product_id) do update set code=excluded.code;
 update workshop_private.catalog75_rev set rev=rev+1 where section=p_section;
 return public.workshop_catalog_editor89(p_section);end $$;
create or replace function public.workshop_catalog_remove89(p_section text,p_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;n text;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 if p_section<>'Hygiène, protection et nettoyage' then perform public.workshop_remove77(p_section,p_id,p_name);return;end if;
 perform 1 from workshop_private.catalog75_rev where section=p_section for update;
 select name into n from workshop_private.catalog75 where id=p_id and section=p_section for update;
 if not found then return;end if;
 if n is distinct from p_name then raise exception 'Cet article a été renommé. Rouvre le catalogue.';end if;
 update public.workshop_order_requests r set items=(select coalesce(jsonb_agg(i order by ord),'[]') from jsonb_array_elements(r.items) with ordinality q(i,ord)
 where not (coalesce(i->>'id','')=p_id::text or (coalesce(i->>'id','')<>p_id::text and (select count(*) from workshop_private.match_product79(i))=1 and exists(select 1 from workshop_private.match_product79(i) m where m.kind='catalog' and m.id=p_id::text)))),version=version+1,updated_at=now()
 where exists(select 1 from jsonb_array_elements(r.items) i where coalesce(i->>'id','')=p_id::text or ((select count(*) from workshop_private.match_product79(i))=1 and exists(select 1 from workshop_private.match_product79(i) m where m.kind='catalog' and m.id=p_id::text)));
 delete from workshop_private.catalog75 where id=p_id and section=p_section;
 update workshop_private.catalog75_rev set rev=rev+1 where section=p_section;end $$;
create or replace function public.workshop_catalog_publish89(p_section text,p_token text,p_changes jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;change_row jsonb;saves jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
 perform 1 from workshop_private.catalog75_rev where section=p_section for update;
 if not found then raise exception 'Section introuvable';end if;
 if p_token is distinct from workshop_private.catalog_token78(p_section) then raise exception 'Le catalogue a changé. Rouvre le brouillon.';end if;
 if jsonb_typeof(p_changes) is distinct from 'array' or jsonb_array_length(p_changes) not between 1 and 250 or octet_length(p_changes::text)>15000000 then raise exception 'Import invalide';end if;
 if exists(select 1 from jsonb_array_elements(p_changes) c where coalesce(c->>'action','') not in ('save','delete')) then raise exception 'Action invalide';end if;
 if exists(select 1 from jsonb_array_elements(p_changes) c where nullif(c->>'id','') is not null group by c->>'id' having count(*)>1) then raise exception 'Article sélectionné deux fois';end if;
 for change_row in select value from jsonb_array_elements(p_changes) where value->>'action'='delete' loop
  if nullif(change_row->>'id','') is null then raise exception 'Article manquant';end if;
  perform public.workshop_catalog_remove89(p_section,(change_row->>'id')::uuid,change_row->>'name');end loop;
 select jsonb_agg(c) into saves from jsonb_array_elements(p_changes) c where c->>'action'='save';
 if saves is not null then perform public.workshop_publish78(p_section,workshop_private.catalog_token78(p_section),saves);end if;end $$;
revoke all on function public.workshop_catalog89(text,integer),public.workshop_catalog_editor89(text),public.workshop_catalog_save89(text,uuid,integer,text,text,text,boolean,boolean),public.workshop_catalog_remove89(text,uuid,text),public.workshop_catalog_publish89(text,text,jsonb) from public,anon;
grant execute on function public.workshop_catalog89(text,integer),public.workshop_catalog_editor89(text),public.workshop_catalog_save89(text,uuid,integer,text,text,text,boolean,boolean),public.workshop_catalog_remove89(text,uuid,text),public.workshop_catalog_publish89(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';commit;
