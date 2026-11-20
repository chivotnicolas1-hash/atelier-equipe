# Atelier Toolbox 33 — Livraison 114

Cette livraison ajoute un module séparé à la version 113. Aucun déploiement de production n’a été réalisé. Le guide d’installation est `MISE-A-JOUR-114.txt` et le script unique est `supabase/114-atelier-toolbox.sql`.

## Modifications

| Fonction | Livraison |
| --- | --- |
| Accueil | 11 tuiles, icônes, recherche, favoris et six outils récents par appareil |
| Pneumatiques | Flancs, diamètres, circonférences, écarts, garde au sol et vitesse théorique ; dessin à échelle commune |
| Électricité | Six couples de grandeurs U/I/R/P, série/parallèle, chute de tension, consommation et autonomie |
| Unités | Huit familles, gallons US/impérial distincts, ch/hp distincts, formules et unités visibles |
| OBD | 16,108 définitions locales P/B/C/U ; recherche par code, mots-clés, famille et constructeur |
| Bibliothèques | 80 fiches initiales : huiles, ampoules, fusibles, visserie, batteries et climatisation |
| Illustrations | Dessins SVG originaux, schématiques et non à l’échelle ; aucune photo de fabricant copiée |
| Climatisation | 23 températures, de −30 à 80 °C, bar absolus ou relatifs à 1,01325 bar ; corrections administratives possibles |
| Collaboration | Propositions privées jusqu’à décision administrateur, refus motivé, photo facultative, recherche catégorie/mot-clé |
| Administration | Ajout, correction et suppression des fiches ; sources, droits, dates ; catégories ; activation des outils |
| Hors connexion | Page locale `toolbox.html`, préparation explicite, cache de fichiers statiques et des corrections techniques publiques déjà synchronisées |

Les favoris et les récents sont locaux ; ils ne se synchronisent pas entre appareils. Les bibliothèques et réglages administratifs se synchronisent lorsque la page connectée est ouverte. Les contributions privées ou partagées de l’équipe et leurs photos ne sont pas conservées dans le cache hors connexion.

## Architecture et droits

Le module se trouve dans `src/toolbox/`. Les calculs purs sont séparés de l’interface et du client Supabase. Les fichiers statiques se trouvent dans `public/toolbox/`. Les données OBD et P/T sont chargées à l’ouverture de l’outil concerné. Les résultats sont affichés par groupes de 40 fiches pour éviter des milliers d’éléments à l’écran.

Trois tables nouvelles : configuration, fiches administrées/contributions et photos. Elles sont protégées par RLS ; les écritures directes sont interdites aux utilisateurs. Les fonctions contrôlent l’identité, le rôle, le propriétaire, la validation et la version. Aucun ancien SQL métier n’est remplacé.

- Collaborateur/modérateur : lire les publications, voir et corriger ses propositions en attente ou refusées ; aucune auto-publication.
- Administrateur : gérer les fiches, les sources, les photos, les catégories et les outils ; valider/refuser.
- Directeur : consultation des données autorisées, sans écriture.
- Invité : références locales seulement ; pas d’accès aux vraies contributions.
- Anonyme : aucune lecture Supabase ; seules les références locales non personnelles sont dans la page autonome.

Une photo est compressée avant envoi. Elle est chargée uniquement au besoin et supprimée avec la fiche, ou remplacée lors d’un changement. Limite globale photos : 20 Mio de texte encodé. Pour les fiches initiales retirées, un repère de masquage est conservé afin qu’elles ne réapparaissent pas au prochain chargement.

## Vérifications réalisées

### Mathématiques et données

Les tests ont vérifié les formules et plusieurs valeurs de référence indépendantes : diamètre 631,9 mm pour 205/55 R16 ; différence 2,4 mm avec 225/45 R17 ; loi d’Ohm 12 V / 2 A = 6 Ω et 24 W ; séries/parallèles ; chute 0,42 V sur l’exemple cuivre ; consommation 120 Wh / 10 Ah ; autonomie théorique 5,1 h sur l’exemple explicitement paramétré.

Toutes les unités de chaque famille ont subi des conversions aller-retour. Contrôles de 25,4 mm/pouce, 9,80665 N·m/kgf·m, gallons US/impérial, ch/hp, 32 °F = 0 °C, zéro absolu et valeurs invalides. Le modèle de serrage est contrôlé par sa formule, sans l’assimiler à un couple automobile prescrit.

Les identifiants OBD sont uniques et au bon format. Les quatre familles sont présentes ; les entrées explicitement réservées ou non attribuées du jeu importé sont exclues. Les codes inconnus ne sont pas complétés. Les plages génériques et constructeur ont été testées, y compris la frontière P3399/P3400. Une nouvelle fiche dans une plage constructeur exige une marque.

Chaque fiche initiale possède une source et une date. La table de saturation est croissante. À 25 °C : R134a = 6,65381 bar absolus ; R1234yf = 6,82697 bar absolus, cohérent avec les 683 kPa arrondis publiés par Chemours pour YF. Le modèle utilisé est CoolProp 8.0.0 / HEOS, Q=0. La validation des corrections de la table est également contrôlée.

### SQL, RLS et synchronisation

Les nouvelles fonctions et politiques RLS ont été exécutées sur une base PostgreSQL locale PGlite. L’authentification et les anciennes fonctions d’accès ont été simulées ; ce n’est pas un essai sur ta base réelle.

Tests réussis : proposition et photo privées ; auteur enregistré par le serveur ; accès croisés refusés ; table et photo protégées par RLS ; modification directe interdite ; collaborateur et modérateur sans droit de publication ; validation administrateur avec source/date/droits ; visibilité de la publication pour un autre compte ; refus motivé et renvoi ; version périmée rejetée ; correction d’une référence initiale ; activation des outils et catégories synchronisées ; suppression et purge photo ; réexécution du script sans perte des réglages ; anonyme/invité/suspendu bloqués sur les données atelier et directeur sans écriture.

La synchronisation renvoie seulement la révision si rien n’a changé. Elle utilise l’horloge commune de 20 secondes. Les tests de l’horloge couvrent le focus, la reconnexion et le désabonnement des vues.

### Hors connexion et navigateur

Tests automatisés du service worker : fichiers HTML/JS/JSON disponibles réseau coupé ; aucune réponse Auth/Supabase interceptée ; une seule prise en charge par requête ; cache précédent conservé après interruption ; remplacement seulement après préparation complète ; anciens fichiers hashés encore lisibles après mise à jour du service worker.

Essai réel dans le navigateur local : préparation des 23 fichiers, confirmation, arrêt du serveur de prévisualisation, rechargement de `toolbox.html`, recherche d’outil et calcul électrique toujours disponibles. Cela simule l’indisponibilité du serveur, sans prétendre couvrir tous les comportements d’un téléphone en mode avion.

Vérification à l’écran du comparateur, recherche et détail P0141 avec source, convertisseur en vue de 390 px et mode sombre. Le parcours de contribution a été essayé avec le composant réel et un serveur simulé : création privée, liste de validation, ajout de source/droits, publication puis présence dans la bibliothèque partagée.

### Non-régression et dépendances

177 fichiers source/actifs/fonctions existants sont identiques. Intégrations limitées à la navigation, l’icône, la disponibilité de rubrique, le point d’entrée métier et le service worker. `vite.config.ts` ajoute la compilation de la page locale et le manifeste. `package.json` et `package-lock.json` sont inchangés.

Tests ciblés réussis des heures hebdomadaires/S4J, pauses déjeuner, règles de compétences/affectations, composition du rack, horloge commune et anciennes routes de notifications. Les modules Consommables, Déchets, Congés, Signalements et Outillage 113 ne sont pas réécrits. La compilation TypeScript/Vite est réussie.

Il ne s’agit pas d’un test exhaustif sur tous les modèles de téléphone, tous les navigateurs ni toutes les anciennes opérations de production. Un essai réel collaborateur/administrateur après installation reste nécessaire.

## Fiabilité, portée et licences

Le référentiel OBD provient de **Wal33D/dtc-database**, révision `04c43d72e7db7197658b6f72fe582c5076d9eee8`, sous licence MIT déclarée par le projet. Les descriptions anglaises sont conservées ; 44 libellés courants ont une traduction française. Le fichier contient 10,139 codes distincts et plusieurs définitions selon la marque. Il ne contient pas de procédures OEM exhaustives ni de données par VIN. La récupération, le format et les doublons ont été contrôlés ; les 16 108 affectations n’ont pas chacune été recertifiées auprès de leur constructeur.

Les causes, symptômes ou descriptions détaillées absents ne sont pas inventés. Les conseils présentés comme méthode générale ne remplacent pas une procédure propre au code et au calculateur. Des marques ou variantes peuvent manquer. Ne pas attribuer à une Peugeot une définition issue d’un autre constructeur simplement parce que le numéro est identique.

Les autres fiches emploient des faits techniques et des reformulations originales, avec un lien vers la référence. Les documents, tableaux graphiques et photos propriétaires d’origine ne sont pas redistribués. Les notices MIT de DTC Database et CoolProp sont fournies. Les illustrations SVG ont été créées pour ce projet. Aucune certification automobile ni homologation n’est délivrée.

## Sources consultées et liens de vérification

Date de préparation : 20 novembre 2026. Les sources sont également affichées dans les fiches. Une date de préparation ne garantit pas qu’un constructeur n’a rien changé depuis.

- [CoolProp R1234yf — modèle d’état](https://coolprop.org/fluid_properties/fluids/R1234yf.html)
- [CoolProp R134a — modèle d’état](https://coolprop.org/fluid_properties/fluids/R134a.html)
- [Cloudflare — limites Workers](https://developers.cloudflare.com/workers/platform/limits/)
- [Cloudflare — facturation des actifs statiques](https://developers.cloudflare.com/workers/static-assets/billing-and-limitations/)
- [DTC Database — MIT](https://github.com/Wal33D/dtc-database)
- [OSRAM — catalogue de formes et culots](https://look.ams-osram.com/m/67da8d745f53dcb9/original/OSRAM-Light-Range-Update-2022-EN.pdf)
- [Mastercool — coupleurs R1234yf](https://mastercool.com/product/r1234yf-conversion-couplers/)
- [Bossard — éléments de fixation](https://media.bossard.com/ch-en/-/media/bossard-group/website/documents/brochures/brochures-products-english/festening-elements-en.pdf)
- [Renault Group — RN17](https://media.renaultgroup.com/renault-group-the-first-automotive-manufacturer-to-introduce-and-exclusively-offer-a-complete-range-of-premium-engine-oils-with-lower-carbon-footprints/?lang=fra)
- [NASA — Fastener Design Manual RP-1228](https://ntrs.nasa.gov/api/citations/19900009424/downloads/19900009424.pdf)
- [Mercedes-Benz — fluides approuvés](https://operatingfluids.mercedes-benz.com/sheet/229.51/en)
- [Mercedes-Benz — fluides approuvés](https://operatingfluids.mercedes-benz.com/sheet/229.52/en)
- [Supabase — trafic sortant](https://supabase.com/docs/guides/platform/manage-your-usage/egress)
- [Supabase — quotas Free](https://supabase.com/pricing)
- [ACEA — séquences 2023](https://www.acea.auto/files/2023_ACEA_oil_sequences_light-duty_engines.pdf)
- [API — Motor Oil Guide](https://www.api.org/-/media/files/certification/engine-oil-diesel/%20publications/motor%20oil%20guide%201020.pdf)
- [Chemours — Opteon YF](https://www.chemours.com/en/-/media/files/opteon/opteon-yf-push-bulletin.pdf)
- [FUCHS — spécifications et homologations](https://www.fuchs.com/gb-en/automotive-lubricants/specifications-approvals/)
- [HELLA — fonctionnement de la climatisation](https://www.hella.com/techworld/en/technical/car-air-conditioning/car-air-conditioning/)
- [HELLA — climatisation automobile](https://www.hella.com/techworld/en/technical/car-air-conditioning/car-refrigerant-oil-filling-quantities/)
- [Littelfuse — catalogue véhicules](https://www.littelfuse.com/assetdocs/littelfuse-commercial-vehicle-catalog?assetguid=aa0a9b38-0b25-4635-996a-b9a784765b60)
- [MAHLE — huiles et fluides de climatisation](https://www.mahle-aftermarket.com/eu/fr/services/filling-quantities/)
- [NIST SP 811 — facteurs de conversion](https://www.nist.gov/pml/special-publication-811/nist-guide-si-appendix-b-conversion-factors/nist-guide-si-appendix-b8)
- [OSRAM — XENARC ORIGINAL](https://www.osram.com/appsj/pdc/pdf.do?cid=GPS01_1056953&lid=EN&vid=PP_EUROPE_Europe_eCat)
- [OSRAM — ORIGINAL LINE](https://www.osram.com/appsj/pdc/pdf.do?cid=GPS01_1057023&lid=EN&vid=MP_EUROPE_EAST_eCat)
- [VARTA — interprétation des tests](https://www.varta-automotive.com/fr-fr/knowledge/articles/article-details/Interpretation-des-tests-de-batteries)
- [Yuasa — contrôle d’une batterie plomb](https://www.yuasabatteries.co.nz/resources/expert-advice/how-to-test-a-lead-acid-battery)

## Impact sur les quotas et les coûts

Aucune API payante, IA externe, abonnement ou dépendance de production supplémentaire. CoolProp a été utilisé uniquement pour calculer les données de cette édition ; il n’est pas installé chez l’utilisateur et n’est pas appelé au fonctionnement. Les liens de source ne sont ouverts que si l’utilisateur les choisit.

| Élément | Impact ajouté |
| --- | --- |
| Références techniques statiques | 1,919,497 octets bruts, stockés avec les fichiers Cloudflare ; zéro stockage Supabase pour ce corpus |
| Préparation hors connexion | 4,546,843 octets bruts environ, 23 fichiers, puis lecture locale ; stockage transitoire voisin du double lors d’une mise à jour atomique |
| Calculateurs / conversions | Zéro requête serveur par calcul |
| Favoris et récents | Stockage navigateur ; zéro requête Supabase |
| Consultation collaborative ouverte | Au plus un appel de synchronisation par cycle de 20 s ; réponse minimale si révision inchangée |
| Fiches administrées | Limite de 500, avec longueurs de texte bornées ; ni les 16 108 définitions OBD ni les fiches initiales ne sont insérées en base |
| Photos | Une par fiche ; moins de 225 ko JPEG avant encodage, moins de 300 ko encodés ; budget global 20 Mio de texte encodé |
| Edge Functions / cron | Aucun nouvel appel planifié ou nouvelle fonction nécessaire |

Références Free consultées : Supabase annonce notamment 500 Mo de base, 1 Go de stockage fichiers et 5 Go de trafic sortant non mis en cache, avec un quota séparé de trafic mis en cache. Les photos de ce module sont dans PostgreSQL : elles consomment la base, pas le quota Storage de 1 Go. Les actifs statiques Cloudflare sont annoncés gratuits et sans limite de requêtes ; les éventuelles invocations Worker restent soumises aux limites du compte existant.

**Exemple de charge, pas une mesure de production :** 13 utilisateurs ouvrant Toolbox deux fois par jour pendant 26 jours, avec 100 ko de texte synchronisé par ouverture, représentent environ 67,6 Mo de corps de réponses. Une heure de page ouverte par personne et par jour produit au maximum 60 840 vérifications de révision par mois, soit environ 3 Mo pour des réponses de 50 octets, hors en-têtes, photos et mises à jour complètes supplémentaires. Les lectures locales et calculs ne s’ajoutent pas à ces volumes.

Le budget maximal de texte d’une fiche est de quelques dizaines de ko ; 500 fiches, les photos plafonnées et les index restent de l’ordre de quelques dizaines de Mo pour ce module. Ce n’est pas une réservation d’espace : les autres données de l’application consomment déjà les mêmes quotas.

**Le solde réel des quotas de ta production n’est pas accessible ici.** Pour garantir le maintien dans le gratuit, contrôle Database et Egress dans Supabase avant et après installation, reste sur le plan gratuit sans activation de dépassement payant et évite d’accumuler des photos inutiles. Aucun paramètre de facturation n’a été changé par cette livraison.

## Vérification après installation

1. Ouvrir la nouvelle rubrique avec un collaborateur et l’administrateur.
2. Vérifier recherche, calcul, favori et récent.
3. Proposer une fiche, constater son absence chez un autre collaborateur, puis la publier et contrôler son apparition après synchronisation.
4. Désactiver/réactiver un outil et corriger une fiche de référence avec source/date.
5. Préparer le cache, ouvrir l’accès local, fermer puis rouvrir cette page sans réseau sur un vrai téléphone.
6. Contrôler les usages Database et Egress du projet existant.
