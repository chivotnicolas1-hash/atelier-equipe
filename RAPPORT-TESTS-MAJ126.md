# MAJ126 — vérifications

Préparée le 27 novembre 2026 sur MAJ125. Aucune modification de production, aucun compte réel ni fausse donnée dans le projet de production.

| Contrôle | Résultat local |
| --- | --- |
| Pont deux colonnes | Deux rails sous la voiture et deux bases longues supprimés ; colonnes, semelles et bras conservés |
| Pont ciseaux | Plateformes et mécanisme conservés |
| Rendu SVG | Deux types et deux orientations rendus par React réel et inspectés après rasterisation Inkscape |
| Remplacement du plan | Composant principal en relief sur PC, vue compacte et écran ; ancien essai privé retiré de l'interface |
| Reprise des choix privés | Types concordants importés ; cas contradictoire entre deux administrateurs laissé inconnu |
| Première installation | Noms, positions, horaires et affectations conservés ; versions incrémentées pour les types repris |
| Réexécution du SQL | Pas de réimport d'un ancien choix après correction, aucune affectation modifiée |
| Sauvegarde de poste | Type et métadonnées dans une seule transaction ; version commune et validation existante conservées |
| Gestion des types | Administrateur actif uniquement ; modérateur, collaborateur, invité, directeur et anonyme refusés à l'écriture |
| Session suspendue/bannie | Nouvelle sauvegarde refusée malgré une session existante |
| Lecteur des postes | Reprend les rôles autorisés sur le lecteur existant ; aucun identifiant personnel ajouté |
| Création/suppression de poste | Création avec type et orientation, suppression logique et bureau sans pont testés |
| Écran sans connexion | Nouveau type ajouté aux postes ; toutes les autres données124 conservées |
| Jeton PC | Inconnu, expiré ou révoqué refusé ; maintenance et rubrique fermée respectées |
| Repli de compatibilité | Seulement sur fonction absente, jamais sur refus de permission |
| Lecture seule du plan | Pas d'action de gestion ; ouverture et fermeture de fiche, accès clavier vérifiés |
| Affectation | Clic transmis au mécanisme existant, sans nouvelle écriture spécifique au rendu |
| Glisser-déposer | Hook et options119 conservés ; transmission du poste principal et du collaborateur vérifiée |
| Double affectation géométrie | Collaborateur visible sur ses deux postes |
| Affichage des présences | Confirmation, présence instantanée, pause et panne conservées |
| Focus depuis Ma journée | Surbrillance et appels de focus/défilement préservés |
| Postes de gestion | Masqués si vides hors préparation, visibles pendant la préparation |
| Éditeur de poste | Type envoyé avec position/orientation/numéro/version dans une seule RPC |
| Navigation depuis le mode écran | Tests de retour à la gestion et de verrou volontaire rejoués avec succès |
| SQL123/124/125 | Tests isolés de permissions, jetons, contacts, ventes, habilitations et formation rejoués |
| Compilation | TypeScript et Vite réussis |
| Comparaison avec MAJ125 | 196 fichiers métier/ressources identiques, six modifiés, un style ajouté ; deux fichiers d'essai devenus inutiles retirés |

## Méthodes et limites

Les migrations et RPC sont exécutées dans PGlite, PostgreSQL isolé, avec fixtures de comptes, postes et journées. La chaîne d'identité, les lecteurs d'écran et les fonctions d'horaires viennent des définitions déjà fournies. Le moteur des postes est repris du script historique51 local, réutilisé sans réécriture par la nouvelle façade. Le calcul de performances ancien utilise un substitut dans les tests de snapshot. Les comptes et données de ces essais ne sont pas livrés.

Les composants TSX réels et leurs événements sont exercés dans un environnement de hooks contrôlé, avec Supabase simulé. Le geste natif complet du glisser-déposer n'est pas rejoué en navigateur : le hook et la validation119 sont identiques à MAJ125, et la transmission de leurs paramètres par le nouveau rendu est vérifiée. Les SVG sont aussi rendus avec React réel puis convertis en image avec Inkscape ; leurs primitives et apparences corrigées sont vérifiées.

Chromium n'étant pas disponible dans l'environnement, aucun test visuel complet sur navigateur, téléphone physique ou compte de production n'est revendiqué. Les dimensions compactes, défilement et règles mobiles sont prévus dans le code ; la vérification sur appareil reste à faire après installation autorisée.

## Architecture

Le rendu principal garde les identifiants de postes, attributs data-station, menus d'affectation, règles métier, focus et points d'intégration du glisser-déposer. Le changement visuel n'introduit aucun nouveau moteur d'affectation. Une colonne lift_kind permet un type partagé, au lieu d'un choix par essai privé. Le type initial reste inconnu en l'absence d'information ; les bureaux restent sans pont.

Les fonctions existantes de postes, d'horaires, de plan et de lecture écran ne sont pas remplacées. Les nouvelles façades les réutilisent pour conserver les contrôles. La lecture de l'écran sans session valide toujours le jeton avant d'enrichir uniquement les métadonnées de postes déjà visibles. Les contrôles de maintenance et de révocation sont conservés.

Les sources du moteur d'affectation/compétences, du glisser-déposer119, des sessions chiffrées, du pourcentage corrigé125, des horaires/formation, des habilitations clim et des fonctions Edge sont inchangées. L'ancien composant d'essai et sa feuille de style sont retirés de l'application ; ses données privées en base ne sont pas supprimées.

## Ressources

Aucune dépendance, API payante, abonnement, nouvelle clé ou fonction Edge. Les ponts sont des SVG locaux. Les lecteurs126 remplacent les anciens appels au même rythme de synchronisation ; aucune requête par pont ni par clic sur la fiche. La colonne ajoute une courte valeur de type par poste. Les quotas globaux Supabase/Cloudflare n'ont pas été mesurés ici.
