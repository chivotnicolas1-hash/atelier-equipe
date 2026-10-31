-- MAJ64, après les quatre scripts MAJ63. Réexécutable.
begin;
-- Protection explicite des tables privées ajoutées en MAJ63.
alter table workshop_private.leave_day_backup enable row level security;
alter table workshop_private.button_ack enable row level security;
revoke all on workshop_private.leave_day_backup,workshop_private.button_ack from public,anon,authenticated;
alter table public.workshop_staff add column if not exists suspended boolean not null default false;
alter table public.workshop_staff add column if not exists suspended_at timestamptz;
alter table public.workshop_staff add column if not exists suspended_by uuid references auth.users(id);
create or replace function public.workshop_suspend_staff(p_staff text,p_suspended boolean) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;s public.workshop_staff%rowtype;begin
 a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;
 if p_suspended is null then raise exception 'État requis.';end if;
 lock table public.workshop_staff in share row exclusive mode;select * into s from public.workshop_staff where id=p_staff for update;
 if not found or s.email='nchivot@norauto.fr' or s.id=a->>'self' then raise exception 'Ce compte ne peut pas être suspendu.';end if;
 if not s.active and not s.suspended then raise exception 'Cette fiche a été supprimée, elle ne peut pas être réactivée ici.';end if;
 update public.workshop_staff set suspended=p_suspended,active=not p_suspended,suspended_at=case when p_suspended then now() end,suspended_by=case when p_suspended then auth.uid() end where id=p_staff;
end $$;
create or replace function public.workshop_suspended_staff() returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Réservé à l’administrateur.' using errcode='42501';end if;return(select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'email',email,'team',team,'suspended_at',suspended_at) order by name),'[]') from public.workshop_staff where suspended);end $$;
-- Accessible à son propre compte seulement, même une fois suspendu.
create or replace function public.workshop_access_status() returns jsonb language plpgsql security definer set search_path='' as $$declare e text;s public.workshop_staff%rowtype;begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501';end if;select lower(email) into e from auth.users where id=auth.uid() and email_confirmed_at is not null;
 if e='nchivot@norauto.fr' then return '{"allowed":true}';end if;
 select * into s from public.workshop_staff where email=e;
 return jsonb_build_object('allowed',coalesce(s.active,false),'suspended',coalesce(s.suspended,false));end $$;
create table if not exists public.workshop_quality_goals(date date primary key,goal integer not null check(goal between 0 and 100000),version integer not null default 1,updated_at timestamptz not null default now(),updated_by uuid references auth.users(id));
create table if not exists public.workshop_quality_results(id uuid primary key,date date not null,author_id uuid not null references auth.users(id),author_name text not null,created_at timestamptz not null default now(),deleted_at timestamptz,deleted_by uuid references auth.users(id));
alter table public.workshop_quality_goals enable row level security;
alter table public.workshop_quality_results enable row level security;
revoke all on public.workshop_quality_goals,public.workshop_quality_results from public,anon,authenticated;
create or replace function public.workshop_quality_status(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;r public.workshop_quality_goals%rowtype;begin
 a:=workshop_private.actor_before30();if p_date is null then raise exception 'Date requise.';end if;select * into r from public.workshop_quality_goals where date=p_date;
 return jsonb_build_object('goal',coalesce(r.goal,case when extract(isodow from p_date) between 1 and 6 then 2 else 0 end),'version',coalesce(r.version,0),'total',(select count(*) from public.workshop_quality_results where date=p_date and deleted_at is null),'manager',coalesce((a->>'manager')::boolean,false),'can_edit',coalesce((a->>'manager')::boolean,false) or workshop_private.has_right('edit_targets'));
end $$;
create or replace function public.workshop_quality_goal(p_date date,p_goal integer,p_version integer) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;r public.workshop_quality_goals%rowtype;begin a:=workshop_private.actor();if not (coalesce((a->>'manager')::boolean,false) or workshop_private.has_right('edit_targets')) then raise exception 'Droit de modification des cibles requis.' using errcode='42501';end if;
 if p_date is null or p_goal is null or p_goal not between 0 and 100000 then raise exception 'Cible invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('quality-goal:'||p_date,0));select * into r from public.workshop_quality_goals where date=p_date for update;if coalesce(r.version,0) is distinct from p_version then raise exception 'Cible modifiée ailleurs. Ferme puis rouvre ce formulaire.';end if;
 insert into public.workshop_quality_goals(date,goal,updated_by) values(p_date,p_goal,auth.uid()) on conflict(date) do update set goal=excluded.goal,version=workshop_quality_goals.version+1,updated_at=now(),updated_by=auth.uid();end $$;
create or replace function public.workshop_quality_add(p_id uuid,p_date date) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;r public.workshop_quality_results%rowtype;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Seuls l’administrateur et les modérateurs peuvent enregistrer un contrôle.' using errcode='42501';end if;
 if p_date is null or p_id is null then raise exception 'Date et identifiant requis.';end if;perform pg_advisory_xact_lock(hashtextextended('quality-result:'||p_id,0));select * into r from public.workshop_quality_results where id=p_id;
 if found then if r.date is distinct from p_date or r.author_id<>auth.uid() then raise exception 'Identifiant déjà utilisé.';end if;return;end if;
 insert into public.workshop_quality_results(id,date,author_id,author_name) values(p_id,p_date,auth.uid(),coalesce((select name from public.workshop_staff where id=a->>'self'),a->>'user'));end $$;
create or replace function public.workshop_quality_history(p_date date) returns jsonb language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;return(select coalesce(jsonb_agg(to_jsonb(r)-'author_id'-'deleted_by' order by created_at desc),'[]') from public.workshop_quality_results r where date=p_date and deleted_at is null);end $$;
create or replace function public.workshop_quality_delete(p_id uuid) returns void language plpgsql security definer set search_path='' as $$declare a jsonb;begin a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux gestionnaires.' using errcode='42501';end if;update public.workshop_quality_results set deleted_at=now(),deleted_by=auth.uid() where id=p_id and deleted_at is null;end $$;
revoke all on function public.workshop_suspend_staff(text,boolean),public.workshop_suspended_staff(),public.workshop_access_status(),public.workshop_quality_status(date),public.workshop_quality_goal(date,integer,integer),public.workshop_quality_add(uuid,date),public.workshop_quality_history(date),public.workshop_quality_delete(uuid) from public,anon,authenticated;
grant execute on function public.workshop_suspend_staff(text,boolean),public.workshop_suspended_staff(),public.workshop_access_status(),public.workshop_quality_status(date),public.workshop_quality_goal(date,integer,integer),public.workshop_quality_add(uuid,date),public.workshop_quality_history(date),public.workshop_quality_delete(uuid) to authenticated;
notify pgrst,'reload schema';commit;
