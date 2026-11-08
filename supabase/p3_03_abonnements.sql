-- ============================================================
--  Q3 — Abonnements et paiements
-- ============================================================
alter table public.profiles
  add column if not exists tarif numeric(8,2),
  add column if not exists periode text check (periode in ('hebdomadaire', 'mensuel')),
  add column if not exists actif_jusqu_a timestamptz,
  add column if not exists rappel_fin_envoye_pour timestamptz,
  add column if not exists stripe_customer_id text,
  add column if not exists stripe_compte text;

create sequence if not exists public.recu_seq;

create table if not exists public.paiements (
  id                uuid primary key default gen_random_uuid(),
  profil_id         uuid not null references public.profiles(id) on delete cascade,
  montant           numeric(8,2) not null check (montant >= 0),
  mode              text not null check (mode in ('especes', 'carte', 'prelevement', 'offert')),
  periode_debut     timestamptz not null,
  periode_fin       timestamptz not null,
  numero_recu       text not null unique
                    default ('DU-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.recu_seq')::text, 5, '0')),
  reference_externe text unique,
  note              text,
  enregistre_par    uuid references auth.users(id),
  created_at        timestamptz not null default now()
);
alter table public.paiements enable row level security;
drop policy if exists "paiements_select" on public.paiements;
create policy "paiements_select" on public.paiements for select
  using (profil_id = auth.uid() or public.is_admin());

-- coeur du système : ajoute une période à la suite (aucun jour perdu)
create or replace function public.prolonger_abonnement(
  p_profil uuid, p_montant numeric, p_mode text, p_periode text,
  p_date timestamptz, p_ref text, p_note text)
returns public.paiements language plpgsql security definer set search_path = public as $$
declare
  v_debut timestamptz;
  v_fin timestamptz;
  v_p public.paiements;
begin
  select greatest(coalesce(actif_jusqu_a, p_date), p_date) into v_debut
    from public.profiles where id = p_profil for update;
  if v_debut is null then raise exception 'Compte introuvable.'; end if;
  v_fin := v_debut + case p_periode when 'hebdomadaire' then interval '7 days' else interval '1 month' end;

  insert into public.paiements (profil_id, montant, mode, periode_debut, periode_fin, reference_externe, note, enregistre_par)
  values (p_profil, p_montant, p_mode, v_debut, v_fin, p_ref, p_note, auth.uid())
  returning * into v_p;

  update public.profiles set actif_jusqu_a = v_fin, rappel_fin_envoye_pour = null where id = p_profil;
  insert into public.notifications (user_id, message) values (p_profil,
    case when p_mode = 'offert'
      then '🎁 DamUp t''offre l''accès jusqu''au ' || to_char(v_fin at time zone 'Europe/Paris', 'DD/MM/YYYY') || '.'
      else '✅ Paiement reçu : ton abonnement DamUp est actif jusqu''au '
           || to_char(v_fin at time zone 'Europe/Paris', 'DD/MM/YYYY') || '.' end);
  return v_p;
end; $$;
revoke execute on function public.prolonger_abonnement(uuid, numeric, text, text, timestamptz, text, text)
  from public, anon, authenticated;
grant execute on function public.prolonger_abonnement(uuid, numeric, text, text, timestamptz, text, text)
  to service_role;

-- admin : paiement en espèces ou période offerte
create or replace function public.admin_enregistrer_paiement(
  p_profil uuid, p_mode text, p_periode text, p_montant numeric,
  p_date date default null, p_note text default null)
returns public.paiements language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_mode not in ('especes', 'offert') then raise exception 'Mode non autorisé ici.'; end if;
  if p_periode not in ('hebdomadaire', 'mensuel') then raise exception 'Période invalide.'; end if;
  if p_mode = 'especes' and (p_montant is null or p_montant <= 0) then raise exception 'Montant invalide.'; end if;
  return public.prolonger_abonnement(
    p_profil, case when p_mode = 'offert' then 0 else p_montant end, p_mode, p_periode,
    coalesce(p_date::timestamp at time zone 'Europe/Paris', now()), null, p_note);
end; $$;
revoke execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) from public, anon;
grant execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) to authenticated;

-- admin : annuler un paiement saisi par erreur
create or replace function public.admin_annuler_paiement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_profil uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  delete from public.paiements where id = p_id and mode in ('especes', 'offert') returning profil_id into v_profil;
  if v_profil is null then raise exception 'Paiement introuvable (les paiements en ligne s''annulent dans Stripe).'; end if;
  update public.profiles
     set actif_jusqu_a = (select max(periode_fin) from public.paiements where profil_id = v_profil)
   where id = v_profil;
end; $$;
revoke execute on function public.admin_annuler_paiement(uuid) from public, anon;
grant execute on function public.admin_annuler_paiement(uuid) to authenticated;

-- admin : offrir une période à tous les comptes d'un type sans abonnement en cours
create or replace function public.admin_offrir_periode_groupe(p_type text, p_jours int) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_type not in ('etablissement', 'hotesse') or p_jours not between 1 and 90 then
    raise exception 'Paramètres invalides.';
  end if;
  update public.profiles set actif_jusqu_a = now() + make_interval(days => p_jours), rappel_fin_envoye_pour = null
   where type = p_type and (actif_jusqu_a is null or actif_jusqu_a < now());
  get diagnostics n = row_count;
  return n;
end; $$;
revoke execute on function public.admin_offrir_periode_groupe(text, int) from public, anon;
grant execute on function public.admin_offrir_periode_groupe(text, int) to authenticated;

-- le compte peut-il agir ? (toujours oui si le paiement de son type est éteint)
create or replace function public.abonnement_ok(p_uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select case p.type
    when 'etablissement' then not public.reglage_bool('paiement_etablissements_actif', false)
                              or coalesce(p.actif_jusqu_a > now(), false)
    when 'hotesse'       then not public.reglage_bool('paiement_hotesses_actif', false)
                              or coalesce(p.actif_jusqu_a > now(), false)
    else true end
  from public.profiles p where p.id = p_uid;
$$;

-- l'ancienne table abonnements n'est plus utilisée
comment on table public.abonnements is 'remplacée par profiles.actif_jusqu_a + paiements (phase 3)';
