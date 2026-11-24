-- ============================================================
--  DamUp : Espace client privé (s14)
--  Code personnel → établissements + hôtesses (photo/prénom)
--  → réservation de table (restaurant / club / les deux) + bouteille
--  → remboursement % si dépense ≥ seuil.
--  Une seule base, un seul back-office, sous-domaine club.damup.fr.
-- ============================================================

-- 1) établissements : visibilité + réglages de remboursement
alter table public.etablissements
  add column if not exists visible_client boolean not null default false,
  add column if not exists remboursement_pct numeric,
  add column if not exists seuil_depense numeric;

-- 2) carte des bouteilles (clubs)
create table if not exists public.bouteilles (
  id uuid primary key default gen_random_uuid(),
  etablissement_id uuid not null references public.etablissements(id) on delete cascade,
  nom text not null,
  prix numeric not null,
  ordre int not null default 0,
  created_at timestamptz not null default now()
);

-- 3) codes clients (un code = une soirée)
create table if not exists public.clients_codes (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  statut text not null default 'actif',
  date_soiree date,
  client_nom text,
  cree_le timestamptz not null default now(),
  utilise_le timestamptz
);

-- 4) réservations de table
create table if not exists public.reservations_client (
  id uuid primary key default gen_random_uuid(),
  code_id uuid not null references public.clients_codes(id),
  client_nom text not null,
  date_soiree date not null,
  restaurant_id uuid references public.etablissements(id),
  club_id uuid references public.etablissements(id),
  bouteille_id uuid references public.bouteilles(id),
  statut text not null default 'nouvelle',
  depense numeric,
  remboursement numeric,
  rembourse boolean not null default false,
  rembourse_le timestamptz,
  cree_le timestamptz not null default now()
);

-- RLS : aucune lecture directe par le client (tout passe par fonctions)
alter table public.clients_codes enable row level security;
alter table public.reservations_client enable row level security;
alter table public.bouteilles enable row level security;

-- ============ FONCTIONS CLIENT (appelées sans compte, avec le code) ============

-- valider un code
create or replace function public.espace_client_valider_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.clients_codes%rowtype;
begin
  select * into c from public.clients_codes where upper(code) = upper(trim(p_code));
  if c.id is null then return jsonb_build_object('valide', false, 'raison', 'introuvable'); end if;
  if c.statut <> 'actif' then return jsonb_build_object('valide', false, 'raison', 'utilise'); end if;
  if c.date_soiree is not null and c.date_soiree < current_date then
    return jsonb_build_object('valide', false, 'raison', 'expire');
  end if;
  return jsonb_build_object('valide', true, 'code_id', c.id, 'date_soiree', c.date_soiree, 'client_nom', c.client_nom);
end; $$;

-- établissements visibles + hôtesses acceptées + bouteilles + réglages
create or replace function public.espace_client_donnees(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.clients_codes%rowtype;
begin
  select * into c from public.clients_codes where upper(code) = upper(trim(p_code));
  if c.id is null or c.statut <> 'actif' then
    return jsonb_build_object('valide', false);
  end if;
  return jsonb_build_object(
    'valide', true,
    'date_soiree', c.date_soiree,
    'etablissements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'nom', e.nom, 'type', e.type, 'ville', e.ville, 'adresse', e.adresse,
        'photos', e.photos, 'remboursement_pct', e.remboursement_pct, 'seuil_depense', e.seuil_depense,
        'bouteilles', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'nom', b.nom, 'prix', b.prix) order by b.ordre) from public.bouteilles b where b.etablissement_id = e.id), '[]'::jsonb),
        'hotesses', coalesce((select jsonb_agg(h) from (
          select distinct on (hh.id) jsonb_build_object('id', hh.id, 'prenom', hh.prenom, 'photo', hh.photos->0) as h
          from public.hotesses hh
          join public.candidatures cd on cd.hotesse_id = hh.id
          join public.missions m on m.id = cd.mission_id
          where m.etablissement_id = e.id
            and cd.statut in ('acceptee','confirmee') and not cd.annulation
            and hh.verifie and hh.photos is not null and jsonb_array_length(hh.photos) > 0
          order by hh.id
        ) t), '[]'::jsonb)
      ) order by e.nom)
      from public.etablissements e where e.visible_client and e.verifie
    ), '[]'::jsonb)
  );
end; $$;

-- créer une réservation (marque le code utilisé)
create or replace function public.espace_client_reserver(p_code text, p_client_nom text, p_restaurant_id uuid, p_club_id uuid, p_bouteille_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.clients_codes%rowtype;
  v_id uuid;
begin
  select * into c from public.clients_codes where upper(code) = upper(trim(p_code));
  if c.id is null then return jsonb_build_object('ok', false, 'erreur', 'Code invalide.'); end if;
  if c.statut <> 'actif' then return jsonb_build_object('ok', false, 'erreur', 'Code déjà utilisé.'); end if;
  if p_restaurant_id is null and p_club_id is null then
    return jsonb_build_object('ok', false, 'erreur', 'Choisissez au moins un établissement.');
  end if;
  -- en club, la bouteille est obligatoire
  if p_club_id is not null and p_bouteille_id is null then
    return jsonb_build_object('ok', false, 'erreur', 'Choisissez une bouteille pour le club.');
  end if;
  insert into public.reservations_client (code_id, client_nom, date_soiree, restaurant_id, club_id, bouteille_id)
  values (c.id, coalesce(nullif(trim(p_client_nom), ''), coalesce(c.client_nom, 'Client')), coalesce(c.date_soiree, current_date), p_restaurant_id, p_club_id, p_bouteille_id)
  returning id into v_id;
  update public.clients_codes set statut = 'utilise', utilise_le = now() where id = c.id;
  return jsonb_build_object('ok', true, 'reservation_id', v_id);
end; $$;

-- réservations d'un code
create or replace function public.espace_client_mes_reservations(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.clients_codes%rowtype;
begin
  select * into c from public.clients_codes where upper(code) = upper(trim(p_code));
  if c.id is null then return jsonb_build_object('valide', false); end if;
  return jsonb_build_object('valide', true, 'reservations', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'date_soiree', r.date_soiree, 'statut', r.statut, 'depense', r.depense, 'remboursement', r.remboursement,
      'restaurant', (select nom from public.etablissements where id = r.restaurant_id),
      'club', (select nom from public.etablissements where id = r.club_id),
      'bouteille', (select nom from public.bouteilles where id = r.bouteille_id)
    ) order by r.cree_le desc)
    from public.reservations_client r where r.code_id = c.id
  ), '[]'::jsonb));
end; $$;

-- fonctions client appelables sans compte
grant execute on function public.espace_client_valider_code(text) to anon, authenticated;
grant execute on function public.espace_client_donnees(text) to anon, authenticated;
grant execute on function public.espace_client_reserver(text, text, uuid, uuid, uuid) to anon, authenticated;
grant execute on function public.espace_client_mes_reservations(text) to anon, authenticated;

-- ============ FONCTIONS ADMIN (back-office) ============

-- générer un code (6 caractères, sans ambiguïtés)
create or replace function public.admin_creer_code(p_client_nom text, p_date_soiree date)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_ok boolean := false;
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
    v_code := translate(v_code, '0O1IL', 'ABCDEF');
    if not exists (select 1 from public.clients_codes where code = v_code) then v_ok := true; end if;
    exit when v_ok;
  end loop;
  insert into public.clients_codes (code, statut, date_soiree, client_nom)
  values (v_code, 'actif', p_date_soiree, nullif(trim(p_client_nom), ''));
  return v_code;
end; $$;

create or replace function public.admin_lister_codes()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'code', c.code, 'statut', c.statut, 'date_soiree', c.date_soiree, 'client_nom', c.client_nom, 'cree_le', c.cree_le
  ) order by c.cree_le desc) from public.clients_codes c), '[]'::jsonb);
end; $$;

create or replace function public.admin_lister_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', r.id, 'client_nom', r.client_nom, 'date_soiree', r.date_soiree, 'statut', r.statut,
    'depense', r.depense, 'remboursement', r.remboursement, 'rembourse', r.rembourse,
    'restaurant', (select nom from public.etablissements where id = r.restaurant_id),
    'club', (select nom from public.etablissements where id = r.club_id),
    'bouteille', (select nom from public.bouteilles where id = r.bouteille_id),
    'code', (select code from public.clients_codes where id = r.code_id),
    'cree_le', r.cree_le
  ) order by r.cree_le desc) from public.reservations_client r), '[]'::jsonb);
end; $$;

-- lister les établissements (avec réglages + bouteilles) pour le back-office
create or replace function public.admin_lister_etablissements_client()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', e.id, 'nom', e.nom, 'type', e.type, 'ville', e.ville,
    'visible_client', e.visible_client, 'remboursement_pct', e.remboursement_pct, 'seuil_depense', e.seuil_depense,
    'bouteilles', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'nom', b.nom, 'prix', b.prix) order by b.ordre)
      from public.bouteilles b where b.etablissement_id = e.id), '[]'::jsonb)
  ) order by e.nom)
  from public.etablissements e where e.type in ('club','restaurant','bar','lounge')), '[]'::jsonb);
end; $$;

-- gérer la visibilité + les réglages d'un établissement
create or replace function public.admin_regler_etablissement_client(p_etablissement uuid, p_visible boolean, p_remboursement_pct numeric, p_seuil_depense numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  update public.etablissements
     set visible_client = p_visible, remboursement_pct = nullif(p_remboursement_pct, 0), seuil_depense = nullif(p_seuil_depense, 0)
   where id = p_etablissement;
end; $$;

-- gérer la carte des bouteilles
create or replace function public.admin_ajouter_bouteille(p_etablissement uuid, p_nom text, p_prix numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  insert into public.bouteilles (etablissement_id, nom, prix, ordre)
  values (p_etablissement, nullif(trim(p_nom), ''), p_prix, coalesce((select max(ordre) + 1 from public.bouteilles where etablissement_id = p_etablissement), 0));
end; $$;

create or replace function public.admin_supprimer_bouteille(p_bouteille uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  delete from public.bouteilles where id = p_bouteille;
end; $$;

-- traiter une réservation : transmettre / confirmer / terminer (avec dépense) / annuler
create or replace function public.admin_traiter_reservation(p_reservation uuid, p_action text, p_depense numeric default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations_client%rowtype;
  v_remboursement numeric := 0;
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  select * into r from public.reservations_client where id = p_reservation;
  if r.id is null then return jsonb_build_object('ok', false, 'erreur', 'Réservation introuvable.'); end if;

  if p_action = 'transmettre' then
    update public.reservations_client set statut = 'transmise' where id = p_reservation;
  elsif p_action = 'confirmer' then
    update public.reservations_client set statut = 'confirmee' where id = p_reservation;
  elsif p_action = 'terminer' then
    v_remboursement := 0;
    if p_depense is not null then
      select round(p_depense * coalesce(e.remboursement_pct, 0) / 100, 2)
        into v_remboursement
        from public.etablissements e
       where e.id = coalesce(r.club_id, r.restaurant_id)
         and e.seuil_depense is not null
         and p_depense >= e.seuil_depense;
    end if;
    update public.reservations_client set statut = 'terminee', depense = p_depense, remboursement = v_remboursement where id = p_reservation;
  elsif p_action = 'rembourse' then
    update public.reservations_client set rembourse = true, rembourse_le = now() where id = p_reservation;
  elsif p_action = 'annuler' then
    update public.reservations_client set statut = 'annulee' where id = p_reservation;
  else
    return jsonb_build_object('ok', false, 'erreur', 'Action inconnue.');
  end if;
  return jsonb_build_object('ok', true, 'remboursement', v_remboursement);
end; $$;

-- fonctions admin
grant execute on function public.admin_creer_code(text, date) to authenticated;
grant execute on function public.admin_lister_codes() to authenticated;
grant execute on function public.admin_lister_reservations() to authenticated;
grant execute on function public.admin_lister_etablissements_client() to authenticated;
grant execute on function public.admin_regler_etablissement_client(uuid, boolean, numeric, numeric) to authenticated;
grant execute on function public.admin_ajouter_bouteille(uuid, text, numeric) to authenticated;
grant execute on function public.admin_supprimer_bouteille(uuid) to authenticated;
grant execute on function public.admin_traiter_reservation(uuid, text, numeric) to authenticated;
