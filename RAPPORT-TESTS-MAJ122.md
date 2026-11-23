# MAJ122 — vérifications

Vérifications locales finalisées le 24 novembre 2026, sur la base MAJ121. Aucun compte réel utilisé, aucun déploiement ni modification de production. Les données sont fictives et isolées.

| Contrôle | Résultat |
| --- | --- |
| Soir avant 18 h 30 | Aucun rappel |
| Soir à partir de 18 h 30 | Un seul destinataire, choisi sur la fin du dernier créneau |
| Matin avant 7 h 30 / avant disponibilité | Aucune notification de disponibilité |
| Matin à partir de 7 h 30 | Un seul destinataire, choisi sur le début du premier créneau |
| Coupure déjeuner | Premier début et dernière fin correctement utilisés |
| Un seul encadrant avec horaires | Choisi le matin et le soir |
| Égalité d'horaires | Départage par nom et identifiant, un seul destinataire |
| Encadrant sans horaire valide, absent ou en congé accepté | Exclu |
| Collaborateur sans droit, invité, directeur, inactif, suspendu, banni ou compte non confirmé | Exclu |
| Aucun encadrant prévu | Pas d'envoi de substitution à une personne sans horaires |
| Planning importé après l'heure habituelle | Sélection au passage suivant, sans décision vide bloquante |
| Récapitulatif déjà préparé | Pas de rappel de préparation le soir |
| Dimanche / publication du samedi | Dimanche exclu, notification du samedi conservée le lundi |
| Heure de Paris été/hiver | Bornes de 7 h 30 / 18 h 30 respectées |
| Passages répétés et horaires changés après enregistrement | Aucun deuxième destinataire ni message supplémentaire |
| Message ancien déjà enregistré | Pas de réémission après installation |
| Erreur forcée de mise en file | Message et décision annulés ensemble ; passage suivant possible |
| Programme consommables appelant la routine existante | Préparation hebdomadaire et ses propres destinataires conservés ; pas de restriction générale de toutes les notifications |
| Fonctions/tables nouvelles | Pas d'accès direct par anon/authenticated ni par un rôle serveur non propriétaire ; aucun droit métier ajouté |
| Réexécution de l'installation | Sauvegarde initiale et décisions conservées, aucun message déclenché par l'installation |
| Vérification finale | Requête exécutée localement sans envoi |
| Déchets : modification des quantités avant/après relance | Validation et dates initiales conservées, pas de seconde validation |
| Déchets : délai en jours ouvrés | Échéance initiale inchangée après correction et relance |
| Déchets : modification d'une demande collectée | Pas de réouverture ni changement de date de ramassage |
| Déchets : droits, concurrence, unités et prestataire | Contrôles de MAJ121 retestés et conservés |
| TypeScript strict et build Vite | Réussis |
| Comparaison avec MAJ121 | 193 fichiers métier/ressources identiques, 2 fichiers de texte d'interface modifiés, aucun supprimé |
| Dépendances et Edge Functions | package.json, verrou et fonctions Edge inchangés |
| Plan, glisser-déposer, préparations automatiques120 et chiffrement local121 | Sources conservées |

## Méthode et portée

Les fonctions SQL sont exécutées dans PGlite, PostgreSQL local isolé. Le moteur de messages et la routine antérieure de récapitulatif sont repris depuis les définitions fournies. Les tables d'identité, comptes, horaires et notifications sont représentées par des fixtures correspondant aux champs utilisés. Le parcours de programmation des consommables existant est exécuté séparément pour vérifier que le remplacement du routage récapitulatif ne le restreint pas.

Les essais de présence des destinataires utilisent les horaires prévus ; ils ne simulent pas de pointage ni de confirmation WorkOrder. Un message enregistré est testé dans l'inbox et sa file de push ; cela ne constitue pas un accusé de réception de téléphone. Les répétitions sont vérifiées dans la base locale ; aucun test de charge à plusieurs serveurs Postgres réels n'est revendiqué.

Le jeu de régression déchets de MAJ121 est rejoué : fonctions fournies, défaut ancien reproduit, correction de chaque quantité, relance puis nouvelle correction, conservation des dates/validation, contrôle des rôles et des unités. Aucun nouveau changement serveur de déchets n'est requis pour cette livraison ; le SQL vérifie que MAJ121 est présent.

## Limites et mise en place

La base réelle, le Cron, le worker push et la réception sur les appareils ne sont pas testés directement. Les paramètres de notifications de téléphone restent nécessaires. La requête de vérification fournie montre les choix possibles avec les horaires réels après installation ; ce n'est pas un envoi de test.

Les textes de deux pages ont été modifiés, sans changement de structure ni de style. Le build et la comparaison de source sont vérifiés ; aucune nouvelle navigation de bout en bout sur téléphone physique n'est revendiquée. Les tests et limites de stockage chiffré décrits pour MAJ121 restent inchangés.

La règle choisit au moment du premier passage utile. Si les horaires changent après ce passage, la notification déjà attribuée n'est pas transférée à une autre personne. Les anciens messages restent conservés et aucune notification mobile déjà partie n'est rappelée.

## Coût et ressources

Aucune nouvelle API, dépendance d'exécution, clé ou abonnement. La tâche de notifications existante continue à fonctionner à sa fréquence habituelle. Le nouveau journal stocke au maximum deux décisions quotidiennes de récapitulatif ; il n'ajoute aucune photo ni pièce jointe. Les quotas globaux du projet ne sont pas mesurés ici et ne sont pas garantis par ces tests.
