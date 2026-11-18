-- Après la mise à jour 103. Ne supprime aucune photo ni aucun produit.
begin;
create or replace function public.workshop_catalog_save103(p_section text,p_id uuid,p_revision integer,p_name text,p_code text,p_photo text,p_clear_photo boolean,p_unavailable boolean,p_managers_only boolean,p_source_kind text default null,p_source_id text default null,p_source_section text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;v integer;n text;new_code text;bytes bytea;uri text;begin
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 n:=btrim(regexp_replace(coalesce(p_name,''),'[[:space:]]+',' ','g'));new_code:=btrim(coalesce(p_code,''));
 if length(n) not between 1 and 200 or length(new_code)>100 then raise exception 'Nom ou code produit invalide.';end if;
 if p_clear_photo is null or p_managers_only is null then raise exception 'Options du produit invalides.';end if;
 select rev into v from workshop_private.catalog75_rev where section=p_section for update;
 if not found then raise exception 'Section introuvable.';end if;
 if v is distinct from p_revision then raise exception 'Le catalogue a changé. Ferme puis rouvre la fiche avant de réessayer.';end if;
 perform 1 from workshop_private.catalog75 where id=p_id and section=p_section for update;
 if not found then raise exception 'Cet article a été retiré du catalogue.';end if;
 if p_source_kind is not null then
  if p_clear_photo then raise exception 'Choisis entre remplacer et supprimer la photo.';end if;
  if p_source_kind='catalog' then
   select photo into bytes from workshop_private.catalog75 where id::text=p_source_id and section=p_source_section;
  elsif p_source_kind='oil' and p_source_section='oil' then
   select x->>'photo' into uri from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) x where x->>'id'=p_source_id;
   if uri ~ '^data:image/(jpeg|png|webp);base64,' then bytes:=decode(split_part(uri,',',2),'base64');end if;
  else raise exception 'Source de photo invalide.';end if;
  if bytes is null then raise exception 'Cette image n’est plus disponible. Rouvre la galerie.';end if;
  if octet_length(bytes)>2000000 then raise exception 'Image trop volumineuse pour être réutilisée.';end if;
 elsif p_photo is not null then
  if p_clear_photo or p_photo !~ '^data:image/webp;base64,[A-Za-z0-9+/=]+$' or length(p_photo)>500000 then raise exception 'Photo WebP invalide ou trop volumineuse.';end if;
  bytes:=decode(split_part(p_photo,',',2),'base64');
  if octet_length(bytes)<12 or substring(bytes from 1 for 4)<>decode('52494646','hex') or substring(bytes from 9 for 4)<>decode('57454250','hex') then raise exception 'Photo WebP illisible.';end if;
 end if;
 update workshop_private.catalog75 set name=n,unavailable=coalesce(p_unavailable,unavailable),managers_only=p_managers_only,
 photo=case when p_clear_photo then null when p_source_kind is not null or p_photo is not null then bytes else photo end
 where id=p_id and section=p_section;
 insert into workshop_private.product_codes83(product_id,code) values(p_id,new_code) on conflict(product_id) do update set code=excluded.code;
 update workshop_private.catalog75_rev set rev=rev+1 where section=p_section;
 -- Un seul chargement final, au lieu de trois lectures de toutes les photos.
 return public.workshop_catalog_editor89(p_section);
end $$;
revoke all on function public.workshop_catalog_save103(text,uuid,integer,text,text,text,boolean,boolean,boolean,text,text,text) from public,anon;
grant execute on function public.workshop_catalog_save103(text,uuid,integer,text,text,text,boolean,boolean,boolean,text,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
