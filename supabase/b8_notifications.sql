-- ============================================================
--  B8 — Notifications : RLS vérifiée/renforcée
--  Chacun ne lit/modifie que SES notifications.
--  Aucune policy INSERT : seuls les déclencheurs (security definer)
--  peuvent en créer.
-- ============================================================
alter table public.notifications enable row level security;

drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own" on public.notifications
  for select using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update using (user_id = auth.uid());

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own" on public.notifications
  for delete using (user_id = auth.uid());
