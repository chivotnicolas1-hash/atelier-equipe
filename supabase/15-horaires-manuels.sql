-- Après la migration 12. Les mises à jour 13 et 14 ne nécessitent pas de SQL.
begin;
alter table public.workshop_staff add column if not exists can_manage_schedule boolean not null default false;
create or replace function workshop_private.actor()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_email text; v_staff text; v_admin boolean; v_role text;
begin
 if auth.uid() is null then raise exception 'Connexion requise.' using errcode='42501'; end if;
 if coalesce(auth.jwt()->'app_metadata'->>'provider','') <> 'email' or not exists (select 1 from jsonb_array_elements(coalesce(auth.jwt()->'amr','[]'::jsonb)) m where m->>'method'='password') then
  raise exception 'Connecte-toi avec les identifiants fournis par ton administrateur.' using errcode='42501';
 end if;
 select lower(u.email) into v_email from auth.users u where u.id=auth.uid() and u.email_confirmed_at is not null;
 if v_email is null then raise exception 'Une adresse e-mail vérifiée est nécessaire.' using errcode='42501'; end if;
 v_admin := v_email='nchivot@norauto.fr';
 select id,role into v_staff,v_role from public.workshop_staff where email=v_email and active;
 if not v_admin and v_staff is null then
  raise exception 'Cette adresse n’est pas autorisée. Demande à l’administrateur de renseigner ton adresse e-mail dans Équipe.' using errcode='42501';
 end if;
 return jsonb_build_object('admin',v_admin,'role',case when v_admin then 'admin' else coalesce(v_role,'employee') end,'manager',v_admin or coalesce(v_role='moderator',false),'can_manage_schedule',v_admin or exists(select 1 from public.workshop_staff where id=v_staff and active and role='moderator' and can_manage_schedule),'reports_all',v_admin or exists(select 1 from public.workshop_staff where id=v_staff and active and team='Encadrants'),'self',v_staff,'user',v_email);
end $$;
revoke all on function workshop_private.actor() from public, anon, authenticated;


create or replace function public.workshop_mutate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; act text; v_id text; v_email text; v_task public.workshop_tasks%rowtype; v_count integer; v_done boolean; v_manager boolean; person public.workshop_staff%rowtype; current_day public.workshop_days%rowtype;
begin
 a:=workshop_private.actor();v_admin:=(a->>'admin')::boolean;v_manager:=(a->>'manager')::boolean;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Action invalide.'; end if;
 act:=p->>'action';v_id:=p->>'id';
 if act in ('staff','createStaff','deleteStaff') and not v_admin then
  raise exception 'Action réservée à l’administration.' using errcode='42501';
 end if;
 if act in ('day','task','editTask','deleteTask') and not v_manager then
  raise exception 'Action réservée à l’administration ou aux modérateurs.' using errcode='42501';
 end if;
 -- Verrou partagé : aucune affectation/import ne peut viser une fiche retirée entre deux contrôles.
 if act in ('staff','createStaff','deleteStaff') then
  lock table public.workshop_staff in share row exclusive mode;
 else
  lock table public.workshop_staff in share mode;
 end if;
 if act in ('staff','deleteStaff','day') then
  select * into person from public.workshop_staff where id=v_id and active for share;
  if not found then raise exception 'Collaborateur introuvable.';end if;
 end if;
 if act in ('task','editTask') and not exists(select 1 from public.workshop_staff where id=p->>'staffId' and active) then
  raise exception 'Choisis un collaborateur actif.';
 end if;
 if act in ('staff','createStaff') and p ? 'can_manage_schedule' and jsonb_typeof(p->'can_manage_schedule') is distinct from 'boolean' then raise exception 'Permission horaires invalide.';end if;
 if act='createStaff' then
  if p->>'role' is not null and p->>'role' not in ('employee','moderator') then raise exception 'Rôle invalide.';end if;
  select lpad((coalesce(max(id::integer),0)+1)::text,greatest(2,length((coalesce(max(id::integer),0)+1)::text)),'0') into v_id from public.workshop_staff;
  insert into public.workshop_staff(id,name,email,team,role,can_manage_schedule)
  values(v_id,trim(p->>'name'),nullif(lower(trim(p->>'email')),''),nullif(p->>'team',''),coalesce(p->>'role','employee'),coalesce(p->>'role','employee')='moderator' and coalesce((p->>'can_manage_schedule')::boolean,false));
 elsif act='deleteStaff' then
  if person.email='nchivot@norauto.fr' or v_id=a->>'self' then raise exception 'Ton compte administrateur ne peut pas être supprimé.';end if;
  update public.workshop_staff set active=false,role='employee',can_manage_schedule=false where id=v_id;
 elsif act='deleteTask' then
  delete from public.workshop_tasks where id=v_id::uuid;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Tâche introuvable.';end if;
 elsif act='staff' then
  if nullif(trim(p->>'name'),'') is null then raise exception 'Renseigne un nom.'; end if;
  v_email:=nullif(lower(trim(p->>'email')),'');
  if person.email='nchivot@norauto.fr' and v_email is distinct from person.email then raise exception 'L’adresse du compte administrateur doit être conservée.';end if;
  if p ? 'role' and (p->>'role' is null or p->>'role' not in ('employee','moderator')) then raise exception 'Rôle invalide.';end if;
  update public.workshop_staff set can_manage_schedule=case when coalesce(p->>'role',role)='moderator' then coalesce((p->>'can_manage_schedule')::boolean,can_manage_schedule) else false end,role=case when p ? 'role' then p->>'role' else role end,name=trim(p->>'name'),email=v_email,team=case when p ? 'team' then nullif(p->>'team','') else team end where id=v_id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Collaborateur introuvable.';end if;
 elsif act='day' then
  lock table public.workshop_days in row exclusive mode;
  if not v_admin then
   select * into current_day from public.workshop_days where date=(p->>'date')::date and staff_id=v_id for update;
   if not found or current_day.presence<>'present' or p->>'presence' is distinct from current_day.presence then
    raise exception 'Le modérateur peut déplacer uniquement les collaborateurs prévus présents.' using errcode='42501';
   end if;
  end if;
  insert into public.workshop_days as existing(date,staff_id,presence,station,confirmed)
  values((p->>'date')::date,v_id,p->>'presence',nullif(p->>'station',''),null)
  on conflict(date,staff_id) do update set
    presence=excluded.presence,station=excluded.station,
    confirmed=case when existing.presence=excluded.presence and existing.station is not distinct from excluded.station then existing.confirmed else null end;
 elsif act='task' then
  insert into public.workshop_tasks(title,details,staff_id,due,priority)
  values(trim(p->>'title'),coalesce(p->>'details',''),p->>'staffId',(p->>'due')::date,p->>'priority');
 elsif act='editTask' then
  update public.workshop_tasks set title=trim(p->>'title'),details=coalesce(p->>'details',''),staff_id=p->>'staffId',due=(p->>'due')::date,priority=p->>'priority' where id=v_id::uuid;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Tâche introuvable.';end if;
 elsif act='complete' then
  if jsonb_typeof(p->'done') is distinct from 'boolean' then raise exception 'Statut invalide.';end if;
  select * into v_task from public.workshop_tasks where id=v_id::uuid and exists(select 1 from public.workshop_staff s where s.id=staff_id and s.active) for update;
  if not found then raise exception 'Tâche introuvable.'; end if;
  if not v_admin and v_task.staff_id is distinct from a->>'self' then
   raise exception 'Cette tâche n’est pas la tienne.' using errcode='42501';
  end if;
  v_done:=(p->>'done')::boolean;
  update public.workshop_tasks set done=case when v_done then 1 else 0 end,
    completed_at=case when v_done then coalesce(completed_at,now()) else null end where id=v_task.id;
 elsif act='confirm' then
  if a->>'self' is null then raise exception 'Associe ton adresse e-mail à ta fiche dans Équipe.';end if;
  update public.workshop_days set confirmed=coalesce(confirmed,now())
   where date=(now() at time zone 'Europe/Paris')::date and staff_id=a->>'self' and presence='present' and station is not null;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Aucun poste ne t’est affecté aujourd’hui.';end if;
 else raise exception 'Action inconnue.';
 end if;
 return jsonb_build_object('ok',true);
exception
 when unique_violation then raise exception 'Cette adresse e-mail est déjà utilisée par un autre collaborateur.';
 when check_violation then raise exception 'Vérifie les informations saisies : nom, e-mail, équipe, présence, poste ou tâche invalide.';
 when foreign_key_violation then raise exception 'Collaborateur introuvable.';
 when not_null_violation then raise exception 'Il manque une information obligatoire.';
end $$;
create or replace function public.workshop_save_schedule(p_staff_id text,p_date date,p_presence text,p_slots jsonb,p_expected jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r public.workshop_days%rowtype; actual jsonb; slot jsonb; previous_end text; clean_slots jsonb:='[]';
begin
 lock table public.workshop_staff in share mode;
 a:=workshop_private.actor();
 if coalesce((a->>'can_manage_schedule')::boolean,false) is not true then raise exception 'Modification des horaires réservée à l’administrateur et aux modérateurs autorisés.' using errcode='42501';end if;
 if p_date is null or not exists(select 1 from public.workshop_staff where id=p_staff_id and active) then raise exception 'Date ou collaborateur invalide.';end if;
 if p_presence is null or p_presence not in ('present','absent','leave','rest','unknown') then raise exception 'Statut invalide.';end if;
 if p_slots is null or jsonb_typeof(p_slots)<>'array' then raise exception 'Créneaux invalides.';end if;
 if jsonb_array_length(p_slots)>4 or (p_presence='present' and jsonb_array_length(p_slots)=0) or (p_presence<>'present' and jsonb_array_length(p_slots)<>0) then raise exception 'Renseigne de 1 à 4 plages pour une journée travaillée, aucune pour les autres statuts.';end if;
 for slot in select value from jsonb_array_elements(p_slots) loop
  if coalesce(slot->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(slot->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Horaire invalide : utilise HH:MM.';end if;
  if slot->>'start'>=slot->>'end' or (previous_end is not null and slot->>'start'<previous_end) then raise exception 'Les plages doivent être ordonnées, sans chevauchement et dans la même journée.';end if;
  previous_end:=slot->>'end';clean_slots:=clean_slots||jsonb_build_array(jsonb_build_object('start',slot->>'start','end',slot->>'end'));
 end loop;
 lock table public.workshop_days in share row exclusive mode;
 select * into r from public.workshop_days where date=p_date and staff_id=p_staff_id for update;
 actual:=jsonb_build_object('presence',coalesce(r.presence,'unknown'),'slots',coalesce(r.slots,'[]'::jsonb),'station',r.station,'confirmed',r.confirmed);
 if p_expected is distinct from actual then raise exception 'Cette journée a changé depuis son ouverture. Ferme puis rouvre les horaires pour actualiser.';end if;
 insert into public.workshop_days as existing(date,staff_id,presence,slots,station,confirmed)
 values(p_date,p_staff_id,p_presence,clean_slots,null,null)
 on conflict(date,staff_id) do update set presence=excluded.presence,slots=excluded.slots,
 station=case when excluded.presence='present' then existing.station else null end,
 confirmed=case when excluded.presence='present' and existing.presence='present' then existing.confirmed else null end;
 return jsonb_build_object('ok',true);
end $$;
revoke all on function public.workshop_save_schedule(text,date,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.workshop_save_schedule(text,date,text,jsonb,jsonb) to authenticated;
notify pgrst,'reload schema';
commit;
