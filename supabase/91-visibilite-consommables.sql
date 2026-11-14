-- Après la MAJ90. Enregistrement immédiat de la visibilité, avec contrôle de version.
begin;
create or replace function public.workshop_visibility91(p_kind text,p_id text,p_version integer,p_reserved boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;sec text;v integer;v_items jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_reserved is null or p_version is null then raise exception 'Visibilité ou version manquante.';end if;
 if p_kind='catalog' then
  select section into sec from workshop_private.catalog75 where id::text=p_id;
  if not found then raise exception 'Article introuvable.';end if;
  select rev into v from workshop_private.catalog75_rev where section=sec for update;
  if v is distinct from p_version then raise exception 'Le catalogue a changé. Ferme puis rouvre la fiche.';end if;
  update workshop_private.catalog75 set managers_only=p_reserved where id::text=p_id and section=sec;
  if not found then raise exception 'Article retiré entre-temps.';end if;
  update workshop_private.catalog75_rev set rev=rev+1 where section=sec returning rev into v;
 elsif p_kind='oil' then
  perform pg_advisory_xact_lock(720072);
  select t.version,t.items into v,v_items from workshop_private.oil_catalog72 t where t.id=1 for update;
  if v is distinct from p_version then raise exception 'Le plan a changé. Ferme puis rouvre l’éditeur.';end if;
  if not exists(select 1 from jsonb_array_elements(v_items) x where x->>'id'=p_id) then raise exception 'Référence introuvable.';end if;
  update workshop_private.oil_catalog72 t set items=(select jsonb_agg(case when x->>'id'=p_id then x||jsonb_build_object('managers_only',p_reserved) else x end order by ord) from jsonb_array_elements(v_items) with ordinality q(x,ord)),version=t.version+1 where t.id=1 returning t.version into v;
 else raise exception 'Type de catalogue inconnu.';end if;
 return jsonb_build_object('reserved',p_reserved,'version',v);
end $$;
revoke all on function public.workshop_visibility91(text,text,integer,boolean) from public,anon,authenticated;
grant execute on function public.workshop_visibility91(text,text,integer,boolean) to authenticated;
notify pgrst,'reload schema';commit;
