-- ============================================================
--  DamUp : policies Row Level Security (RLS)
--  Le schéma active RLS partout ; SANS ces règles, tout est
--  bloqué. Ici on définit QUI peut lire/écrire QUOI.
--  Règle générale : chacun accède à SES données ; l'admin à tout.
-- ============================================================

-- ---------- table des réglages (prix, options) ----------
-- L'admin modifie les prix SANS toucher au code (exigence porteur).
create table if not exists public.settings (
  key   text primary key,
  value jsonb not null
);
alter table public.settings enable row level security;

-- ---------- fonction "est administrateur ?" ----------
-- security definer : la fonction lit `profiles` même si l'appelant
-- n'a pas d'accès direct (nécessaire pour vérifier le type admin).
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and type = 'admin');
$$;

-- ---------- profiles ----------
create policy "profiles_select_own" on public.profiles
  for select using (id = auth.uid() or is_admin());
create policy "profiles_insert_own" on public.profiles
  for insert with check (id = auth.uid());
create policy "profiles_update_admin" on public.profiles
  for update using (is_admin());

-- ---------- hotesses ----------
-- Lecture : toute personne connectée (les établissements doivent voir
-- les candidates à leurs missions pour le swipe). À durcir plus tard
-- en limitant aux établissements vérifiés.
create policy "hotesses_select_auth" on public.hotesses
  for select using (auth.role() = 'authenticated');
create policy "hotesses_insert_own" on public.hotesses
  for insert with check (id = auth.uid());
create policy "hotesses_update_own" on public.hotesses
  for update using (id = auth.uid() or is_admin());

-- ---------- etablissements ----------
create policy "etablissements_select_auth" on public.etablissements
  for select using (auth.role() = 'authenticated');
create policy "etablissements_insert_own" on public.etablissements
  for insert with check (id = auth.uid());
create policy "etablissements_update_own" on public.etablissements
  for update using (id = auth.uid() or is_admin());

-- ---------- missions ----------
create policy "missions_select_auth" on public.missions
  for select using (auth.role() = 'authenticated');
create policy "missions_insert_own" on public.missions
  for insert with check (etablissement_id = auth.uid());
create policy "missions_update_own" on public.missions
  for update using (etablissement_id = auth.uid() or is_admin());

-- ---------- candidatures ----------
-- L'établissement voit/valide les candidatures à SES missions.
create policy "candidatures_select" on public.candidatures
  for select using (
    hotesse_id = auth.uid() or is_admin()
    or exists (select 1 from public.missions m
               where m.id = mission_id and m.etablissement_id = auth.uid())
  );
create policy "candidatures_insert_own" on public.candidatures
  for insert with check (hotesse_id = auth.uid());
create policy "candidatures_update" on public.candidatures
  for update using (
    hotesse_id = auth.uid() or is_admin()
    or exists (select 1 from public.missions m
               where m.id = mission_id and m.etablissement_id = auth.uid())
  );

-- ---------- avis ----------
create policy "avis_select_auth" on public.avis
  for select using (auth.role() = 'authenticated');
create policy "avis_insert_etab" on public.avis
  for insert with check (etablissement_id = auth.uid());

-- ---------- signalements ----------
create policy "signalements_insert_auth" on public.signalements
  for insert with check (signalant_id = auth.uid());
create policy "signalements_select_admin" on public.signalements
  for select using (is_admin());
create policy "signalements_update_admin" on public.signalements
  for update using (is_admin());

-- ---------- messages ----------
create policy "messages_select_participant" on public.messages
  for select using (expediteur_id = auth.uid() or destinataire_id = auth.uid() or is_admin());
create policy "messages_insert_participant" on public.messages
  for insert with check (expediteur_id = auth.uid());

-- ---------- abonnements ----------
create policy "abonnements_select_own" on public.abonnements
  for select using (etablissement_id = auth.uid() or is_admin());
create policy "abonnements_insert_own" on public.abonnements
  for insert with check (etablissement_id = auth.uid() or is_admin());

-- ---------- equipe ----------
create policy "equipe_all_admin" on public.equipe
  for all using (is_admin()) with check (is_admin());

-- ---------- settings ----------
create policy "settings_select_auth" on public.settings
  for select using (auth.role() = 'authenticated');
create policy "settings_write_admin" on public.settings
  for all using (is_admin()) with check (is_admin());

-- ---------- valeurs par défaut ----------
insert into public.settings (key, value) values
  ('prix_hebdo', to_jsonb(25)),
  ('prix_mensuel', to_jsonb(79))
on conflict (key) do nothing;
