-- MAJ39, après MAJ38. Réexécutable.
begin;
create table if not exists public.workshop_signatures(user_id uuid primary key references auth.users(id) on delete cascade,signature text,job_title text not null default '',version integer not null default 1,updated_at timestamptz not null default now());
alter table public.workshop_signatures enable row level security;
revoke all on public.workshop_signatures from public,anon,authenticated;
alter table public.workshop_reports add column if not exists client_notified boolean;
alter table public.workshop_reports add column if not exists author_job text;
alter table public.workshop_reports add column if not exists author_signature text;
alter table public.workshop_reports add column if not exists signed_at timestamptz;
create or replace function public.workshop_my_signature() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_signatures%rowtype;t text;begin a:=workshop_private.actor();select * into r from public.workshop_signatures where user_id=auth.uid();select team into t from public.workshop_staff where id=a->>'self';return jsonb_build_object('signature',r.signature,'job_title',coalesce(nullif(r.job_title,''),t,''),'version',coalesce(r.version,0));end $$;
create or replace function public.workshop_save_signature(p_signature text,p_job_title text,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare r public.workshop_signatures%rowtype;begin perform workshop_private.actor();
 if p_job_title is null or length(trim(p_job_title))>100 then raise exception 'Fonction limitée à 100 caractères.';end if;
 if p_signature is not null and (length(p_signature)>120000 or p_signature !~ '^data:image/png;base64,iVBORw0KGgo[A-Za-z0-9+/]*={0,2}$') then raise exception 'Signature PNG invalide ou trop volumineuse.';end if;
 perform pg_advisory_xact_lock(hashtextextended('signature:'||auth.uid()::text,0));select * into r from public.workshop_signatures where user_id=auth.uid();if p_version is distinct from coalesce(r.version,0) then raise exception 'Profil modifié ailleurs. Ferme puis rouvre Mon profil.';end if;
 insert into public.workshop_signatures(user_id,signature,job_title) values(auth.uid(),p_signature,trim(p_job_title)) on conflict(user_id) do update set signature=excluded.signature,job_title=excluded.job_title,version=workshop_signatures.version+1,updated_at=now();end $$;
-- Une correction via n’importe quelle version de l’application invalide la signature.
create or replace function workshop_private.invalidate_report_signature() returns trigger language plpgsql set search_path='' as $$
begin if (new.version,new.registration,new.notes,new.before_intervention,new.client_notified) is distinct from (old.version,old.registration,old.notes,old.before_intervention,old.client_notified) then new.author_signature:=null;new.signed_at:=null;end if;return new;end $$;
revoke all on function workshop_private.invalidate_report_signature() from public,anon,authenticated;
drop trigger if exists workshop_report_signature_guard on public.workshop_reports;
create trigger workshop_report_signature_guard before update on public.workshop_reports for each row execute function workshop_private.invalidate_report_signature();
create or replace function workshop_private.sign_report(p_id uuid,p_sign boolean) returns void language plpgsql security definer set search_path='' as $$
declare r public.workshop_reports%rowtype;s public.workshop_signatures%rowtype;t text;begin
 select * into r from public.workshop_reports where id=p_id for update;
 if p_sign and r.author_id is distinct from auth.uid() then raise exception 'Seul l’auteur peut apposer sa signature.' using errcode='42501';end if;
 select * into s from public.workshop_signatures where user_id=r.author_id;select st.team into t from public.workshop_staff st join auth.users u on lower(u.email)=st.email where u.id=r.author_id;
 if p_sign and s.signature is null then raise exception 'Enregistre d’abord ta signature dans Mon profil.';end if;
 update public.workshop_reports set author_job=case when author_id=auth.uid() then coalesce(nullif(s.job_title,''),t,author_job) else author_job end,author_signature=case when p_sign then s.signature else null end,signed_at=case when p_sign then now() else null end where id=p_id;
end $$;
revoke all on function workshop_private.sign_report(uuid,boolean) from public,anon,authenticated;
create or replace function public.workshop_create_report(p_id uuid,p_registration text,p_notes text,p_photos jsonb,p_before_intervention boolean,p_client_notified boolean,p_sign boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;r public.workshop_reports%rowtype;already boolean;begin perform workshop_private.actor();if p_client_notified is null or p_sign is null then raise exception 'Choix requis.';end if;
 perform pg_advisory_xact_lock(hashtextextended('report-location:'||p_id::text,0));select * into r from public.workshop_reports where id=p_id;already:=found;
 if already and (r.client_notified is distinct from p_client_notified or (r.author_signature is not null) is distinct from p_sign) then raise exception 'Signalement déjà enregistré avec un autre contexte.';end if;
 result:=public.workshop_create_report(p_id,p_registration,p_notes,p_photos,p_before_intervention);
 if not already then update public.workshop_reports set client_notified=p_client_notified where id=p_id;perform workshop_private.sign_report(p_id,p_sign);end if;return result;end $$;
create or replace function public.workshop_update_report(p_id uuid,p_version integer,p_registration text,p_notes text,p_photos jsonb,p_before_intervention boolean,p_client_notified boolean,p_sign boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();if p_client_notified is null or p_sign is null then raise exception 'Choix requis.';end if;result:=public.workshop_update_report(p_id,p_version,p_registration,p_notes,p_photos,p_before_intervention);update public.workshop_reports set client_notified=p_client_notified where id=p_id;perform workshop_private.sign_report(p_id,p_sign);return result;end $$;
do $$begin if to_regprocedure('public.workshop_get_report_before39(uuid)') is null then alter function public.workshop_get_report(uuid) rename to workshop_get_report_before39;end if;end $$;
revoke all on function public.workshop_get_report_before39(uuid) from public,anon,authenticated;
create or replace function public.workshop_get_report(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;r public.workshop_reports%rowtype;begin result:=public.workshop_get_report_before39(p_id);select * into r from public.workshop_reports where id=p_id;return result||jsonb_build_object('client_notified',r.client_notified,'author_job',r.author_job,'author_signature',r.author_signature,'signed_at',r.signed_at,'can_sign',coalesce(r.author_id=auth.uid(),false));end $$;
revoke all on function public.workshop_my_signature(),public.workshop_save_signature(text,text,integer),public.workshop_create_report(uuid,text,text,jsonb,boolean,boolean,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,boolean,boolean,boolean),public.workshop_get_report(uuid) from public,anon,authenticated;
grant execute on function public.workshop_my_signature(),public.workshop_save_signature(text,text,integer),public.workshop_create_report(uuid,text,text,jsonb,boolean,boolean,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,boolean,boolean,boolean),public.workshop_get_report(uuid) to authenticated;
notify pgrst,'reload schema';commit;
