-- ============================================================
--  A5 : Partenaire Instagram (réglages modifiables)
-- ============================================================
insert into public.settings (key, value) values
  ('partenaire_nom', '"Le Barreau des Barmans"'),
  ('partenaire_lien', '"https://www.instagram.com/le_barreau_des_barmans/"'),
  ('partenaire_logo', '"assets/partenaire-barreau.png"')
on conflict (key) do update set value = excluded.value;
