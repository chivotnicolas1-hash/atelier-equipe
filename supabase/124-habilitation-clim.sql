-- MAJ124 : ajout isolé. Aucune habilitation déduite des équipes/compétences.
-- La case est une déclaration de l'administrateur, pas un certificat généré.
begin;
do $$begin
 if to_regprocedure('public.workshop_screen_read123(text,date)') is null
 or to_regprocedure('public.workshop_pc_access()') is null
 or to_regprocedure('workshop_private.actor_before30()') is null then
  raise exception 'Installe les prérequis de la MAJ123 avant ce script.';
 end if;
end $$;

create table if not exists workshop_private.staff_aircon124(
 staff_id text primary key references public.workshop_staff(id) on delete cascade,
 enabled boolean not null default false,
 version integer not null default 1 check(version>0),
 updated_at timestamptz not null default now(),
 updated_by uuid
);
alter table workshop_private.staff_aircon124 enable row level security;
revoke all on workshop_private.staff_aircon124 from public,anon,authenticated;

create or replace function public.workshop_staff_aircon124(p_staff text,p_enabled boolean default null,p_version integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.staff_aircon124%rowtype;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('team');
 if not coalesce((a->>'admin')::boolean,false) or not exists(
  select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())
 )then raise exception 'Réservé à l’administrateur actif.' using errcode='42501';end if;
 -- Verrou commun aux changements de cette fiche ; une fiche retirée ne peut plus être marquée.
 perform 1 from public.workshop_staff where id=p_staff and active and not coalesce(suspended,false)
  and coalesce(role,'employee') not in('guest','director') for share;
 if not found then raise exception 'Fiche collaborateur indisponible.';end if;
 if p_enabled is not null then perform pg_advisory_xact_lock(hashtextextended('staff-aircon124:'||p_staff,0));end if;
 select * into r from workshop_private.staff_aircon124 where staff_id=p_staff;
 if p_enabled is not null then
  if p_version is distinct from coalesce(r.version,0)then
   raise exception 'L’habilitation a changé sur un autre appareil. La case va être remise à jour ; vérifie-la avant de réessayer.';
  end if;
  if r.staff_id is null or r.enabled is distinct from p_enabled then
   insert into workshop_private.staff_aircon124(staff_id,enabled,updated_by)
   values(p_staff,p_enabled,auth.uid())
   on conflict(staff_id)do update set enabled=excluded.enabled,version=workshop_private.staff_aircon124.version+1,
    updated_at=now(),updated_by=excluded.updated_by returning * into r;
  end if;
 end if;
 return jsonb_build_object('enabled',coalesce(r.enabled,false),'version',coalesce(r.version,0));
end $$;
revoke all on function public.workshop_staff_aircon124(text,boolean,integer) from public,anon,authenticated;
grant execute on function public.workshop_staff_aircon124(text,boolean,integer) to authenticated;

create or replace function workshop_private.screen_aircon124()
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_object_agg(c.staff_id,true),'{}') from workshop_private.staff_aircon124 c
 join public.workshop_staff s on s.id=c.staff_id
 where c.enabled and s.active and not coalesce(s.suspended,false) and coalesce(s.role,'employee')not in('guest','director');
$$;
revoke all on function workshop_private.screen_aircon124() from public,anon,authenticated;

create or replace function public.workshop_screen_aircon124()
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor_before30();
 if not exists(select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())) or not public.workshop_pc_access()then
  raise exception 'Accès écran refusé.' using errcode='42501';
 end if;
 perform workshop_private.assert_section('plan');
 return workshop_private.screen_aircon124();
end $$;
revoke all on function public.workshop_screen_aircon124() from public,anon,authenticated;
grant execute on function public.workshop_screen_aircon124() to authenticated;

create or replace function public.workshop_screen_read124(p_token text,p_date date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;flags jsonb;begin
 -- D'abord TOUTES les protections existantes du PC ; jamais d'accès sans jeton valide.
 r:=public.workshop_screen_read123(p_token,p_date);
 if r is null or r?'unavailable'then return r;end if;
 -- Ne joindre que les habilitations des personnes déjà visibles dans ce snapshot.
 select coalesce(jsonb_object_agg(c.staff_id,true),'{}')into flags
 from workshop_private.staff_aircon124 c join public.workshop_staff s on s.id=c.staff_id
 where c.enabled and s.active and not coalesce(s.suspended,false)
 and coalesce(s.role,'employee')not in('guest','director')
 and exists(select 1 from jsonb_array_elements(coalesce(r#>'{data,staff}','[]'))p where p->>'id'=c.staff_id);
 return r||jsonb_build_object('aircon124',flags);
end $$;
revoke all on function public.workshop_screen_read124(text,date) from public,anon,authenticated;
grant execute on function public.workshop_screen_read124(text,date) to anon,authenticated;
notify pgrst,'reload schema';
commit;
