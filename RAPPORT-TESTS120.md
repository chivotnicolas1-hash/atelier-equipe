# MAJ120 — rapport des vérifications

Tests locaux du 23 novembre 2026, sur une copie de MAJ119 et des données fictives isolées. Aucun test sur un compte réel, aucune écriture de production ni déploiement.

## Résultats

| Périmètre | Résultat |
| --- | --- |
| Installation npm ci avec le verrou mis à jour | Réussie dans un dossier isolé |
| TypeScript strict de l'application, build Vite 8.3.8 / Node 24 | Réussis |
| TypeScript des trois fonctions Edge, types SDK et déclaration Deno de test | Réussi |
| Origines exactes/multiples, configuration absente ou invalide, prévol, méthode et JSON | Réponses et refus attendus |
| Corps excessif, UTF-8, longueur déclarée et flux interrompu | Limites vérifiées |
| Login et comptes : mot de passe faux, limites, jeton absent, rôle non admin, erreur RPC, session valide | Réussis avec clients Auth simulés |
| Récupération : huit caractères, HMAC, ancien code long, usage unique, compte banni, refus Auth et erreur ambiguë | Réussis avec clients simulés ; mécanismes existants conservés |
| Contrôle d'accès : RPC/réseau/PC en échec, rôle PC refusé et suspension | Contenu masqué ; reprise seulement après nouvelle vérification réussie |
| Proposition automatique : horaires, présence, autonomie, rareté/polyvalence, amplitude, congés, suspension, bureaux/encadrants | Réussis en PostgreSQL local |
| Invités/directeurs, postes en panne/bloqués, unicité des affectations proposées | Exclusions/règles existantes conservées |
| Affectations publiées avant/après génération | Identiques ; aucune publication automatique |
| Ancienne clôture à 01 h 04 puis passage à 05 h | Défaut reproduit avec la définition exacte fournie du moteur déployé |
| Annulation avant 5 h sans brouillon ni affectation | Rien avant 5 h ; génération unique à partir de 5 h ; ancien état archivé |
| Annulation à 5 h exactement ou après | Aucune recréation automatique |
| Annulation à 04 h 59 min 59 s | Relance autorisée ; publication toujours manuelle |
| Publication tracée, y compris plan vide | Protégée contre la reprise automatique |
| Brouillon manuel, plan affecté et suppression sans motif connu | Conservés ; pas de reprise automatique destructive |
| Horaires importés tardivement | Pas de brouillon vide ni perte du marqueur ; génération au passage suivant |
| Heure de Paris été/hiver | Limite de 5 h respectée |
| Échec forcé pendant une relance | Aucun brouillon orphelin ni perte de l'ancien état ; réessai ensuite possible |
| RPC de secours/statut | Admin/modérateur seulement, rubrique fermée respectée, autre date sans génération |
| Composant automatique | Secours unique à l'ouverture du jour, recharge parent après génération, cycle périodique en lecture, réponses tardives ignorées |
| Motifs et historique affichés | Clôture, reprise précoce, heure de Paris et attente des horaires vérifiées |
| Échec moteur après une écriture simulée | Sous-transaction annulée ; seul le code d'erreur est conservé |
| Échec du nettoyage des journaux | N'annule pas le traitement du plan |
| Installation finale livrée, deux exécutions | Trois sauvegardes inchangées, même programme actif, aucune affectation modifiée |
| Installation finale avec prérequis absent en cours de transaction | Échec puis rollback : tables, fonctions, droits et programme antérieurs conservés |
| Requête finale de vérification | Exécutée avec succès, sans génération ; règle/sauvegardes/droits/programme/dernier passage vérifiés |
| Permissions des tables techniques et de l'ancienne fonction renommée | Accès client refusé ; aucune nouvelle permission métier |
| Publication après déplacement dans le brouillon119 | Réussie via les moteurs existants ; permis temporaires nettoyés |
| Transfert119 : panne, compétence, bureau, suspension/congé, version concurrente | Refus attendus ; présence confirmée et horaires conservés |
| Géométrie cumulable et publication manuelle | Règles existantes conservées |
| Chaîne d'identité et quatre politiques d'outillage fournies | Chargées telles quelles localement ; auteur/admin, enfants, invité et compte sans association vérifiés |
| Métadonnée utilisateur admin=true | Ne donne aucun droit administrateur dans la chaîne fournie |
| Deux RPC administrateur : retrait anonyme | Anonyme refusé ; droits connectés/serveur préexistants conservés ; aucun droit nouveau ; autres RPC publiques non ciblées inchangées |
| Plan classique et autres pages | Comparaison des fichiers et tests ciblés ; pas de remplacement du plan ni nouveau conteneur d'objectifs |
| Atelier Live et anciens diagnostics/scripts | Absents de l'archive finale |
| Audit npm du verrou final, développement compris | Zéro vulnérabilité connue signalée à la date du contrôle |

## Méthodes et portée

Les handlers Edge réels sont exécutés sous Node avec Request/Response/WebCrypto ; leurs clients Supabase sont simulés. Les trois blocs de protection autonomes sont comparés à l'identique. Le typage utilise les types du SDK ; ce n'est pas un déploiement Deno réel.

Les composants réels TSX s'exécutent avec un environnement de hooks contrôlé. Les contrôles portent sur les branches d'accès, le cycle de secours/statut et les réponses tardives ; ils ne constituent pas une navigation complète sur téléphone.

Les moteurs et RPC SQL sont exécutés dans PGlite, PostgreSQL local isolé, avec les anciennes fonctions nécessaires et des jeux fictifs. Les définitions reçues de la production sont utilisées pour la reproduction du défaut et la chaîne d'identité/politiques. Les essais de limite horaire utilisent des dates et horloges de test, sans modifier le SQL livré. pg_cron n'étant pas fourni par PGlite, son contrat schedule/alter_job et l'absence de doublon sont vérifiés avec un substitut local. Les journaux réels transmis confirment séparément que le Cron existant s'exécutait.

Pour isoler l'effet des ACL, les deux RPC administrateur sont représentées par des fonctions inoffensives de mêmes signatures. Les contrôles d'identité fournis sont testés séparément ; toutes les opérations catalogue et tous les calculs du bilan mensuel ne sont pas rejoués.

La comparaison avec MAJ119 montre 186 fichiers métier/ressources existants identiques, sept fichiers ciblés modifiés, plus package.json et package-lock.json pour l'outillage. Les scripts SQL de cette livraison remplacent les anciens fichiers d'installation dans l'archive, pas les données en base. Les clés distinctes des composants d'objectifs/statut, issues du correctif antérieur, sont conservées.

## Limites à contrôler après installation autorisée

- Aucun déploiement réel : liste d'origines, en-têtes Cloudflare et exécution de la nouvelle tâche restent à vérifier sur le projet après mise en place.
- Aucun paramètre Auth, session, secret ou MFA réel n'a été modifié ou certifié.
- Aucun mot de passe réel utilisé et aucun appareil physique testé pour cette branche.
- Le plan, ses styles et les autres parcours métier restent conservés ; tous les parcours de l'application n'ont pas été rejoués de bout en bout.
- Les anciens événements sans motif ne permettent pas d'identifier rétrospectivement une publication vide par rapport à une annulation. La nouvelle règle est prudente et ne publie jamais.
- L'audit npm ne couvre ni les imports Deno hébergés, ni toute l'infrastructure, ni les vulnérabilités encore inconnues.
- Le volume global des quotas gratuits n'a pas été mesuré. Aucun nouveau service payant n'est introduit.
