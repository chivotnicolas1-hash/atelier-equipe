begin;
-- Un renommage ne dépend pas de la révision globale (stock/classement).
create or replace function public.workshop_catalog_rename84(p_section text,p_id uuid,p_expected_name text,p_name text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb;old_name text;new_name text;result jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 new_name:=btrim(regexp_replace(coalesce(p_name,''),'[[:space:]]+',' ','g'));
 if length(new_name)<1 or length(new_name)>200 then raise exception 'La désignation doit contenir entre 1 et 200 caractères.';end if;
 -- Même ordre de verrouillage que les changements de stock.
 perform 1 from workshop_private.catalog75_rev where section=p_section for update;
 if not found then raise exception 'Section de catalogue introuvable.';end if;
 select name into old_name from workshop_private.catalog75 where id=p_id and section=p_section for update;
 if not found then raise exception 'Cet article a été retiré du catalogue.';end if;
 -- Une nouvelle tentative identique est sans effet ; un autre renommage
 -- concurrent n’est jamais écrasé silencieusement.
 if old_name is distinct from p_expected_name and old_name is distinct from new_name then
  raise exception 'Le nom a été modifié entre-temps. Ferme puis rouvre le catalogue avant de réessayer.';
 end if;
 update workshop_private.catalog75 set name=new_name where id=p_id and section=p_section
 returning jsonb_build_object('id',id,'name',name) into result;
 update workshop_private.catalog75_rev set rev=rev+1 where section=p_section;
 return result;
end $$;
revoke all on function public.workshop_catalog_rename84(text,uuid,text,text) from public,anon;
grant execute on function public.workshop_catalog_rename84(text,uuid,text,text) to authenticated;
notify pgrst,'reload schema';
commit;
