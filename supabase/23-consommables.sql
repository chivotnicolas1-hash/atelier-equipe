-- MAJ23 : appliquer après MAJ22. Accès équipe et encadrants.
begin;
create or replace function workshop_private.order_actor() returns jsonb language plpgsql security definer set search_path='' as $$
begin return workshop_private.actor();end $$;
revoke all on function workshop_private.order_actor() from public,anon,authenticated;
create or replace function public.workshop_list_orders(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; can_manage boolean;
begin
 a:=workshop_private.order_actor();can_manage:=coalesce((a->>'reports_all')::boolean,false);
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('can_manage',can_manage,'total',(select count(*) from public.workshop_order_requests where can_manage or author_id=auth.uid()),'items',(select coalesce(jsonb_agg(to_jsonb(r)||jsonb_build_object('can_edit',can_manage or (r.author_id=auth.uid() and r.status='pending')) order by r.created_at desc,r.id),'[]') from (select * from public.workshop_order_requests where can_manage or author_id=auth.uid() order by created_at desc,id limit 30 offset p_offset) r));
end $$;
create or replace function public.workshop_save_order(p_id uuid,p_version integer,p_items jsonb,p_notes text) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; item jsonb; clean jsonb:='[]'; person text;
begin
 a:=workshop_private.order_actor();
 if p_id is null or p_version is null then raise exception 'Demande invalide.';end if;
 if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Liste d’articles invalide.';end if;
 if jsonb_array_length(p_items) not between 1 and 30 then raise exception 'Ajoute de 1 à 30 articles.';end if;
 if p_notes is null or length(p_notes)>2000 then raise exception 'Commentaire limité à 2000 caractères.';end if;
 for item in select value from jsonb_array_elements(p_items) loop
  if jsonb_typeof(item)<>'object' or length(trim(coalesce(item->>'label',''))) not between 1 and 200 or length(coalesce(item->>'reference',''))>120 or length(coalesce(item->>'supplier',''))>150 then raise exception 'Renseigne un article valide (200 caractères maximum).';end if;
  if jsonb_typeof(item->'quantity') is distinct from 'number' or coalesce(item->>'quantity','') !~ '^[0-9]{1,3}$' or (item->>'quantity')::integer not between 1 and 999 then raise exception 'Quantité entière de 1 à 999 attendue.';end if;
  clean:=clean||jsonb_build_array(jsonb_build_object('label',trim(item->>'label'),'quantity',(item->>'quantity')::integer));
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if found then
  if not coalesce((a->>'reports_all')::boolean,false) and (r.author_id is distinct from auth.uid() or r.status='validated') then raise exception 'Modification réservée à l’auteur avant validation ou aux encadrants.' using errcode='42501';end if;
  if p_version is distinct from r.version then raise exception 'La demande a changé entre-temps. Ferme puis rouvre-la.';end if;
  update public.workshop_order_requests set items=clean,version=version+1,updated_at=now(),status='pending',validated_at=null,validated_by=null,validated_name=null where id=p_id;
 else
  if p_version<>0 then raise exception 'Demande introuvable.';end if;
  select name into person from public.workshop_staff where id=a->>'self';
  insert into public.workshop_order_requests(id,author_id,author_name,items,notes) values(p_id,auth.uid(),coalesce(person,a->>'user'),clean,trim(p_notes));
 end if;
 return (select to_jsonb(o) from public.workshop_order_requests o where id=p_id);
end $$;
create or replace function public.workshop_validate_order(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype; person text;
begin
 a:=workshop_private.order_actor();
 if not ((a->>'admin')::boolean or (a->>'reports_all')::boolean) then raise exception 'Validation réservée aux encadrants.' using errcode='42501';end if;
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if r.status='validated' then return to_jsonb(r);end if;
 if p_version is distinct from r.version then raise exception 'Cette demande a été modifiée. Actualise-la avant validation.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_order_requests set status='validated',version=version+1,updated_at=now(),validated_at=now(),validated_by=auth.uid(),validated_name=coalesce(person,a->>'user') where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
revoke all on function public.workshop_list_orders(integer),public.workshop_save_order(uuid,integer,jsonb,text),public.workshop_validate_order(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_list_orders(integer),public.workshop_save_order(uuid,integer,jsonb,text),public.workshop_validate_order(uuid,integer) to authenticated;
notify pgrst,'reload schema';

create or replace function public.workshop_delete_order(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_order_requests%rowtype;
begin
 a:=workshop_private.order_actor();
 if not coalesce((a->>'reports_all')::boolean,false) then raise exception 'Suppression réservée aux encadrants.' using errcode='42501';end if;
 select * into r from public.workshop_order_requests where id=p_id for update;
 if not found then raise exception 'Commande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'La commande a changé. Ferme puis rouvre-la.';end if;
 delete from public.workshop_order_requests where id=p_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_delete_order(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_delete_order(uuid,integer) to authenticated;
commit;
