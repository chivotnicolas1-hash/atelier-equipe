# MAJ128 — vérifications

Préparée le 28 novembre 2026 sur MAJ127. Aucun accès réel, déploiement, fausse donnée ou notification vers un utilisateur de production.

| Contrôle | Résultat local |
| --- | --- |
| Gabarit caméra | Correspondance du cadre CSS vers les pixels du capteur, mode cover et bornes testés |
| Photo importée | Correspondance contain testée ; décodage borné existant réutilisé |
| Capture | Seul le cadre est capturé ; largeur bornée ; pas de demande de microphone |
| Arrêt caméra | Pistes arrêtées à la capture, fermeture et blocage de l'application |
| OCR réel | Quatre plaques synthétiques correctement reconnues avec Tesseract6 installé, contraste réduit et inclinaisons ±2° |
| Préparation OCR | Contraste, seuillage et petites rotations exécutés avec le code réel et un canvas natif de test ; transformée réinitialisée avant traitement des pixels |
| Propositions | Doublons regroupés ; substitution incertaine de chiffres signalée ; aucun caractère manquant inventé ; vérification avant remplissage |
| Obligatoire par appareil | default/denied, absence d'abonnement, abonnement d'un autre appareil/compte refusés |
| Activation/révocation | Ouverture après validation, rebloquage après révocation ; espace masqué/inert et fenêtre non fermable |
| Réseau ou réponse invalide | Aucune ouverture à défaut de vérification ; erreur explicite |
| Continuité de saisie | Contenu déjà monté conservé caché pendant le blocage ; autres dialogues masqués |
| Exceptions | Invité de démonstration exempt ; écran atelier autorisé sans session inchangé |
| Endpoint SQL | Comptes réels requis ; seuls les endpoints de auth.uid retournés ; anonyme/suspension refusés |
| Destinataires signalements | Équipe Encadrants avec présence et horaires du jour de Paris ; y compris rôle Collaborateur |
| Destinataires exclus | Sans créneaux, formation, congé accepté, invité/directeur, suspension et bannissement |
| Nouvelle fiche | Un message par personne ; tous ses appareils sont mis en file |
| Idempotence et modifications | Reprise du même identifiant ou correction sans doublon |
| Annulation | Transaction annulée sans message ou élément de file résiduel |
| Réinstallation | Sans envoi historique |
| Notification et accès | Route locale reports autorisée par le service worker ; URL externe refusée ; boîte de notifications marque lu et ouvre Signalements |
| Mon poste | Fond masqué aux technologies d'assistance, non interactif, vrai type/bureau et double affectation pris en charge |
| Régression127 | Tests du plan2.0, non-affectés, déplacements, symbole interdit, éditeur, focus et lecteurs écran rejoués |
| SQL antérieurs | Tests isolés123 à127 rejoués avant les nouveaux tests |
| Compilation | TypeScript et Vite réussis |

## Méthodes et limites

SQL exécuté dans PGlite, PostgreSQL isolé, avec la chaîne d'identité et les fonctions antérieures déjà fournies. Les comptes, jours, abonnements et signalements sont fictifs et isolés. La création de signalement et la fonction de mise en message sont reprises des définitions/scripts existants. Aucun envoi web-push externe n'est effectué ; les messages et éléments de file sont contrôlés en base. Le calcul de performances ancien des tests de snapshot reste représenté par un substitut.

L'OCR utilise réellement Tesseract.js6 et ses données anglaises locales existantes. Des images de test sont générées, cadrées puis préparées par les nouvelles fonctions réelles au moyen d'un canvas natif réservé aux tests. Les quatre cas attendus sont AA-123-BB, DQ-610-RK, FH-258-ZX et BC-789-DE. Ce résultat ne représente pas une mesure d'amélioration sur des photos réelles et ne garantit pas la reconnaissance d'une plaque floue, réfléchissante ou inclinée fortement.

Les composants TSX et événements sont testés dans un environnement de hooks contrôlé avec médias, service worker et Supabase simulés. La géométrie et le traitement des pixels sont exercés séparément ; l'accès physique à la caméra et la livraison des notifications sur un téléphone ne sont pas vérifiés ici. Le service worker réel est exécuté dans un contexte isolé pour contrôler la route autorisée. Les dépendances de test ne sont pas ajoutées à l'application livrée.

Chromium n'étant pas disponible dans l'environnement, aucun test visuel complet en navigateur ou téléphone physique n'est revendiqué. Une vérification sur appareils réels, après installation autorisée, reste nécessaire.

## Permissions et architecture

Le déclencheur AFTER INSERT n'envoie rien directement sur le réseau : il réutilise workshop_private.message dans la transaction du signalement. Une annulation supprime donc aussi les notifications en attente. Le programme et la fonction Edge existants prennent ensuite la file en charge. Aucun droit de consultation des signalements n'est donné aux simples membres Encadrants ; seuls leurs droits actuels s'appliquent.

Le contrôle de notifications vérifie la permission web et la correspondance entre abonnement local et compte courant. Il ne prouve pas la livraison effective et n'a pas accès à tous les réglages système. Le blocage d'interface ne remplace pas RLS/les contrôles d'autorisation SQL et ne prétend pas empêcher un client modifié. Les comptes de démonstration et le lecteur PC sans session sont exemptés ; les écrans de maintenance existants restent prioritaires.

Les images du scanner restent locales, ne sont pas jointes automatiquement au signalement et n'utilisent pas d'API externe. Le cadre est prélevé avant l'OCR. Les bitmaps, canvas de travail, pistes caméra et workers sont libérés après utilisation ou annulation. La saisie manuelle reste disponible.

## Ressources et sources

Aucune API payante, dépendance de production, abonnement, nouvelle clé ou fonction Edge. Un RPC léger vérifie le compte/appareil au cycle existant ; chaque nouveau signalement crée un message par encadrant éligible et une entrée de file par abonnement. La consommation globale des quotas Supabase/Cloudflare n'est pas mesurée ici.

Documentation primaire consultée pour les API utilisées :

- MDN, MediaDevices.getUserMedia : https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia
- Tesseract.js, API worker/recognize/setParameters : https://github.com/naptha/tesseract.js/blob/master/docs/api.md
- MDN, Notifications et permission : https://developer.mozilla.org/en-US/docs/Web/API/Notifications_API/Using_the_Notifications_API

Les types de la dépendance Tesseract6 effectivement installée ont également été vérifiés ; aucune mise à niveau de dépendance n'est introduite.

Comparaison des sources, ressources publiques et fonctions Edge avec MAJ127 : 197 fichiers identiques, sept modifiés, six ajoutés et l'ancien lecteur devenu inutilisé supprimé. package.json et son verrou sont identiques. Les fonctions Edge et les ressources OCR restent inchangées.
