-- ============================================================
--  S5 : alertes de connexion (appareils connus des membres)
-- ============================================================
create table if not exists public.connexions_admin (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users(id) on delete cascade,
  appareil   text not null,
  navigateur text,
  created_at timestamptz not null default now()
);
alter table public.connexions_admin enable row level security;
