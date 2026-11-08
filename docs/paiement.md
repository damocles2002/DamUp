# Paiement en ligne DamUp (Stripe) — Guide pour le porteur de projet

Tout est construit mais **éteint par défaut**. Tant que tu ne fais rien, aucun paiement n'est exigé
(période bêta).

## 1. Créer ton compte Stripe (mode test d'abord)

1. Va sur [stripe.com](https://stripe.com) et crée un compte (gratuit).
2. Reste en **mode test** (interrupteur « Test » en haut à droite du tableau de bord).
3. Dans **Réglages → Moyens de paiement**, active :
   - **Carte bancaire** (Card)
   - **Prélèvement SEPA** (SEPA Direct Debit) — Stripe demandera une vérification d'identité
     supplémentaire (c'est normal, prépare une pièce d'identité).

## 2. Où coller les clés dans Supabase

Dashboard Supabase → **Edge Functions → Secrets**. Ajoute ces 3 secrets (jamais dans le code) :

| Secret | Valeur |
| --- | --- |
| `STRIPE_SECRET_KEY` | ta clé secrète Stripe (`sk_test_…` en test) |
| `STRIPE_WEBHOOK_SECRET` | le secret du webhook (voir ci-dessous) |
| `STRIPE_COMPTE` | un libellé libre, ex. `perso-2026` |

## 3. Déclarer le webhook dans Stripe

1. Dans Stripe → **Développeurs → Webhooks → Ajouter un endpoint**.
2. URL : `https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/stripe-webhook`
3. Événements à cocher :
   - `invoice.paid`
   - `invoice.payment_failed`
   - `checkout.session.completed`
   - `charge.dispute.created`
4. Stripe affiche un **secret de signature** (`whsec_…`) : copie-le dans le secret
   `STRIPE_WEBHOOK_SECRET` de Supabase.

## 4. Tester

Une fois `paiement_en_ligne_actif` activé dans les Réglages :
- **Carte** : numéro `4242 4242 4242 4242`, n'importe quelle date future, n'importe quel CVC.
- **SEPA** : IBAN de test `DE89370400440532013000`.

## 5. Passer en mode réel

1. Dans Stripe, passe en **mode réel**.
2. Remplace `STRIPE_SECRET_KEY` par la clé réelle (`sk_live_…`).
3. Refais un webhook en mode réel (nouveau secret `whsec_…` → mets à jour `STRIPE_WEBHOOK_SECRET`).

## 6. Changer de compte Stripe (micro-entreprise → société)

1. Remplace les **3 secrets** (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_COMPTE`).
2. Résilie les abonnements en cours sur l'ancien compte (tableau de bord Stripe).
3. Les abonnés en ligne verront « Réactive ton paiement » et referont une fois le paiement
   (leurs anciennes autorisations restent liées à l'ancien compte).
4. Les paiements **en espèces** ne sont pas concernés.

## 7. Factures automatiques

À chaque paiement (espèces, carte ou prélèvement), une **facture DamUp** est créée, numérotée
(`F-2026-00001`…), enregistrée en PDF et envoyée automatiquement par e-mail. Un **avoir**
(`A-2026-00001`…) remplace la facture en cas d'annulation.

- **Dans Stripe, désactive l'envoi des factures Stripe** aux clients (garde seulement les reçus de
  paiement si besoin) : seule la facture DamUp fait foi, pour éviter deux numérotations.
  (Stripe → Réglages → E-mails clients → Factures → désactiver.)

- **Les factures exigent ton SIRET** : remplis Réglages → Mentions sur les factures dès la création de
  ta micro-entreprise. Avant cela, l'encaissement est bloqué avec un message clair.

- **Facturation électronique** : elle devient progressivement obligatoire en France entre entreprises,
  via des plateformes agréées. Les factures étant enregistrées de façon structurée, il sera possible
  de les y transmettre ; vérifie le calendrier qui s'applique à toi avec ton comptable.

- **Avant le premier vrai paiement** : lance le script `supabase/remise_a_zero_paiements.sql`
  (paiements de test, compteurs de reçus et de factures remis à zéro).
