-- MAJ60 — après MAJ59. Réexécutable. Suppression définitive des données BEG.
begin;
alter table public.workshop_leave_requests add column if not exists ever_accepted boolean not null default false;
update public.workshop_leave_requests set ever_accepted=true where status='accepted' or exists(select 1 from jsonb_array_elements(history) h where h->>'status'='accepted');
create or replace function workshop_private.leave_lock_accepted() returns trigger language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 if tg_op='DELETE' then a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Seul l’administrateur peut supprimer une demande.' using errcode='42501';end if;return old;end if;
 if tg_op='UPDATE' then
 new.ever_accepted:=old.ever_accepted or new.status='accepted';
 if old.ever_accepted and (new.first_name,new.last_name,new.centre,new.periods) is distinct from (old.first_name,old.last_name,old.centre,old.periods) then
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Congés déjà validés : modification réservée à l’administrateur.' using errcode='42501';end if;end if;
 else new.ever_accepted:=new.status='accepted';end if;return new;end $$;
drop trigger if exists workshop_leave_accepted_lock on public.workshop_leave_requests;
create trigger workshop_leave_accepted_lock before insert or update or delete on public.workshop_leave_requests for each row execute function workshop_private.leave_lock_accepted();
-- Enrichit la liste existante sans contourner son verrou de rubrique ni ses droits.
do $$begin if to_regprocedure('public.workshop_leave_list_before60(integer)') is null then alter function public.workshop_leave_list(integer) rename to workshop_leave_list_before60;end if;end $$;
create or replace function public.workshop_leave_list(p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin r:=public.workshop_leave_list_before60(p_offset);return (select coalesce(jsonb_agg(x||jsonb_build_object('ever_accepted',(select ever_accepted from public.workshop_leave_requests where id=(x->>'id')::uuid)) order by n),'[]') from jsonb_array_elements(r) with ordinality t(x,n));end $$;
alter table public.workshop_waste add column if not exists is_full boolean;
alter table public.workshop_waste add column if not exists full_expected date;
create or replace function workshop_private.waste_provider(c jsonb) returns text language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;p text;n text;begin
 if c is null or jsonb_typeof(c)<>'array' or jsonb_array_length(c) not between 1 and 7 then raise exception 'Sélection de déchets invalide.';end if;
 if (select count(distinct x) from jsonb_array_elements(c)x)<>jsonb_array_length(c) then raise exception 'Déchet en double.';end if;
 for v in select value from jsonb_array_elements(c) loop k:=v#>>'{}';
 if jsonb_typeof(v)<>'string' or k not in ('batteries','ferraille','fonte','aluminium','filtres','huiles','bidons','futs','souilles','refroidissement','aerosols','pneus') then raise exception 'Déchet invalide.';end if;
 n:=case when k='pneus' then 'Gurdebeke' when k in ('batteries','ferraille','fonte','aluminium') then 'Grandidier' else 'Chimirec' end;
 if p is not null and n<>p then raise exception 'Crée une demande séparée pour chaque prestataire.';end if;p:=n;
 end loop;return p;end $$;
create or replace function workshop_private.check_waste_counts(c jsonb,q jsonb) returns void language plpgsql set search_path='' as $$
declare k text;n numeric;begin
 perform workshop_private.waste_provider(c);if q is null or jsonb_typeof(q)<>'object' then raise exception 'Quantités invalides.';end if;
 if c='["pneus"]'::jsonb then if q<>'{}'::jsonb then raise exception 'Précise l’état de la benne à pneus, sans nombre de bacs.';end if;return;end if;
 for k in select jsonb_array_elements_text(c) loop
 if not q ? k or jsonb_typeof(q->k)<>'number' then raise exception 'Renseigne chaque quantité.';end if;n:=(q->>k)::numeric;
 if k='huiles' then if n<=0 or n>100000 or round(n,1)<>n then raise exception 'Huiles : de 0,1 à 100 000 litres, une décimale maximum.';end if;
 elsif n<1 or n>999 or trunc(n)<>n then raise exception 'Quantité : entier de 1 à 999.';end if;end loop;
 if (select count(*) from jsonb_object_keys(q))<>jsonb_array_length(c) then raise exception 'Quantités incohérentes.';end if;
end $$;
create or replace function workshop_private.check_tyre_status(c jsonb,p_full boolean,p_expected date) returns void language plpgsql set search_path='' as $$begin
 if c='["pneus"]'::jsonb then
 if p_full is null then raise exception 'Indique si la benne à pneus est pleine.';end if;
 if not p_full and (p_expected is null or p_expected<(now() at time zone 'Europe/Paris')::date or p_expected>(now() at time zone 'Europe/Paris')::date+366) then raise exception 'Indique une date prévue de remplissage entre aujourd’hui et un an.';end if;
 if p_full and p_expected is not null then raise exception 'La benne est pleine : aucune date prévisionnelle nécessaire.';end if;
 elsif p_full is not null or p_expected is not null then raise exception 'État de benne réservé aux pneus.';end if;
end $$;
alter table public.workshop_waste drop constraint if exists workshop_waste_tyre_status_check;
alter table public.workshop_waste add constraint workshop_waste_tyre_status_check check((provider='Gurdebeke' and is_full is not null and ((is_full and full_expected is null) or (not is_full and full_expected is not null))) or (provider<>'Gurdebeke' and is_full is null and full_expected is null));

create or replace function public.workshop_create_waste_v60(p_id uuid,p_categories jsonb,p_notes text,p_counts jsonb,p_full boolean,p_expected date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');perform workshop_private.check_waste_counts(p_categories,p_counts);perform workshop_private.check_tyre_status(p_categories,p_full,p_expected);
 if p_id is null or p_notes is null or length(p_notes)>2000 then raise exception 'Formulaire invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('waste:'||p_id::text,0));select * into r from public.workshop_waste where id=p_id;
 if found then if r.author_id is distinct from auth.uid() or r.categories is distinct from p_categories or r.bin_counts is distinct from p_counts or r.is_full is distinct from p_full or r.full_expected is distinct from p_expected or r.notes is distinct from trim(p_notes) then raise exception 'Cette demande existe déjà.';end if;return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 insert into public.workshop_waste(id,author_id,author_name,categories,notes,bin_counts,provider,is_full,full_expected) values(p_id,auth.uid(),coalesce(person,a->>'user'),p_categories,trim(p_notes),p_counts,workshop_private.waste_provider(p_categories),p_full,p_expected) returning * into r;return to_jsonb(r);end $$;

create or replace function public.workshop_update_waste_v60(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb,p_full boolean,p_expected date) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('waste');if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 perform workshop_private.check_waste_counts(p_categories,p_counts);perform workshop_private.check_tyre_status(p_categories,p_full,p_expected);if p_notes is null or length(p_notes)>2000 then raise exception 'Précisions invalides.';end if;
 select * into r from public.workshop_waste where id=p_id for update;if not found then raise exception 'Demande introuvable.';end if;
 if p_version is distinct from r.version then raise exception 'Demande modifiée entre-temps.';end if;
 if r.provider<>workshop_private.waste_provider(p_categories) then raise exception 'Le prestataire ne peut pas être changé : crée une nouvelle demande.';end if;
 if r.categories=p_categories and r.notes=trim(p_notes) and r.bin_counts=p_counts and r.is_full is not distinct from p_full and r.full_expected is not distinct from p_expected then return to_jsonb(r);end if;
 select name into person from public.workshop_staff where id=a->>'self';
 update public.workshop_waste set categories=p_categories,notes=trim(p_notes),bin_counts=p_counts,is_full=p_full,full_expected=p_expected,version=version+1,updated_at=now(),updated_name=coalesce(person,a->>'user'),validated_at=null,validated_name=null,validated_by=null,collected_at=null,collected_name=null where id=p_id returning * into r;return to_jsonb(r);end $$;
create or replace function public.workshop_create_waste(p_id uuid,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return public.workshop_create_waste_v60(p_id,p_categories,p_notes,p_counts,null,null);end $$;
create or replace function public.workshop_update_waste(p_id uuid,p_version integer,p_categories jsonb,p_notes text,p_counts jsonb) returns jsonb language plpgsql security definer set search_path='' as $$begin return public.workshop_update_waste_v60(p_id,p_version,p_categories,p_notes,p_counts,null,null);end $$;

create or replace function public.workshop_waste_by_provider(p_provider text,p_offset integer default 0) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();perform workshop_private.assert_section('waste');
 if p_provider not in ('Grandidier','Chimirec','Gurdebeke') or p_provider is null or p_offset is null or p_offset<0 then raise exception 'Prestataire ou page invalide.';end if;
 if a->>'role'='guest' then return jsonb_build_object('can_manage',false,'total',0,'items','[]'::jsonb);end if;
 return jsonb_build_object('can_manage',coalesce((a->>'manager')::boolean,false),'total',(select count(*) from public.workshop_waste where provider=p_provider),'items',(select coalesce(jsonb_agg(to_jsonb(w) order by created_at desc,id),'[]') from (select * from public.workshop_waste where provider=p_provider order by created_at desc,id limit 30 offset p_offset)w));end $$;

delete from public.workshop_target_sale_edits where sale_id in (select id from public.workshop_target_sales where category='beg');
delete from public.workshop_target_sales where category='beg';
alter table public.workshop_target_sales drop constraint if exists workshop_target_sales_category_check;
alter table public.workshop_target_sales add constraint workshop_target_sales_category_check check(category in ('purge','batteries','geometry','clim'));
alter table public.workshop_service_targets drop column if exists beg;

create or replace function public.workshop_service_targets(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor_before30();if p_date is null then raise exception 'Date requise.';end if;return (select jsonb_build_object('date',date,'purge',purge,'batteries',batteries,'geometry',geometry,'clim',clim) from public.workshop_service_targets where date=p_date);end $$;

create or replace function public.workshop_import_daily_targets(p_rows jsonb,p_replace boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;k text;d date;n integer;saved integer:=0;skipped integer:=0;seen date[]:='{}';
begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Import réservé à l’administrateur.' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 366 or p_replace is null then raise exception 'Import invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('daily-targets-import',0));
 for r in select value from jsonb_array_elements(p_rows) loop
 if r->>'date' is null or r->>'date' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'Date invalide.';end if;d:=(r->>'date')::date;if d=any(seen) then raise exception 'Date en double.';end if;seen:=array_append(seen,d);
 foreach k in array array['purge','batteries','geometry','clim'] loop
 if r->>k is null or r->>k !~ '^[0-9]{1,6}$' or (r->>k)::integer>100000 then raise exception 'Cible invalide : %',k;end if;end loop;
 if p_replace then
 insert into public.workshop_service_targets values(d,(r->>'purge')::integer,(r->>'batteries')::integer,(r->>'geometry')::integer,(r->>'clim')::integer,now(),auth.uid()) on conflict(date) do update set purge=excluded.purge,batteries=excluded.batteries,geometry=excluded.geometry,clim=excluded.clim,updated_at=now(),updated_by=auth.uid();
 else insert into public.workshop_service_targets values(d,(r->>'purge')::integer,(r->>'batteries')::integer,(r->>'geometry')::integer,(r->>'clim')::integer,now(),auth.uid()) on conflict(date) do nothing;end if;
 get diagnostics n=row_count;saved:=saved+n;skipped:=skipped+1-n;
 end loop;return jsonb_build_object('saved',saved,'skipped',skipped);end $$;

create or replace function public.workshop_save_service_targets(p_date date,p_targets jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;k text;current_targets jsonb;
begin
 a:=workshop_private.actor();
 if not coalesce((a->>'manager')::boolean,false) then raise exception 'Modification des cibles réservée à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 if p_date is null or p_targets is null or jsonb_typeof(p_targets)<>'object' then raise exception 'Cibles invalides.';end if;
 if p_targets-array['purge','batteries','geometry','clim']<>'{}'::jsonb then raise exception 'Catégorie inconnue.';end if;
 foreach k in array array['purge','batteries','geometry','clim'] loop
  if not(p_targets ? k) or jsonb_typeof(p_targets->k)<>'number' or (p_targets->>k)!~ '^(0|[1-9][0-9]*)$' then raise exception 'Chaque cible doit être un entier entre 0 et 100000.';end if;
  if (p_targets->>k)::numeric>100000 then raise exception 'Chaque cible doit être un entier entre 0 et 100000.';end if;
 end loop;
 -- Même verrou que l’import PDF : aucun écrasement silencieux entre les deux.
 perform pg_advisory_xact_lock(hashtextextended('daily-targets-import',0));
 current_targets:=public.workshop_service_targets(p_date);
 if current_targets is distinct from p_expected then raise exception 'Les cibles ont été modifiées ailleurs. Actualise-les avant de recommencer.';end if;
 insert into public.workshop_service_targets(date,purge,batteries,geometry,clim,updated_at,updated_by)
 values(p_date,(p_targets->>'purge')::integer,(p_targets->>'batteries')::integer,(p_targets->>'geometry')::integer,(p_targets->>'clim')::integer,clock_timestamp(),auth.uid())
 on conflict(date) do update set purge=excluded.purge,batteries=excluded.batteries,geometry=excluded.geometry,clim=excluded.clim,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 return public.workshop_target_sales_status(p_date);
end $$;

do $$begin execute replace(pg_get_functiondef('public.workshop_add_target_sale(uuid,date,text)'::regprocedure),'''beg'',','');end $$;
revoke all on function workshop_private.leave_lock_accepted(),workshop_private.check_tyre_status(jsonb,boolean,date),public.workshop_leave_list_before60(integer),public.workshop_leave_list(integer),public.workshop_create_waste_v60(uuid,jsonb,text,jsonb,boolean,date),public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date) from public,anon,authenticated;
grant execute on function public.workshop_leave_list(integer),public.workshop_create_waste_v60(uuid,jsonb,text,jsonb,boolean,date),public.workshop_update_waste_v60(uuid,integer,jsonb,text,jsonb,boolean,date) to authenticated;
notify pgrst,'reload schema';commit;
