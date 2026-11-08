-- ============================================================
--  A5 : Partenaire Instagram (réglages modifiables)
-- ============================================================
insert into public.settings (key, value) values
  ('partenaire_nom', '"Le Barreau des Barmans"'),
  ('partenaire_lien', '"https://www.instagram.com/le_barreau_des_barmans/"'),
  ('partenaire_logo', '""')
on conflict (key) do nothing;
