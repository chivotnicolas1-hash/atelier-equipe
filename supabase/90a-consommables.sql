-- MAJ90, après 89a à 89d. Réexécutable.
begin;
alter table workshop_private.catalog75 add column if not exists managers_only boolean not null default false;
create or replace function workshop_private.catalog_manager90() returns boolean language plpgsql stable security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();return coalesce((a->>'admin')::boolean,false) or coalesce(a->>'role'='moderator',false);end $$;
create or replace function workshop_private.restricted90(line jsonb) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from (select * from workshop_private.match_product79(line) union select * from workshop_private.match_product79(line-'id')) m
 left join workshop_private.catalog75 c on m.kind='catalog' and c.id::text=m.id
 where coalesce(c.managers_only,false) or (m.kind='oil' and exists(select 1 from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) o where o->>'id'=m.id and coalesce((o->>'managers_only')::boolean,false))))
$$;
-- Lecture filtrée côté serveur, y compris pour l'ancien client 76.
create or replace function public.workshop_catalog89(p_section text,p_known integer default -1) returns jsonb language plpgsql security definer set search_path='' as $$
declare v integer;r jsonb;manager boolean;begin
 manager:=workshop_private.catalog_manager90();perform workshop_private.assert_section('orders');
 select rev into v from workshop_private.catalog75_rev where section=p_section for share;
 if not found then raise exception 'Section introuvable';end if;
 if v=p_known then return jsonb_build_object('rev',v);end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'unavailable',unavailable,'managers_only',managers_only,'photo',case when photo is null then null else 'data:image/webp;base64,'||replace(encode(photo,'base64'),E'\n','') end) order by position,id),'[]') into r from workshop_private.catalog75 where section=p_section and (manager or not managers_only);
 return jsonb_build_object('rev',v,'items',r);end $$;
create or replace function public.workshop_catalog76(p_section text,p_known integer default -1) returns jsonb language sql security definer set search_path='' as $$select public.workshop_catalog89(p_section,p_known)$$;
create or replace function public.workshop_catalog_save90(p_section text,p_id uuid,p_revision integer,p_name text,p_code text,p_photo text default null,p_clear_photo boolean default false,p_unavailable boolean default null,p_managers_only boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 -- L'ancienne fonction garde son contrôle administrateur, verrou et version.
 perform public.workshop_catalog_save89(p_section,p_id,p_revision,p_name,p_code,p_photo,p_clear_photo,p_unavailable);
 update workshop_private.catalog75 set managers_only=coalesce(p_managers_only,false) where id=p_id and section=p_section;
 return public.workshop_catalog_editor89(p_section);
end $$;
do $$begin
 if to_regprocedure('public.workshop_oils72_before90(jsonb,integer)') is null then alter function public.workshop_oils72(jsonb,integer) rename to workshop_oils72_before90;end if;
 if to_regprocedure('public.workshop_list_orders_before90(integer)') is null then alter function public.workshop_list_orders(integer) rename to workshop_list_orders_before90;end if;
 if to_regprocedure('public.workshop_save_order_before90(uuid,integer,jsonb,text)') is null then alter function public.workshop_save_order(uuid,integer,jsonb,text) rename to workshop_save_order_before90;end if;
end $$;
create or replace function public.workshop_oils72(p_items jsonb default null,p_version integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;manager boolean;begin
 manager:=workshop_private.catalog_manager90();
 if p_items is not null and exists(select 1 from jsonb_array_elements(p_items) o where o ? 'managers_only' and jsonb_typeof(o->'managers_only')<>'boolean') then raise exception 'Visibilité du produit invalide.';end if;
 r:=public.workshop_oils72_before90(p_items,p_version);
 if not manager and jsonb_typeof(r->'items')='array' then r:=jsonb_set(r,'{items}',(select coalesce(jsonb_agg(o order by ord),'[]') from jsonb_array_elements(r->'items') with ordinality q(o,ord) where not coalesce((o->>'managers_only')::boolean,false)));end if;
 return r;end $$;
-- Métadonnées calculées depuis le catalogue, jamais depuis le formulaire client.
create or replace function workshop_private.order_line90(line jsonb) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m record;o jsonb;section_name text:='Divers';icon_name text:='misc';begin
 if (select count(*) from workshop_private.match_product79(line))=1 then
  select * into m from workshop_private.match_product79(line);section_name:=m.section;
  if m.kind='oil' then
   select x into o from workshop_private.oil_catalog72 t cross join lateral jsonb_array_elements(t.items) x where x->>'id'=m.id;
   icon_name:=case when o->>'kind'='tank' or coalesce(o->>'pack','') ~* '(^|[^0-9])1[ ]?000[ ]*L' then 'tank' when coalesce(o->>'pack','') ~* '(^|[^0-9])(200|210|60)[ ]*L' then 'drum' when coalesce(o->>'pack','') ~* '(^|[^0-9])20[ ]*L' then 'can' else 'oil' end;
  else icon_name:='photo';end if;
 end if;
 return line||jsonb_build_object('section90',section_name,'icon90',icon_name);
end $$;
create or replace function workshop_private.order_view90(r jsonb,manager boolean) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare lines jsonb;begin
 if r is null or jsonb_typeof(r->'items') is distinct from 'array' then return r;end if;
 select coalesce(jsonb_agg(workshop_private.order_line90(i)||jsonb_build_object('previous_out_of_stock',coalesce(r->>'status','')='pending' and exists(
 select 1 from public.workshop_order_requests prior cross join lateral jsonb_array_elements(prior.items) prev
 where prior.deleted_at is null and prior.status='validated' and prior.week_start=(r->>'week_start')::date-7 and coalesce((prev->>'out_of_stock')::boolean,false)
 and (nullif(prev->>'id','')=nullif(i->>'id','') or lower(trim(prev->>'label'))=lower(trim(i->>'label'))))) order by ord),'[]') into lines
 from jsonb_array_elements(r->'items') with ordinality q(i,ord) where manager or not workshop_private.restricted90(i);
 return jsonb_set(r,'{items}',lines);
end $$;
create or replace function public.workshop_list_orders(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;manager boolean;begin
 manager:=workshop_private.catalog_manager90();r:=public.workshop_list_orders_before90(p_offset);
 return jsonb_set(r,'{items}',(select coalesce(jsonb_agg(workshop_private.order_view90(o,manager) order by ord),'[]') from jsonb_array_elements(r->'items') with ordinality q(o,ord)));
end $$;
create or replace function public.workshop_save_order(p_id uuid,p_version integer,p_items jsonb,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare manager boolean;r jsonb;hidden jsonb;begin
 manager:=workshop_private.catalog_manager90();
 if not manager then
  if jsonb_typeof(p_items) is distinct from 'array' then raise exception 'Liste invalide.';end if;
  if exists(select 1 from jsonb_array_elements(p_items) i where workshop_private.restricted90(i)) then raise exception 'Cet article est réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
  perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
  perform 1 from public.workshop_order_requests where id=p_id for update;
  select coalesce(jsonb_agg(i),'[]') into hidden from public.workshop_order_requests o cross join lateral jsonb_array_elements(o.items) i where o.id=p_id and workshop_private.restricted90(i);
  -- Ne jamais effacer les lignes masquées quand un collaborateur enregistre.
  p_items:=p_items||hidden;
 end if;
 r:=public.workshop_save_order_before90(p_id,p_version,p_items,p_notes);
 return workshop_private.order_view90(r,manager);
end $$;
-- Défense sur toute écriture, y compris les anciennes RPC encore utilisées.
create or replace function workshop_private.guard_order90() returns trigger language plpgsql security definer set search_path='' as $$
declare i jsonb;old_i jsonb;begin
 if auth.uid() is null or workshop_private.catalog_manager90() then return new;end if;
 for i in select value from jsonb_array_elements(new.items) loop
  if workshop_private.restricted90(i) then
   old_i:=null;if tg_op='UPDATE' then select x into old_i from jsonb_array_elements(old.items) x where nullif(x->>'id','')=nullif(i->>'id','');end if;
   if old_i is null or (i->>'label') is distinct from (old_i->>'label') or (i->>'quantity') is distinct from (old_i->>'quantity') or coalesce(i->>'out_of_stock','false') is distinct from coalesce(old_i->>'out_of_stock','false') then raise exception 'Article réservé à l’administration et à la modération.' using errcode='42501';end if;
  end if;
 end loop;
 if tg_op='UPDATE' and exists(select 1 from jsonb_array_elements(old.items) x where workshop_private.restricted90(x) and not exists(select 1 from jsonb_array_elements(new.items) y where nullif(y->>'id','')=nullif(x->>'id','') and y->>'label'=x->>'label' and y->>'quantity'=x->>'quantity' and coalesce(y->>'out_of_stock','false')=coalesce(x->>'out_of_stock','false'))) then raise exception 'Une ligne réservée ne peut pas être retirée par un collaborateur.' using errcode='42501';end if;
 return new;
end $$;
drop trigger if exists guard_order90 on public.workshop_order_requests;
create trigger guard_order90 before insert or update of items on public.workshop_order_requests for each row execute function workshop_private.guard_order90();
revoke all on function public.workshop_oils72_before90(jsonb,integer),public.workshop_list_orders_before90(integer),public.workshop_save_order_before90(uuid,integer,jsonb,text),workshop_private.catalog_manager90(),workshop_private.restricted90(jsonb),workshop_private.order_line90(jsonb),workshop_private.order_view90(jsonb,boolean),workshop_private.guard_order90() from public,anon,authenticated;
revoke all on function public.workshop_catalog_save90(text,uuid,integer,text,text,text,boolean,boolean,boolean),public.workshop_catalog89(text,integer),public.workshop_catalog76(text,integer),public.workshop_oils72(jsonb,integer),public.workshop_list_orders(integer),public.workshop_save_order(uuid,integer,jsonb,text) from public,anon;
grant execute on function public.workshop_catalog_save90(text,uuid,integer,text,text,text,boolean,boolean,boolean),public.workshop_catalog89(text,integer),public.workshop_catalog76(text,integer),public.workshop_oils72(jsonb,integer),public.workshop_list_orders(integer),public.workshop_save_order(uuid,integer,jsonb,text) to authenticated;
notify pgrst,'reload schema';commit;
