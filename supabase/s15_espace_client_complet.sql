-- ============================================================
--  DamUp : Espace client privé — modèle de données COMPLET (s15)
--  Remplace la v1 simplifiée par les 8 tables du cahier des charges.
-- ============================================================

-- ---- migration depuis la v1 simplifiée ----
drop function if exists public.espace_client_valider_code(text);
drop function if exists public.espace_client_donnees(text);
drop function if exists public.espace_client_reserver(text, text, uuid, uuid, uuid);
drop function if exists public.espace_client_mes_reservations(text);
drop function if exists public.admin_creer_code(text, date);
drop function if exists public.admin_lister_codes();
drop function if exists public.admin_lister_reservations();
drop function if exists public.admin_lister_etablissements_client();
drop function if exists public.admin_regler_etablissement_client(uuid, boolean, numeric, numeric);
drop function if exists public.admin_ajouter_bouteille(uuid, text, numeric);
drop function if exists public.admin_supprimer_bouteille(uuid);
drop function if exists public.admin_traiter_reservation(uuid, text, numeric);
drop table if exists public.reservations_client;
drop table if exists public.clients_codes;
drop table if exists public.bouteilles;
alter table public.etablissements drop column if exists visible_client, drop column if exists remboursement_pct, drop column if exists seuil_depense;

-- ---- 1) clients : une fiche par client ----
create table if not exists public.clients (
  id uuid primary key default gen_random_uuid(),
  prenom text not null,
  nom text not null,
  telephone text unique,
  email text,
  majeur_confirme boolean not null default false,
  majeur_confirme_le timestamptz,
  statut text not null default 'actif',
  nb_no_show integer not null default 0,
  notes_admin text,
  date_creation timestamptz not null default now()
);

-- ---- 2) codes_acces : un code = un client = une soirée ----
create table if not exists public.codes_acces (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  client_id uuid not null references public.clients(id) on delete cascade,
  date_soiree date not null,
  valide_du timestamptz,
  valide_jusqu_au timestamptz,
  statut text not null default 'actif',
  date_premiere_utilisation timestamptz,
  nb_essais_echoues integer not null default 0,
  cree_le timestamptz not null default now()
);

-- ---- 3) avantages_etablissement : réglages fixés par l'admin ----
create table if not exists public.avantages_etablissement (
  etablissement_id uuid primary key references public.etablissements(id) on delete cascade,
  seuil_depense_eur numeric,
  pourcentage_client numeric,
  pourcentage_commission numeric,
  bouteille_obligatoire boolean not null default false,
  actif boolean not null default false
);

-- ---- 4) bouteilles : carte de chaque club ----
create table if not exists public.bouteilles (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements(id) on delete cascade,
  nom text not null,
  categorie text,
  contenance_cl integer,
  prix_eur numeric not null,
  disponible boolean not null default true,
  ordre integer not null default 0,
  created_at timestamptz not null default now()
);

-- ---- 5) reservations : une demande de table ----
create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id),
  code_acces_id uuid not null references public.codes_acces(id),
  etablissement_id uuid not null references public.etablissements(id),
  date_soiree date not null,
  heure_arrivee time,
  nb_personnes integer not null default 1,
  bouteille_id uuid references public.bouteilles(id),
  message_client text,
  statut text not null default 'en_attente',
  date_transmission timestamptz,
  date_confirmation timestamptz,
  motif_refus text,
  date_creation timestamptz not null default now()
);

-- ---- 6) remboursements : le remboursement du client ----
create table if not exists public.remboursements (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  montant_declare_etablissement numeric,
  photo_facture text,
  montant_retenu numeric,
  seuil_applique numeric,
  pourcentage_applique numeric,
  montant_a_rembourser numeric,
  moyen_paiement text,
  coordonnees_paiement text,
  statut text not null default 'en_attente_justificatifs',
  date_virement timestamptz,
  reference_virement text,
  created_at timestamptz not null default now()
);

-- ---- 7) commissions : ce que l'établissement doit à DamUp ----
create table if not exists public.commissions (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid not null references public.reservations(id) on delete cascade,
  etablissement_id uuid not null references public.etablissements(id),
  montant_depense numeric,
  pourcentage_applique numeric,
  montant_commission numeric,
  statut text not null default 'a_facturer',
  date_reception timestamptz,
  created_at timestamptz not null default now()
);

-- ---- 8) signalements_clients ----
create table if not exists public.signalements_clients (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.clients(id) on delete cascade,
  reservation_id uuid references public.reservations(id),
  auteur_type text not null,
  auteur_id uuid not null,
  motif text,
  description text,
  statut text not null default 'ouvert',
  decision text,
  created_at timestamptz not null default now()
);

-- RLS : tout passe par des fonctions, pas de lecture directe
alter table public.clients enable row level security;
alter table public.codes_acces enable row level security;
alter table public.avantages_etablissement enable row level security;
alter table public.bouteilles enable row level security;
alter table public.reservations enable row level security;
alter table public.remboursements enable row level security;
alter table public.commissions enable row level security;
alter table public.signalements_clients enable row level security;
