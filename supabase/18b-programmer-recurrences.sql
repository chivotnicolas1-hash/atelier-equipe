-- Après 18-taches-recurrentes.sql. Exécuter avec SQL Editor (rôle postgres).
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('atelier-taches-recurrentes','* * * * *',
 $$select workshop_private.generate_recurring_tasks();$$);
