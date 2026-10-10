-- Mise à jour 03 : équipes métier. Les données existantes sont conservées.
begin;
alter table public.workshop_staff add column if not exists team text;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='workshop_staff_team_allowed' and conrelid='public.workshop_staff'::regclass) then
  alter table public.workshop_staff add constraint workshop_staff_team_allowed check(team in ('Technicien services rapide','Electrotechnicien','Mécatronicien','Mécanicien'));
 end if;
end $$;
create or replace function public.workshop_load(p_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; v_staff jsonb; v_days jsonb; v_tasks jsonb;
begin
 a:=workshop_private.actor(); v_admin:=(a->>'admin')::boolean;
 if p_date is null then raise exception 'Choisis une date.'; end if;
 select coalesce(jsonb_agg(case when v_admin then to_jsonb(s) else jsonb_build_object('id',s.id,'name',s.name,'team',s.team) end order by s.id),'[]'::jsonb)
 into v_staff from public.workshop_staff s;
 select coalesce(jsonb_agg(to_jsonb(d) order by d.staff_id),'[]'::jsonb) into v_days
 from public.workshop_days d where d.date=p_date;
 select coalesce(jsonb_agg(to_jsonb(t) order by t.done,t.due,t.created_at desc),'[]'::jsonb) into v_tasks
 from public.workshop_tasks t where v_admin or t.staff_id=a->>'self';
 return a || jsonb_build_object('staff',v_staff,'days',v_days,'tasks',v_tasks,'date',p_date);
end $$;
revoke all on function public.workshop_load(date) from public, anon, authenticated;
grant execute on function public.workshop_load(date) to authenticated;

create or replace function public.workshop_mutate(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare a jsonb; v_admin boolean; act text; v_id text; v_email text; v_task public.workshop_tasks%rowtype; v_count integer; v_done boolean;
begin
 a:=workshop_private.actor();v_admin:=(a->>'admin')::boolean;
 if p is null or jsonb_typeof(p)<>'object' then raise exception 'Action invalide.'; end if;
 act:=p->>'action';v_id:=p->>'id';
 if act in ('staff','day','task','editTask') and not v_admin then
  raise exception 'Action réservée à l’administration.' using errcode='42501';
 end if;
 if act='staff' then
  if nullif(trim(p->>'name'),'') is null then raise exception 'Renseigne un nom.'; end if;
  v_email:=nullif(lower(trim(p->>'email')),'');
  update public.workshop_staff set name=trim(p->>'name'),email=v_email,team=case when p ? 'team' then nullif(p->>'team','') else team end where id=v_id;
  get diagnostics v_count=row_count;
  if v_count=0 then raise exception 'Collaborateur introuvable.';end if;
 elsif act='day' then
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
  select * into v_task from public.workshop_tasks where id=v_id::uuid for update;
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
revoke all on function public.workshop_mutate(jsonb) from public, anon, authenticated;
grant execute on function public.workshop_mutate(jsonb) to authenticated;


notify pgrst, 'reload schema';
commit;
