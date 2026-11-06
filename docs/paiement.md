# Paiement & abonnement — DamUp

## Principe
Les **établissements** paient un abonnement (hebdomadaire ou mensuel). Les hôtesses ne paient rien.

Deux modes, **bascule possible depuis le back-office admin sans toucher au code** :

| Mode | Quand l'utiliser | Rôle de DamUp |
|------|------------------|---------------|
| **Paddle** | Pas encore de société | Paddle est le "Merchant of Record" : il encaisse, facture et reverse la TVA à la place de DamUp |
| **Stripe** | Une société est créée | DamUp encaisse directement via Stripe (compte pro), gère sa propre TVA |

## Prix (modifiables dans l'admin, sans dev)
- Hebdomadaire : 25 € (par défaut)
- Mensuel : 79 € (par défaut)
- Essai gratuit : 7 jours

→ Ces valeurs sont stockées dans la table `settings` et modifiables dans l'onglet **Réglages** du back-office.

## Ce qu'il faut pour activer le paiement (à faire ensemble)

### Étape 1 — Créer un compte Paddle
1. Aller sur https://paddle.com et créer un compte (gratuit).
2. Créer les **produits/prix** d'abonnement (hebdo + mensuel) dans le dashboard Paddle.
3. Récupérer la **clé API** (Settings → API Keys) et les **Price IDs**.

### Étape 2 — Me donner ces éléments
- La clé API Paddle
- Les 2 Price IDs (hebdo, mensuel)

### Étape 3 — Je branche
Je déploie l'Edge Function `paiement` (crée un lien de paiement) et je relie :
- le bouton « S'abonner » de l'espace établissement → Paddle
- le **webhook** Paddle → Supabase (mise à jour automatique de l'abonnement : actif/expiré)

## Table `abonnements` (déjà prête)
Colonnes : `plan` (hebdo/mensuel), `prix`, `processeur` (paddle/stripe), `statut` (essai/actif/expire/resilie), `debut`, `fin`.

La logique est prête : il ne manque que les clés Paddle.
