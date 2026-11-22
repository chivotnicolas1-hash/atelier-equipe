# Atelier Fayet 33 — vérifications de la MAJ117

Date : 22 novembre 2026. Base : MAJ116, issue de la MAJ113 après annulation
de Toolbox 114, avec pictogramme voiture 115. La mise en page de l’accueil
116 est conservée. Aucun déploiement sur Supabase, GitHub ou Cloudflare.

## Périmètre

- Pictogrammes décoratifs des cibles, sans changer les calculs, les ventes,
  les contrôles qualité, les délais ni leurs permissions.
- Historique des enlèvements dans une rubrique commune en bas de Déchets,
  par année de Paris et famille ; enlèvements complets et partiels.
- Compatibilité et conservation des photos des signalements.
- Récupération autonome par code personnel, choisie par Nicolas, sans e-mail
  ni SMS ; voie de secours par le responsable conservée.

## Contrôles locaux effectués

| Contrôle | Résultat / portée |
|---|---|
| TypeScript et compilation Vite de production | Réussite. Avertissement préexistant de taille de certains bundles conservé. |
| SQL 117a et 117b | Exécutés sur PostgreSQL local via PGlite, puis réexécutés sans perte de données. |
| Isolation des données de récupération | Un utilisateur ne voit que ses métadonnées, jamais une empreinte ; pas de lecture/écriture directe des tables privées ; fonctions serveur interdites à authenticated et anon. |
| Réinitialisation | Mauvais ID/code, expiré, déjà utilisé, compte inactif ou suspendu : refus. Changement d’ID compatible via le résolveur existant. |
| Concurrence des codes | Contrôle de version à la génération, consommation sous verrou avant appel Auth, seconde utilisation refusée. Une restitution tardive ne remplace pas un nouveau code. |
| Limites de tentatives | Compte : 8 / 15 min ; réseau pseudonymisé : 40 / 15 min ; globale : 200 / 15 min. Compteurs périmés nettoyés lors des appels. Protection de volume du corps HTTP. |
| Fonction Edge de récupération | Code réellement exécuté en test avec SDK/Auth simulés : vérification du jeton et de l’ancien mot de passe, association au bon utilisateur, aléa 128 bits, empreinte SHA-256, aucune clé serveur ni alias en réponse. |
| Erreurs Auth | Refus explicite du nouveau mot de passe : restitution du code. Réponse réseau ambiguë : pas de réactivation automatique. Pas d’écriture Auth pour mauvais code, mauvais utilisateur, compte banni ou limitation. |
| Réinitialisation administrateur | Fonction workshop-accounts réellement exécutée avec SDK simulé : invalidation du code existant avant modification ; erreur SQL ou droits insuffisants : pas d’écriture Auth. |
| Notification de réinitialisation | Destinataire du compte, message idempotent ; utilisation du circuit existant, sans nouveau cron. |
| Historique des déchets | Données complètes/partielles, famille désactivée conservée, demande en attente exclue, quantité décimale, benne à pneus, ancienne quantité absente, filtres année/famille, pagination au-delà de 50 lignes. |
| Permissions Déchets | Anonyme refusé, invité sans historique réel, directeur en lecture ; rubrique fermée respectée. Actions existantes de la demande réutilisées pour administrateur/modérateur. |
| Photos : formats et tailles | Signatures JPEG/PNG/WebP vérifiées, fichier sans type MIME accepté, court WebP lossless reconnu ; fichiers vides/invalides/trop lourds rejetés ; base64 limité à 300 000 caractères. |
| Ressources images | Fermeture du bitmap et libération du canvas ; pas de secours HTML intégral sur une photo dépassant 12,5 millions de pixels. |
| Navigation/synchronisation existantes | Horloge commune 20 s, retour au premier plan, reconnexion et désabonnement ; routes de notifications conservées. |
| Non-régression ciblée | Horaires hebdomadaires/S4J, pauses, critères de compétence/affectation, composition du rack. |
| Comparaison des sources | 171 fichiers src/public/Edge existants identiques ; 11 fichiers fonctionnels modifiés dans le périmètre annoncé. Configuration Edge adaptée séparément. Aucun fichier métier existant supprimé. |
| Dépendances | package.json et package-lock.json identiques à la version 116 ; aucune nouvelle API ni bibliothèque payante. |

## Vérifications dans le navigateur

Effectuées avec les vrais composants React et des données/API locales de
simulation, dans un cadre mobile de 390 px :

- Cibles en clair et sombre : pictogrammes discrets, non cliquables,
  masqués pour les lecteurs d’écran, texte et commandes conservés.
- Page Déchets : historique en bas, ouverture, classement 2026/2025,
  filtre 2025 et détail d’un enlèvement partiel.
- Ajout et enregistrement d’un signalement avec cinq JPEG de 12 Mpx,
  dont un fichier sans type MIME : cinq photos conservées et répertoriées.
- Lot comprenant un faux HEIC invalide en deuxième position : quatre
  images acceptées, erreur explicite sur la deuxième, poursuite du lot.
- Navigateur simulé sans createImageBitmap : cinq photos et leurs cinq
  aperçus préparés grâce au secours borné.
- Erreur réseau simulée au moment d’enregistrer : message d’envoi non
  confirmé et cinq photos toujours présentes dans le formulaire.
- Génération d’un code fictif, confirmation de conservation et ouverture
  du formulaire de récupération ; parcours de nouveau mot de passe simulé
  réussi, sans compte réel modifié.

Les fonctionnalités serveur de récupération ont été testées séparément
avec des appels HTTP et SQL locaux. Le parcours visuel n’envoie jamais de
vrai mot de passe à Supabase.

## Limites à conserver

Le téléphone du collègue et ses fichiers n’ont pas été fournis. Le cas exact
ne peut pas être reproduit ni sa cause certifiée. Les corrections traitent
plusieurs fragilités constatées dans le code et testent des cas concrets.
Un essai sur ce téléphone reste nécessaire ; en cas d’échec, relever le
modèle, le navigateur, le format et le message exact.

Le secours simulé dans Chrome n’équivaut pas à un essai matériel sur Safari,
Android ou un appareil réellement à court de mémoire. HEIC/HEIF ne sont
pas convertis. Les photos restent facultatives, cinq maximum, dix Mo chacune.

La vraie instance Supabase Auth, le déploiement Deno distant, les données de
production et la réception des notifications mobiles n’ont pas été testés.
La validation finale doit être faite sur un compte de test après installation.
Le SQL réutilise les API existantes workshop_login100, actor_before30,
assert_section et message ; il ne suppose pas la structure privée du stockage
des ID de connexion.

## Sécurité et données

Le code personnel est généré avec crypto.getRandomValues, transmis uniquement
à son propriétaire après vérification du mot de passe actuel, et conservé en
mémoire du formulaire jusqu’à fermeture. Une copie texte peut être téléchargée
volontairement par l’utilisateur. La base conserve seulement son empreinte,
son propriétaire, la date de création, l’échéance, la consommation et la version.
L’application n’ajoute pas de journal contenant un code ou un mot de passe.
Les tentatives réseau sont regroupées sous une empreinte salée par une valeur
serveur ; aucune adresse IP brute n’est ajoutée aux tables de cette fonction.
Les limites par compte et globale restent applicables même si un en-tête
réseau n’est pas digne de confiance.

Les mots de passe sont toujours modifiés par Supabase Auth côté serveur.
La fonction publique ne permet pas une réinitialisation avec l’ID seul.
Une récupération implique un accès réseau et un code préparé auparavant.
Sans code valide, le responsable intervient via le circuit existant.

## Impact sur l’infrastructure

Aucun abonnement, prestataire e-mail/SMS, API externe payante ou dépendance IA.
Les calculs de vente et les photos gardent les infrastructures existantes.

- Deux petites tables privées pour les empreintes et les limites de tentatives.
  Une seule ligne de code par compte ; pas de photo dans ces tables.
- Une Edge Function supplémentaire, appelée uniquement à la génération ou à
  l’utilisation d’un code. Pas de nouvelle tâche planifiée.
- Un index sur les dates de ramassage ; aucune copie ni migration massive
  des anciennes demandes. L’historique est calculé sur les données existantes.
- Historique demandé uniquement quand la rubrique est ouverte, puis synchronisé
  avec l’horloge commune ; pages de 50 lignes pour limiter les réponses.
- Pas de requête serveur liée aux pictogrammes : SVG locaux existants.
- La limite de taille actuelle des photos est conservée ; pas d’augmentation
  volontaire du budget de stockage par photo ou du nombre de photos.

Le reliquat réel des quotas Supabase/Cloudflare n’est pas accessible dans ce
travail. Aucun dépassement ne peut donc être garanti ou mesuré ici ; les rares
appels de récupération et l’historique paginé utilisent les quotas du projet
existant, sans nouveau service facturé imposé.

## Références de conception

Documentation consultée le 22 novembre 2026 ; conception adaptée au projet,
sans revendication de certification de sécurité complète.

- Supabase, mise à jour serveur d’un utilisateur :
  https://supabase.com/docs/reference/javascript/auth-admin-updateuserbyid
- Supabase, éditeur et déploiement des fonctions :
  https://supabase.com/docs/guides/functions/quickstart-dashboard
- Supabase, variables d’environnement des fonctions :
  https://supabase.com/docs/guides/functions/secrets
- Supabase, sessions et expiration des JWT :
  https://supabase.com/docs/guides/auth/sessions
- OWASP, récupération de compte, codes hors ligne et limitations :
  https://cheatsheetseries.owasp.org/cheatsheets/Forgot_Password_Cheat_Sheet.html
