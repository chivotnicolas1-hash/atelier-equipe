-- Appliquer après 03-equipes.sql. Ajout de la fiche administrateur sans toucher à Auth.
begin;
lock table public.workshop_staff in share row exclusive mode;
alter table public.workshop_staff drop constraint if exists workshop_staff_team_allowed;
alter table public.workshop_staff add constraint workshop_staff_team_allowed
 check(team in ('Technicien services rapide','Electrotechnicien','Mécatronicien','Mécanicien','Encadrants'));
-- Réutilise la fiche si elle est déjà associée à cette adresse.
-- Sinon, ajoute une nouvelle fiche ; aucun des 13 collaborateurs n’est remplacé.
insert into public.workshop_staff(id,name,email,team)
select lpad((coalesce(max(id::integer),0)+1)::text,2,'0'),
 'Nicolas Chivot','nchivot@norauto.fr','Encadrants'
from public.workshop_staff
having not exists(select 1 from public.workshop_staff where email='nchivot@norauto.fr');
update public.workshop_staff set team='Encadrants' where email='nchivot@norauto.fr';
notify pgrst, 'reload schema';
commit;
