-- ============================================================
--  M2 — Notifications push : appareils + préférences
-- ============================================================
create table if not exists public.appareils_push (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  endpoint   text not null unique,
  p256dh     text not null,
  auth_cle   text not null,
  appareil   text,
  created_at timestamptz not null default now()
);
alter table public.appareils_push enable row level security;
drop policy if exists "appareils_push_perso" on public.appareils_push;
create policy "appareils_push_perso" on public.appareils_push for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create table if not exists public.preferences_notif (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  push_actif      boolean not null default true,
  email_missions  boolean not null default true,
  email_messages  boolean not null default false,
  email_compte    boolean not null default true,
  updated_at      timestamptz not null default now()
);
alter table public.preferences_notif enable row level security;
drop policy if exists "preferences_notif_perso" on public.preferences_notif;
create policy "preferences_notif_perso" on public.preferences_notif for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
