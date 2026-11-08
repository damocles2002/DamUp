-- ============================================================
--  G2 — Mode de paiement « Virement »
-- ============================================================

-- 1. contrainte de mode : ajoute 'virement'
alter table public.paiements drop constraint if exists paiements_mode_check;
alter table public.paiements add constraint paiements_mode_check
  check (mode in ('especes', 'virement', 'carte', 'prelevement', 'offert'));

-- 2. référence de virement fixe par établissement
alter table public.profiles add column if not exists reference_virement text unique;

create or replace function public.reference_virement(p_uid uuid) returns text
language plpgsql security definer set search_path = public as $$
declare v_ref text; v_nom text;
begin
  if auth.uid() <> p_uid and not public.is_admin() then
    raise exception 'Accès non autorisé.' using hint = 'acces_interdit';
  end if;
  select reference_virement into v_ref from public.profiles where id = p_uid;
  if v_ref is null then
    select regexp_replace(upper(coalesce(nom, 'ETAB')), '[^A-Z0-9]', '', 'g') into v_nom
      from public.etablissements where id = p_uid;
    v_nom := coalesce(nullif(v_nom, ''), 'ETAB');
    if length(v_nom) > 12 then v_nom := left(v_nom, 12); end if;
    v_ref := 'DAMUP-' || v_nom || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 4));
    update public.profiles set reference_virement = v_ref where id = p_uid;
  end if;
  return v_ref;
end; $$;
revoke execute on function public.reference_virement(uuid) from public, anon;
grant execute on function public.reference_virement(uuid) to authenticated;

-- 3. admin_enregistrer_paiement : accepte 'virement' comme 'especes'
create or replace function public.admin_enregistrer_paiement(
  p_profil uuid, p_mode text, p_periode text, p_montant numeric,
  p_date date default null, p_note text default null)
returns public.paiements language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_mode not in ('especes', 'virement', 'offert') then raise exception 'Mode non autorisé ici.'; end if;
  if p_periode not in ('hebdomadaire', 'mensuel') then raise exception 'Période invalide.'; end if;
  if p_mode in ('especes', 'virement') and (p_montant is null or p_montant <= 0) then raise exception 'Montant invalide.'; end if;
  return public.prolonger_abonnement(
    p_profil, case when p_mode = 'offert' then 0 else p_montant end, p_mode, p_periode,
    coalesce(p_date::timestamp at time zone 'Europe/Paris', now()), null, p_note);
end; $$;
revoke execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) from public, anon;
grant execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) to authenticated;

-- 4. admin_annuler_paiement : accepte aussi 'virement' (avoir créé)
create or replace function public.admin_annuler_paiement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_p public.paiements%rowtype;
  v_facture public.factures%rowtype;
  v_avoir_id uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select * into v_p from public.paiements where id = p_id and mode in ('especes', 'virement', 'offert');
  if v_p.id is null then raise exception 'Paiement introuvable (les paiements en ligne s''annulent dans Stripe).'; end if;
  select * into v_facture from public.factures where paiement_id = p_id and type = 'facture';
  if v_facture.id is not null then
    insert into public.factures (numero, type, facture_origine, profil_id, vendeur, client, lignes, total, mode_paiement, acquittee_le)
    values (public.prochain_numero('avoir'), 'avoir', v_facture.id, v_p.profil_id, v_facture.vendeur, v_facture.client, v_facture.lignes, -v_facture.total, v_facture.mode_paiement, now())
    returning id into v_avoir_id;
    perform public.envoyer_facture(v_avoir_id);
  end if;
  delete from public.paiements where id = p_id;
  update public.profiles set actif_jusqu_a = (select max(periode_fin) from public.paiements where profil_id = v_p.profil_id) where id = v_p.profil_id;
end; $$;
revoke execute on function public.admin_annuler_paiement(uuid) from public, anon;
grant execute on function public.admin_annuler_paiement(uuid) to authenticated;

-- 5. la référence est lisible par l'établissement lui-même et l'admin
--    (déjà couvert par la RLS de profiles : id = auth.uid() ou is_admin())
