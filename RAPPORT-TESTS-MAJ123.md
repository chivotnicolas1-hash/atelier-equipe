# MAJ123 — vérifications

Préparation du 26 novembre 2026 sur MAJ122. Aucun déploiement ni modification de production, aucune utilisation de mot de passe réel et aucun message envoyé à un prestataire.

| Contrôle | Résultat |
| --- | --- |
| Connexion depuis l'écran autorisé, administrateur et modérateur | Retour à l'espace de gestion, pas de rebascule initiale vers le mode écran |
| Ancien verrou et page de retour | Effacés dans ce parcours ; autorisation du PC conservée |
| Compte identifié par sa fiche et son ID, sans champ e-mail d'affichage | Retour de gestion vérifié |
| Changement de compte depuis l'écran connecté | Contrôle PC avant transfert ; retour de gestion après succès |
| Compte refusé par le contrôle PC | Aucune session transférée ni sortie du verrou |
| Mode écran volontaire et bouton de connexion | Parcours existants conservés |
| Confettis après ajout de vente | Déclenchés après succès uniquement ; erreur sans animation |
| Double clic sur l'ajout | Une requête, un événement d'animation |
| Première lecture et rafraîchissement des cibles | Pas de confettis rejoués |
| Nouvel enregistrement reçu par l'écran atelier | Marqueur détecté une seule fois pour la journée courante |
| Correction de quantité | Pas de changement de date de création, donc pas de nouvelle animation d'écran |
| Animation | 42 éléments, non interactifs, arrêt automatique ; mouvement réduit respecté |
| Texte qualité | « Hors ventes » dans les deux composants concernés |
| Fiches prestataires | Trois fiches distinctes, vierges par défaut ; lecture/modification admin et modérateurs |
| Coordonnées et auteur | Enregistrement/affichage et version mis à jour ; identifiant Auth de l'éditeur non retourné |
| Concurrence et validation des champs | Mauvaise version, prestataire inconnu, téléphone/e-mail invalides ou champs excessifs refusés |
| Collaborateur, invité, directeur, anonyme | Aucun accès aux contacts, ni à la table privée |
| Compte suspendu ou banni avec session existante | Lecture/modification des contacts et détail authentifié refusés pour admin/modérateur |
| Rubrique déchets fermée | Refus du modérateur conservé |
| Fiche fermée | Aucun appel de lecture ; liens téléphone et e-mail construits sans interpréter un lien arbitraire |
| Agrégation des ventes | Somme par personne et cible, cibles personnalisées comprises, homonymes séparés |
| Suppressions et sélection de date | Ventes supprimées et autres journées exclues du détail |
| Écran connecté | Admin/modérateur/directeur autorisés selon les contrôles existants ; autres rôles refusés |
| Nouveau détail des ventes | Noms et quantités seulement, sans identifiant Auth, e-mail ni historique de saisie |
| Écran sans connexion | Nouveau détail accessible uniquement avec un jeton de PC valide |
| Jeton invalide, inconnu, expiré ou révoqué | Refus ; aucun repli vers un accès non autorisé |
| Maintenance et plan fermé du PC d'affichage | Écran indisponible, aucun détail ajouté |
| Autres données de l'écran | Comparaison avec la fonction réelle fournie : plan, informations, thème et paramètres conservés |
| Ancien SQL seulement | Compteurs/plan conservés ; détail indisponible expliqué ; pas de contournement des erreurs de permission |
| Survol | Noms et quantités individuels, souris/clavier, fermeture Échap et placement près d'un bord vérifiés |
| Réinstallation SQL | Aucune perte de coordonnées enregistrées |
| Vérification finale | Exécutée localement en lecture seule |
| TypeScript strict et build Vite | Réussis |
| Comparaison avec MAJ122 | 188 fichiers métier/ressources identiques ; 7 fichiers ciblés modifiés ; 4 modules/styles ajoutés ; aucun supprimé |
| Dépendances et fonctions Edge | Paquets, verrou, configuration et fonctions Edge inchangés |
| Plan classique, glisser-déposer, sessions chiffrées | Sources conservées |

## Méthodes

Les fonctions SQL nouvelles sont exécutées dans PGlite, PostgreSQL isolé. La chaîne d'identité et la lecture du PC d'affichage sont reprises des définitions transmises. Les tables de comptes et de ventes sont représentées par des fixtures. Le calcul de performance préexistant, non modifié, est représenté par un substitut pour isoler le test de la nouvelle façade ; ses anciens calculs ne sont pas tous rejoués.

Les composants TSX et leurs handlers réels sont exécutés avec un environnement de hooks contrôlé et un client Supabase simulé. Les événements de clic, double clic, survol, clavier, succès/échec et changement de compte sont vérifiés. Le test de navigation exécute les expressions et effets du composant réel, pas une copie indépendante de sa logique. Les tests n'ajoutent aucune dépendance à l'application livrée.

Un lancement de navigateur local a été tenté, mais le binaire Chromium attendu n'est pas installé dans l'environnement. Aucun test visuel complet avec un vrai navigateur ni sur un téléphone physique n'est donc revendiqué. Les vérifications d'infobulle portent sur les événements et classes de placement ; le rendu réel doit être contrôlé après déploiement autorisé.

## Sécurité et limites

La fonction publique de lecture sans session délègue d'abord à la fonction existante de validation du jeton. En cas de révocation, expiration, maintenance ou rubrique fermée, elle n'ajoute pas les données de vente. Le repli de compatibilité dans l'interface se limite aux fonctions absentes ; un refus de droits ne déclenche jamais ce repli.

Les contacts ne sont pas inclus dans ce snapshot. La table est privée, avec RLS activée et aucun privilège client direct. Les RPC vérifient le rôle et la rubrique côté serveur. Le détail des ventes ne révèle pas les identifiants de connexion. Aucun nouveau mécanisme de récupération ou de chiffrement des mots de passe n'est introduit ; les protections antérieures restent en place.

Les sources du moteur de vente, du délai de cinq minutes, des notifications122, des demandes de déchets et du plan ne sont pas réécrites par ce SQL. Les régressions sont évaluées par comparaison et tests ciblés ; l'ensemble des parcours de la production n'a pas été rejoué.

## Coût et ressources

Aucune API payante, nouveau service, abonnement ou dépendance de production. Les confettis sont calculés sur l'appareil. Sur un écran connecté, un RPC de détail s'ajoute au cycle de 20 secondes ; sur le PC autorisé sans session, le même snapshot transporte le détail, sans requête par survol. Les contacts ne sont lus que lorsque leur fiche est ouverte. La nouvelle table ne contient que les coordonnées des trois prestataires, sans image ni pièce jointe.

Le quota global du projet n'est pas mesuré ici : son respect n'est pas garanti par ces essais. Les nouveaux appels restent limités aux vues effectivement ouvertes, avec le cycle existant.
