-- Après les scripts 03 et 04. Import de plannings : aucun compte ou poste créé.
begin;
alter table public.workshop_days add column if not exists slots jsonb not null default '[]'::jsonb;
alter table public.workshop_days drop constraint if exists workshop_days_presence_check;
alter table public.workshop_days add constraint workshop_days_presence_check check(presence in ('unknown','present','absent','leave','rest'));
create or replace function public.workshop_import_schedule(p_rows jsonb,p_replace boolean default false)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a jsonb; r jsonb; slot jsonb; v_slots jsonb; v_staff text; v_date date; v_presence text;
 v_previous_end text; existing public.workshop_days%rowtype; saved integer:=0; skipped integer:=0;
begin
 a:=workshop_private.actor();
 if (a->>'admin')::boolean is not true then raise exception 'Import réservé à l’administrateur.' using errcode='42501';end if;
 if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception 'Liste de journées invalide.';end if;
 if jsonb_array_length(p_rows)<1 or jsonb_array_length(p_rows)>1200 then raise exception 'Import limité à 1200 journées.';end if;
 if exists(select 1 from jsonb_array_elements(p_rows) x group by x->>'staff_id',x->>'date' having count(*)>1) then raise exception 'Doublons de personne et date dans cet import.';end if;
 -- L’import et les changements manuels ne peuvent pas se superposer.
 lock table public.workshop_days in share row exclusive mode;
 for r in select value from jsonb_array_elements(p_rows) loop
  if coalesce(r->>'date','') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then raise exception 'Date ISO attendue.';end if;
  v_staff:=r->>'staff_id';v_date:=(r->>'date')::date;v_presence:=r->>'presence';v_slots:=r->'slots';
  if v_date is null or not exists(select 1 from public.workshop_staff where id=v_staff) then raise exception 'Date ou collaborateur invalide.';end if;
  if v_presence is null or v_presence not in ('present','rest','absent','leave') then raise exception 'Vérifie le statut de chaque journée.';end if;
  if v_slots is null or jsonb_typeof(v_slots)<>'array' then raise exception 'Créneaux invalides.';end if;
  if jsonb_array_length(v_slots)>4 or (v_presence='present' and jsonb_array_length(v_slots)=0) or (v_presence<>'present' and jsonb_array_length(v_slots)<>0) then raise exception 'Créneaux incompatibles avec le statut.';end if;
  v_previous_end:=null;
  for slot in select value from jsonb_array_elements(v_slots) loop
   if coalesce(slot->>'start','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' or coalesce(slot->>'end','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then raise exception 'Horaire invalide : utiliser HH:MM.';end if;
   if (slot->>'start') >= (slot->>'end') or (v_previous_end is not null and (slot->>'start')<v_previous_end) then raise exception 'Les créneaux doivent être ordonnés, sans chevauchement et dans la même journée.';end if;
   v_previous_end:=slot->>'end';
  end loop;
  select * into existing from public.workshop_days where date=v_date and staff_id=v_staff;
  if found then
   if existing.confirmed is not null or not coalesce(p_replace,false) then skipped:=skipped+1;continue;end if;
   if existing.presence=v_presence and existing.slots=v_slots then skipped:=skipped+1;continue;end if;
   update public.workshop_days set presence=v_presence,slots=v_slots,
     station=case when v_presence='present' then station else null end,confirmed=null
    where date=v_date and staff_id=v_staff;
  else
   insert into public.workshop_days(date,staff_id,presence,station,confirmed,slots) values(v_date,v_staff,v_presence,null,null,v_slots);
  end if;
  saved:=saved+1;
 end loop;
 return jsonb_build_object('saved',saved,'skipped',skipped);
end $$;
revoke all on function public.workshop_import_schedule(jsonb,boolean) from public,anon,authenticated;
grant execute on function public.workshop_import_schedule(jsonb,boolean) to authenticated;
notify pgrst,'reload schema';
commit;
