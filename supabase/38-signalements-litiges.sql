-- MAJ38 : après 37. Réexécutable.
begin;
-- Les nouveaux signalements n’exigent plus de lieu. L’historique est conservé.
create or replace function public.workshop_create_report(p_id uuid,p_registration text,p_notes text,p_photos jsonb,p_before_intervention boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();if p_before_intervention is null then raise exception 'Choix requis.';end if;
 perform pg_advisory_xact_lock(hashtextextended('report-location:'||p_id::text,0));
 if exists(select 1 from public.workshop_reports where id=p_id and before_intervention is distinct from p_before_intervention) then raise exception 'Signalement déjà enregistré avec un autre contexte.';end if;
 result:=public.workshop_create_report(p_id,p_registration,p_notes,p_photos);update public.workshop_reports set before_intervention=p_before_intervention where id=p_id;return result;end $$;
create or replace function public.workshop_update_report(p_id uuid,p_version integer,p_registration text,p_notes text,p_photos jsonb,p_before_intervention boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform workshop_private.actor();if p_before_intervention is null then raise exception 'Choix requis.';end if;result:=public.workshop_update_report(p_id,p_version,p_registration,p_notes,p_photos);update public.workshop_reports set before_intervention=p_before_intervention where id=p_id;return result;end $$;
alter table public.workshop_disputes add column if not exists level smallint check(level between 1 and 3);
create or replace function public.workshop_save_dispute(p_id uuid,p_version integer,p_client text,p_registration text,p_description text,p_followup text,p_status text,p_level integer) returns void language plpgsql security definer set search_path='' as $$
begin perform workshop_private.actor();if p_level is null or p_level not between 1 and 3 then raise exception 'Choisis le niveau 1, 2 ou 3.';end if;perform public.workshop_save_dispute(p_id,p_version,p_client,p_registration,p_description,p_followup,p_status);update public.workshop_disputes set level=p_level where id=p_id;end $$;
create or replace function public.workshop_delete_dispute(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_disputes%rowtype;begin a:=workshop_private.actor();if not coalesce((a->>'admin')::boolean,false) then raise exception 'Suppression réservée à l’administrateur.' using errcode='42501';end if;select * into r from public.workshop_disputes where id=p_id for update;if not found then raise exception 'Litige introuvable.';end if;if p_version is distinct from r.version then raise exception 'Litige modifié entre-temps. Actualise avant de le supprimer.';end if;delete from public.workshop_disputes where id=p_id;end $$;
revoke all on function public.workshop_create_report(uuid,text,text,jsonb,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,boolean),public.workshop_save_dispute(uuid,integer,text,text,text,text,text,integer),public.workshop_delete_dispute(uuid,integer) from public,anon,authenticated;
grant execute on function public.workshop_create_report(uuid,text,text,jsonb,boolean),public.workshop_update_report(uuid,integer,text,text,jsonb,boolean),public.workshop_save_dispute(uuid,integer,text,text,text,text,text,integer),public.workshop_delete_dispute(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
