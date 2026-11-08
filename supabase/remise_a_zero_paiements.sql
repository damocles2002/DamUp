-- ⚠️⚠️⚠️  ATTENTION : À NE PAS EXÉCUTER SANS RAISON  ⚠️⚠️⚠️
--
-- Ce script SUPPRIME TOUS les paiements de test et remet la
-- numérotation des reçus à 1.
--
-- À lancer UNE SEULE FOIS, juste avant le premier vrai paiement.
-- Ne jamais l'exécuter en cours d'utilisation normale : cela
-- effacerait tout l'historique de facturation.

delete from public.paiements;
alter sequence public.recu_seq restart with 1;
