# Espace client privé DamUp (club.damup.fr)

Espace client accessible avec un **code personnel** (valable une soirée).
Le client voit les établissements partenaires + les hôtesses (photo + prénom),
puis réserve une table (restaurant / club / les deux) avec une bouteille en club.

## Accès test (avant sous-domaine)
Le dossier `club/` est servi avec le site principal :
- https://damup.fr/club/
- https://damocles2002.github.io/DamUp/club/

Le code est la seule protection : sans code valide, rien ne s'affiche.

## Mise en ligne sur club.damup.fr (sous-domaine)
1. Créer un dépôt GitHub séparé (ex. `damocles2002/DamUp-Club`) contenant le contenu de `club/` à la racine.
2. Dans GitHub → Settings → Pages : activer, branche `main`, dossier `/`.
3. Le fichier `CNAME` (`club.damup.fr`) est déjà fourni.
4. Chez l'hébergeur du domaine (zone DNS de damup.fr), ajouter :
   - enregistrement **CNAME** : `club` → `damocles2002.github.io`
5. Attendre la propagation (quelques minutes à 24 h). Le certificat HTTPS (Let's Encrypt)
   est fourni automatiquement par GitHub Pages.

## Non-référencement
- Chaque page porte `<meta name="robots" content="noindex, nofollow">`.
- `robots.txt` bloque tout (actif une fois le sous-domaine déployé).
- Vérifier quelques semaines après la mise en ligne qu'une recherche Google
  « club.damup.fr » ne remonte rien.

## admin.damup.fr (back-office)
Le back-office reste **unique** : il vit dans `admin.html` du site principal
(https://damup.fr/admin.html). Pour le servir aussi sur `admin.damup.fr`, même principe :
dépôt séparé + CNAME `admin.damup.fr` → `damocles2002.github.io`, ou redirection DNS.
