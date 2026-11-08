# DamUp

Plateforme de mise en relation entre **hôtesses de table** et **établissements** (bars, restaurants, clubs, lounges). Fini le bouche-à-oreille : publication, candidature, sélection par swipe, QR code à l'entrée.

## Stack
- **Frontend** : web mobile-first (HTML/CSS/JS + SDK Supabase)
- **Backend** : Supabase (Postgres + Storage + Edge Functions)
- **Déploiement** : GitHub Pages

## Espaces
- **Hôtesse** — profil (4–7 photos), missions, candidatures, QR code à l'entrée
- **Établissement** — missions, sélection par swipe, avis, abonnement
- **Administrateur** — modération, prix, équipe & droits, statistiques

## Structure
- `index.html` — vitrine
- `login.html` — connexion / inscription
- `hotesse.html` — espace hôtesse
- `etablissement.html` — espace établissement
- `admin.html` — back-office
- `js/config.js` — configuration Supabase (URL + clé anon publique)
- `supabase/schema.sql` — schéma de base de données (RLS activé)

## Identité visuelle
- Logo : « La Couronne »
- Couleurs : aubergine `#2A1120`, champagne `#E7CFA8`, ivoire `#F4E8D6`
- Polices : Bodoni Moda (titres), Jost (textes)

## Application installable (PWA)
- `manifest.webmanifest` + `sw.js` + icônes `assets/icon-*.png`
- **À chaque mise en ligne, augmenter la `VERSION` dans `sw.js`** (pour que les
  navigateurs rechargent le cache).
