# MAJ121 — vérifications et limites

Préparation du 23 novembre 2026 sur la copie de MAJ120. Aucun déploiement ni accès en écriture à la production. Les contrôles utilisent les définitions SQL et métadonnées déjà fournies, des fixtures isolées et le SDK installé dans le projet.

| Contrôle | Résultat |
| --- | --- |
| TypeScript strict et compilation Vite | Réussis |
| Présence : définition SQL fournie, collaborateur avec horaires sans poste | Confirmé ; la règle existante fonctionne et n'est pas réécrite |
| Deux clics sur la confirmation | Premier horodatage conservé |
| ID d'un autre collaborateur fourni à l'action | Seule la fiche de l'identité serveur est confirmée |
| Sans horaires, absent ou planning seulement futur | Aucune confirmation du jour créée |
| Administrateur hors créneau | Non confirmé ; règle horaire existante conservée |
| Compteur et liste | Même sélection ; horaires valides, actifs, sans doublon ; administrateurs/modérateurs inclus ; invités/directeurs exclus |
| Handler WorkOrder réel extrait du TSX | Recontrôle serveur malgré un affichage déjà confirmé, anti-double-clic, ouverture après succès, fenêtre fermée en cas d'échec, autre date non confirmée, popup bloquée gérée |
| Synchronisation | Même cycle commun de 20 secondes ; retour de cache de navigation ajouté sans second minuteur |
| Ancienne correction déchets | Défaut reproduit : les champs de validation étaient effacés |
| Nouvelle correction : quantité par déchet, ajout de type, notes | Réussis ; création/validation/collecte et auteurs conservés |
| Relance enregistrée | Horodatage propre ajouté ; dates et quantités de la demande conservées |
| Délai de ramassage | Même échéance en jours ouvrés avant/après correction et relance |
| Demande déjà collectée | Corrigée sans réouverture ni changement de date de collecte |
| Demande non validée | Reste non validée |
| Litres avec décimale et bacs entiers | Validations existantes conservées |
| Mauvaise version, quantité invalide ou autre prestataire | Refus attendus |
| Administrateur/modérateur | Correction autorisée |
| Collaborateur après validation, invité/directeur/anonyme | Correction centrale refusée ; aucun accès direct aux données/sauvegarde |
| Rubrique déchets fermée | Refus conservé dans la fonction de correction |
| Installation SQL, deux exécutions | Une sauvegarde immuable ; aucune demande réécrite |
| Vérification SQL finale | Exécutée localement sans écriture métier |
| AES-GCM | Chiffrement/déchiffrement avec le vrai Web Crypto de Node ; clé 256 bits non exportable |
| Ancienne session locale | Migrée puis retirée de son ancienne clé en clair |
| Nouvelle instance du stockage | Session déchiffrée avec la clé conservée |
| IV et séparation des contextes | IV aléatoire ; déplacement d'un contenu vers une autre clé rejeté par authentification |
| Altération du chiffré | Détectée, session écartée, ancienne copie en clair non réactivée |
| Deux instances créant la clé | Même clé sélectionnée atomiquement ; sessions cohérentes |
| Écriture, rotation et effacement | Ordre conservé ; session supprimée non restaurée |
| Stockage indisponible | Repli mémoire signalé ; pas de nouveau stockage persistant en clair ; marqueur empêchant le retour d'une ancienne session |
| SDK Supabase réel | setSession, getSession, nouvelle instance, refreshSession et signOut local réussis avec le nouvel adaptateur |
| SDK en mode PC | Session en mémoire, aucune écriture de l'adaptateur, nouvelle instance non connectée |
| Dépendances | package.json et verrou inchangés ; aucune nouvelle dépendance de production |
| Comparaison avec MAJ120 | 187 fichiers existants identiques, 6 fichiers ciblés modifiés, 2 modules ajoutés, aucun fichier métier supprimé |
| Plan classique, glisser-déposer et serveur automatique120 | Sources inchangées |
| Fonctions Edge120, récupération et secrets | Inchangés ; aucun nouveau déploiement Edge nécessaire |

## Méthodes

Les tests SQL s'exécutent dans PGlite, PostgreSQL isolé. Les fonctions de déchets et la chaîne de confirmation fournies sont chargées depuis les métadonnées antérieures ; les rôles/identités sont représentés par des fixtures. Les contrôles ciblent les chemins touchés, et ne remplacent pas un audit des paramètres et permissions réels du projet.

Les tests du stockage utilisent `fake-indexeddb` uniquement dans le dossier de test, avec le vrai moteur Web Crypto de Node. Les tests SDK utilisent le vrai paquet Supabase du projet et des réponses Auth synthétiques ; aucun mot de passe ou compte réel n'est utilisé. Le handler WorkOrder est extrait du code réel et exécuté avec des événements/fenêtres simulés. Les tests de compteur exécutent les fonctions TypeScript réelles.

## Limites

Un essai avec Chromium installé a été tenté, mais son démarrage est bloqué par les permissions de l'environnement. Ce test navigateur n'est donc **pas validé**. Aucun essai sur un téléphone physique ni navigation complète de la nouvelle application n'est revendiqué. La persistance des CryptoKey dans les navigateurs utilisés et la migration d'une session réelle sont à vérifier lors de la mise en place ; le repli mémoire est prévu si le stockage est indisponible.

Les compteurs réels de l'équipe ne sont pas consultables ici. Le SQL de vérification fourni permet de comparer l'agrégat serveur au compteur affiché après installation. Les dates effacées avant cette correction ne sont pas reconstituées automatiquement.

Le chiffrement local ne protège pas contre un appareil compromis ni contre l'utilisation des clés par un script malveillant exécuté dans l'application. Il ne remplace pas les politiques RLS, les contrôles des fonctions, les mots de passe, HTTPS ou les mesures contre les XSS. Ce n'est pas une migration générale de tous les champs Supabase vers un chiffrement applicatif.

## Coût et quotas

Aucun service payant, API externe ou dépendance d'exécution ajoutée. Le chiffrement utilise l'appareil, sans requête Supabase supplémentaire. Un clic WorkOrder déjà confirmé effectue désormais le même contrôle idempotent qu'un premier clic, afin de ne pas se fier seulement à l'affichage. La synchronisation reste à 20 secondes. La seule nouvelle table serveur contient une définition de fonction de sauvegarde ; aucune nouvelle photo ou fichier métier n'est ajouté. Les quotas globaux du projet ne sont pas mesurés ici.

## Sources techniques

- [Supabase — stockage des mots de passe, bcrypt et sel](https://supabase.com/docs/guides/auth/password-security).
- [Supabase — sessions et stockage](https://supabase.com/docs/guides/auth/sessions).
- [OWASP — limites des stockages du navigateur et des clés non exportables](https://cheatsheetseries.owasp.org/cheatsheets/HTML5_Security_Cheat_Sheet.html).

Le conseil OWASP de limiter l'exposition des jetons à JavaScript reste pertinent : une architecture de cookies HttpOnly demanderait une couche serveur et une revue plus large des appels. Le chiffrement local livré n'est pas présenté comme une protection équivalente ni comme un accès « inviolable ».
