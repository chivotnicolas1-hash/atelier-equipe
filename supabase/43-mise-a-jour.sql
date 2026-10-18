-- MAJ43 : mise à jour d’une base existante (MAJ40 minimum). Inclut MAJ42.
-- MAJ42, après 40-profils-signalements.sql. 40b et 41 facultatifs.
begin;
-- Désactivation de toute ancienne entrée du débrief payant.
do $$begin
 if to_regprocedure('public.workshop_debrief_context(date,integer)') is not null then
 revoke all on function public.workshop_debrief_context(date,integer) from public,anon,authenticated;
 end if;
end $$;

-- Formulaire F9900, réservé aux gestionnaires, avec protection contre les écrasements.
create table if not exists public.workshop_quality_settings(id boolean primary key default true check(id),url text not null default '',version integer not null default 0);
insert into public.workshop_quality_settings(id) values(true) on conflict do nothing;
alter table public.workshop_quality_settings enable row level security;
revoke all on public.workshop_quality_settings from public,anon,authenticated;
create or replace function public.workshop_quality_form(p_url text default null,p_version integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_quality_settings%rowtype;
begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Accès réservé à l’administrateur et aux modérateurs.' using errcode='42501';end if;
 select * into r from public.workshop_quality_settings where id for update;
 if p_url is not null then
 if p_version is distinct from r.version then raise exception 'Configuration modifiée ailleurs. Actualise la page.';end if;
 if p_url<>'' and (length(p_url)>1500 or p_url !~ '^https://docs[.]google[.]com/forms/d/(e/)?[A-Za-z0-9_-]+/viewform[?]embedded=true$') then raise exception 'Lien Google Forms invalide.';end if;
 update public.workshop_quality_settings set url=p_url,version=version+1 where id returning * into r;
 end if;return jsonb_build_object('url',r.url,'version',r.version);end $$;

-- Tous les comptes, y compris invités, peuvent enregistrer uniquement leur propre signature.
create or replace function public.workshop_signature_gate() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin a:=workshop_private.actor_before30();return jsonb_build_object('admin',coalesce((a->>'admin')::boolean,false),'required',not exists(select 1 from public.workshop_signatures where user_id=auth.uid() and signature is not null));end $$;
create or replace function public.workshop_my_signature() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_signatures%rowtype;t text;begin a:=workshop_private.actor_before30();select * into r from public.workshop_signatures where user_id=auth.uid();select team into t from public.workshop_staff where id=a->>'self';return jsonb_build_object('signature',r.signature,'job_title',coalesce(nullif(r.job_title,''),t,''),'version',coalesce(r.version,0));end $$;
create or replace function public.workshop_save_signature(p_signature text,p_job_title text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_signatures%rowtype;t text;effective text;
begin a:=workshop_private.actor_before30();
 if p_signature is null or length(p_signature)>120000 or p_signature !~ '^data:image/png;base64,iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$' then raise exception 'Une signature PNG est obligatoire.';end if;
 if p_job_title is null or length(trim(p_job_title))>100 then raise exception 'Fonction limitée à 100 caractères.';end if;
 perform pg_advisory_xact_lock(hashtextextended('signature:'||auth.uid()::text,0));select * into r from public.workshop_signatures where user_id=auth.uid();
 if p_version is distinct from coalesce(r.version,0) then raise exception 'Profil modifié ailleurs. Actualise la page.';end if;
 select team into t from public.workshop_staff where id=a->>'self';effective:=coalesce(nullif(r.job_title,''),t,'');
 if not coalesce((a->>'admin')::boolean,false) then
 if p_job_title is distinct from effective then raise exception 'La fonction est modifiable uniquement par l’administrateur.' using errcode='42501';end if;
 p_job_title:=coalesce(r.job_title,'');end if;
 insert into public.workshop_signatures(user_id,signature,job_title) values(auth.uid(),p_signature,trim(p_job_title)) on conflict(user_id) do update set signature=excluded.signature,job_title=excluded.job_title,version=workshop_signatures.version+1,updated_at=now();
end $$;

-- Suppression personnelle. On conserve la clé d’événement pour ne pas recréer une notification programmée.
alter table public.workshop_messages add column if not exists deleted_at timestamptz;
create or replace function public.workshop_delete_notification(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor_before30();update public.workshop_messages set deleted_at=coalesce(deleted_at,now()),read_at=coalesce(read_at,now()),body='',url='/' where id=p_id and user_id=auth.uid();end $$;
create or replace function public.workshop_message_status(p_read uuid default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;latest date;begin a:=workshop_private.actor_before30();
 if p_read is not null then update public.workshop_messages set read_at=coalesce(read_at,now()) where id=p_read and user_id=auth.uid() and deleted_at is null;end if;
 if coalesce((a->>'manager')::boolean,false) then select max(date) into latest from public.workshop_handover where release_at<=now();end if;
 return jsonb_build_object('recap_date',latest,'recap_unread',coalesce(latest>(select last_date from public.workshop_recap_reads where user_id=auth.uid()),latest is not null),'items',(select coalesce(jsonb_agg(to_jsonb(m) order by created_at desc),'[]') from (select id,body,url,created_at,read_at from public.workshop_messages where user_id=auth.uid() and deleted_at is null order by created_at desc limit 100)m));end $$;

-- Origine non déduite des anciens niveaux : les anciens dossiers restent « à préciser ».
alter table public.workshop_disputes add column if not exists customer_service boolean;
alter table public.workshop_disputes add column if not exists resolution text not null default '';
alter table public.workshop_disputes add column if not exists closed_at timestamptz;
alter table public.workshop_disputes add column if not exists closed_name text;
create or replace function public.workshop_save_dispute(p_id uuid,p_version integer,p_client text,p_registration text,p_description text,p_followup text,p_status text,p_level integer,p_customer_service boolean,p_resolution text) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_disputes%rowtype;person text;
begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Litiges réservés aux gestionnaires.' using errcode='42501';end if;
 if p_customer_service is null then raise exception 'Précise si le service client Norauto a contacté l’atelier.';end if;
 if p_customer_service and (p_level is null or p_level not between 1 and 3) then raise exception 'Choisis le niveau 1, 2 ou 3.';end if;
 if p_resolution is null or length(p_resolution)>6000 or (p_status='resolved' and length(trim(p_resolution))=0) then raise exception 'Renseigne la résolution pour clôturer le dossier.';end if;
 perform pg_advisory_xact_lock(hashtextextended('dispute:'||p_id::text,0));select * into r from public.workshop_disputes where id=p_id for update;
 perform public.workshop_save_dispute(p_id,p_version,p_client,p_registration,p_description,p_followup,p_status);
 select updated_name into person from public.workshop_disputes where id=p_id;
 update public.workshop_disputes set customer_service=p_customer_service,level=case when p_customer_service then p_level else null end,resolution=trim(p_resolution),closed_at=case when p_status='resolved' then case when r.status='resolved' then coalesce(r.closed_at,now()) else now() end else null end,closed_name=case when p_status='resolved' then case when r.status='resolved' then coalesce(r.closed_name,person) else person end else null end where id=p_id;
end $$;
-- Les anciennes interfaces ne doivent pas contourner la résolution obligatoire.
revoke all on function public.workshop_save_dispute(uuid,integer,text,text,text,text,text),public.workshop_save_dispute(uuid,integer,text,text,text,text,text,integer) from public,anon,authenticated;
revoke all on function public.workshop_quality_form(text,integer),public.workshop_signature_gate(),public.workshop_my_signature(),public.workshop_save_signature(text,text,integer),public.workshop_delete_notification(uuid),public.workshop_message_status(uuid),public.workshop_save_dispute(uuid,integer,text,text,text,text,text,integer,boolean,text) from public,anon,authenticated;
grant execute on function public.workshop_quality_form(text,integer),public.workshop_signature_gate(),public.workshop_my_signature(),public.workshop_save_signature(text,text,integer),public.workshop_delete_notification(uuid),public.workshop_message_status(uuid),public.workshop_save_dispute(uuid,integer,text,text,text,text,text,integer,boolean,text) to authenticated;
notify pgrst,'reload schema';commit;

-- MAJ43. Nécessite MAJ42. Réexécutable.
begin;
create table if not exists public.workshop_service_targets(date date primary key,purge integer not null check(purge between 0 and 100000),batteries integer not null check(batteries between 0 and 100000),beg integer not null check(beg between 0 and 100000),geometry integer not null check(geometry between 0 and 100000),clim integer not null check(clim between 0 and 100000),updated_at timestamptz not null default now(),updated_by uuid references auth.users(id) on delete set null);
alter table public.workshop_service_targets enable row level security;
revoke all on public.workshop_service_targets from public,anon,authenticated;
create or replace function public.workshop_service_targets(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor_before30();if p_date is null then raise exception 'Date requise.';end if;return (select jsonb_build_object('date',date,'purge',purge,'batteries',batteries,'beg',beg,'geometry',geometry,'clim',clim) from public.workshop_service_targets where date=p_date);end $$;
create or replace function public.workshop_import_daily_targets(p_rows jsonb,p_replace boolean default false) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;k text;d date;n integer;saved integer:=0;skipped integer:=0;seen date[]:='{}';
begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Import réservé à l’administrateur.' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' or jsonb_array_length(p_rows) not between 1 and 366 or p_replace is null then raise exception 'Import invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('daily-targets-import',0));
 for r in select value from jsonb_array_elements(p_rows) loop
 if r->>'date' is null or r->>'date' !~ '^20[0-9]{2}-[0-9]{2}-[0-9]{2}$' then raise exception 'Date invalide.';end if;d:=(r->>'date')::date;if d=any(seen) then raise exception 'Date en double.';end if;seen:=array_append(seen,d);
 foreach k in array array['purge','batteries','beg','geometry','clim'] loop
 if r->>k is null or r->>k !~ '^[0-9]{1,6}$' or (r->>k)::integer>100000 then raise exception 'Cible invalide : %',k;end if;end loop;
 if p_replace then
 insert into public.workshop_service_targets values(d,(r->>'purge')::integer,(r->>'batteries')::integer,(r->>'beg')::integer,(r->>'geometry')::integer,(r->>'clim')::integer,now(),auth.uid()) on conflict(date) do update set purge=excluded.purge,batteries=excluded.batteries,beg=excluded.beg,geometry=excluded.geometry,clim=excluded.clim,updated_at=now(),updated_by=auth.uid();
 else insert into public.workshop_service_targets values(d,(r->>'purge')::integer,(r->>'batteries')::integer,(r->>'beg')::integer,(r->>'geometry')::integer,(r->>'clim')::integer,now(),auth.uid()) on conflict(date) do nothing;end if;
 get diagnostics n=row_count;saved:=saved+n;skipped:=skipped+1-n;
 end loop;return jsonb_build_object('saved',saved,'skipped',skipped);end $$;
create or replace function public.workshop_delete_all_notifications() returns void language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor_before30();update public.workshop_messages set deleted_at=now(),read_at=coalesce(read_at,now()),body='',url='/' where user_id=auth.uid() and deleted_at is null;end $$;
revoke all on function public.workshop_service_targets(date),public.workshop_import_daily_targets(jsonb,boolean),public.workshop_delete_all_notifications() from public,anon,authenticated;
grant execute on function public.workshop_service_targets(date),public.workshop_import_daily_targets(jsonb,boolean),public.workshop_delete_all_notifications() to authenticated;
notify pgrst,'reload schema';commit;
