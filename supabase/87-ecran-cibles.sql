-- MAJ87 : nécessite les mises à jour 85 et 86. Réexécutable.
begin;
do $$begin
 if to_regprocedure('public.workshop_screen_read85_before87(text)') is null then
  alter function public.workshop_screen_read85(text) rename to workshop_screen_read85_before87;
 end if;
end$$;
-- Conserve les contrôles d’autorisation, d’expiration, de maintenance et de disponibilité.
revoke all on function public.workshop_screen_read85_before87(text) from public,anon,authenticated;
create or replace function public.workshop_screen_read85(p_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s jsonb;d date;g jsonb;tot jsonb;custom_tot jsonb;labels jsonb;q jsonb;
begin
 s:=public.workshop_screen_read85_before87(p_token);
 if s is null or s ? 'unavailable' then return s;end if;
 d:=(s->>'date')::date;
 select jsonb_build_object('purge',purge,'batteries',batteries,'geometry',geometry,'clim',clim)
 into g from public.workshop_service_targets where date=d;
 g:=coalesce(g,'{}'::jsonb)||workshop_private.target_goals86(d);
 select coalesce(jsonb_object_agg(category,n),'{}'::jsonb) into tot from
 (select category,sum(quantity) n from public.workshop_target_sales
 where date=d and deleted_at is null and category in ('purge','batteries','geometry','clim') group by category)x;
 select coalesce(jsonb_object_agg('custom:'||target_id,n),'{}'::jsonb) into custom_tot from
 (select target_id,sum(quantity) n from workshop_private.sales86
 where date=d and deleted_at is null group by target_id)x;
 select coalesce(jsonb_object_agg('custom:'||id,name),'{}'::jsonb) into labels
 from workshop_private.targets86 where starts_on<=d;
 q:=jsonb_build_object('goal',coalesce((select goal from public.workshop_quality_goals where date=d),
 case when extract(isodow from d) between 1 and 6 then 2 else 0 end),
 'total',(select count(*) from public.workshop_quality_results where date=d and deleted_at is null));
 -- Compteurs uniquement : aucun auteur, lien de formulaire ou droit d’édition.
 return s||jsonb_build_object('performance',jsonb_build_object('targets',g,'totals',tot||custom_tot,'labels',labels,'quality',q));
end$$;
revoke all on function public.workshop_screen_read85(text) from public,anon,authenticated;
grant execute on function public.workshop_screen_read85(text) to anon,authenticated;
notify pgrst,'reload schema';
commit;
