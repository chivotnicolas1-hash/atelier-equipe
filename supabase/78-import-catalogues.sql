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

-- Empreinte du contenu : le classement des commandes ne bloque pas la publication.
create or replace function workshop_private.catalog_token78(p_section text) returns text language sql security definer set search_path='' as $$
select md5(coalesce(jsonb_agg(jsonb_build_array(id,name,unavailable,md5(photo)) order by id)::text,'[]')) from workshop_private.catalog75 where section=p_section
$$;
create or replace function public.workshop_catalog78(p_section text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
perform 1 from workshop_private.catalog75_rev where section=p_section for share;
return public.workshop_catalog76(p_section,-1)||jsonb_build_object('token',workshop_private.catalog_token78(p_section));end $$;
create or replace function public.workshop_publish78(p_section text,p_token text,p_changes jsonb) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;c jsonb;i uuid;v int;n text;ph bytea;begin
a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur' using errcode='42501';end if;
select rev into strict v from workshop_private.catalog75_rev where section=p_section for update;
if p_token is distinct from workshop_private.catalog_token78(p_section) then raise exception 'Le catalogue a changé depuis l’ouverture. Ferme le brouillon, rouvre-le et vérifie les changements.';end if;
if jsonb_typeof(p_changes) is distinct from 'array' then raise exception 'Import invalide.';end if;
if jsonb_array_length(p_changes) not between 1 and 250 or octet_length(p_changes::text)>15000000 then raise exception 'Import invalide ou trop volumineux.';end if;
if exists(select 1 from jsonb_array_elements(p_changes) x where nullif(x->>'id','') is not null group by x->>'id' having count(*)>1) then raise exception 'Un article ne peut apparaître deux fois.';end if;
for c in select value from jsonb_array_elements(p_changes) loop
 i:=nullif(c->>'id','')::uuid;n:=trim(c->>'name');
 if i is not null and not exists(select 1 from workshop_private.catalog75 where id=i and section=p_section) then raise exception 'Article absent de cette section.';end if;
 if c->>'action'='delete' then
  if i is null then raise exception 'Article manquant.';end if;
  select rev into v from workshop_private.catalog75_rev where section=p_section;
  perform public.workshop_catalog_change75(p_section,v,'delete',i,'');
 elsif c->>'action'='save' then
  if n is null or length(n) not between 1 and 200 then raise exception 'Désignation invalide.';end if;
  ph:=null;
  if c ? 'photo' then
   if coalesce(c->>'photo','') !~ '^data:image/webp;base64,[A-Za-z0-9+/=]+$' or length(c->>'photo')>500000 then raise exception 'Photo WebP invalide ou trop volumineuse.';end if;
   ph:=decode(split_part(c->>'photo',',',2),'base64');
   if substring(ph from 1 for 4)<>decode('52494646','hex') or substring(ph from 9 for 4)<>decode('57454250','hex') then raise exception 'Photo WebP illisible.';end if;
  end if;
  if i is null then insert into workshop_private.catalog75(section,name,photo,position) select p_section,n,ph,coalesce(max(position),0)+1 from workshop_private.catalog75 where section=p_section;
  else update workshop_private.catalog75 set name=n,photo=case when c ? 'photo' then ph else photo end where id=i and section=p_section;end if;
 else raise exception 'Action invalide.';end if;
end loop;
update workshop_private.catalog75_rev set rev=rev+1 where section=p_section;
end $$;
revoke all on function workshop_private.catalog_token78(text) from public,anon,authenticated;
revoke all on function public.workshop_catalog78(text),public.workshop_publish78(text,text,jsonb) from public,anon;
grant execute on function public.workshop_catalog78(text),public.workshop_publish78(text,text,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
