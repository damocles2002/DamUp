-- ============================================================
--  Q2 — Réglages : lecture depuis le SQL + valeurs par défaut
-- ============================================================
create or replace function public.reglage_num(p_cle text, p_defaut numeric) returns numeric
language sql stable security definer set search_path = public as $$
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s where s.key = p_cle), p_defaut);
$$;
create or replace function public.reglage_bool(p_cle text, p_defaut boolean) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select (s.value #>> '{}')::boolean from public.settings s where s.key = p_cle), p_defaut);
$$;

insert into public.settings (key, value) values
  ('essai_jours', '7'),
  ('delai_confirmation_h', '12'),
  ('delai_confirmation_court_h', '3'),
  ('max_hotesses_mission', '50'),
  ('missions_pour_retirer_signe', '3'),
  ('signes_avant_suspension', '3'),
  ('inscriptions_ouvertes', 'true'),
  ('villes', '[]'),
  ('contact_email', '""'),
  ('annonce', '""'),
  ('maintenance', 'false'),
  ('maintenance_message', '"DamUp est en maintenance, reviens dans quelques minutes."'),
  ('paiement_etablissements_actif', 'false'),
  ('paiement_hotesses_actif', 'false'),
  ('paiement_en_ligne_actif', 'false'),
  ('prix_defaut_etablissement', '79'),
  ('periode_defaut_etablissement', '"mensuel"'),
  ('prix_defaut_hotesse', '0'),
  ('periode_defaut_hotesse', '"mensuel"'),
  ('vendeur_nom', '""'),
  ('vendeur_siret', '""'),
  ('vendeur_adresse', '""'),
  ('mention_tva', '"TVA non applicable, art. 293 B du CGI"')
on conflict (key) do nothing;

drop policy if exists "settings_select_anon" on public.settings;
create policy "settings_select_anon" on public.settings for select to anon using (true);
