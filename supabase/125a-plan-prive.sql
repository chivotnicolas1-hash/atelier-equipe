-- MAJ125 : essai privé du plan, sans publication ni modification des postes.
begin;
do $$begin
 if to_regprocedure('workshop_private.actor()')is null or to_regclass('public.workshop_stations')is null then
  raise exception 'Identité ou postes de l’atelier absents.';
 end if;
end $$;
create table if not exists workshop_private.plan_preview125(
 user_id uuid primary key references auth.users(id)on delete cascade,
 types jsonb not null default'{}' check(jsonb_typeof(types)='object'),
 version integer not null default 1 check(version>0),updated_at timestamptz not null default now()
);
alter table workshop_private.plan_preview125 enable row level security;
revoke all on workshop_private.plan_preview125 from public,anon,authenticated;
create or replace function public.workshop_plan_preview125(p_types jsonb default null,p_version integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r workshop_private.plan_preview125%rowtype;visible_types jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('plan');
 if not coalesce((a->>'admin')::boolean,false)or not exists(
  select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self' and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())
 )then raise exception 'Essai réservé à l’administrateur actif.' using errcode='42501';end if;
 if p_types is not null then
  if jsonb_typeof(p_types)is distinct from'object' or octet_length(p_types::text)>20000 then raise exception 'Configuration de ponts invalide.';end if;
  if exists(select 1 from jsonb_each(p_types)x where jsonb_typeof(x.value)is distinct from'string'
   or x.value#>>'{}'not in('scissor','two_post')or not exists(
    select 1 from public.workshop_stations s where s.id=x.key and s.active and not s.office))then
   raise exception 'Poste ou type de pont invalide dans cet essai.';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('plan-preview125:'||auth.uid()::text,0));
 end if;
 select * into r from workshop_private.plan_preview125 where user_id=auth.uid();
 if p_types is not null then
  if p_version is distinct from coalesce(r.version,0)then raise exception 'Cet essai a changé sur un autre appareil. Ferme puis rouvre-le avant d’enregistrer.';end if;
  if r.user_id is null or r.types is distinct from p_types then
   insert into workshop_private.plan_preview125(user_id,types)values(auth.uid(),p_types)
   on conflict(user_id)do update set types=excluded.types,version=workshop_private.plan_preview125.version+1,updated_at=now()
   returning * into r;
  end if;
 end if;
 select coalesce(jsonb_object_agg(x.key,x.value),'{}')into visible_types from jsonb_each(coalesce(r.types,'{}'))x
 join public.workshop_stations s on s.id=x.key and s.active and not s.office;
 return jsonb_build_object('types',visible_types,'version',coalesce(r.version,0));
end $$;
revoke all on function public.workshop_plan_preview125(jsonb,integer) from public,anon,authenticated;
grant execute on function public.workshop_plan_preview125(jsonb,integer) to authenticated;
notify pgrst,'reload schema';
commit;
