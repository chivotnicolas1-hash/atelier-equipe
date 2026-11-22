-- À exécuter APRÈS 118b. Aucun secret, appel HTTP ou clé API.
begin;
create extension if not exists pg_cron;
create or replace function workshop_private.plan_tick118() returns void
language plpgsql security definer set search_path='' as $$
begin
 perform workshop_private.plan_automatic118(now());
 -- Nettoie uniquement l'historique de CE programme, jamais les autres tâches.
 delete from cron.job_run_details where jobid in (select jobid from cron.job where jobname='atelier-plan-brouillon-118') and end_time<now()-interval '7 days';
end $$;
revoke all on function workshop_private.plan_tick118() from public,anon,authenticated;
-- L'heure de Paris est évaluée par la fonction : changements été/hiver gérés.
-- Dès 05:00, puis réessai toutes les 10 min si aucun horaire n'est disponible.
select cron.schedule('atelier-plan-brouillon-118','*/10 * * * *','select workshop_private.plan_tick118();');
-- Premier passage sans attendre le prochain réveil du programme.
select workshop_private.plan_automatic118(now());
commit;
