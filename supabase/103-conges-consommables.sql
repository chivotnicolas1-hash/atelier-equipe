-- Après SQL100 puis SQL102. Migration transactionnelle, aucun historique effacé.
begin;
CREATE OR REPLACE FUNCTION public.workshop_leave_list_v63(p_year integer, p_team boolean DEFAULT false, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;items jsonb;years jsonb;n integer;begin a:=workshop_private.actor();if a->>'role'='guest' or (p_team and not coalesce((a->>'manager')::boolean,false)) then raise exception 'Demandes inaccessibles.' using errcode='42501';end if;
if p_year is null or p_year not between 2020 and 2100 or p_offset is null or p_offset<0 or p_team is null then raise exception 'Année ou page invalide.';end if;
select coalesce(jsonb_agg(y order by y desc),'[]') into years from(select distinct generate_series(extract(year from (p->>'start')::date)::int,extract(year from (p->>'end')::date)::int) y from public.workshop_leave_requests r cross join lateral jsonb_array_elements(r.periods)p where p_team or r.author_id=auth.uid())v;
select count(*) into n from public.workshop_leave_requests r where (p_team or r.author_id=auth.uid()) and exists(select 1 from jsonb_array_elements(r.periods)p where (p->>'start')::date<=make_date(p_year,12,31) and (p->>'end')::date>=make_date(p_year,1,1));
select coalesce(jsonb_agg(v.item order by v.created_at desc),'[]') into items from(select r.created_at,to_jsonb(r)-'signature'-'decided_signature'-'author_id'-'staff_id'-'decided_by'-'history'||jsonb_build_object('own',r.author_id=auth.uid()) item from public.workshop_leave_requests r where (p_team or r.author_id=auth.uid()) and exists(select 1 from jsonb_array_elements(r.periods)p where (p->>'start')::date<=make_date(p_year,12,31) and (p->>'end')::date>=make_date(p_year,1,1)) order by r.created_at desc limit 30 offset p_offset)v;
return jsonb_build_object('items',items,'years',years,'total',n);end $function$
;
CREATE OR REPLACE FUNCTION public.workshop_leave_get_before59(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;r public.workshop_leave_requests%rowtype;begin
 a:=workshop_private.actor();select * into r from public.workshop_leave_requests where id=p_id;
 if a->>'role'='guest' or r.id is null or not (r.author_id=auth.uid() or coalesce((a->>'manager')::boolean,false)) then raise exception 'Demande inaccessible.' using errcode='42501';end if;
 return to_jsonb(r)-'author_id'-'staff_id'-'decided_by';
end $function$
;
CREATE OR REPLACE FUNCTION public.workshop_leave_download(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;r public.workshop_leave_requests%rowtype;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('leave');
 select * into r from public.workshop_leave_requests where id=p_id for share;
 if r.id is null or (not coalesce((a->>'manager')::boolean,false) and (r.author_id is distinct from auth.uid() or r.status<>'accepted')) then raise exception 'Le téléchargement est disponible uniquement pour ta demande acceptée.' using errcode='42501';end if;
 return to_jsonb(r)-'author_id'-'staff_id'-'decided_by';end $function$
;
create or replace function workshop_private.leave_periods103(p_periods jsonb,p_exceptional boolean,p_swap boolean) returns jsonb language plpgsql immutable set search_path='' as $$
declare r jsonb;begin
 if p_exceptional is null or p_swap is null or jsonb_typeof(p_periods) is distinct from 'array' then raise exception 'Formulaire d’absence invalide.';end if;
 if p_exceptional then
  if jsonb_array_length(p_periods)<>1 or p_periods->0->>'kind'<>'other' or length(btrim(coalesce(p_periods->0->>'detail',''))) not between 1 and 150 then raise exception 'Précise un motif de 1 à 150 caractères et une période unique.';end if;
  return jsonb_build_array((p_periods->0)||jsonb_build_object('exceptional103',true,'swap_rest103',p_swap));
 end if;
 select coalesce(jsonb_agg(item-'exceptional103'-'swap_rest103' order by ord),'[]') into r from jsonb_array_elements(p_periods) with ordinality x(item,ord);return r;
end $$;
revoke all on function workshop_private.leave_periods103(jsonb,boolean,boolean) from public,anon,authenticated;
create or replace function public.workshop_leave_save103(p_id uuid,p_first text,p_last text,p_centre text,p_periods jsonb,p_version integer,p_certified boolean,p_exceptional boolean,p_swap boolean) returns void language plpgsql security definer set search_path='' as $$begin
 perform public.workshop_leave_save(p_id,p_first,p_last,p_centre,workshop_private.leave_periods103(p_periods,p_exceptional,p_swap),p_version,p_certified);
end $$;
create or replace function public.workshop_leave_admin_edit103(p_id uuid,p_version integer,p_first text,p_last text,p_centre text,p_periods jsonb,p_exceptional boolean,p_swap boolean) returns void language plpgsql security definer set search_path='' as $$begin
 perform public.workshop_leave_admin_edit(p_id,p_version,p_first,p_last,p_centre,workshop_private.leave_periods103(p_periods,p_exceptional,p_swap));
end $$;
revoke all on function public.workshop_leave_save103(uuid,text,text,text,jsonb,integer,boolean,boolean,boolean) from public,anon;
grant execute on function public.workshop_leave_save103(uuid,text,text,text,jsonb,integer,boolean,boolean,boolean) to authenticated;
revoke all on function public.workshop_leave_admin_edit103(uuid,integer,text,text,text,jsonb,boolean,boolean) from public,anon;
grant execute on function public.workshop_leave_admin_edit103(uuid,integer,text,text,text,jsonb,boolean,boolean) to authenticated;
-- Paramètres de sections : une liste complète de clés, validation et verrou de version.
insert into workshop_private.settings81(id,settings,version) values(1,'{"sections":{},"reminders":{"orders":{"enabled":true,"mode":"weekly","weekday":2,"time":"09:00","date":""},"waste":{"enabled":false,"mode":"weekly","weekday":5,"time":"09:00","date":""}}}',1) on conflict(id) do nothing;
create or replace function public.workshop_settings103(p_settings jsonb default null,p_version integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.settings81%rowtype;k text;v jsonb;next_settings jsonb;begin
 a:=workshop_private.actor_before30();
 if p_settings is null then select * into r from workshop_private.settings81 where id=1;return jsonb_build_object('settings',r.settings,'version',r.version);end if;
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 select * into r from workshop_private.settings81 where id=1 for update;
 if not found or p_version is distinct from r.version then raise exception 'Les réglages ont changé. Ferme puis rouvre cet écran avant de réessayer.';end if;
 if jsonb_typeof(p_settings) is distinct from 'object' or jsonb_typeof(p_settings->'sections') is distinct from 'object' or jsonb_typeof(p_settings->'reminders') is distinct from 'object' then raise exception 'Réglages incomplets.';end if;
 for k,v in select * from jsonb_each(p_settings->'sections') loop
 if k not in ('journee','plan','tasks','reports','team','orders','waste','polls','recap','quality','disputes','settings','inbox','leave','lunch','skills','catalog.vidange','catalog.eclairage','catalog.oil','catalog.pneus','catalog.gaz','catalog.hygiene','catalog.freins','waste.Grandidier','waste.Chimirec','waste.Gurdebeke') then if v is distinct from r.settings->'sections'->k then raise exception 'Section inconnue : %',k;end if;continue;end if;
 if jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'title') is distinct from 'string' or length(btrim(v->>'title')) not between 1 and 90 or jsonb_typeof(v->'description') is distinct from 'string' or length(v->>'description')>300 then raise exception 'Nom ou description invalide pour la section %.',k;end if;
 end loop;
 for k,v in select * from jsonb_each(p_settings->'reminders') loop
 if k not in ('orders','waste') then if v is distinct from r.settings->'reminders'->k then raise exception 'Rappel inconnu.';end if;continue;end if;
 if jsonb_typeof(v) is distinct from 'object' or jsonb_typeof(v->'enabled') is distinct from 'boolean' or coalesce(v->>'mode','') not in ('weekly','once') or coalesce(v->>'weekday','') !~ '^[1-7]$' or coalesce(v->>'time','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Paramètres de rappel invalides.';end if;
 if v->>'mode'='once' and (v->>'enabled')::boolean then
 if coalesce(v->>'date','') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Date de rappel requise.';end if;
 perform (v->>'date')::date;end if;
 end loop;
 if not (p_settings->'reminders' ? 'orders') or not (p_settings->'reminders' ? 'waste') then raise exception 'Rappels incomplets.';end if;
 next_settings:=r.settings||jsonb_build_object('sections',p_settings->'sections','reminders',p_settings->'reminders');
 if next_settings is distinct from r.settings then update workshop_private.settings81 set settings=next_settings,version=version+1 where id=1 returning * into r;end if;
 return jsonb_build_object('settings',r.settings,'version',r.version);
end $$;
revoke all on function public.workshop_settings103(jsonb,integer) from public,anon;grant execute on function public.workshop_settings103(jsonb,integer) to authenticated;
-- Copie d'une image existante sans réencoder ni retransmettre le fichier en base64.
create or replace function public.workshop_catalog_save103(p_section text,p_id uuid,p_revision integer,p_name text,p_code text,p_photo text,p_clear_photo boolean,p_unavailable boolean,p_managers_only boolean,p_source_kind text default null,p_source_id text default null,p_source_section text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;bytes bytea;uri text;r jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_source_kind is not null then
  if p_source_kind='catalog' then select photo into bytes from workshop_private.catalog75 where id::text=p_source_id and section=p_source_section;
  elsif p_source_kind='oil' then
   select item->>'photo' into uri from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) item where item->>'id'=p_source_id;
   if uri ~ '^data:image/(jpeg|png|webp);base64,' then bytes:=decode(split_part(uri,',',2),'base64');end if;
  else raise exception 'Source de photo invalide.';end if;
  if bytes is null then raise exception 'Cette image n’est plus disponible. Rouvre la galerie.';end if;
  if octet_length(bytes)>2000000 then raise exception 'Image trop volumineuse pour être réutilisée.';end if;
 end if;
 -- Le nom, le code, la disponibilité et la version restent validés par le moteur existant.
 r:=public.workshop_catalog_save90(p_section,p_id,p_revision,p_name,p_code,case when p_source_kind is null then p_photo else null end,case when p_source_kind is null then p_clear_photo else false end,p_unavailable,p_managers_only);
 if p_source_kind is not null then
  update workshop_private.catalog75 set photo=bytes where id=p_id and section=p_section;
  if not found then raise exception 'Article retiré du catalogue.';end if;
  update workshop_private.catalog75_rev set rev=greatest(rev,p_revision+1) where section=p_section;
  return public.workshop_catalog_editor89(p_section);
 end if;
 return r;
end $$;
revoke all on function public.workshop_catalog_save103(text,uuid,integer,text,text,text,boolean,boolean,boolean,text,text,text) from public,anon;grant execute on function public.workshop_catalog_save103(text,uuid,integer,text,text,text,boolean,boolean,boolean,text,text,text) to authenticated;
notify pgrst,'reload schema';commit;
