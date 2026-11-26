-- MAJ125 : un statut de journée supplémentaire. Aucune journée existante réécrite à l'installation.
begin;
do $$declare c record;begin
 if to_regprocedure('public.workshop_save_schedule(text,date,text,jsonb,jsonb)')is null then raise exception 'Fonction de gestion des horaires absente.';end if;
 select conname,pg_get_expr(conbin,conrelid)expr into c from pg_constraint
 where conrelid='public.workshop_days'::regclass and conname='workshop_days_presence_check'and contype='c';
 if c.conname is null then raise exception 'Contrainte de statut non reconnue. Arrêt sans modification.';end if;
 -- Conserver toutes les valeurs autorisées par la contrainte existante, puis ajouter training.
 if position('''training'''in c.expr)=0 then
  execute format('alter table public.workshop_days drop constraint %I, add constraint %I check((%s) or presence=%L)',c.conname,c.conname,c.expr,'training');
 end if;
end $$;
create or replace function public.workshop_save_schedule125(p_staff_id text,p_date date,p_presence text,p_slots jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('plan');
 if not coalesce((a->>'can_manage_schedule')::boolean,false)or not exists(
  select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self'and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())
 )then raise exception 'Modification réservée à l’administrateur et aux modérateurs autorisés.' using errcode='42501';end if;
 if p_presence is distinct from'training'then
  return public.workshop_save_schedule(p_staff_id,p_date,p_presence,p_slots,p_expected);
 end if;
 if p_slots is null or jsonb_typeof(p_slots)is distinct from'array'or jsonb_array_length(p_slots)<>0 then
  raise exception 'Une journée en formation ne comporte pas de créneau disponible à l’atelier.';
 end if;
 -- Réutiliser tous les contrôles, verrous et comparaisons de version du moteur existant.
 -- L'étape transitoire absent reste dans la même transaction, invisible aux autres sessions.
 r:=public.workshop_save_schedule(p_staff_id,p_date,'absent',p_slots,p_expected);
 update public.workshop_days set presence='training',station=null,geometry=false,confirmed=null
 where date=p_date and staff_id=p_staff_id;
 if not found then raise exception 'Journée non enregistrée.';end if;
 return r||jsonb_build_object('presence','training');
end $$;
revoke all on function public.workshop_save_schedule125(text,date,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.workshop_save_schedule125(text,date,text,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
