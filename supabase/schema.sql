-- ============================================================
--  DamUp — schéma de base de données (Supabase / PostgreSQL)
--  Rôles : hôtesses, établissements, administrateur + équipe
--  Modèle SaaS : abonnement payé par les établissements.
--  Chaque table est protégée par Row Level Security (RLS) :
--  un utilisateur ne voit QUE ses propres données (sécurité).
-- ============================================================

-- ---------- profils (liés à auth.users) ----------
-- Un compte = un profil. `type` sépare hôtesse / établissement.
-- C'est le "point d'entrée" commun à l'authentification Supabase.
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  type        text not null check (type in ('hotesse','etablissement','admin')),
  email       text,
  created_at  timestamptz not null default now()
);

-- ---------- hôtesses ----------
-- Les infos affichées publiquement sont LIMITÉES (prénom, âge, ville,
-- photos) : seuls les établissements VÉRIFIÉS voient les candidates
-- à leurs missions. Le reste est réservé à l'administrateur.
create table if not exists public.hotesses (
  id              uuid primary key references public.profiles(id) on delete cascade,
  prenom          text not null,
  age             int  not null check (age >= 18),  -- âge minimum légal
  ville           text,
  instagram       text,
  photos          jsonb not null default '[]'::jsonb,   -- 4 à 7 photos
  note_moyenne    numeric(2,1) default 5.0,             -- calculée depuis les avis
  nb_avis         int default 0,
  verifie         boolean not null default false,       -- validée par l'admin
  id_document     text,          -- pièce d'identité (supprimée après validation)
  signes_negatifs int default 0, -- retiré après 3 missions honorées
  created_at      timestamptz not null default now()
);

-- ---------- établissements ----------
create table if not exists public.etablissements (
  id                uuid primary key references public.profiles(id) on delete cascade,
  nom               text not null,
  type              text check (type in ('bar','restaurant','club','lounge')),
  adresse           text,
  ville             text,
  siret             text,
  responsable_nom   text,
  id_document_resp  text,          -- pièce d'identité du responsable (vérif SIRET)
  photos            jsonb not null default '[]'::jsonb,
  videos            jsonb not null default '[]'::jsonb,  -- URLs stockées dans Storage
  verifie           boolean not null default false,
  abonnement_actif  boolean not null default false,
  created_at        timestamptz not null default now()
);

-- ---------- missions (annonces) ----------
-- Publier : date, horaires, lieu, nb d'hôtesses, articles offerts.
-- Mise en ligne SANS validation préalable (l'admin reçoit une notif).
create table if not exists public.missions (
  id               uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements(id) on delete cascade,
  titre            text,
  date             date not null,
  heure_debut      time not null,
  heure_fin        time not null,
  adresse          text,
  nb_hotesses      int not null default 1,   -- nombre recherché
  articles_offerts jsonb not null default '[]'::jsonb, -- boisson/entrée/plat/dessert/chicha
  medias           jsonb not null default '[]'::jsonb, -- photos/vidéos du lieu
  repetable        boolean not null default false,     -- mission récurrente
  statut           text not null default 'ouverte'
                   check (statut in ('ouverte','en_cours','terminee','annulee')),
  created_at       timestamptz not null default now()
);

-- ---------- candidatures ----------
-- Une hôtesse postule (seule ou en groupe). Après sélection, elle
-- CONFIRME dans un délai (12h, ou 1h si < 24h avant la mission).
create table if not exists public.candidatures (
  id            uuid primary key default gen_random_uuid(),
  mission_id    uuid not null references public.missions(id) on delete cascade,
  hotesse_id    uuid not null references public.hotesses(id) on delete cascade,
  groupe_id     uuid,      -- regroupe les candidates d'un même groupe
  statut        text not null default 'en_attente'
                check (statut in ('en_attente','acceptee','refusee','confirmee')),
  qr_code       text,      -- unique par mission + hôtesse (scanné à l'entrée)
  confirme_a    timestamptz, -- échéance de confirmation
  annulation    boolean not null default false, -- => signe négatif
  created_at    timestamptz not null default now(),
  unique (mission_id, hotesse_id)
);

-- ---------- avis (sens unique : établissement → hôtesse) ----------
create table if not exists public.avis (
  id               uuid primary key default gen_random_uuid(),
  mission_id       uuid not null references public.missions(id) on delete cascade,
  etablissement_id uuid not null references public.etablissements(id),
  hotesse_id       uuid not null references public.hotesses(id),
  note             int not null check (note between 1 and 5),
  criteres         jsonb not null default '[]'::jsonb, -- critères notés (à définir)
  commentaire      text,
  created_at       timestamptz not null default now()
);

-- ---------- signalements (dans les 2 sens) ----------
create table if not exists public.signalements (
  id            uuid primary key default gen_random_uuid(),
  signalant_type text not null check (signalant_type in ('hotesse','etablissement')),
  signalant_id  uuid not null,
  cible_type    text not null check (cible_type in ('hotesse','etablissement','mission')),
  cible_id      uuid not null,
  motif         text,
  statut        text not null default 'nouveau' check (statut in ('nouveau','traite')),
  decision      text,     -- trace de la décision de l'admin
  created_at    timestamptz not null default now()
);

-- ---------- messagerie ----------
-- S'ouvre APRÈS la sélection, se ferme APRÈS l'événement.
-- Photos autorisées, PAS de téléphone ni réseaux sociaux.
create table if not exists public.messages (
  id                uuid primary key default gen_random_uuid(),
  mission_id        uuid not null references public.missions(id) on delete cascade,
  expediteur_type   text not null check (expediteur_type in ('hotesse','etablissement')),
  expediteur_id     uuid not null,
  destinataire_type text not null check (destinataire_type in ('hotesse','etablissement')),
  destinataire_id   uuid not null,
  contenu           text,
  photo_url         text,
  created_at        timestamptz not null default now()
);

-- ---------- abonnements (établissements payants) ----------
-- Prix modifiables par l'admin SANS développement. Deux processeurs :
-- Paddle (sans société) ou Stripe (avec société) — choix fait dans l'admin.
create table if not exists public.abonnements (
  id               uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements(id) on delete cascade,
  plan             text not null check (plan in ('hebdomadaire','mensuel')),
  prix             numeric(8,2) not null,
  processeur       text not null default 'paddle' check (processeur in ('paddle','stripe')),
  statut           text not null default 'essai'
                   check (statut in ('essai','actif','expire','resilie')),
  debut            timestamptz not null default now(),
  fin              timestamptz,
  created_at       timestamptz not null default now()
);

-- ---------- équipe (back-office, grille de droits) ----------
-- L'administrateur principal a tous les accès. Chaque autre membre
-- a des droits cochés dans une grille (jsonb).
create table if not exists public.equipe (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  nom     text,
  role    text,
  droits  jsonb not null default '{}'::jsonb, -- grille de droits à cocher
  created_at timestamptz not null default now()
);

-- ---------- index (performance) ----------
create index if not exists idx_missions_etab     on public.missions(etablissement_id);
create index if not exists idx_missions_statut   on public.missions(statut);
create index if not exists idx_cand_mission      on public.candidatures(mission_id);
create index if not exists idx_cand_hotesse      on public.candidatures(hotesse_id);
create index if not exists idx_avis_hotesse      on public.avis(hotesse_id);
create index if not exists idx_messages_mission  on public.messages(mission_id);

-- ---------- RLS : on active la protection sur toutes les tables ----------
alter table public.profiles      enable row level security;
alter table public.hotesses      enable row level security;
alter table public.etablissements enable row level security;
alter table public.missions      enable row level security;
alter table public.candidatures  enable row level security;
alter table public.avis          enable row level security;
alter table public.signalements  enable row level security;
alter table public.messages      enable row level security;
alter table public.abonnements   enable row level security;
alter table public.equipe        enable row level security;

-- Les policies détaillées sont définies dans un fichier séparé (policies.sql)
-- une fois les règles métier finalisées avec l'utilisateur.
