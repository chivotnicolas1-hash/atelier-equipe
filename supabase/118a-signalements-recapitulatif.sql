-- MAJ118, sur une base déjà mise à jour en MAJ117. Réexécutable.
-- Les RPC d'origine continuent de contrôler l'accès et la publication.
begin;
create or replace function workshop_private.handover_reports118(p_item jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare d date;n bigint;
begin
 if p_item is null or p_item='null'::jsonb then return p_item;end if;
 if jsonb_typeof(p_item)<>'object' or p_item->>'date' is null then return p_item;end if;
 d:=(p_item->>'date')::date;
 select count(*) into n from public.workshop_reports r
 where r.created_at >= (d::timestamp at time zone 'Europe/Paris')
   and r.created_at < ((d+1)::timestamp at time zone 'Europe/Paris');
 return p_item||jsonb_build_object('reports_count',n,'reports_date',d);
end $$;
create or replace function public.workshop_list_handovers118(p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb;begin
 r:=public.workshop_list_handovers(p_offset);
 return jsonb_set(r,'{items}',(select coalesce(jsonb_agg(workshop_private.handover_reports118(x) order by ord),'[]') from jsonb_array_elements(r->'items') with ordinality t(x,ord)));
end $$;
create or replace function public.workshop_morning118(p_ack date default null)
returns jsonb language plpgsql security definer set search_path='' as $$
begin return workshop_private.handover_reports118(public.workshop_morning82(p_ack));end $$;
revoke all on function workshop_private.handover_reports118(jsonb),public.workshop_list_handovers118(integer),public.workshop_morning118(date) from public,anon,authenticated;
grant execute on function public.workshop_list_handovers118(integer),public.workshop_morning118(date) to authenticated;
notify pgrst,'reload schema';
commit;
