# Atelier Fayet 33 — vérifications de la MAJ118

22 novembre2026. Base : application complète117, sans Toolbox114.
Aucun déploiement ni modification de comptes réels.

## Modifications

- Dossiers de signalements déplacés sous la recherche, avant la liste ; mêmes filtres et autorisations.
- Nouveaux codes de récupération de8 caractères, anciens codes 32hex conservés. Aucun changement de longueur minimale des mots de passe.
- Nombre de signalements de la journée du récapitulatif, dans l'historique et le popup matinal.
- Préparation automatique quotidienne d'un brouillon privé, avec horaires et compétences ; publication exclusivement manuelle.

## Contrôles locaux

| Vérification | Résultat et portée |
|---|---|
| Compilation TypeScript/Vite | Compilation de production réussie ; avertissement non bloquant de taille de certains bundles. |
| SQL 118a et118b | Exécutés sur PostgreSQL local PGlite, puis réexécutés sans perte des données de test. |
| Compteur du récapitulatif | Plusieurs/zéro signalement, limite de minuit de Paris, journée de23 heures au passage été, comptage du samedi pour le récapitulatif du lundi. Métadonnées ajoutées aux seuls récapitulatifs déjà autorisés par les RPC existantes ; accusé de lecture transmis. |
| Permissions récapitulatif | Refus des profils non autorisés conservé ; aucune fonction publique permettant de compter arbitrairement les signalements. Réponse nulle conservée quand aucun récapitulatif n'est proposé. |
| Plan : compétences et horaires | Postes rares, polyvalence utile, durée travaillée, présence prévue, autonomie, séparation encadrants/techniciens, congés acceptés, absents, sans horaires, comptes inactifs/suspendus, invités/directeurs, ponts bloqués/en panne. |
| Plan : protection | Un seul brouillon par date ; répétition idempotente ; brouillon manuel ou plan affecté conservé ; aucun changement de workshop_days lors de la génération ; absence de recréation après annulation/publication ; import tardif puis nouvel essai ; heures été/hiver. |
| Publication | Moteur de publication existant de la MAJ56 exécuté localement : les jours ne changent qu'après publication par un gestionnaire. Aucun appel de publication dans le générateur. |
| Permissions plan | Fonction automatique et table de suivi inaccessibles aux clients anon/authenticated, y compris admin/modérateur ; statut réservé aux gestionnaires et fermeture de rubrique respectée. Tâche exécutée par le propriétaire SQL/Cron, sans usurpation de session. |
| Programmation118c | Contrat cron.schedule testé avec substitut local : nom stable, un seul programme, intervalle 10 min, premier passage, nettoyage limité aux journaux de ce programme. L'extension pg_cron réelle n'est pas disponible dans PGlite. |
| Edge recovery, code réel exécuté avec SDK/Auth simulés |8 caractères, alphabet32 symboles, aléa cryptographique40 bits, HMAC-SHA256 lié à une clé serveur pour les nouveaux codes, compatibilité SHA256 des anciens.128 générations distinctes. Normalisation majuscules/espaces/tirets, formats invalides rejetés. |
| Sécurité de récupération | Vérification session + mot de passe actuel, liaison du compte, empreinte seule transmise au SQL, code à usage unique. Mauvais ID/code, expiration, suspension/inactivité et compte banni refusés. Limites compte 8/15 min, réseau 40/15 min et globale 200/15 min réexécutées sur SQL 117 inchangé. |
| Erreurs de récupération | Aucun changement Auth sans preuve valide. Refus Auth4xx : restitution du code ; résultat réseau ambigu : code non réactivé. Invalidation du code avant réinitialisation par le responsable conservée et testée. |
| Interface, navigateur | Composants réels avec données/serveur simulés : dossiers sous recherche, bascule personnel/équipe ; champ acceptant8 caractères et indication de compatibilité ; compteur dans récapitulatif et popup ; détails de proposition du plan. Vue mobile 390 px, contrôle ordinateur 1280 px, clair et sombre. Aucun mot de passe réel saisi ou modifié. |
| Non-régression ciblée |180 fichiers fonctionnels existants inchangés ; 7 modifiés dans le périmètre demandé. Horaires hebdomadaires, coupure déjeuner, compétences/affectations, composition du rack, routes de notifications et horloge commune 20 s vérifiés. Préparation/validation/mémoire des photos réexécutées ; circuit workshop-accounts conservé. |
| Livraison | Archive complète de sources, assets, fonctions Edge existantes et uniquement les 3 nouveaux SQL. Sans node_modules, dist, variables d'environnement, pages de test, anciens guides et _redirects. |

## Choix et limites

Un code8 caractères offre moins d'entropie qu'un code32hex : aléa uniforme40 bits,
usage unique, empreinte liée à une clé hors base, limitation des tentatives et
réinitialisation de secours par le responsable sont maintenus. Il reste une
preuve d'accès sensible à conserver séparément du mot de passe. Changer la clé
utilisée pour le HMAC invalide les codes courts correspondants, sans modifier
les mots de passe. Les anciens codes longs restent compatibles.

Le calcul de signalements porte sur les fiches conservées. Une suppression
définitive réduit le nombre d'un ancien récapitulatif ; il ne s'agit pas d'un
journal d'audit immuable.

Le moteur de proposition est déterministe et ne couvre pas toutes les contraintes
d'une optimisation horaire complète. Aucun pont n'est promis couvert pendant
toute son amplitude d'ouverture. Le gestionnaire vérifie et publie. Un brouillon
déjà généré n'est pas écrasé lors d'un import ultérieur.

Pas de test sur la base Supabase réelle, pas d'exécution du véritable pg_cron,
ni de notification sur un téléphone réel. Pas de test de charge/concurrence
multi-connexion : verrouillage, contrôle de version, répétitions et permissions
ont été testés localement. Le schéma local reprend les structures connues des
migrations précédentes ; le guide prévoit la vérification des tâches Cron après
installation.

## Coût et exploitation

Aucune dépendance, API, souscription ou fonction IA ajoutée. Un programme SQL
passe144 fois par jour au maximum ; après traitement il s'arrête immédiatement.
Une proposition et une petite ligne de suivi au maximum par journée concernée.
Les journaux du nouveau Cron sont conservés7 jours, sans toucher aux autres.
Le statut du plan est lu seulement sur la page de préparation, avec l'horloge
existante 20 s. Le comptage des signalements réutilise l'index créé sur created_at.
Ces opérations utilisent les ressources et quotas existants ; leur gratuité
reste liée à la consommation totale du projet et à son offre Supabase/Cloudflare.

## Références utilisées

- Architecture du projet et migrations52c,53,56,58,59,117, fonctions et composants existants.
- Supabase Cron : https://supabase.com/docs/guides/cron/quickstart (nom stable, programmation et historique).
- OWASP récupération de mot de passe : https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html (aléa, usage unique, expiration, limitation des tentatives, réponses génériques).
