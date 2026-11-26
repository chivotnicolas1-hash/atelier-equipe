# MAJ124 — vérifications et modifications

Préparation sur MAJ123. Aucune modification de production ni utilisation d'un compte réel.

| Contrôle | Résultat local |
| --- | --- |
| Case de la fiche administrateur | Lecture de la valeur, activation et désactivation répétées, version mise à jour |
| Enregistrement immédiat | Confirmation après réponse ; aucun double appel sur un double clic |
| Modification concurrente | Refus d'écrasement ; dernière valeur relue dans la case |
| SQL absent ou réseau indisponible | Erreur visible, aucune habilitation validée artificiellement |
| Valeur initiale | Décochée ; aucune déduction à partir d'autres données |
| Permissions de la fiche | Administrateur actif uniquement ; modérateur, collaborateur, invité, directeur et anonyme refusés côté serveur |
| Compte suspendu/banni, session encore valide | Nouveaux accès refusés |
| Table et agrégation privées | RLS activée ; privilèges clients révoqués |
| Lecture écran connecté | Administrateur, modérateur et directeur selon les droits PC existants |
| Écran sans connexion | Jeton valide exigé ; jeton inconnu, expiré ou révoqué refusé |
| Maintenance et fermeture du plan | Aucun détail ajouté lorsque le snapshot est indisponible |
| Contenu du snapshot | Plan, coordonnées d'affichage, performances et détails des ventes123 conservés ; seuls les indicateurs d'habilitation sont ajoutés |
| Indicateur sur le roster | Même flocon que la cible Clim ; dernier élément à droite de la bonne ligne ; horaires et affectation conservés |
| Synchronisation | Changement/retrait reçu au snapshot ou au cycle de lecture suivant ; cycle existant de 20 secondes |
| Erreur de lecture des habilitations | Plan et horaires encore visibles ; message d'indisponibilité ; ancien flocon effacé |
| Compatibilité SQL | Repli vers 123, puis 89 seulement pour une fonction absente ; jamais après un refus de droits |
| Nom de compte PC | Nom de la fiche utilisé ; NOM Prénom si distingués ; noms composés conservés ; aucun repli vers l'adresse technique |
| Connexion et changement de compte depuis l'écran | Tests de navigation123 rejoués sur les sources124, retour à la gestion conservé |
| Ancien mode écran volontaire | Verrou et sortie par mot de passe conservés |
| Réinstallation SQL124 | Habilitations et versions conservées |
| Diagnostic124 | Exécuté en lecture seule dans l'environnement isolé |
| Non-régression SQL123 | Contacts, détails des ventes, permissions et contrôles de jeton rejoués avec succès |
| TypeScript et build Vite | Réussis |
| Comparaison des sources | 196 fichiers métier/ressources identiques, trois modifiés, trois ajoutés, aucun supprimé |
| Dépendances et Edge Functions | Inchangées |

## Méthodes et limites

Les SQL sont exécutés avec PGlite dans une base isolée. La chaîne d'identité et la fonction de lecture du PC autorisé sont celles des définitions fournies précédemment. Les tables de test, comptes et ventes sont fictifs et isolés ; le calcul de performance antérieur est remplacé par un substitut dans ces essais. Les permissions sont vérifiées sous les rôles PostgreSQL anon/authenticated, avec plusieurs rôles applicatifs et des sessions suspendues/bannies.

Les composants TSX et leurs handlers réels sont exécutés dans un environnement de hooks contrôlé avec un client Supabase simulé. Les lectures, clics, retours serveur, conflits et rafraîchissements sont vérifiés. Le placement à droite est vérifié par l'ordre JSX et les règles flex dédiées. Le même export d'icône Snowflake est utilisé que dans la cible Clim.

Le navigateur Chromium n'étant pas disponible dans cet environnement, aucun test visuel complet en navigateur ou sur téléphone physique n'est revendiqué. La validation du rendu réel et des comptes de production reste à effectuer après l'installation autorisée. Il ne s'agit pas d'un audit complet de la base en production ni de tous les parcours historiques.

Les sources du plan classique, de la matrice des compétences, des ventes/confettis123, de l'authentification Supabase, des sessions chiffrées et les fonctions Edge sont identiques à MAJ123. Les trois fichiers modifiés sont workshop.tsx, workshop-display.tsx et window-screen85.tsx ; les nouveaux modules concernent la case, son style et le nom d'affichage.

## Ressources et données

Aucune dépendance de production ajoutée, aucune API payante, aucun nouveau service. Une petite table privée conserve les indicateurs avec version et auteur de modification ; aucun document ou image n'est stocké. L'écran connecté ajoute une RPC au cycle existant ; l'écran sans connexion reçoit le booléen dans son snapshot, sans requête par collaborateur. Le quota global Supabase/Cloudflare n'est pas mesuré ici.

Les habilitations sont actuelles, pas historisées par jour. La case n'établit pas la validité d'un certificat et n'altère pas les règles d'affectation de la matrice de compétences.
