# MAJ125 — vérifications

Préparation du 27 novembre 2026 sur MAJ124. Aucune modification, fausse donnée ou utilisation de compte réel en production.

| Contrôle | Résultat local |
| --- | --- |
| Exemple batteries 7/3, géométrie 3/6 | 66,7 % ; dix ventes conservées, six contributions créditées sur neuf |
| Compensation entre cibles | Impossible ; chaque contribution est plafonnée à sa propre cible |
| 100 % et arrondis | 100 % uniquement si chaque cible positive est atteinte ; un 99,99 % incomplet ne devient pas 100 % affiché |
| Matrice de 121 combinaisons de ventes | Condition de 100 % vérifiée pour chaque combinaison |
| Objectifs absents/incomplets/nuls et cibles personnalisées | Cas couverts ; contrôles qualité non ajoutés au calcul |
| Cohérence des vues | Même fonction de calcul utilisée par l'application et les écrans atelier |
| Barre PC | Nom retiré ; pas de repli vers l'adresse technique |
| Plan privé | Bouton et rendu limités à l'espace administrateur |
| RPC privée | Lecture/écriture refusées aux modérateurs, collaborateurs, invités, directeurs et anonymes |
| Isolation par administrateur | Deux comptes administrateurs fictifs ont des configurations séparées |
| Types de ponts | Ciseaux/deux colonnes acceptés ; valeur initiale inconnue ; autres valeurs et postes de gestion refusés |
| Répétition et concurrence | Sauvegarde sans doublon, absence d'incrément inutile, mauvaise version refusée |
| Rafraîchissement en cours d'édition | Une réponse commencée avant une modification ne remplace pas les choix non enregistrés |
| Fermeture | Retour au plan classique, confirmation d'abandon des modifications non enregistrées |
| Plan existant | Source inchangée ; choix du type dans l'essai sans écriture des postes publics |
| Rendu SVG | Modèles ciseaux et deux colonnes, orientations normales/90°, rendus réellement par React et inspectés après rasterisation |
| Sélection En formation | Envoi vers la nouvelle RPC sans créneau d'atelier ; libellé partagé visible |
| Passage Présent vers Formation | Statut enregistré ; poste, géométrie, confirmation et créneaux retirés |
| Retour Formation vers Présent | Horaires valides acceptés ; ancienne version de journée refusée |
| Droits sur les horaires | Administrateur et modérateur explicitement autorisé seulement |
| Semaine et import PDF | Formation restituée par la semaine ; import sans remplacement conserve la journée ; remplacement explicite fonctionne |
| Compteurs de présence | Formation exclue, même si un objet client incohérent comportait des créneaux |
| Comptes suspendus/bannis | Nouveaux accès refusés malgré une session existante |
| Réinstallation et diagnostic | Sans perte du réglage privé ; diagnostic final exécuté en lecture seule |
| SQL123/124 | Tests de contacts, ventes d'écran, jetons, habilitations clim et permissions rejoués avec succès |
| Navigation depuis le mode écran | Tests123 rejoués sur les sources125 ; retour à la gestion et verrou volontaire conservés |
| TypeScript et build Vite | Réussis |

## Méthodes et limites

Tests SQL dans PGlite, PostgreSQL isolé, sous rôles anon/authenticated avec différents rôles applicatifs. La chaîne d'identité, le lecteur de PC autorisé et le moteur des horaires proviennent des définitions fournies précédemment. Les tables, comptes et ventes sont des fixtures isolées ; le calcul ancien de performances d'écran est remplacé par un substitut pour tester la façade. Aucun jeu de test n'est livré dans le ZIP.

Les composants TSX et leurs événements réels sont exécutés dans un environnement de hooks contrôlé avec Supabase simulé. Les SVG sont aussi rendus par React réel puis convertis en image avec Inkscape, pour vérifier les deux modèles et leurs orientations. Cela ne constitue pas un test complet du rendu de toute l'application en navigateur.

Chromium n'étant pas disponible dans l'environnement utilisé, aucun test visuel complet sur navigateur, compte de production ou téléphone physique n'est revendiqué. Le comportement mobile est prévu par la grille défilante et le panneau de détail placé en dessous ; la validation sur appareil reste nécessaire après installation autorisée.

Le plan classique, le moteur d'identité, les sessions chiffrées, la matrice des compétences, le glisser-déposer, les habilitations clim et le composant de confettis sont conservés. Les données de vente restent inchangées : seule leur contribution au pourcentage est plafonnée.

## Architecture et coût

Le plan privé utilise des illustrations SVG isométriques, sans bibliothèque 3D ni rendu WebGL. Une table privée avec RLS conserve les types par compte administrateur. La RPC ne retourne aucun identifiant Auth ; elle ne modifie pas les postes, affectations ou brouillons de l'équipe. Il n'existe pas d'action de publication de ce plan privé.

Le nouveau statut est une journée entière sans disponibilité à l'atelier. Il ne constitue pas une gestion du temps de formation rémunéré et n'ajoute pas d'heures au total atelier. La contrainte SQL existante est étendue avec une alternative, sans retirer ses autres valeurs autorisées ; les données ne sont pas converties à l'installation. Le moteur de sauvegarde et d'import préexistant reste en place.

Aucune API payante, dépendance, abonnement, clé ou nouvelle fonction Edge. La configuration privée est petite et n'est consultée que si le plan privé est ouvert ; son rafraîchissement est suspendu en cours d'édition. Le respect des quotas globaux dépend de l'usage total du projet et n'a pas été mesuré ici.
