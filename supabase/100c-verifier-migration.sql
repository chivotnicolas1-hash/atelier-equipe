-- LECTURE SEULE : après installation et finalisation depuis l'application.
select s.name,l.login_id,s.active,a.anonymized_at is not null as coordonnee_remplacee,
 a.user_id is not null as compte_associe
from public.workshop_staff s join workshop_private.accounts100 a on a.staff_id=s.id
left join public.workshop_custom_logins100 l on l.staff_id=s.id order by s.name;
-- Résultat attendu : aucune adresse personnelle sur les fiches de l'application.
select count(*) as fiches_avec_ancienne_adresse from public.workshop_staff
where nullif(email,'') is not null and email not like '%@atelier.invalid';
-- Contrôle d'éventuels comptes Auth non associés à une fiche atelier.
-- Ces comptes ne sont pas supprimés automatiquement : ne pas supprimer un UUID au hasard.
select count(*) as comptes_auth_hors_fiches from auth.users u
where not exists(select 1 from workshop_private.accounts100 a where a.user_id=u.id);
