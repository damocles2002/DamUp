-- ============================================================
--  B7 : Avis et abonnements encadrés
-- ============================================================
-- un seul avis par hôtesse et par mission, seulement après une mission confirmée
alter table public.avis drop constraint if exists avis_unique;
alter table public.avis add constraint avis_unique unique (mission_id, hotesse_id);
drop policy if exists "avis_insert_etab" on public.avis;
create policy "avis_insert_etab" on public.avis for insert with check (
  etablissement_id = auth.uid()
  and exists (
    select 1 from public.missions m
    join public.candidatures c on c.mission_id = m.id
    where m.id = avis.mission_id and m.etablissement_id = auth.uid()
      and c.hotesse_id = avis.hotesse_id and c.statut = 'confirmee' and not c.annulation
      and m.date <= current_date));

-- un établissement ne peut plus s'offrir un abonnement lui-même
drop policy if exists "abonnements_insert_own" on public.abonnements;
create policy "abonnements_insert_admin" on public.abonnements for insert with check (public.is_admin());
