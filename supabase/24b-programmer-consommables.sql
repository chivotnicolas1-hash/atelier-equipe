-- Après 24-consommables-hebdomadaires.sql. SQL Editor, rôle postgres.
-- Contrôle chaque heure ; création une seule fois par semaine ISO (heure de Paris).
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule('atelier-consommables-hebdomadaires','0 * * * *',
 $$select workshop_private.ensure_weekly_order();$$);
