begin;
-- Conserve le correctif du SQL 76 pour les installations avec safeupdate.
create or replace function workshop_private.refresh_freq76() returns trigger language plpgsql security definer set search_path='' as $$begin update workshop_private.catalog75_rev set rev=rev+1 where section is not null;return null;end $$;
create or replace function public.workshop_remove77(p_section text,p_id uuid,p_name text) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;v int;n text;begin
a:=workshop_private.actor();
if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
select rev into strict v from workshop_private.catalog75_rev where section=p_section for update;
select name into n from workshop_private.catalog75 where section=p_section and id=p_id for update;
if not found then return;end if;
if n is distinct from p_name then raise exception 'Cet article a été renommé. Vérifie son nouveau nom avant de le retirer.';end if;
perform public.workshop_catalog_change75(p_section,v,'delete',p_id,'');
end $$;
revoke all on function public.workshop_remove77(text,uuid,text) from public,anon;
grant execute on function public.workshop_remove77(text,uuid,text) to authenticated;
notify pgrst,'reload schema';commit;
