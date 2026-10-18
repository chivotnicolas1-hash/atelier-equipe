-- MAJ44 : base existante à jour jusqu’à MAJ43. Réexécutable.
begin;
alter table public.workshop_signatures add column if not exists invalidated_at timestamptz;
alter table public.workshop_signatures add column if not exists invalidated_by uuid references auth.users(id) on delete set null;
create or replace function public.workshop_admin_signature(p_staff text,p_remove boolean default false,p_version integer default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;uid uuid;r public.workshop_signatures%rowtype;
begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Gestion des signatures réservée à l’administrateur.' using errcode='42501';end if;
 select u.id into uid from public.workshop_staff s join auth.users u on lower(u.email)=s.email where s.id=p_staff and s.active;
 if uid is null then raise exception 'Ce collaborateur ne possède pas encore de compte de connexion.';end if;
 perform pg_advisory_xact_lock(hashtextextended('signature:'||uid::text,0));select * into r from public.workshop_signatures where user_id=uid;
 if p_remove is null then raise exception 'Action invalide.';end if;
 if p_remove then
 if p_version is distinct from coalesce(r.version,0) then raise exception 'La signature a changé. Ferme puis rouvre cette fenêtre avant de la supprimer.';end if;
 if r.signature is null then raise exception 'Aucune signature à supprimer.';end if;
 update public.workshop_signatures set signature=null,version=version+1,updated_at=now(),invalidated_at=now(),invalidated_by=auth.uid() where user_id=uid returning * into r;
 end if;return jsonb_build_object('signature',r.signature,'version',coalesce(r.version,0));end $$;
create or replace function public.workshop_signature_gate() returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_signatures%rowtype;begin a:=workshop_private.actor_before30();select * into r from public.workshop_signatures where user_id=auth.uid();return jsonb_build_object('admin',coalesce((a->>'admin')::boolean,false),'required',r.signature is null,'invalidated',r.signature is null and r.invalidated_at is not null);end $$;
-- Un signalement de l’auteur ne peut être certifié avec une signature retirée.
create or replace function workshop_private.certify_report(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;person text;begin a:=workshop_private.actor();
 if exists(select 1 from public.workshop_reports where id=p_id and author_id=auth.uid()) then
 perform pg_advisory_xact_lock(hashtextextended('signature:'||auth.uid()::text,0));
 if not exists(select 1 from public.workshop_signatures where user_id=auth.uid() and signature is not null) then raise exception 'Enregistre ta signature dans Mon profil avant de certifier ce signalement.';end if;
 end if;
 perform workshop_private.sign_report(p_id,exists(select 1 from public.workshop_reports r join public.workshop_signatures s on s.user_id=r.author_id where r.id=p_id and r.author_id=auth.uid() and s.signature is not null));select name into person from public.workshop_staff where id=a->>'self';update public.workshop_reports set certified_at=now(),certified_name=coalesce(person,a->>'user') where id=p_id;end $$;
-- Conserver le timestamp de présence lors d’un déplacement (y compris retrait puis affectation).
create or replace function workshop_private.keep_confirmation_on_move() returns trigger language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 if old.date=new.date and old.staff_id=new.staff_id and old.presence='present' and new.presence='present' and old.confirmed is not null and old.station is distinct from new.station and auth.uid() is not null then
 a:=workshop_private.actor_before30();if coalesce((a->>'manager')::boolean,false) then new.confirmed:=old.confirmed;end if;
 end if;return new;end $$;
drop trigger if exists workshop_keep_confirmation_move on public.workshop_days;
create trigger workshop_keep_confirmation_move before update on public.workshop_days for each row execute function workshop_private.keep_confirmation_on_move();
revoke all on function workshop_private.keep_confirmation_on_move(),workshop_private.certify_report(uuid),public.workshop_admin_signature(text,boolean,integer),public.workshop_signature_gate() from public,anon,authenticated;
grant execute on function public.workshop_admin_signature(text,boolean,integer),public.workshop_signature_gate() to authenticated;
notify pgrst,'reload schema';commit;
