-- Réexécutable, même si la MAJ40b n’a jamais été installée.
-- Coupe l’accès de l’ancienne fonction payante, sans supprimer l’historique.
begin;
do $$begin
 if to_regprocedure('public.workshop_debrief_context(date,integer)') is not null then
  revoke all on function public.workshop_debrief_context(date,integer) from public,anon,authenticated;
 end if;
end $$;
notify pgrst,'reload schema';commit;
