-- ============================================================
--  F1 — Factures : base de données
--  Compteurs, table factures, numérotation continue,
--  création de facture (et avoir), envoi via Edge Function.
-- ============================================================

-- numérotation continue, sans trou (exigence comptable)
create table if not exists public.compteurs (
  nom    text primary key,
  annee  int  not null,
  valeur int  not null default 0
);
alter table public.compteurs enable row level security;   -- accès par fonctions uniquement

-- factures et avoirs
create table if not exists public.factures (
  id           uuid primary key default gen_random_uuid(),
  numero       text not null unique,
  type         text not null default 'facture' check (type in ('facture', 'avoir')),
  paiement_id  uuid unique references public.paiements(id) on delete set null,
  facture_origine uuid references public.factures(id),
  profil_id    uuid not null references public.profiles(id),
  date_emission timestamptz not null default now(),
  vendeur      jsonb not null,
  client       jsonb not null,
  lignes       jsonb not null,
  total        numeric(8,2) not null,
  mode_paiement text not null,
  acquittee_le timestamptz,
  pdf_chemin   text,
  envoyee_le   timestamptz,
  envoi_erreur text,
  created_at   timestamptz not null default now()
);
alter table public.factures enable row level security;
drop policy if exists "factures_lecture" on public.factures;
create policy "factures_lecture" on public.factures for select
  using (profil_id = auth.uid() or public.is_admin());
-- aucune règle d'écriture ni de suppression

-- prochain numéro : F-2026-00001 / A-2026-00001 (compteur verrouillé, remis à 0 au changement d'année)
create or replace function public.prochain_numero(p_nom text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_annee int := extract(year from now())::int;
  v_prefix text := case when p_nom = 'facture' then 'F' else 'A' end;
  v_annee_c int;
  v_val int;
begin
  select annee, valeur into v_annee_c, v_val from public.compteurs where nom = p_nom for update;
  if v_val is null then
    insert into public.compteurs (nom, annee, valeur) values (p_nom, v_annee, 1);
    v_val := 1;
  elsif v_annee_c <> v_annee then
    update public.compteurs set annee = v_annee, valeur = 1 where nom = p_nom;
    v_val := 1;
  else
    update public.compteurs set valeur = valeur + 1 where nom = p_nom returning valeur into v_val;
  end if;
  return v_prefix || '-' || v_annee || '-' || lpad(v_val::text, 5, '0');
end; $$;
revoke execute on function public.prochain_numero(text) from public, anon, authenticated;

-- envoi d'une facture à la fonction Edge facture-envoyer (secret partagé)
create or replace function public.envoyer_facture(p_facture_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_anon text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;
  if v_secret is null then
    update public.factures set envoi_erreur = 'Secret NOTIFIER_SECRET introuvable' where id = p_facture_id;
    return;
  end if;
  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/facture-envoyer',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('facture_id', p_facture_id::text)
  );
end; $$;
revoke execute on function public.envoyer_facture(uuid) from public, anon, authenticated;

-- création d'une facture (figée) à partir d'un paiement
create or replace function public.creer_facture(p_paiement uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  p public.paiements%rowtype;
  v_numero text;
  v_facture_id uuid;
  v_vendeur jsonb;
  v_etab public.etablissements%rowtype;
  v_profil public.profiles%rowtype;
  v_designation text;
begin
  select * into p from public.paiements where id = p_paiement;
  if not found then return; end if;
  if p.mode = 'offert' then return; end if;

  -- vendeur : réglages obligatoires (sinon on bloque l'encaissement)
  v_vendeur := jsonb_build_object(
    'nom', (select value from public.settings where key = 'vendeur_nom'),
    'adresse', (select value from public.settings where key = 'vendeur_adresse'),
    'siret', (select value from public.settings where key = 'vendeur_siret'),
    'mention_tva', coalesce((select value from public.settings where key = 'mention_tva'), 'TVA non applicable, art. 293 B du CGI')
  );
  if v_vendeur->>'nom' is null or v_vendeur->>'nom' = ''
     or v_vendeur->>'adresse' is null or v_vendeur->>'adresse' = ''
     or v_vendeur->>'siret' is null or v_vendeur->>'siret' = '' then
    raise exception 'Complète tes informations de vendeur dans Réglages → Mentions sur les factures avant d''encaisser';
  end if;

  select * into v_profil from public.profiles where id = p.profil_id;
  select * into v_etab from public.etablissements where id = p.profil_id;

  v_numero := public.prochain_numero('facture');
  v_designation := 'Abonnement DamUp — période du ' || to_char(p.periode_debut at time zone 'Europe/Paris', 'DD/MM/YYYY')
                   || ' au ' || to_char(p.periode_fin at time zone 'Europe/Paris', 'DD/MM/YYYY');

  insert into public.factures (numero, type, paiement_id, profil_id, vendeur, client, lignes, total, mode_paiement, acquittee_le)
  values (
    v_numero, 'facture', p.id, p.profil_id,
    v_vendeur,
    jsonb_build_object('nom', v_etab.nom, 'adresse', v_etab.adresse, 'siret', v_etab.siret, 'email', v_profil.email),
    jsonb_build_array(jsonb_build_object('designation', v_designation, 'periode', v_designation, 'quantite', 1, 'prix_unitaire', p.montant, 'total', p.montant)),
    p.montant, p.mode, p.created_at
  )
  returning id into v_facture_id;

  perform public.envoyer_facture(v_facture_id);
end; $$;
revoke execute on function public.creer_facture(uuid) from public, anon, authenticated;

-- déclencheur : chaque paiement (sauf offert) crée une facture
create or replace function public.creer_facture_trigger() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.mode <> 'offert' then
    perform public.creer_facture(new.id);
  end if;
  return new;
end; $$;
drop trigger if exists creer_facture_trigger on public.paiements;
create trigger creer_facture_trigger after insert on public.paiements
for each row execute function public.creer_facture_trigger();
revoke execute on function public.creer_facture_trigger() from public, anon, authenticated;

-- annulation d'un paiement : la facture reste, un avoir est créé
create or replace function public.admin_annuler_paiement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_p public.paiements%rowtype;
  v_facture public.factures%rowtype;
  v_avoir_id uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select * into v_p from public.paiements where id = p_id and mode in ('especes', 'offert');
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

-- bucket Storage privé pour les PDF de factures
insert into storage.buckets (id, name, public) values ('factures', 'factures', false)
on conflict (id) do nothing;

-- accès Storage aux PDF : admin ou titulaire du dossier <profil_id>/
drop policy if exists "factures_lecture_storage" on storage.objects;
create policy "factures_lecture_storage" on storage.objects for select to authenticated
  using (bucket_id = 'factures'
         and (public.is_admin() or (storage.foldername(name))[1] = auth.uid()::text));
