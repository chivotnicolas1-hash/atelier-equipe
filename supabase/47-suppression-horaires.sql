-- MAJ47 : nécessite MAJ46. Réexécutable.
begin;
create or replace function public.workshop_schedule_week(p_date date,p_staff_id text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;person text;monday date;
begin
 a:=workshop_private.actor_before30();
 if not coalesce((a->>'admin')::boolean,false) then
  if p_staff_id is not null and p_staff_id is distinct from a->>'self' then raise exception 'Les horaires des autres collaborateurs sont réservés à l’administrateur.' using errcode='42501';end if;
  return public.workshop_my_week(p_date)||jsonb_build_object('can_delete',false,'staff_id',a->>'self');
 end if;
 person:=coalesce(p_staff_id,a->>'self');
 if p_date is null or not exists(select 1 from public.workshop_staff where id=person and active and role<>'guest') then raise exception 'Date ou collaborateur invalide.';end if;
 monday:=p_date-(extract(isodow from p_date)::integer-1);
 return jsonb_build_object('start',monday,'staff_id',person,'can_delete',true,'days',
 (select jsonb_agg(jsonb_build_object('date',monday+n,'presence',coalesce(d.presence,'unknown'),'slots',coalesce(d.slots,'[]'::jsonb)) order by n)
 from generate_series(0,6)n left join public.workshop_days d on d.date=monday+n and d.staff_id=person));
end $$;

create or replace function public.workshop_delete_schedule(p_staff_id text,p_date date,p_expected_slots jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_days%rowtype;
begin
 lock table public.workshop_staff in share mode;
 a:=workshop_private.actor();
 if not coalesce((a->>'admin')::boolean,false) then raise exception 'Suppression des horaires réservée à l’administrateur.' using errcode='42501';end if;
 if p_date is null or p_expected_slots is null or jsonb_typeof(p_expected_slots)<>'array'
 or not exists(select 1 from public.workshop_staff where id=p_staff_id and active and role<>'guest') then raise exception 'Date ou collaborateur invalide.';end if;
 lock table public.workshop_days in share row exclusive mode;
 select * into r from public.workshop_days where date=p_date and staff_id=p_staff_id for update;
 if not found or r.slots='[]'::jsonb then return;end if;
 if r.slots is distinct from p_expected_slots then raise exception 'Ces horaires ont été modifiés ailleurs. Actualise la semaine avant de les supprimer.';end if;
 -- Seuls les créneaux sont retirés. Le poste, le statut et la confirmation
 -- restent inchangés, de même que la seconde affectation géométrie.
 update public.workshop_days set slots='[]'::jsonb where date=p_date and staff_id=p_staff_id;
end $$;
revoke all on function public.workshop_schedule_week(date,text),public.workshop_delete_schedule(text,date,jsonb) from public,anon,authenticated;
grant execute on function public.workshop_schedule_week(date,text),public.workshop_delete_schedule(text,date,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
