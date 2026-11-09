-- ============================================================
--  E1 : Équipe & droits réels (base de données)
-- ============================================================

alter table public.equipe add column if not exists suspendu boolean not null default false;
alter table public.equipe add column if not exists proprietaire boolean not null default false;
create unique index if not exists equipe_un_seul_proprietaire on public.equipe (proprietaire) where proprietaire;

-- le propriétaire : le compte admin@damup.fr (à adapter si l'e-mail change)
insert into public.equipe (user_id, nom, role, droits, proprietaire)
select u.id, 'Propriétaire', 'proprietaire', '{}'::jsonb, true
  from auth.users u where u.email = 'admin@damup.fr'
   and not exists (select 1 from public.equipe e where e.user_id = u.id);
update public.equipe e set proprietaire = true, role = 'proprietaire'
  from auth.users u where u.id = e.user_id and u.email = 'admin@damup.fr';

-- l'appelant a-t-il ce droit ?
create or replace function public.a_le_droit(p_droit text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipe e
    join public.profiles p on p.id = e.user_id
    where e.user_id = auth.uid() and p.type = 'admin' and not e.suspendu and not p.suspendu
      and (e.proprietaire or coalesce((e.droits ->> p_droit)::boolean, false))
  );
$$;

create or replace function public.est_proprietaire() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.equipe where user_id = auth.uid() and proprietaire and not suspendu);
$$;

-- is_admin() = membre actif de l'équipe (ouvre le back-office + tableau de bord)
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p join public.equipe e on e.user_id = p.id
    where p.id = auth.uid() and p.type = 'admin' and not p.suspendu and not e.suspendu
  );
$$;

create table if not exists public.journal_admin (
  id         uuid primary key default gen_random_uuid(),
  auteur_id  uuid references auth.users(id),
  action     text not null,
  cible_type text,
  cible_id   uuid,
  details    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
alter table public.journal_admin enable row level security;
drop policy if exists "journal_lecture" on public.journal_admin;
create policy "journal_lecture" on public.journal_admin for select using (public.a_le_droit('voir_journal'));

create or replace function public.journaliser(p_action text, p_cible_type text, p_cible_id uuid, p_details jsonb default '{}')
returns void language sql security definer set search_path = public as $$
  insert into public.journal_admin (auteur_id, action, cible_type, cible_id, details)
  values (auth.uid(), p_action, p_cible_type, p_cible_id, coalesce(p_details, '{}'::jsonb));
$$;
revoke execute on function public.journaliser(text, text, uuid, jsonb) from public, anon, authenticated;
