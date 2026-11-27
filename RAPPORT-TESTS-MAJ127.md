# MAJ127 — vérifications

Préparation du 27 novembre 2026 sur MAJ126. Aucune modification de production, aucun compte réel ni fausse donnée injectée dans Supabase de production.

| Contrôle | Résultat local |
| --- | --- |
| Sélection des non-affectés | Présence et créneau valide requis ; poste principal ou géométrie déjà attribués exclus |
| Comptes et statuts exclus | Absents, repos, congés, formation, sans horaires, invités, directeurs, suspendus/inactifs exclus |
| Unicité | Une fiche par personne, tri par nom |
| Position du cadre | À droite des espaces de gestion ; colonne occupée évitée ; position de secours sans bureau |
| Brouillon uniquement | Cadre masqué hors préparation et en consultation seule |
| Disparition | Nom retiré après affectation ; cadre supprimé lorsque vide |
| Départ de glissement | Source nulle explicite, pas de faux identifiant de poste ; mode dédié et confirmation conservés |
| Géométrie seule | Déjà considérée comme une affectation ; depuis le cadre, première affectation principale à Géométrie correcte |
| Prévalidation client | Brouillon obligatoire pour la source nulle, compétence et panne toujours contrôlées |
| RPC serveur | Administrateur/modérateur actifs uniquement ; autres rôles refusés |
| Session suspendue/bannie | Nouvel accès refusé même avec une session existante |
| Version et baseline | Ancienne version, source déjà affectée et horaires changés refusés |
| Congé accepté et formation | Première affectation refusée |
| Destination | Panne, incompétence et équipe incompatible refusées ; pont bloqué manuel toujours autorisé |
| Données publiées | Identiques avant/après enregistrements dans le brouillon |
| Publication | Effectuée uniquement par l'action de publication existante et explicite |
| Déplacement entre postes | Moteur119 réutilisé, cumul géométrie conservé |
| Repli | Ancien déplacement119 seulement si nouvelle fonction absente et source non nulle ; jamais sur refus de droits |
| Symbole interdit | Surimpression sur pont bloqué/en panne, deux libellés conservés ; aucune surimpression sur pont disponible |
| Fiche et rendu du plan | Tests126 rejoués : postes 3D, affectations, bureaux, focus, états, présence, lecture seule et éditeur |
| Accès écran et migrations antérieures | Tests SQL123 à126 rejoués dans la base isolée |
| Navigation écran | Tests de retour à la gestion et verrou volontaire rejoués |
| Compilation TypeScript/Vite | Réussie |

## Méthodes et limites

Les migrations et RPC sont exécutées dans PGlite, PostgreSQL isolé. La chaîne d'identité, les lecteurs d'écran et les fonctions d'horaires sont repris des définitions déjà fournies. Les fonctions de préparation/affectation sont reprises des scripts52/56 locaux, puis le moteur119 est installé et réutilisé. Le nouveau contrôle est exercé sous plusieurs rôles PostgreSQL et applicatifs avec des fixtures isolées. Le calcul ancien de performances d'écran reste représenté par un substitut dans les tests de snapshot.

Les composants TSX et leurs événements réels sont exécutés avec des hooks contrôlés et Supabase simulé. La confirmation de déplacement extraite du composant réel est exécutée pour vérifier le payload nul, le numéro de version, le message de brouillon et les replis d'erreur. Le hook de geste conserve son moteur ; seul le type de source autorise désormais null. Le geste complet sur écran tactile n'est pas rejoué sur appareil réel.

Le navigateur Chromium n'étant pas disponible dans l'environnement, aucun test visuel complet en navigateur ou téléphone physique n'est revendiqué. La surimpression est vérifiée par sa présence conditionnelle, son libellé accessible et les règles de placement centrées sur le dessin. Une vérification sur appareil reste nécessaire après installation autorisée.

## Architecture et permissions

Le cadre n'est pas un poste et n'est pas une destination de dépôt. Aucun identifiant de poste artificiel n'est écrit. Sa position et ses personnes sont calculées à partir du plan et de la journée déjà chargés, en tenant compte du brouillon actuellement affiché. Il ne crée pas de table, de collaborateur ou de journée.

La RPC127 contrôle la première affectation sous verrou, vérifie la baseline, la source réellement vide, la disponibilité et la destination, puis délègue la sauvegarde au moteur de brouillon existant. Les déplacements entre postes délèguent au moteur119. Aucune action de publication n'est introduite. La nouvelle fonction vérifie les comptes suspendus/bannis et ne donne aucun droit supplémentaire aux autres rôles.

Les symboles de pont n'altèrent pas les permissions : panne et blocage restent deux états différents, avec les règles manuelles déjà définies. Les modèles3D corrigés126, les types de ponts partagés, le pourcentage des cibles, les horaires/formation, les sessions chiffrées et les fonctions Edge restent conservés.

## Ressources

Aucune dépendance, API payante, nouvelle clé ou fonction Edge. La liste utilise les données déjà chargées et se recalcule localement. Le cycle de synchronisation reste inchangé ; le nouveau RPC remplace l'ancien appel sur confirmation de déplacement. La consommation globale des quotas du projet n'est pas mesurée ici.
