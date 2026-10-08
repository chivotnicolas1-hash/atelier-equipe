# Atelier Équipe — connexion par identifiants

Version mise à jour : connexion par adresse e-mail et mot de passe fournis par l’administrateur. Aucun compte Google ou ChatGPT requis. Administrateur : nchivot@norauto.fr.

## 1. Mettre à jour votre base déjà créée

Vous avez déjà exécuté 01-installation.sql : ouvrez maintenant `supabase/02-connexion-identifiants.sql`, copiez tout dans une nouvelle requête du SQL Editor de Supabase, puis cliquez sur Run. Aucune présence, tâche ou fiche n’est effacée.
Pour une installation totalement neuve seulement, exécutez `01-installation.sql`, qui intègre désormais la connexion par mot de passe.

## 2. Réglages Supabase

Dans Authentication → Sign In / Providers :
- Activez Email.
- Désactivez Google si vous l’aviez activé.
- Désactivez **Allow new users to sign up**.
- Laissez les connexions anonymes désactivées.

L’application ne propose aucune inscription ni connexion par lien magique. Les fonctions de données exigent une session issue d’une authentification par mot de passe.

## 3. Créer le premier administrateur

Dans Supabase → Authentication → Users → Add user → Create new user :
- Adresse : nchivot@norauto.fr
- Mot de passe : choisissez votre mot de passe personnel (12 caractères minimum conseillés).
- Activez Auto Confirm User / confirmation automatique si cette option est proposée.

Ne transmettez pas votre mot de passe dans la conversation. Si un compte existe déjà pour cette adresse, ne le supprimez pas : demandez la marche à suivre pour le réinitialiser.
Le droit administrateur est contrôlé côté serveur, pas dans le navigateur.

## 4. Activer la création des comptes depuis l’application

Cette étape déploie une fonction serveur Supabase ; elle est nécessaire au bouton « Créer / réinitialiser l’accès ».

Dans Supabase → Edge Functions, créez une fonction via l’éditeur, nommée exactement **workshop-accounts**. Remplacez le code par le contenu de `supabase/functions/workshop-accounts/index.ts`, puis déployez-la.

Dans les réglages de cette fonction, désactivez le contrôle JWT hérité de la passerelle (Verify JWT / Enforce JWT verification). C’est nécessaire à la compatibilité avec les clés récentes : le code fourni valide lui-même chaque jeton avec `auth.getUser`, puis vérifie les droits administrateur via SQL avant toute création ou modification de compte. Ne supprimez pas ces vérifications.

Les variables SUPABASE_URL et SUPABASE_SERVICE_ROLE_KEY sont fournies par l’environnement des fonctions Supabase. Aucune clé secrète ne doit être copiée dans l’application ou le navigateur.

Alternative pour un utilisateur disposant de la CLI Supabase :

```sh
supabase functions deploy workshop-accounts --project-ref ifzdtnysccmcjfpnqyze --no-verify-jwt
```

À défaut de cette fonction, un administrateur du projet peut créer les comptes manuellement dans Authentication → Users, puis associer leur adresse à la fiche de l’application.

## 5. Héberger l’application

Le dossier **dist** contient la version prête à héberger. L’URL Supabase et la clé publique fournies y sont intégrées.

Pour une publication manuelle avec Netlify : connectez-vous à https://app.netlify.com/drop et déposez uniquement le dossier **dist**, contenant index.html. Ne publiez pas le dossier complet des sources et scripts SQL.

Si une précédente version a été publiée, remplacez son déploiement avec ce nouveau dossier dist. La première application hébergée sur ChatGPT reste distincte et n’est pas modifiée par ce ZIP.

## 6. Distribuer les identifiants

1. Connectez-vous à la nouvelle application avec nchivot@norauto.fr et votre mot de passe.
2. Dans Équipe, modifiez une fiche : nom et adresse e-mail du collaborateur, puis enregistrez.
3. Cliquez sur « Créer / réinitialiser l’accès » et choisissez son mot de passe (12 à 128 caractères).
4. Conservez-le avant de valider, puis transmettez au collaborateur le lien, son adresse de connexion et son mot de passe par votre canal habituel.
5. Si le compte existe déjà pour cette adresse, cette action remplace son mot de passe. Elle ne retrouve ni n’affiche jamais l’ancien mot de passe.

Chaque personne doit avoir une adresse unique. Aucune messagerie Google n’est exigée. Les collaborateurs ne peuvent pas créer d’autres comptes. Les autres sessions déjà ouvertes peuvent rester actives après une réinitialisation : celle-ci n’est pas une fonction de révocation d’accès. Pour retirer immédiatement l’accès aux données, retirez l’adresse e-mail de sa fiche.

## Application et mobile

Le plan de l’atelier, les 13 fiches, les affectations par jour, les confirmations de présence et les tâches sont conservés. Les collaborateurs ne peuvent valider que leurs propres tâches et leur présence du jour. L’administrateur organise l’ensemble.

Pour utiliser la vue Collaborateur avec votre compte administrateur, associez votre adresse à votre propre fiche si vous faites partie des 13 collaborateurs.

L’application se rafraîchit toutes les 20 secondes. Sur iPhone : Safari → Partager → Sur l’écran d’accueil. Sur Android : Chrome → menu → Installer l’application. Internet est nécessaire pour lire et enregistrer les données.

## Sources et compilation

Node.js 22 récent et npm sont requis uniquement pour modifier/recompiler les sources :

```sh
npm ci
```

Copiez `.env.example` vers `.env`, puis :

```sh
npm run dev
npm run build
```

Le résultat est dans dist. En déploiement depuis Git, définissez VITE_SUPABASE_URL et VITE_SUPABASE_PUBLISHABLE_KEY chez l’hébergeur. N’utilisez jamais une clé de service dans ces variables.

## Vérifications et limites

La version web compile et les contrôles TypeScript passent. Le SQL a été exécuté dans PostgreSQL embarqué (PGlite), y compris après la première installation. Les tests vérifient les droits administrateur/collaborateur, les refus d’accès croisés, les changements de poste et l’exclusion de Google.

Les tables et fonctions de votre vrai projet ne sont pas modifiées automatiquement par ce ZIP. L’Edge Function est fournie mais reste à déployer et à tester dans votre projet. La connexion réelle, la création de comptes et l’installation mobile restent à vérifier après configuration. Aucun secret ni mot de passe d’utilisateur n’est inclus dans les fichiers.

Références :
- https://supabase.com/docs/guides/auth/general-configuration
- https://supabase.com/docs/reference/javascript/auth-admin-createuser
- https://supabase.com/docs/guides/functions/auth-legacy-jwt
- https://docs.netlify.com/deploy/create-deploys/
