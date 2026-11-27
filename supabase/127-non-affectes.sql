-- MAJ127 : première affectation par glisser-déposer dans un brouillon uniquement.
-- Aucune table ou donnée métier modifiée à l'installation.
begin;
do $$begin
 if to_regprocedure('public.workshop_move119(date,text,text,text,text,boolean,integer)')is null
 or to_regprocedure('public.workshop_plan_edit(date,text,integer,text,text,boolean)')is null
 or to_regprocedure('workshop_private.plan_baseline(date)')is null
 or to_regprocedure('workshop_private.scheduled_minutes118(jsonb)')is null then
  raise exception 'Prérequis du moteur de préparation/glisser-déposer absents.';
 end if;
end $$;
create or replace function public.workshop_move127(p_date date,p_staff text,p_from text,p_to text,p_expected_station text,p_expected_geometry boolean,p_draft_version integer default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_days%rowtype;draft public.workshop_plan_drafts%rowtype;e jsonb;begin
 a:=workshop_private.actor();perform workshop_private.assert_section('plan');
 if not(coalesce((a->>'admin')::boolean,false)or coalesce((a->>'manager')::boolean,false))or not exists(
  select 1 from public.workshop_staff s join auth.users u on u.id=auth.uid()
  where s.id=a->>'self'and s.active and not coalesce(s.suspended,false)
  and(u.banned_until is null or u.banned_until<=now())
 )then raise exception 'Réservé à l’administration et à la modération actives.' using errcode='42501';end if;
 -- Les déplacements existants entre postes gardent leur moteur et leurs protections.
 if p_from is not null then
  return public.workshop_move119(p_date,p_staff,p_from,p_to,p_expected_station,p_expected_geometry,p_draft_version);
 end if;
 if p_date is null or p_staff is null or p_to is null or p_draft_version is null
 or p_expected_station is not null or p_expected_geometry is distinct from false then
  raise exception 'La première affectation nécessite une personne non affectée dans un brouillon.';
 end if;
 lock table public.workshop_days in share row exclusive mode;
 lock table public.workshop_skills in share mode;
 lock table public.workshop_station_status in share mode;
 perform pg_advisory_xact_lock(hashtextextended('plan:'||p_date::text,0));
 select * into r from public.workshop_days where date=p_date and staff_id=p_staff for update;
 if not found then raise exception 'Présence introuvable pour cette journée.';end if;
 select * into draft from public.workshop_plan_drafts where date=p_date for update;
 if draft.date is null or draft.version is distinct from p_draft_version
 or draft.baseline is distinct from workshop_private.plan_baseline(p_date)then
  raise exception 'Le brouillon ou les horaires ont changé. Actualise le plan avant de réessayer.';
 end if;
 if(select count(*)from jsonb_array_elements(draft.entries)x where x->>'staff_id'=p_staff)<>1 then
  raise exception 'Collaborateur absent ou en doublon dans le brouillon.';
 end if;
 select x into e from jsonb_array_elements(draft.entries)x where x->>'staff_id'=p_staff;
 if e->>'station'is not null or coalesce((e->>'geometry')::boolean,false)then
  raise exception 'Ce collaborateur est déjà affecté. Recommence depuis son poste.';
 end if;
 if not exists(select 1 from public.workshop_staff s where s.id=p_staff and s.active
  and not coalesce(s.suspended,false)and s.role not in('guest','director'))
 or r.presence<>'present' or workshop_private.scheduled_minutes118(r.slots)<=0
 or exists(select 1 from public.workshop_leave_requests l cross join lateral jsonb_array_elements(l.periods)x
  where l.staff_id=p_staff and l.status='accepted'and p_date between(x->>'start')::date and(x->>'end')::date)then
  raise exception 'Collaborateur non disponible : présence et horaires requis, hors congé accepté.';
 end if;
 if not workshop_private.assignment_allowed(p_staff,p_date,p_to)then
  raise exception 'Destination interdite : vérifie compétence Autonome, équipe, présence, horaires et état du pont.';
 end if;
 -- Le moteur de préparation applique la sauvegarde versionnée ; aucune publication ici.
 perform public.workshop_plan_edit(p_date,'save',p_draft_version,p_staff,p_to,false);
 return jsonb_build_object('changed',true,'draft',true,'station',p_to,'geometry',false);
end $$;
revoke all on function public.workshop_move127(date,text,text,text,text,boolean,integer)from public,anon,authenticated;
grant execute on function public.workshop_move127(date,text,text,text,text,boolean,integer)to authenticated;
notify pgrst,'reload schema';
commit;
