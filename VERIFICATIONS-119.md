# Atelier Fayet 33 — vérifications MAJ119

23 novembre 2026. Base : MAJ118 corrigée, sans Toolbox 33. Aucun déploiement réel.

## Fonctionnement ajouté

Mode de déplacement volontaire sur le plan des administrateurs/modérateurs.
Glissement depuis la carte du poste principal, indication de compatibilité,
confirmation avant enregistrement. Menus existants conservés. Géométrie cumulable.
En brouillon, aucune publication automatique. En lecture seule, aucune commande
de déplacement ni poignée n’est proposée.

## Tests effectués

| Contrôle | Résultat / portée |
|---|---|
| TypeScript et production Vite | Compilation réussie. |
| SQL 119 | Exécuté sur PostgreSQL local PGlite, réexécuté sans doubler l’extension du garde ni perdre sa définition originale. |
| Transfert du jour | Fonction SQL réelle exécutée : changement atomique du poste, horaires et confirmation strictement conservés, aucun nouvel événement de confirmation. |
| Destinations | Compétence absente, bureau pour technicien, pôle technique pour encadrant, pont en panne : refus. Pont bloqué : transfert manuel autorisé. |
| Permissions | Appels admin et modérateur acceptés ; collaborateur, invité, directeur et anonyme refusés. Rubrique fermée respectée. Table privée des autorisations inaccessible. Ancienne RPC renommée non exposée. |
| Protection existante | Garde original exécuté pour les autres changements ; changement SQL direct d’un poste principal vers un autre encore refusé. Aucun indicateur fourni par un client n’accorde de permission. |
| Présence / congé | Congé accepté et compte suspendu refusés. Confirmation conservée, sans retrait intermédiaire du poste. |
| Concurrence | Ancien poste ou état géométrie attendu différent : refus. Version de brouillon périmée ou baseline horaires changée : refus. Verrous et comparaisons exécutés localement, pas de test de charge multi-connexion. |
| Géométrie | Ajout complémentaire conservant le poste principal, transfert du principal conservant la géométrie ; départ depuis la géométrie secondaire refusé ; même destination sans écriture. |
| Préparation / publication | Futur sans brouillon refusé. Transfert dans le brouillon ne changeant pas workshop_days. Publication ultérieure par le moteur existant réussie et nettoyage des autorisations transitoires vérifié. Annulation du brouillon conservée. |
| Prévalidation JavaScript | Compétences, horaires, équipes, absence, panne, pont bloqué, invité/directeur, mauvais poste source et même destination vérifiés. La base refait les vérifications. |
| Geste réel dans le navigateur | Composant WorkshopPlan réel avec données de test : activation volontaire, glissement souris Pont 1 → Pont 2, confirmation, nom déplacé et mention Présence confirmée conservée. Dépôt sur pont en panne refusé, aucune confirmation proposée, personne restant sur Pont 2. |
| Lecture seule | Bouton et poignées supprimés quand le plan passe en lecture seule ; affectations et horaires toujours visibles. |
| Non-régression ciblée | Comparaison des fichiers existants : seuls workshop.tsx, workshop-plan.tsx et l’import CSS dans main.tsx changent. Autres pages, assets, dépendances et Edge Functions inchangés. Identifiants distincts du correctif118 conservés. |

## Architecture et sécurité

Le transfert publié est un UPDATE unique de station/geometry. Il ne retire
ni ne recrée de ligne de présence et ne met jamais confirmed à null.
Une autorisation privée liée à la transaction et au changement exact permet
au garde de laisser passer uniquement le transfert contrôlé. Elle est retirée
avant le retour de la fonction ; une erreur annule la transaction.

Le corps du garde existant est sauvegardé puis réutilisé intégralement pour
les autres opérations. La publication habituelle est enveloppée pour installer
les mêmes autorisations exactes du brouillon, puis appelle le moteur original
avec ses contrôles de version, baseline, compétences et publication.
Aucune fonction publique ne permet de créer soi-même ces autorisations.
Les tables privées utilisent RLS sans accès direct pour anon/authenticated.

Les affectations multiples géométrie gardent la sémantique existante. Le dépôt
n’est pas un échange : les collègues déjà au poste de destination ne sont pas
déplacés. La personne non affectée reste à placer via les menus habituels.

## Limites et installation

Tests locaux avec schéma connu des migrations précédentes et services simulés
pour l’interface. Pas de modification de la base Supabase réelle ni de test de
notification mobile réelle. Le geste tactile utilise Pointer Events et un mode
activable limitant les conflits de défilement, mais n’a pas été testé sur un
vrai téléphone : contrôle à effectuer après installation. Les menus existants
restent une alternative sur tous les appareils.

Un seul nouveau SQL est nécessaire : `supabase/119-glisser-deposer.sql`.
Aucune Edge Function ni clé supplémentaire. Pas de dépendance, API payante ou
nouveau Cron ; requête de transfert seulement après confirmation, synchronisation
20 s existante. Les quotas actuels continuent de s’appliquer.

ZIP complet nettoyé : sources, assets, configurations et fonctions Edge conservées ;
uniquement le nouveau SQL 119, guide et rapport 119. Sans variables d’environnement,
node_modules, dist, pages de test, anciens guides ou fichier _redirects.
