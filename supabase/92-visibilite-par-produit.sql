-- Après la MAJ91 : visibilité indépendante des changements sur les autres articles.
begin;
create or replace function public.workshop_visibility92(p_kind text,p_id text,p_expected boolean,p_reserved boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;sec text;v integer;previous_v integer;actual boolean;v_items jsonb;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_reserved is null or p_expected is null then raise exception 'Visibilité ou version manquante.';end if;
 if p_kind='catalog' then
  select section into sec from workshop_private.catalog75 where id::text=p_id;
  if not found then raise exception 'Article introuvable.';end if;
  select rev into v from workshop_private.catalog75_rev where section=sec for update;
  previous_v:=v;
  select managers_only into actual from workshop_private.catalog75 where id::text=p_id and section=sec for update;
  if not found then raise exception 'Article introuvable.';end if;
  if actual=p_reserved then return jsonb_build_object('reserved',actual,'version',v,'previous_version',previous_v);end if;
  if actual is distinct from p_expected then raise exception 'La visibilité de cet article a changé. Rouvre la fiche.';end if;
  update workshop_private.catalog75 set managers_only=p_reserved where id::text=p_id and section=sec;
  if not found then raise exception 'Article retiré entre-temps.';end if;
  update workshop_private.catalog75_rev set rev=rev+1 where section=sec returning rev into v;
 elsif p_kind='oil' then
  perform pg_advisory_xact_lock(720072);
  select t.version,t.items into v,v_items from workshop_private.oil_catalog72 t where t.id=1 for update;
  previous_v:=v;
  if not exists(select 1 from jsonb_array_elements(v_items) x where x->>'id'=p_id) then raise exception 'Référence introuvable.';end if;
  select coalesce((x->>'managers_only')::boolean,false) into actual from jsonb_array_elements(v_items) x where x->>'id'=p_id;
  if actual=p_reserved then return jsonb_build_object('reserved',actual,'version',v,'previous_version',previous_v);end if;
  if actual is distinct from p_expected then raise exception 'La visibilité de cette référence a changé. Rouvre l’éditeur.';end if;
  update workshop_private.oil_catalog72 t set items=(select jsonb_agg(case when x->>'id'=p_id then x||jsonb_build_object('managers_only',p_reserved) else x end order by ord) from jsonb_array_elements(v_items) with ordinality q(x,ord)),version=t.version+1 where t.id=1 returning t.version into v;
 else raise exception 'Type de catalogue inconnu.';end if;
 return jsonb_build_object('reserved',p_reserved,'version',v,'previous_version',previous_v);
end $$;
revoke all on function public.workshop_visibility92(text,text,boolean,boolean) from public,anon,authenticated;
grant execute on function public.workshop_visibility92(text,text,boolean,boolean) to authenticated;
notify pgrst,'reload schema';commit;
