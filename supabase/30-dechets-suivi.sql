-- MAJ30 : à exécuter après 29-releves-dechets.sql. Réexécutable.
begin;
alter table public.workshop_waste add column if not exists bin_counts jsonb not null default '{}';
alter table public.workshop_waste add column if not exists collected_at timestamptz;
alter table public.workshop_waste add column if not exists collected_name text;
alter table public.workshop_waste add column if not exists updated_at timestamptz;
alter table public.workshop_waste add column if not exists updated_name text;
-- Les anciennes demandes conservent un nombre inconnu, sans quantité inventée.
create or replace function workshop_private.check_waste_counts(c jsonb,q jsonb) returns void language plpgsql set search_path='' as $$
declare k text;v jsonb;
begin
 if c is null or jsonb_typeof(c)<>'array' or q is null or jsonb_typeof(q)<>'object' then raise exception 'Déchets ou nombres de bacs invalides.';end if;
 if jsonb_array_length(c) not between 1 and 5 or (select count(distinct x) from jsonb_array_elements(c) x)<>jsonb_array_length(c) then raise exception 'Sélection de déchets invalide.';end if;
 for v in select value from jsonb_array_elements(c) loop
  k:=v#>>'{}';
  if jsonb_typeof(v)<>'string' or k not in ('batteries','ferraille','fonte','aluminium','filtres') then raise exception 'Type de déchet invalide.';end if;
  if not q ? k or jsonb_typeof(q->k)<>'number' then raise exception 'Renseigne le nombre de bacs pour chaque déchet.';end if;
  if (q->>k)::numeric<1 or (q->>k)::numeric>999 or trunc((q->>k)::numeric)<>(q->>k)::numeric then raise exception 'Nombre de bacs : entier de 1 à 999.';end if;
 end loop;
 if (select count(*) from jsonb_object_keys(q))<>jsonb_array_length(c) then raise exception 'Quantités incohérentes avec les déchets sélectionnés.';end if;
end $$;
revoke all on function workshop_private.check_waste_counts(jsonb,jsonb) from public,anon,authenticated;
create or replace function public.workshop_create_waste(p_id uuid,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;result jsonb;
begin
 a:=workshop_private.actor();perform workshop_private.check_waste_counts(p_categories,p_counts);
 if p_id is null then raise exception 'Identifiant manquant.';end if;
 perform pg_advisory_xact_lock(hashtextextended('waste:'||p_id::text,0));
 select * into r from public.workshop_waste where id=p_id;
 if found and r.bin_counts is distinct from p_counts then raise exception 'Cette demande existe déjà avec une autre quantité.';end if;
 result:=public.workshop_create_waste(p_id,p_categories,p_notes);
 update public.workshop_waste set bin_counts=p_counts where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
-- L'ancien appel sans quantités n'est plus accessible aux clients.
revoke all on function public.workshop_create_waste(uuid,jsonb,text) from public,anon,authenticated;
create or replace function public.workshop_update_waste(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Modification réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 perform workshop_private.check_waste_counts(p_categories,p_counts);
 if p_notes is null or length(p_notes)>2000 then raise exception 'Précisions invalides.';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps : actualise la liste.';end if;
 if r.categories=p_categories and r.notes=trim(p_notes) and r.bin_counts=p_counts then return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set categories=p_categories,notes=trim(p_notes),bin_counts=p_counts,version=version+1,updated_at=now(),updated_name=coalesce(person,a->>'user'),validated_at=null,validated_name=null,validated_by=null,collected_at=null,collected_name=null where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
create or replace function public.workshop_collect_waste(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Confirmation réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if r.collected_at is not null then return to_jsonb(r);end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps : actualise la liste.';end if;
 if r.validated_at is null then raise exception 'Valide d’abord la demande de ramassage.';end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set collected_at=now(),collected_name=coalesce(person,a->>'user'),version=version+1 where id=p_id returning * into r;
 return to_jsonb(r);
end $$;
create or replace function public.workshop_delete_waste(p_id uuid,p_version integer) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;
begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Suppression réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_waste where id=p_id for update;
 if not found then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps : actualise la liste.';end if;
 delete from public.workshop_waste where id=p_id;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_create_waste(uuid,jsonb,text,jsonb),public.workshop_update_waste(uuid,integer,jsonb,text,jsonb),public.workshop_collect_waste(uuid,integer),public.workshop_delete_waste(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_create_waste(uuid,jsonb,text,jsonb),public.workshop_update_waste(uuid,integer,jsonb,text,jsonb),public.workshop_collect_waste(uuid,integer),public.workshop_delete_waste(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
