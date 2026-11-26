-- MAJ126 : généralisation du plan 2.0. Ajouter un type ne change pas les affectations.
begin;
do $$declare first_install boolean;begin
 if to_regprocedure('public.workshop_get_stations()')is null
 or to_regprocedure('public.workshop_save_station(text,integer,text,text,integer,integer,boolean,boolean,boolean)')is null
 or to_regprocedure('public.workshop_screen_read124(text,date)')is null then
  raise exception 'Prérequis postes/écran124 manquants. Installe les mises à jour précédentes.';
 end if;
 first_install:=not exists(select 1 from pg_attribute where attrelid='public.workshop_stations'::regclass and attname='lift_kind'and not attisdropped);
 alter table public.workshop_stations add column if not exists lift_kind text not null default'unknown';
 if not exists(select 1 from pg_constraint where conrelid='public.workshop_stations'::regclass and conname='workshop_stations_lift_kind126_check')then
  alter table public.workshop_stations add constraint workshop_stations_lift_kind126_check check(lift_kind in('unknown','scissor','two_post'));
 end if;
 -- Import UNIQUE des choix déjà enregistrés dans l'essai privé, seulement s'ils ne se contredisent pas.
 -- Une réexécution ne rétablit jamais un ancien choix à la place d'une correction récente.
 if first_install and to_regclass('workshop_private.plan_preview125')is not null then
  execute $import$
   with choices as(
    select x.key station_id,x.value#>>'{}'kind
    from workshop_private.plan_preview125 p
    join workshop_private.accounts100 a on a.user_id=p.user_id and a.is_admin
    join public.workshop_staff st on st.id=a.staff_id and st.active and not coalesce(st.suspended,false)
    join auth.users u on u.id=p.user_id and(u.banned_until is null or u.banned_until<=now())
    cross join lateral jsonb_each(p.types)x
    where jsonb_typeof(x.value)='string'and x.value#>>'{}'in('scissor','two_post')
   ),unambiguous as(select station_id,min(kind)kind from choices group by station_id having count(distinct kind)=1)
   update public.workshop_stations s set lift_kind=c.kind,version=s.version+1 from unambiguous c
   where s.id=c.station_id and s.active and not s.office and s.lift_kind='unknown'
  $import$;
 end if;
end $$;

create or replace function public.workshop_get_stations126()
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=public.workshop_get_stations();
 if jsonb_typeof(r)is distinct from'array'then raise exception 'Liste des postes indisponible.';end if;
 return(select coalesce(jsonb_agg(x.value||jsonb_build_object('lift_kind',case when s.office then'unknown'else coalesce(s.lift_kind,'unknown')end)order by x.ord),'[]')
  from jsonb_array_elements(r)with ordinality x(value,ord)left join public.workshop_stations s on s.id=x.value->>'id');
end $$;
revoke all on function public.workshop_get_stations126() from public,anon,authenticated;
-- La géométrie et le type sont des métadonnées du plan, sans donnée personnelle.
-- Reprendre les rôles déjà autorisés sur le lecteur de postes existant.
do $$begin
 if has_function_privilege('anon','public.workshop_get_stations()','EXECUTE')then grant execute on function public.workshop_get_stations126()to anon;end if;
 if has_function_privilege('authenticated','public.workshop_get_stations()','EXECUTE')then grant execute on function public.workshop_get_stations126()to authenticated;end if;
end $$;

create or replace function public.workshop_save_station126(p_id text,p_version integer,p_name text,p_number text,p_col integer,p_row integer,p_office boolean,p_rotate boolean,p_delete boolean default false,p_lift_kind text default'unknown')
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;begin
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false)or not exists(
  select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self'and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())
 )then raise exception 'Gestion des postes réservée à l’administrateur actif.' using errcode='42501';end if;
 if p_lift_kind is null or p_lift_kind not in('unknown','scissor','two_post')then raise exception 'Type de pont invalide.';end if;
 -- Le moteur existant conserve les contrôles, verrou global, emplacement, version et suppression.
 perform public.workshop_save_station(p_id,p_version,p_name,p_number,p_col,p_row,p_office,p_rotate,p_delete);
 if not p_delete then
  update public.workshop_stations set lift_kind=case when p_office then'unknown'else p_lift_kind end where id=p_id and active;
  if not found then raise exception 'Poste non enregistré.';end if;
 end if;
 return public.workshop_get_stations126();
end $$;
revoke all on function public.workshop_save_station126(text,integer,text,text,integer,integer,boolean,boolean,boolean,text)from public,anon,authenticated;
grant execute on function public.workshop_save_station126(text,integer,text,text,integer,integer,boolean,boolean,boolean,text)to authenticated;

create or replace function public.workshop_screen_read126(p_token text,p_date date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;stations jsonb;begin
 -- Toujours valider le PC, la révocation, l'expiration, la maintenance et la rubrique avant tout ajout.
 r:=public.workshop_screen_read124(p_token,p_date);
 if r is null or r?'unavailable'then return r;end if;
 select coalesce(jsonb_agg(x.value||jsonb_build_object('lift_kind',case when s.office then'unknown'else coalesce(s.lift_kind,'unknown')end)order by x.ord),'[]')into stations
 from jsonb_array_elements(coalesce(r->'stations','[]'))with ordinality x(value,ord)
 left join public.workshop_stations s on s.id=x.value->>'id';
 return jsonb_set(r,'{stations}',stations);
end $$;
revoke all on function public.workshop_screen_read126(text,date)from public,anon,authenticated;
grant execute on function public.workshop_screen_read126(text,date)to anon,authenticated;
notify pgrst,'reload schema';
commit;
