begin;
create table if not exists workshop_private.waste_types112(key text primary key,label text not null,provider text not null check(provider in ('Grandidier','Chimirec','Gurdebeke')),unit text not null check(unit in ('bin','litre','drum','can','piece','tyres')),active boolean not null default true,position integer not null,version integer not null default 1);
revoke all on workshop_private.waste_types112 from public,anon,authenticated;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('batteries','Vieilles batteries','Grandidier','bin',0) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('ferraille','Ferraille','Grandidier','bin',1) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('fonte','Fonte','Grandidier','bin',2) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('aluminium','Aluminium','Grandidier','bin',3) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('filtres','Filtres usagés','Chimirec','bin',4) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('huiles','Huiles usagées','Chimirec','litre',5) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('bidons','Bidons vides','Chimirec','can',6) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('futs','Fûts vides','Chimirec','drum',7) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('souilles','Matériaux souillés (fût 200 L)','Chimirec','drum',8) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('refroidissement','Liquide de refroidissement (fût 200 L)','Chimirec','drum',9) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('aerosols','Aérosols (fût 200 L)','Chimirec','drum',10) on conflict(key) do nothing;
insert into workshop_private.waste_types112(key,label,provider,unit,position) values('pneus','Anciens pneus','Gurdebeke','tyres',11) on conflict(key) do nothing;
create or replace function public.workshop_waste_types112() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();perform workshop_private.assert_section('waste');return jsonb_build_object('can_edit_pending',coalesce(a->>'role','employee') not in ('guest','director'),'items',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('used',case when coalesce((a->>'admin')::boolean,false) then exists(select 1 from public.workshop_waste w where w.categories ? t.key) else false end) order by t.position,t.key),'[]') from workshop_private.waste_types112 t));end $$;
create or replace function public.workshop_waste_type_save112(p_key text,p_version integer,p_label text,p_provider text,p_unit text,p_active boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.waste_types112%rowtype;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if length(btrim(coalesce(p_label,''))) not between 1 and 100 or p_provider is null or p_provider not in ('Grandidier','Chimirec','Gurdebeke') or p_unit is null or p_unit not in ('bin','litre','drum','can','piece','tyres') or p_active is null then raise exception 'Nom, prestataire ou unité invalide.';end if;
 if p_key is null then
  if p_version is distinct from 0 or p_unit='tyres' then raise exception 'Nouveau type invalide.';end if;
  if (select count(*) from workshop_private.waste_types112 where active)>=100 then raise exception 'Maximum 100 types actifs.';end if;
  insert into workshop_private.waste_types112(key,label,provider,unit,active,position) select 'custom_'||replace(gen_random_uuid()::text,'-',''),btrim(p_label),p_provider,p_unit,p_active,coalesce(max(position),0)+1 from workshop_private.waste_types112;
 else
  select * into r from workshop_private.waste_types112 where key=p_key for update;
  if not found or p_version is distinct from r.version then raise exception 'Ce type a changé. Rouvre sa fiche.';end if;
  if (r.provider is distinct from p_provider or r.unit is distinct from p_unit) and (p_key='pneus' or exists(select 1 from public.workshop_waste where categories ? p_key)) then raise exception 'Ce type est déjà utilisé : conserve son prestataire et son unité. Crée un nouveau type si nécessaire.';end if;
  if p_unit='tyres' and p_key<>'pneus' then raise exception 'Cette unité est réservée à la benne à pneus.';end if;
  update workshop_private.waste_types112 set label=btrim(p_label),provider=p_provider,unit=p_unit,active=p_active,version=version+1 where key=p_key;
 end if;
end $$;
create or replace function workshop_private.waste_provider(c jsonb) returns text language plpgsql stable security definer set search_path='' as $$
declare v jsonb;k text;n text;p text;begin
 if c is null or jsonb_typeof(c)<>'array' or jsonb_array_length(c) not between 1 and 50 or (select count(distinct x) from jsonb_array_elements(c)x)<>jsonb_array_length(c) then raise exception 'Sélection de déchets invalide.';end if;
 for v in select value from jsonb_array_elements(c) loop
  if jsonb_typeof(v)<>'string' then raise exception 'Déchet invalide.';end if;k:=v#>>'{}';select provider into n from workshop_private.waste_types112 where key=k;
  if not found then raise exception 'Type de déchet inconnu.';end if;
  if p is not null and p<>n then raise exception 'Crée une demande séparée pour chaque prestataire.';end if;p:=n;
 end loop;return p;
end $$;
create or replace function workshop_private.check_waste_counts(c jsonb,q jsonb) returns void language plpgsql set search_path='' as $$
declare k text;n numeric;u text;expected integer:=0;begin
 perform workshop_private.waste_provider(c);if jsonb_typeof(q) is distinct from 'object' then raise exception 'Quantités invalides.';end if;
 for k in select jsonb_array_elements_text(c) loop
  select unit into strict u from workshop_private.waste_types112 where key=k;
  if u='tyres' then continue;end if;expected:=expected+1;
  if not q ? k or jsonb_typeof(q->k)<>'number' then raise exception 'Renseigne chaque quantité.';end if;n:=(q->>k)::numeric;
  if u='litre' then if n<=0 or n>100000 or round(n,1)<>n then raise exception 'Volume : de 0,1 à 100 000 litres, une décimale maximum.';end if;
  elsif n<1 or n>999 or trunc(n)<>n then raise exception 'Quantité : entier de 1 à 999.';end if;
 end loop;
 if (select count(*) from jsonb_object_keys(q))<>expected then raise exception 'Quantités incohérentes.';end if;
end $$;
-- Conserver les noms d’arguments de la fonction déjà installée.
do $tyres$ declare target_oid oid;d text;body text;begin
 target_oid:='workshop_private.check_tyre_status(jsonb,boolean,date)'::regprocedure;select prosrc into body from pg_proc where pg_proc.oid=target_oid;
 d:=pg_get_functiondef(target_oid);execute replace(d,body,$newbody$begin
 if $1 ? 'pneus' then
  if $2 is null or ($2 and $3 is not null) or (not $2 and $3 is null) then raise exception 'Précise si la benne à pneus est pleine et, sinon, sa date prévue de remplissage.';end if;
 elsif $2 is not null or $3 is not null then raise exception 'L’état de la benne ne concerne que les pneus.';end if;
end $newbody$);
end $tyres$;
alter table public.workshop_waste drop constraint if exists workshop_waste_tyre_status_check;
alter table public.workshop_waste add constraint workshop_waste_tyre_status_check check(((categories ? 'pneus') and is_full is not null and ((is_full and full_expected is null) or (not is_full and full_expected is not null))) or (not(categories ? 'pneus') and is_full is null and full_expected is null));
create or replace function workshop_private.waste_type_guard112() returns trigger language plpgsql security definer set search_path='' as $$
declare k text;t workshop_private.waste_types112%rowtype;begin
 for k in select jsonb_array_elements_text(new.categories) loop
  select * into t from workshop_private.waste_types112 where key=k for share;
  if not found or (not t.active and (tg_op='INSERT' or not(old.categories ? k))) then raise exception 'Ce type a été supprimé des nouvelles demandes. Actualise la liste.';end if;
 end loop;return new;end $$;
drop trigger if exists waste_type_guard112 on public.workshop_waste;
create trigger waste_type_guard112 before insert or update of categories on public.workshop_waste for each row execute function workshop_private.waste_type_guard112();
create or replace function public.workshop_create_waste112(p_id uuid,p_categories jsonb,p_notes text,p_counts jsonb,p_full boolean,p_expected date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor();if coalesce(a->>'role','employee') in ('guest','director') then raise exception 'Compte en lecture seule.' using errcode='42501';end if;return public.workshop_create_waste_v60(p_id,p_categories,p_notes,p_counts,p_full,p_expected);end $$;
create or replace function public.workshop_update_waste112(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb,p_full boolean,p_expected date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');if coalesce(a->>'role','employee') in ('guest','director') then raise exception 'Compte en lecture seule.' using errcode='42501';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found or r.version is distinct from p_version then raise exception 'Cette demande a changé. Ferme puis rouvre-la.';end if;
 if coalesce((a->>'manager')::boolean,false) or coalesce((a->>'admin')::boolean,false) then return public.workshop_update_waste_v60(p_id,p_version,p_categories,p_notes,p_counts,p_full,p_expected);end if;
 if r.validated_at is not null or r.collected_at is not null then raise exception 'Cette demande est validée. Seuls l’administrateur et les modérateurs peuvent la modifier.' using errcode='42501';end if;
 perform workshop_private.check_waste_counts(p_categories,p_counts);perform workshop_private.check_tyre_status(p_categories,p_full,p_expected);
 if p_notes is null or length(p_notes)>2000 or r.provider is distinct from workshop_private.waste_provider(p_categories) then raise exception 'Précisions ou prestataire invalide.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set categories=p_categories,bin_counts=p_counts,notes=btrim(p_notes),is_full=p_full,full_expected=p_expected,version=version+1,updated_at=now(),updated_name=coalesce(person,a->>'user') where id=p_id returning * into r;return to_jsonb(r);
end $$;
CREATE OR REPLACE FUNCTION public.workshop_partial72(p_id uuid, p_version integer, p_amounts jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare a jsonb;r public.workshop_waste%rowtype;k text;n numeric;v numeric;lefts jsonb:='{}';cats jsonb:='[]';person text;begin a:=workshop_private.actor();
if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé aux gestionnaires';end if;
select * into r from public.workshop_waste where id=p_id for update;
if not found or r.version is distinct from p_version or r.validated_at is null or r.collected_at is not null then raise exception 'Demande modifiée ou non validée';end if;
if jsonb_typeof(p_amounts) is distinct from 'object' or p_amounts='{}'::jsonb then raise exception 'Indique les quantités enlevées';end if;
for k in select jsonb_object_keys(p_amounts) loop
if k='pneus' or not (r.categories ? k) or jsonb_typeof(p_amounts->k)<>'number' then raise exception 'Élément invalide';end if;
n:=(p_amounts->>k)::numeric;if n<=0 or ((select unit from workshop_private.waste_types112 where key=k)<>'litre' and n<>trunc(n)) then raise exception 'Quantité invalide';end if;end loop;
for k in select jsonb_array_elements_text(r.categories) loop
if k='pneus' then cats:=cats||jsonb_build_array(k);continue;end if;v:=(r.bin_counts->>k)::numeric;n:=coalesce((p_amounts->>k)::numeric,0);if v is null or n>v then raise exception 'Quantité supérieure au restant';end if;
if v>n then lefts:=lefts||jsonb_build_object(k,v-n);cats:=cats||jsonb_build_array(k);end if;end loop;
if cats='[]'::jsonb then perform public.workshop_collect_waste(p_id,p_version);return;end if;
select name into person from public.workshop_staff where id=a->>'self';
update public.workshop_waste set categories=cats,bin_counts=lefts,version=version+1,pickups72=pickups72||jsonb_build_array(jsonb_build_object('at',now(),'by',coalesce(person,a->>'user'),'amounts',p_amounts)) where id=p_id;
end $function$
;
revoke all on function public.workshop_waste_types112() from public,anon;grant execute on function public.workshop_waste_types112() to authenticated;
revoke all on function public.workshop_waste_type_save112(text,integer,text,text,text,boolean) from public,anon;grant execute on function public.workshop_waste_type_save112(text,integer,text,text,text,boolean) to authenticated;
revoke all on function public.workshop_create_waste112(uuid,jsonb,text,jsonb,boolean,date) from public,anon;grant execute on function public.workshop_create_waste112(uuid,jsonb,text,jsonb,boolean,date) to authenticated;
revoke all on function public.workshop_update_waste112(uuid,integer,jsonb,text,jsonb,boolean,date) from public,anon;grant execute on function public.workshop_update_waste112(uuid,integer,jsonb,text,jsonb,boolean,date) to authenticated;
notify pgrst,'reload schema';commit;
