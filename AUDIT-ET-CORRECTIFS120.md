# MAJ120 — plan automatique et sécurité

État préparé le 23 novembre 2026 sur la version stable MAJ119. Atelier Live est écarté. Aucun déploiement Cloudflare, appel de modification Supabase ou test sur un compte réel n'a été effectué. Les diagnostics transmis par le propriétaire ont été lus ; l'accès direct à la base et aux réglages du Dashboard n'est pas disponible.

## Cause du défaut de préparation

Le programme `atelier-plan-brouillon-118` est actif toutes les dix minutes. Les 24 passages fournis de 05 h à 08 h 50 sont réussis. La définition déployée du moteur retourne pourtant `already_processed` dès qu'une ligne existe pour le jour dans `plan_runs118`.

Pour le 23 novembre, cette ligne a été créée à 01 h 04, puis clôturée pour la dernière fois à 08 h 47, heure de Paris. Dix affectations existent déjà. Le test annulé évoqué par le propriétaire est compatible avec ce constat ; l'ancien journal ne conserve pas le motif de chaque suppression. Le succès Cron prouvait l'exécution, pas la création d'un brouillon.

## Correction préparée

Une annulation avant 5 h ne bloque plus le réveil du matin s'il n'existe aucun brouillon ni aucune affectation pour la date concernée. À 5 h exactement ou après, l'annulation reste respectée. Une publication enregistrée après installation est protégée, y compris un plan volontairement vide. Les anciennes clôtures sans motif ne sont reprises qu'avec la condition restrictive « clôture précoce, sans affectation ni brouillon » ; elles ne peuvent jamais publier automatiquement.

Le moteur existant conserve son calcul : présence et horaires, autonomie, rareté des compétences, amplitude, encadrants et bureaux, congés, suspension, exclusion des invités/directeurs et équipements indisponibles. La génération ne modifie pas le plan publié. Les verrous existants sont conservés ; une relance conserve l'ancien état dans un événement privé et utilise une mise à jour conditionnelle pour éviter d'écraser une décision concurrente.

Les actions manuelles délèguent au moteur déjà présent, y compris les gardes de glisser-déposer119. Le motif de clôture est transmis dans un contexte transactionnel restauré même en cas d'erreur. Les suppressions hors parcours applicatif sont classées « inconnues », sans reprise automatique.

Le contrôle serveur s'exécute dans une sous-transaction : un échec annule les écritures partielles puis enregistre seulement le code d'erreur. Un problème de nettoyage des journaux ne peut pas annuler la préparation. Le dernier contrôle du jour est conservé 90 jours. Le programme existant est réactivé, sans deuxième tâche.

Deux RPC de suivi/secours sont réservées aux administrateurs et modérateurs, avec contrôle de rubrique. Le secours ne travaille que sur le jour calculé côté serveur et ne s'exécute qu'une fois à l'ouverture du plan du jour. Les contrôles périodiques restent en lecture, selon le cycle commun de 20 secondes. Le composant recharge les données après génération et ignore les réponses tardives après fermeture/changement de date. Ses explications distinguent l'attente, la clôture, la relance et l'échec.

## Revue de sécurité fondée sur les éléments fournis

| Élément | Constat et traitement |
| --- | --- |
| Tables et accès directs | Le diagnostic fourni recense 87 tables, sans lecture anonyme ni écriture directe des rôles clients. Quatre tables d'outillage ont une lecture connectée sous RLS. Pas de révocation globale improvisée. |
| Identité | La chaîne fournie exige une identité Auth confirmée, une connexion par mot de passe et une fiche active associée via la table privée. Le droit administrateur vient de `accounts100.is_admin`, pas d'une métadonnée utilisateur libre. |
| Outillage113 | Les quatre politiques fournies filtrent la lecture sur l'auteur ou l'admin ; photos et événements héritent de la demande parente. Tests locaux sur les définitions reçues. |
| Anciennes fonctions privilégiées | Aucun wrapper public `_before…` exécutable par authenticated ni fonction privilégiée sans search_path fixe n'a été relevé dans le diagnostic fourni. Cette observation ne couvre pas tous les chemins de l'application. |
| Deux RPC administrateur anonymes | Retrait de PUBLIC/anon sur `workshop_catalog_code88(text,uuid,text,text,text)` et `workshop_monthly82(date)` seulement. Leurs contrôles internes exigent déjà l'admin. Les droits connectés/serveur préexistants sont conservés sans en ajouter. |
| Deux tables privées sans RLS | `catalog_seed107` et `waste_types112` n'accordent aucun accès direct client dans le diagnostic. Pas d'activation de RLS à l'aveugle : examiner propriétaire et usages internes d'abord. |
| Fonctions publiques légitimes | Connexion, demande de mot de passe, maintenance, thème et écran autorisé restent accessibles selon leurs mécanismes existants. |
| Contrôle d'accès de l'interface | Un échec RPC/réseau/contrôle PC masque le contenu protégé jusqu'à vérification réussie. Ce garde d'interface ne remplace pas les contrôles serveur. |

### Fonctions Edge

Les fichiers autonomes `workshop-login`, `workshop-recovery` et `workshop-accounts` utilisent une liste d'origines HTTPS exacte, fermée si absente/invalide. L'origine retenue est `https://atelier-equipe.chivotnicolas1.workers.dev` dans `WORKSHOP_ALLOWED_ORIGINS`, à renseigner avant déploiement. Les requêtes sont limitées à POST/OPTIONS et JSON. La lecture du corps est bornée avant accumulation : 2 ko pour login, 4 ko pour comptes et récupération. Les réponses sensibles sont sans cache.

CORS n'est pas une authentification : un client hors navigateur peut omettre ou imiter Origin. Les contrôles existants de mot de passe, jeton, rôle et limitations de tentatives restent indispensables et sont conservés. Les endpoints publics et validations manuelles justifient de conserver `verify_jwt=false` tel que configuré. La fonction push n'est pas modifiée. Le code de récupération de huit caractères, HMAC, consommation unique et secrets existants restent conservés.

### En-têtes et dépendances

Les en-têtes Cloudflare ajoutent nosniff, absence de référent, protection de l'application contre son intégration dans un site tiers, interdiction des objets embarqués et restrictions de base/formulaire. La caméra de même origine est conservée, ainsi que les pages intégrées à l'intérieur de l'application. Le cache spécifique du service worker et de l'index reste inchangé.

La CSP reste partielle : les sources de scripts et de connexions ne sont pas toutes restreintes. Une politique plus stricte requiert l'inventaire des ressources OCR, PDF, caméra et intégrations réelles. Aucun contrôle DDoS global ni audit complet de l'infrastructure n'est prétendu.

Vite passe de 8.0.13 à 8.3.8 avec son verrou. L'audit npm du verrou obtenu ne signale plus de vulnérabilité connue, développement compris. Les dépendances applicatives directes ne sont pas modifiées. Une alerte sur un outil de compilation ne démontre pas une intrusion du site déployé.

## Installation et retour

`supabase/120-installation.sql` regroupe tous les changements dans une transaction unique. Les prérequis sont vérifiés ; les trois anciennes définitions sont sauvegardées une seule fois en privé. Le script ajoute le suivi/traçage, adapte les fonctions du plan, réduit les deux permissions anonymes, puis met à jour la même tâche Cron et effectue un contrôle initial pouvant créer un brouillon réel. Aucune publication ni réinitialisation métier.

`supabase/120f-verification-lecture-seule.sql` contrôle la règle, les sauvegardes, permissions, programme et dernier passage sans déclencher de génération. Les diagnostics historiques et anciens scripts inutiles ne sont pas livrés.

Le guide décrit l'ordre : validation du SQL, installation/vérification, secret d'origine, trois fonctions Edge, puis sources GitHub/Cloudflare. Rien n'a été appliqué. Une restauration de l'interface ne désactive pas les traitements serveur : Cron et secours doivent être arrêtés ensemble si nécessaire. Les définitions sauvegardées permettent de préparer un retour ciblé ; aucun script destructeur de retrait automatique n'est fourni.

## Coût, quotas et suites possibles

Aucun nouveau service, API payante, abonnement ou dépendance d'exécution. Le programme existant reste toutes les dix minutes. Les nouvelles données sont du texte/JSON de suivi ; pas de nouvelle image. La croissance des événements dépend du nombre d'actions sur les plans. Le volume global de la base et les quotas réels du projet n'ont pas été mesurés : aucun respect global des quotas gratuits n'est garanti.

Les réglages Auth réels, sessions, inscriptions, durée des jetons, limitations et secrets restent à examiner séparément. La MFA avec contrôle serveur et secours pour les comptes de gestion serait une étape suivante ; elle n'est pas implémentée ici. Cette livraison est un renforcement ciblé, pas une certification générale de sécurité.

## Références consultées pour la préparation

- [Supabase Cron](https://supabase.com/docs/guides/cron) et [gestion des tâches](https://supabase.com/docs/guides/cron/quickstart).
- [Fonctions et permissions Supabase](https://supabase.com/docs/guides/database/functions).
- [Limitations Auth](https://supabase.com/docs/guides/auth/rate-limits) et [sécurité des mots de passe](https://supabase.com/docs/guides/auth/password-security).
- [En-têtes des assets Cloudflare Workers](https://developers.cloudflare.com/workers/static-assets/headers/).
- [Avis Vite/launch-editor GHSA-587h-7wmj-h5pm](https://github.com/advisories/GHSA-587h-7wmj-h5pm) et [version Vite 8.3.8](https://github.com/vitejs/vite/releases/tag/v8.3.8).
