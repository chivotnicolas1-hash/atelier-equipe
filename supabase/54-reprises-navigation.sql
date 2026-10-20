-- MAJ54 : après MAJ53. Réexécutable.
begin;
alter table public.workshop_lunch_handoffs add column if not exists edited_name text;
alter table public.workshop_lunch_handoffs add column if not exists edited_at timestamptz;
create or replace function public.workshop_lunch_manage(p_id uuid,p_version integer,p_action text,p_bt text default null,p_remaining text default null) returns void language plpgsql security definer set search_path='' as $$
declare a jsonb;r public.workshop_lunch_handoffs%rowtype;begin
 a:=workshop_private.actor();if not coalesce((a->>'manager')::boolean,false) then raise exception 'Réservé aux administrateurs et modérateurs.' using errcode='42501';end if;
 if p_action is null or p_action not in ('edit','delete') then raise exception 'Action invalide.';end if;
 perform pg_advisory_xact_lock(hashtextextended('lunch-handoff:'||p_id::text,0));select * into r from public.workshop_lunch_handoffs where id=p_id for update;
 if not found or r.version is distinct from p_version then raise exception 'Cette reprise a été modifiée ou supprimée. Actualise la liste.';end if;
 if p_action='delete' then
  -- Supprime aussi les messages et envois encore en attente liés à cette fiche.
  delete from public.workshop_push_queue q using public.workshop_push_subscriptions s,public.workshop_messages m where q.subscription_id=s.id and s.user_id=m.user_id and m.event_key='handoff:'||p_id::text and q.kind='message' and q.body=m.body and q.url=m.url;
  delete from public.workshop_messages where event_key='handoff:'||p_id::text;
  delete from public.workshop_lunch_handoffs where id=p_id;
 else
  if length(trim(coalesce(p_bt,''))) not between 1 and 40 or length(trim(coalesce(p_remaining,''))) not between 1 and 2000 then raise exception 'Renseigne le numéro de BT et le reste à faire.';end if;
  update public.workshop_lunch_handoffs set bt=trim(p_bt),remaining=trim(p_remaining),version=version+1,updated_at=now(),edited_at=now(),edited_name=coalesce((select name from public.workshop_staff where id=a->>'self'),a->>'user') where id=p_id;
 end if;
end $$;
revoke all on function public.workshop_lunch_manage(uuid,integer,text,text,text) from public,anon,authenticated;
grant execute on function public.workshop_lunch_manage(uuid,integer,text,text,text) to authenticated;
notify pgrst,'reload schema';commit;
