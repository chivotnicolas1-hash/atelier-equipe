begin;
-- Aucun mot de passe ni code de récupération en clair dans ces tables.
create table if not exists workshop_private.recovery117(
 user_id uuid primary key references auth.users(id) on delete cascade,
 staff_id text not null unique references public.workshop_staff(id) on delete cascade,
 code_hash text not null check(code_hash ~ '^[0-9a-f]{64}$'),
 created_at timestamptz not null default now(),expires_at timestamptz not null,
 used_at timestamptz,attempt_id uuid,version integer not null default 1
);
create table if not exists workshop_private.recovery_limits117(key text primary key,window_at timestamptz not null,n integer not null);
alter table workshop_private.recovery117 enable row level security;
alter table workshop_private.recovery_limits117 enable row level security;
revoke all on workshop_private.recovery117,workshop_private.recovery_limits117 from public,anon,authenticated;

create or replace function workshop_private.recovery_budget117(p_login text,p_network text) returns boolean
language plpgsql security definer set search_path='' as $$
declare k text;count_n integer;cap integer;ok boolean:=true;
begin
 perform pg_advisory_xact_lock(1170117);
 delete from workshop_private.recovery_limits117 where window_at<=now()-interval '15 minutes';
 if (select count(*) from workshop_private.recovery_limits117)>5000 then return false;end if;
 foreach k in array array['global','network:'||coalesce(p_network,'unknown'),'account:'||encode(sha256(convert_to(lower(btrim(coalesce(p_login,''))),'UTF8')),'hex')] loop
  insert into workshop_private.recovery_limits117 values(k,now(),0) on conflict(key) do nothing;
  update workshop_private.recovery_limits117 set n=case when window_at<=now()-interval '15 minutes' then 1 else n+1 end,
   window_at=case when window_at<=now()-interval '15 minutes' then now() else window_at end where key=k returning n into count_n;
  cap:=case when k='global' then 200 when k like 'network:%' then 40 else 8 end;
  if count_n>cap then return false;end if;
 end loop;
 return ok;
end $$;
revoke all on function workshop_private.recovery_budget117(text,text) from public,anon,authenticated;

create or replace function public.workshop_recovery_status117() returns jsonb
language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.recovery117%rowtype;
begin
 a:=workshop_private.actor_before30();if a->>'role'='guest' then raise exception 'Compte de démonstration.' using errcode='42501';end if;
 select * into r from workshop_private.recovery117 where user_id=auth.uid();
 return jsonb_build_object('active',r.user_id is not null and r.used_at is null and r.expires_at>now(),'created_at',r.created_at,'expires_at',r.expires_at,'version',coalesce(r.version,0));
end $$;

-- Les opérations suivantes sont réservées à la nouvelle Edge Function.
create or replace function public.workshop_recovery_budget117(p_login text,p_network text) returns boolean
language sql security definer set search_path='' as $$select workshop_private.recovery_budget117(p_login,p_network)$$;

create or replace function public.workshop_recovery_save117(p_user uuid,p_staff text,p_hash text,p_expected integer) returns void
language plpgsql security definer set search_path='' as $$
declare v integer;s public.workshop_staff%rowtype;
begin
 if p_user is null or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_expected is null then raise exception 'Code invalide.';end if;
 select * into s from public.workshop_staff where id=p_staff for update;
 if not found or not s.active or coalesce((to_jsonb(s)->>'suspended')::boolean,false) or coalesce(to_jsonb(s)->>'role','employee')='guest' then raise exception 'Compte indisponible.';end if;
 perform pg_advisory_xact_lock(hashtextextended('recovery117:'||p_user::text,0));
 select version into v from workshop_private.recovery117 where user_id=p_user for update;
 if coalesce(v,0)<>p_expected then raise exception 'La récupération a changé. Ferme puis rouvre cette rubrique avant de recommencer.';end if;
 insert into workshop_private.recovery117(user_id,staff_id,code_hash,expires_at) values(p_user,p_staff,p_hash,now()+interval '365 days')
 on conflict(user_id) do update set staff_id=excluded.staff_id,code_hash=excluded.code_hash,created_at=now(),expires_at=excluded.expires_at,used_at=null,attempt_id=null,version=recovery117.version+1;
end $$;

create or replace function public.workshop_recovery_claim117(p_login text,p_hash text,p_network text,p_attempt uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare r workshop_private.recovery117%rowtype;s public.workshop_staff%rowtype;lookup jsonb;
begin
 if not workshop_private.recovery_budget117(p_login,p_network) then return jsonb_build_object('limited',true);end if;
 if p_login is null or p_login !~* '^[a-z0-9_-]{3,32}$' or p_hash is null or p_hash !~ '^[0-9a-f]{64}$' or p_attempt is null or length(coalesce(p_network,''))>100 then return null;end if;
 -- Réutilise le résolveur d’ID existant : aucun accès supposé à la structure
 -- privée des identifiants de la MAJ100 ; un changement d’ID reste compatible.
 lookup:=public.workshop_login100(p_login);
 if coalesce((lookup->>'limited')::boolean,false) then return jsonb_build_object('limited',true);end if;
 select k.* into r from workshop_private.recovery117 k join auth.users u on u.id=k.user_id where lower(u.email)=lower(lookup->>'email') for update of k;
 if not found then return null;end if;
 select * into s from public.workshop_staff where id=r.staff_id and active;
 if not found or coalesce((to_jsonb(s)->>'suspended')::boolean,false) or coalesce(to_jsonb(s)->>'role','employee')='guest' then return null;end if;
 if r.code_hash<>p_hash or r.used_at is not null or r.expires_at<=now() then return null;end if;
 update workshop_private.recovery117 set used_at=now(),attempt_id=p_attempt,version=version+1 where user_id=r.user_id;
 return jsonb_build_object('user_id',r.user_id,'staff_id',r.staff_id);
end $$;

-- Uniquement si Auth a explicitement refusé le changement (pas de réactivation
-- après erreur réseau ambiguë, ni d’écrasement d’un nouveau code généré ailleurs).
create or replace function public.workshop_recovery_release117(p_user uuid,p_attempt uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 update workshop_private.recovery117 set used_at=null,attempt_id=null,version=version+1 where user_id=p_user and attempt_id=p_attempt and used_at>now()-interval '5 minutes';
end $$;

create or replace function public.workshop_recovery_invalidate117(p_user uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 update workshop_private.recovery117 set used_at=now(),attempt_id=null,version=version+1 where user_id=p_user and used_at is null;
end $$;

create or replace function public.workshop_recovery_notice117(p_user uuid,p_attempt uuid) returns void
language plpgsql security definer set search_path='' as $$begin
 if not exists(select 1 from workshop_private.recovery117 where user_id=p_user and attempt_id=p_attempt and used_at is not null) then raise exception 'Réinitialisation inconnue.';end if;
 perform workshop_private.message(p_user,'Ton mot de passe a été réinitialisé avec ton code de récupération. Génère un nouveau code dans Mon profil. Si tu n’es pas à l’origine de cette action, contacte ton administrateur.','/?notifications=inbox','recovery117:'||p_attempt::text);
end $$;

revoke all on function public.workshop_recovery_status117() from public,anon,authenticated;
grant execute on function public.workshop_recovery_status117() to authenticated;
do $$declare f record;begin for f in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('workshop_recovery_budget117','workshop_recovery_save117','workshop_recovery_claim117','workshop_recovery_release117','workshop_recovery_invalidate117','workshop_recovery_notice117') loop
 execute format('revoke all on function %s from public,anon,authenticated',f.sig);execute format('grant execute on function %s to service_role',f.sig);
end loop;end $$;
notify pgrst,'reload schema';
commit;
