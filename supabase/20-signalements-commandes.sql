begin;
-- Une affectation existante doit être retirée avant tout changement de poste.
create or replace function workshop_private.protect_station_move() returns trigger language plpgsql set search_path='' as $$
begin
 if old.station is not null and new.station is not null and old.station is distinct from new.station then
  raise exception 'Retire d’abord le collaborateur de son poste actuel avant de l’affecter à un autre poste.';
 end if;
 return new;
end $$;
revoke all on function workshop_private.protect_station_move() from public,anon,authenticated;
drop trigger if exists workshop_station_move_guard on public.workshop_days;
create trigger workshop_station_move_guard before update of station on public.workshop_days for each row execute function workshop_private.protect_station_move();

alter table public.workshop_reports add column if not exists version integer not null default 1;
alter table public.workshop_reports add column if not exists updated_at timestamptz;
alter table public.workshop_reports add column if not exists updated_by uuid references auth.users(id) on delete set null;
create or replace function public.workshop_get_report(p_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype; photos jsonb;
begin
 a:=workshop_private.actor();
 select * into r from public.workshop_reports where id=p_id and ((a->>'reports_all')::boolean or author_id=auth.uid());
 if not found then raise exception 'Signalement introuvable ou non autorisé.' using errcode='42501';end if;
 select coalesce(jsonb_agg(photo order by position),'[]'::jsonb) into photos from public.workshop_report_photos where report_id=p_id;
 return jsonb_build_object('id',r.id,'author_name',r.author_name,'registration',r.registration,'notes',r.notes,'created_at',r.created_at,'photos',photos,'version',r.version,'updated_at',r.updated_at,'can_edit',(a->>'admin')::boolean or r.author_id=auth.uid());
end $$;
create or replace function public.workshop_update_report(p_id uuid,p_version integer,p_registration text,p_notes text,p_photos jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_reports%rowtype; plate text; item jsonb; i integer:=0;
begin
 a:=workshop_private.actor();
 select * into r from public.workshop_reports where id=p_id for update;
 if not found or not ((a->>'admin')::boolean or coalesce(r.author_id=auth.uid(),false)) then raise exception 'Seuls l’auteur et l’administrateur peuvent modifier ce signalement.' using errcode='42501';end if;
 if p_version is distinct from r.version then raise exception 'Ce signalement a été modifié entre-temps. Ferme puis rouvre sa fiche.';end if;
 plate:=upper(trim(p_registration));
 if plate is null or length(plate) not between 3 and 20 or plate !~ '^[A-Z0-9][A-Z0-9 -]+[A-Z0-9]$' then raise exception 'Immatriculation invalide.';end if;
 if p_notes is null or length(p_notes)>2000 then raise exception 'Commentaire limité à 2000 caractères.';end if;
 if p_photos is null or jsonb_typeof(p_photos)<>'array' then raise exception 'Liste de photos invalide.';end if;
 if jsonb_array_length(p_photos)>5 then raise exception 'Maximum 5 photos par signalement.';end if;
 for item in select value from jsonb_array_elements(p_photos) loop
  if jsonb_typeof(item)<>'string' or length(item#>>'{}')>300000 or (item#>>'{}') !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$' then raise exception 'Photo invalide ou trop volumineuse.';end if;
 end loop;
 update public.workshop_reports set registration=plate,notes=trim(p_notes),version=version+1,updated_at=now(),updated_by=auth.uid() where id=p_id;
 delete from public.workshop_report_photos where report_id=p_id;
 for item in select value from jsonb_array_elements(p_photos) loop
  insert into public.workshop_report_photos(report_id,position,photo) values(p_id,i,item#>>'{}');i:=i+1;
 end loop;
 return jsonb_build_object('id',r.id,'created_at',r.created_at,'updated_at',now());
end $$;
revoke all on function public.workshop_update_report(uuid,integer,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.workshop_update_report(uuid,integer,text,text,jsonb) to authenticated;

create table if not exists public.workshop_order_requests(
 id uuid primary key, author_id uuid references auth.users(id) on delete set null,author_name text not null,
 items jsonb not null,notes text not null default '',status text not null default 'pending' check(status in ('pending','validated')),
 version integer not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),
 validated_at timestamptz,validated_by uuid references auth.users(id) on delete set null,validated_name text
);
alter table public.workshop_order_requests enable row level security;
revoke all on public.workshop_order_requests from public,anon,authenticated;
-- Phase pilote : accès administrateur seulement. Aucun autre compte ne peut lire/écrire par API.
create or replace function workshop_private.order_actor() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;
begin a:=workshop_private.actor();if (a->>'admin')::boolean is not true then raise exception 'Le formulaire de commandes est réservé à l’administrateur pendant cette phase de préparation.' using errcode='42501';end if;return a;end $$;
revoke all on function workshop_private.order_actor() from public,anon,authenticated;
create or replace function public.workshop_list_orders(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.order_actor();
 if p_offset is null or p_offset<0 then raise exception 'Page invalide.';end if;
 return jsonb_build_object('total',(select count(*) from public.workshop_order_requests),'items',(select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at desc,r.id),'[]') from (select * from public.workshop_order_requests order by created_at desc,id limit 30 offset p_offset) r));
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
  clean:=clean||jsonb_build_array(jsonb_build_object('label',trim(item->>'label'),'reference',trim(coalesce(item->>'reference','')),'supplier',trim(coalesce(item->>'supplier','')),'quantity',(item->>'quantity')::integer));
 end loop;
 perform pg_advisory_xact_lock(hashtextextended('order:'||p_id::text,0));
 select * into r from public.workshop_order_requests where id=p_id for update;
 if found then
  if r.status='validated' then raise exception 'Cette demande est validée et ne peut plus être modifiée.';end if;
  if p_version is distinct from r.version then raise exception 'La demande a changé entre-temps. Ferme puis rouvre-la.';end if;
  update public.workshop_order_requests set items=clean,notes=trim(p_notes),version=version+1,updated_at=now() where id=p_id;
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
commit;
