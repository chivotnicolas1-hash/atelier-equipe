begin;
alter table public.workshop_waste add column if not exists reminders73 jsonb not null default '[]';
create or replace function public.workshop_waste_remind73(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_waste%rowtype;person text;
begin a:=workshop_private.actor();
if not (coalesce((a->>'manager')::boolean,false) or coalesce((public.workshop_waste_pending()->>'can_progress')::boolean,false)) then raise exception 'Droit de suivi des déchets requis' using errcode='42501';end if;
select * into r from public.workshop_waste where id=p_id for update;
if not found or r.collected_at is not null or r.version is distinct from p_version then raise exception 'Cette demande a changé ou a été clôturée. Vérifie son suivi.';end if;
select name into person from public.workshop_staff where id=a->>'self';
update public.workshop_waste set reminders73=reminders73||jsonb_build_array(jsonb_build_object('at',now(),'by',coalesce(person,a->>'user'))),version=version+1 where id=p_id;
end $$;
create or replace function workshop_private.waste_with_reminders73(data jsonb) returns jsonb language sql stable security definer set search_path='' as $$
select data||jsonb_build_object('items',coalesce((select jsonb_agg(e.item||jsonb_build_object('reminders73',coalesce(w.reminders73,'[]'::jsonb)) order by e.ord) from jsonb_array_elements(data->'items') with ordinality as e(item,ord) left join public.workshop_waste w on w.id::text=(e.item->>'id')),'[]'::jsonb))
$$;
create or replace function public.workshop_waste_pending73() returns jsonb language sql security definer set search_path='' as $$select workshop_private.waste_with_reminders73(public.workshop_waste_pending())$$;
create or replace function public.workshop_waste_provider73(p_provider text,p_offset integer) returns jsonb language sql security definer set search_path='' as $$select workshop_private.waste_with_reminders73(public.workshop_waste_by_provider(p_provider,p_offset))$$;
revoke all on function workshop_private.waste_with_reminders73(jsonb) from public,anon,authenticated;
revoke all on function public.workshop_waste_remind73(uuid,integer),public.workshop_waste_pending73(),public.workshop_waste_provider73(text,integer) from public,anon;
grant execute on function public.workshop_waste_remind73(uuid,integer),public.workshop_waste_pending73(),public.workshop_waste_provider73(text,integer) to authenticated;
notify pgrst,'reload schema';commit;
