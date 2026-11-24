-- ============================================================
--  DamUp : Espace client privé — fonctions serveur (s16)
--  Client (anon, par code) + Admin (authentifié, par droits).
-- ============================================================

-- ---------- helpers ----------
create or replace function public.normaliser_code(p_code text)
returns text language sql immutable as $$
  select upper(replace(replace(trim(coalesce(p_code, '')), ' ', ''), '-', ''));
$$;

-- ============ FONCTIONS CLIENT (anon, par code) ============

-- valider un code → info client + session
create or replace function public.espace_client_valider_code(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
  cl public.clients%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null then return jsonb_build_object('valide', false); end if;
  if c.statut <> 'actif' then return jsonb_build_object('valide', false); end if;
  if c.valide_jusqu_au is not null and now() > c.valide_jusqu_au then
    update public.codes_acces set statut = 'expire' where id = c.id;
    return jsonb_build_object('valide', false);
  end if;
  select * into cl from public.clients where id = c.client_id;
  if cl.id is null or cl.statut <> 'actif' then return jsonb_build_object('valide', false); end if;
  if c.date_premiere_utilisation is null then
    update public.codes_acces set date_premiere_utilisation = now() where id = c.id;
  end if;
  return jsonb_build_object(
    'valide', true, 'code_id', c.id, 'client_id', cl.id,
    'prenom', cl.prenom, 'date_soiree', c.date_soiree, 'majeur_confirme', cl.majeur_confirme
  );
end; $$;

-- confirmer 18 ans + acceptation des conditions (horodaté)
create or replace function public.espace_client_confirmer_majeur(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null or c.statut <> 'actif' then return jsonb_build_object('ok', false); end if;
  update public.clients set majeur_confirme = true, majeur_confirme_le = now() where id = c.client_id;
  return jsonb_build_object('ok', true);
end; $$;

-- données : établissements visibles + hôtesses du soir + bouteilles + avantage
create or replace function public.espace_client_donnees(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null or c.statut <> 'actif' then return jsonb_build_object('valide', false); end if;
  return jsonb_build_object(
    'valide', true,
    'date_soiree', c.date_soiree,
    'etablissements', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'nom', e.nom, 'type', e.type, 'ville', e.ville, 'adresse', e.adresse, 'photos', e.photos,
        'seuil_depense_eur', a.seuil_depense_eur, 'pourcentage_client', a.pourcentage_client,
        'bouteille_obligatoire', a.bouteille_obligatoire,
        'bouteilles', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'nom', b.nom, 'categorie', b.categorie, 'contenance_cl', b.contenance_cl, 'prix_eur', b.prix_eur) order by b.categorie, b.prix_eur) from public.bouteilles b where b.etablissement_id = e.id and b.disponible), '[]'::jsonb),
        'hotesses', coalesce((select jsonb_agg(h) from (
          select distinct on (hh.id) jsonb_build_object('id', hh.id, 'prenom', hh.prenom, 'photo', hh.photos->0) as h
          from public.hotesses hh
          join public.candidatures cd on cd.hotesse_id = hh.id
          join public.missions m on m.id = cd.mission_id
          join public.profiles p on p.id = hh.id
          where m.etablissement_id = e.id
            and m.date = c.date_soiree
            and cd.statut = 'confirmee' and not cd.annulation
            and not p.suspendu
          order by hh.id
        ) t), '[]'::jsonb)
      ) order by e.nom)
      from public.etablissements e
      join public.avantages_etablissement a on a.etablissement_id = e.id
      where a.actif and e.verifie
    ), '[]'::jsonb)
  );
end; $$;

-- simulateur de remboursement
create or replace function public.espace_client_simuler(p_code text, p_etablissement_id uuid, p_montant numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
  a public.avantages_etablissement%rowtype;
  v_remb numeric := 0;
  v_manque numeric := 0;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null or c.statut <> 'actif' then return jsonb_build_object('valide', false); end if;
  select * into a from public.avantages_etablissement where etablissement_id = p_etablissement_id and actif;
  if a.etablissement_id is null then return jsonb_build_object('valide', false); end if;
  if p_montant >= coalesce(a.seuil_depense_eur, 0) then
    v_remb := round(p_montant * coalesce(a.pourcentage_client, 0) / 100, 2);
  else
    v_manque := round(coalesce(a.seuil_depense_eur, 0) - p_montant, 2);
  end if;
  return jsonb_build_object('valide', true, 'montant', p_montant, 'rembourse', v_remb, 'manque', v_manque);
end; $$;

-- créer une réservation
create or replace function public.espace_client_reserver(
  p_code text, p_etablissement_id uuid, p_heure_arrivee text, p_nb_personnes int, p_bouteille_id uuid, p_message text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
  cl public.clients%rowtype;
  a public.avantages_etablissement%rowtype;
  v_id uuid;
  v_heure time;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null then return jsonb_build_object('ok', false, 'erreur', 'Code invalide ou expiré.'); end if;
  if c.statut <> 'actif' then return jsonb_build_object('ok', false, 'erreur', 'Code invalide ou expiré.'); end if;
  if c.valide_jusqu_au is not null and now() > c.valide_jusqu_au then
    update public.codes_acces set statut = 'expire' where id = c.id;
    return jsonb_build_object('ok', false, 'erreur', 'Code invalide ou expiré.');
  end if;
  select * into cl from public.clients where id = c.client_id;
  if cl.statut <> 'actif' then return jsonb_build_object('ok', false, 'erreur', 'Compte non autorisé.'); end if;

  select * into a from public.avantages_etablissement where etablissement_id = p_etablissement_id and actif;
  if a.etablissement_id is null then return jsonb_build_object('ok', false, 'erreur', 'Établissement indisponible.'); end if;

  -- heure au format HH:MM (tranches de 30 min)
  begin
    v_heure := p_heure_arrivee::time;
  exception when others then
    return jsonb_build_object('ok', false, 'erreur', 'Heure invalide.');
  end;
  if extract(minute from v_heure) not in (0, 30) then
    return jsonb_build_object('ok', false, 'erreur', 'Heure par tranches de 30 minutes.');
  end if;
  if p_nb_personnes < 1 or p_nb_personnes > 20 then
    return jsonb_build_object('ok', false, 'erreur', 'Nombre de personnes entre 1 et 20.');
  end if;

  -- bouteille obligatoire si club
  if a.bouteille_obligatoire and p_bouteille_id is null then
    return jsonb_build_object('ok', false, 'erreur', 'Choisissez une bouteille.');
  end if;
  if p_bouteille_id is not null then
    if not exists (select 1 from public.bouteilles where id = p_bouteille_id and etablissement_id = p_etablissement_id and disponible) then
      return jsonb_build_object('ok', false, 'erreur', 'Bouteille invalide.');
    end if;
  end if;

  insert into public.reservations (client_id, code_acces_id, etablissement_id, date_soiree, heure_arrivee, nb_personnes, bouteille_id, message_client)
  values (cl.id, c.id, p_etablissement_id, c.date_soiree, v_heure, p_nb_personnes, p_bouteille_id, nullif(trim(p_message), ''))
  returning id into v_id;
  return jsonb_build_object('ok', true, 'reservation_id', v_id);
end; $$;

-- mes réservations (toutes soirées confondues, par client)
create or replace function public.espace_client_mes_reservations(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null then return jsonb_build_object('valide', false); end if;
  return jsonb_build_object('valide', true, 'reservations', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', r.id, 'date_soiree', r.date_soiree, 'heure_arrivee', r.heure_arrivee, 'nb_personnes', r.nb_personnes,
      'statut', r.statut, 'motif_refus', r.motif_refus,
      'etablissement', (select nom from public.etablissements where id = r.etablissement_id),
      'etablissement_type', (select type from public.etablissements where id = r.etablissement_id),
      'bouteille', (select nom from public.bouteilles where id = r.bouteille_id),
      'remboursement', (select montant_a_rembourser from public.remboursements where reservation_id = r.id)
    ) order by r.date_soiree desc, r.date_creation desc)
    from public.reservations r where r.client_id = c.client_id
  ), '[]'::jsonb));
end; $$;

-- envoyer la photo de facture + coordonnées de paiement (écran remboursement)
create or replace function public.espace_client_envoyer_facture(
  p_code text, p_reservation_id uuid, p_photo_facture text, p_moyen_paiement text, p_coordonnees text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
  r public.reservations%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null then return jsonb_build_object('ok', false, 'erreur', 'Code invalide.'); end if;
  select * into r from public.reservations where id = p_reservation_id and client_id = c.client_id;
  if r.id is null then return jsonb_build_object('ok', false, 'erreur', 'Réservation introuvable.'); end if;
  if p_moyen_paiement not in ('virement', 'wero', 'lydia') then
    return jsonb_build_object('ok', false, 'erreur', 'Moyen de paiement invalide.');
  end if;
  update public.remboursements
     set photo_facture = p_photo_facture, moyen_paiement = p_moyen_paiement, coordonnees_paiement = p_coordonnees,
         statut = case when statut = 'en_attente_justificatifs' then 'a_valider' else statut end
   where reservation_id = p_reservation_id;
  return jsonb_build_object('ok', true);
end; $$;

-- fonctions client appelables sans compte
grant execute on function public.espace_client_valider_code(text) to anon, authenticated;
grant execute on function public.espace_client_confirmer_majeur(text) to anon, authenticated;
grant execute on function public.espace_client_donnees(text) to anon, authenticated;
grant execute on function public.espace_client_simuler(text, uuid, numeric) to anon, authenticated;
grant execute on function public.espace_client_reserver(text, uuid, text, int, uuid, text) to anon, authenticated;
grant execute on function public.espace_client_mes_reservations(text) to anon, authenticated;
grant execute on function public.espace_client_envoyer_facture(text, uuid, text, text, text) to anon, authenticated;

-- ============ FONCTIONS ADMIN ============

-- ---- clients ----
create or replace function public.admin_creer_client(p_prenom text, p_nom text, p_telephone text, p_email text default null)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  insert into public.clients (prenom, nom, telephone, email)
  values (nullif(trim(p_prenom), ''), nullif(trim(p_nom), ''), nullif(trim(p_telephone), ''), nullif(trim(p_email), ''))
  returning id into v_id;
  return v_id;
end; $$;

create or replace function public.admin_lister_clients()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'prenom', c.prenom, 'nom', c.nom, 'telephone', c.telephone, 'email', c.email,
    'majeur_confirme', c.majeur_confirme, 'statut', c.statut, 'nb_no_show', c.nb_no_show, 'notes_admin', c.notes_admin
  ) order by c.date_creation desc) from public.clients c), '[]'::jsonb);
end; $$;

create or replace function public.admin_statut_client(p_client uuid, p_statut text, p_notes text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('suspendre_utilisateurs') then raise exception 'Droit insuffisant.'; end if;
  if p_statut not in ('actif', 'suspendu', 'banni') then raise exception 'Statut invalide.'; end if;
  update public.clients set statut = p_statut, notes_admin = coalesce(p_notes, notes_admin) where id = p_client;
  if p_statut = 'banni' then
    update public.codes_acces set statut = 'revoque' where client_id = p_client and statut = 'actif';
    update public.reservations set statut = 'annulee'
     where client_id = p_client and statut in ('en_attente', 'transmise', 'confirmee');
  end if;
end; $$;

-- ---- codes ----
create or replace function public.admin_creer_code(p_client uuid, p_date_soiree date)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_client public.clients%rowtype;
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  select * into v_client from public.clients where id = p_client;
  if v_client.id is null then raise exception 'Client introuvable.'; end if;
  if v_client.statut in ('suspendu', 'banni') then raise exception 'Client suspendu ou banni : impossible de créer un code.'; end if;
  loop
    v_code := 'DAMUP-' || (select string_agg(substr('ABCDEFGHJKMNPQRSTUVWXYZ23456789', (floor(random()*32))::int + 1, 1), '') from generate_series(1,6));
    exit when not exists (select 1 from public.codes_acces where code = v_code);
  end loop;
  insert into public.codes_acces (code, client_id, date_soiree, valide_du, valide_jusqu_au)
  values (v_code, p_client, p_date_soiree, now(), (p_date_soiree::timestamp + interval '1 day 6 hours') at time zone 'Europe/Paris');
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
    'id', c.id, 'code', c.code, 'date_soiree', c.date_soiree, 'statut', c.statut,
    'valide_jusqu_au', c.valide_jusqu_au, 'nb_essais_echoues', c.nb_essais_echoues,
    'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients where id = c.client_id),
    'client_id', c.client_id
  ) order by c.cree_le desc) from public.codes_acces c), '[]'::jsonb);
end; $$;

create or replace function public.admin_revoquer_code(p_code uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  update public.codes_acces set statut = 'revoque' where id = p_code;
end; $$;

-- ---- avantages (établissements) ----
create or replace function public.admin_lister_avantages()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', e.id, 'nom', e.nom, 'type', e.type, 'ville', e.ville,
    'actif', coalesce(a.actif, false),
    'seuil_depense_eur', a.seuil_depense_eur, 'pourcentage_client', a.pourcentage_client,
    'pourcentage_commission', a.pourcentage_commission, 'bouteille_obligatoire', coalesce(a.bouteille_obligatoire, false),
    'bouteilles', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'nom', b.nom, 'categorie', b.categorie, 'contenance_cl', b.contenance_cl, 'prix_eur', b.prix_eur, 'disponible', b.disponible) order by b.ordre) from public.bouteilles b where b.etablissement_id = e.id), '[]'::jsonb)
  ) order by e.nom)
  from public.etablissements e
  left join public.avantages_etablissement a on a.etablissement_id = e.id
  where e.type in ('club','restaurant','bar','lounge')), '[]'::jsonb);
end; $$;

create or replace function public.admin_regler_avantage(
  p_etablissement uuid, p_actif boolean, p_seuil numeric, p_pct_client numeric, p_pct_commission numeric, p_bouteille_obligatoire boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  insert into public.avantages_etablissement (etablissement_id, seuil_depense_eur, pourcentage_client, pourcentage_commission, bouteille_obligatoire, actif)
  values (p_etablissement, nullif(p_seuil, 0), nullif(p_pct_client, 0), nullif(p_pct_commission, 0), coalesce(p_bouteille_obligatoire, false), p_actif)
  on conflict (etablissement_id) do update
    set seuil_depense_eur = excluded.seuil_depense_eur, pourcentage_client = excluded.pourcentage_client,
        pourcentage_commission = excluded.pourcentage_commission, bouteille_obligatoire = excluded.bouteille_obligatoire, actif = excluded.actif;
end; $$;

-- ---- bouteilles ----
create or replace function public.admin_ajouter_bouteille(p_etablissement uuid, p_nom text, p_categorie text, p_contenance integer, p_prix numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  insert into public.bouteilles (etablissement_id, nom, categorie, contenance_cl, prix_eur, ordre)
  values (p_etablissement, nullif(trim(p_nom), ''), nullif(trim(p_categorie), ''), p_contenance, p_prix, coalesce((select max(ordre) + 1 from public.bouteilles where etablissement_id = p_etablissement), 0));
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

create or replace function public.admin_basculer_bouteille(p_bouteille uuid, p_disponible boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('reglages') then raise exception 'Droit insuffisant.'; end if;
  update public.bouteilles set disponible = p_disponible where id = p_bouteille;
end; $$;

-- ---- réservations ----
create or replace function public.admin_lister_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', r.id, 'date_soiree', r.date_soiree, 'heure_arrivee', r.heure_arrivee, 'nb_personnes', r.nb_personnes,
    'statut', r.statut, 'motif_refus', r.motif_refus, 'message_client', r.message_client,
    'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients where id = r.client_id),
    'etablissement', (select nom from public.etablissements where id = r.etablissement_id),
    'etablissement_type', (select type from public.etablissements where id = r.etablissement_id),
    'bouteille', (select nom from public.bouteilles where id = r.bouteille_id),
    'bouteille_prix', (select prix_eur from public.bouteilles where id = r.bouteille_id)
  ) order by r.date_creation desc) from public.reservations r), '[]'::jsonb);
end; $$;

create or replace function public.admin_traiter_reservation(p_reservation uuid, p_action text, p_motif text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations%rowtype;
  a public.avantages_etablissement%rowtype;
  v_remb numeric;
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  select * into r from public.reservations where id = p_reservation;
  if r.id is null then return jsonb_build_object('ok', false, 'erreur', 'Réservation introuvable.'); end if;

  if p_action = 'transmettre' then
    if r.statut <> 'en_attente' then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'transmise', date_transmission = now() where id = p_reservation;
  elsif p_action = 'confirmer' then
    if r.statut <> 'transmise' then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'confirmee', date_confirmation = now() where id = p_reservation;
  elsif p_action = 'refuser' then
    if r.statut not in ('en_attente', 'transmise') then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'refusee', motif_refus = p_motif where id = p_reservation;
  elsif p_action = 'terminer' then
    if r.statut <> 'confirmee' then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'terminee' where id = p_reservation;
    -- créer remboursement + commission en copiant les réglages du jour
    select * into a from public.avantages_etablissement where etablissement_id = r.etablissement_id;
    insert into public.remboursements (reservation_id, seuil_applique, pourcentage_applique)
    values (p_reservation, a.seuil_depense_eur, a.pourcentage_client);
    insert into public.commissions (reservation_id, etablissement_id, pourcentage_applique)
    values (p_reservation, r.etablissement_id, a.pourcentage_commission);
  elsif p_action = 'no_show' then
    if r.statut <> 'confirmee' then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'no_show' where id = p_reservation;
    -- incrémenter nb_no_show + suspension auto à 2
    update public.clients set nb_no_show = nb_no_show + 1 where id = r.client_id;
    if (select nb_no_show from public.clients where id = r.client_id) >= 2 then
      update public.clients set statut = 'suspendu' where id = r.client_id;
    end if;
  elsif p_action = 'annuler' then
    if r.statut in ('terminee', 'no_show', 'refusee', 'annulee') then return jsonb_build_object('ok', false, 'erreur', 'Transition refusée.'); end if;
    update public.reservations set statut = 'annulee' where id = p_reservation;
  else
    return jsonb_build_object('ok', false, 'erreur', 'Action inconnue.');
  end if;
  return jsonb_build_object('ok', true);
end; $$;

-- annulation par le client
create or replace function public.espace_client_annuler(p_code text, p_reservation uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  c public.codes_acces%rowtype;
  r public.reservations%rowtype;
begin
  select * into c from public.codes_acces where replace(code, '-', '') = public.normaliser_code(p_code);
  if c.id is null then return jsonb_build_object('ok', false); end if;
  select * into r from public.reservations where id = p_reservation and client_id = c.client_id;
  if r.id is null then return jsonb_build_object('ok', false); end if;
  if r.statut in ('terminee', 'no_show', 'refusee', 'annulee') then return jsonb_build_object('ok', false); end if;
  update public.reservations set statut = 'annulee' where id = p_reservation;
  return jsonb_build_object('ok', true);
end; $$;
grant execute on function public.espace_client_annuler(text, uuid) to anon, authenticated;

-- ---- remboursements ----
create or replace function public.admin_lister_remboursements()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', rb.id, 'reservation_id', rb.reservation_id, 'statut', rb.statut,
    'montant_declare_etablissement', rb.montant_declare_etablissement, 'montant_retenu', rb.montant_retenu,
    'seuil_applique', rb.seuil_applique, 'pourcentage_applique', rb.pourcentage_applique,
    'montant_a_rembourser', rb.montant_a_rembourser, 'moyen_paiement', rb.moyen_paiement,
    'coordonnees_paiement', rb.coordonnees_paiement, 'photo_facture', rb.photo_facture,
    'date_virement', rb.date_virement, 'reference_virement', rb.reference_virement,
    'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients cl join public.reservations r on r.client_id = cl.id where r.id = rb.reservation_id),
    'etablissement', (select nom from public.etablissements e join public.reservations r on r.etablissement_id = e.id where r.id = rb.reservation_id)
  ) order by rb.created_at desc) from public.remboursements rb), '[]'::jsonb);
end; $$;

-- l'établissement (ou l'admin) déclare le montant réellement dépensé
create or replace function public.admin_declarer_depense(p_reservation uuid, p_montant numeric)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r public.reservations%rowtype;
  rb public.remboursements%rowtype;
  v_remb numeric := 0;
  v_statut text;
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  select * into r from public.reservations where id = p_reservation;
  if r.id is null then return jsonb_build_object('ok', false); end if;
  select * into rb from public.remboursements where reservation_id = p_reservation;
  if rb.id is null then return jsonb_build_object('ok', false, 'erreur', 'Aucune ligne de remboursement.'); end if;
  -- montant retenu = celui de l'établissement
  if p_montant >= coalesce(rb.seuil_applique, 0) then
    v_remb := round(p_montant * coalesce(rb.pourcentage_applique, 0) / 100, 2);
    v_statut := 'a_valider';
  else
    v_remb := 0;
    v_statut := 'non_eligible';
  end if;
  update public.remboursements set montant_declare_etablissement = p_montant, montant_retenu = p_montant, montant_a_rembourser = v_remb, statut = v_statut where id = rb.id;
  update public.commissions set montant_depense = p_montant, montant_commission = round(p_montant * coalesce(pourcentage_applique, 0) / 100, 2) where reservation_id = p_reservation;
  return jsonb_build_object('ok', true, 'remboursement', v_remb, 'statut', v_statut);
end; $$;

-- valider / refuser / marquer payé un remboursement
create or replace function public.admin_traiter_remboursement(p_remboursement uuid, p_action text, p_motif text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare rb public.remboursements%rowtype;
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  select * into rb from public.remboursements where id = p_remboursement;
  if p_action = 'valider' then
    if rb.statut not in ('a_valider', 'ecart') then raise exception 'Transition refusée.'; end if;
    update public.remboursements set statut = 'valide' where id = p_remboursement;
  elsif p_action = 'payer' then
    if rb.statut <> 'valide' then raise exception 'Valider d''abord.'; end if;
    update public.remboursements set statut = 'rembourse', date_virement = now(), reference_virement = p_motif where id = p_remboursement;
  elsif p_action = 'refuser' then
    update public.remboursements set statut = 'refuse' where id = p_remboursement;
  else
    raise exception 'Action inconnue.';
  end if;
end; $$;

-- ---- commissions ----
create or replace function public.admin_lister_commissions()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', c.id, 'etablissement', (select nom from public.etablissements where id = c.etablissement_id),
    'montant_depense', c.montant_depense, 'pourcentage_applique', c.pourcentage_applique,
    'montant_commission', c.montant_commission, 'statut', c.statut, 'date_reception', c.date_reception
  ) order by c.created_at desc) from public.commissions c), '[]'::jsonb);
end; $$;

create or replace function public.admin_statut_commission(p_commission uuid, p_statut text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  if p_statut not in ('a_facturer', 'facturee', 'recue') then raise exception 'Statut invalide.'; end if;
  update public.commissions set statut = p_statut, date_reception = case when p_statut = 'recue' then now() else date_reception end where id = p_commission;
end; $$;

-- ---- signalements clients ----
create or replace function public.signaler_client(p_client uuid, p_reservation uuid, p_motif text, p_description text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_type text;
begin
  select type into v_type from public.profiles where id = auth.uid();
  if v_type not in ('hotesse', 'etablissement', 'admin') then raise exception 'Non autorisé.'; end if;
  insert into public.signalements_clients (client_id, reservation_id, auteur_type, auteur_id, motif, description)
  values (p_client, p_reservation, v_type, auth.uid(), p_motif, p_description);
end; $$;
grant execute on function public.signaler_client(uuid, uuid, text, text) to authenticated;

create or replace function public.admin_lister_signalements_clients()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('signalements') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', s.id, 'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients where id = s.client_id),
    'client_id', s.client_id, 'auteur_type', s.auteur_type, 'motif', s.motif, 'description', s.description,
    'statut', s.statut, 'decision', s.decision, 'created_at', s.created_at
  ) order by s.created_at desc) from public.signalements_clients s), '[]'::jsonb);
end; $$;

create or replace function public.admin_traiter_signalement_client(p_signalement uuid, p_decision text, p_statut_client text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare s public.signalements_clients%rowtype;
begin
  if not public.a_le_droit('signalements') then raise exception 'Droit insuffisant.'; end if;
  select * into s from public.signalements_clients where id = p_signalement;
  update public.signalements_clients set statut = 'traite', decision = p_decision where id = p_signalement;
  if p_statut_client in ('actif', 'suspendu', 'banni') then
    update public.clients set statut = p_statut_client where id = s.client_id;
    if p_statut_client = 'banni' then
      update public.codes_acces set statut = 'revoque' where client_id = s.client_id and statut = 'actif';
      update public.reservations set statut = 'annulee' where client_id = s.client_id and statut in ('en_attente', 'transmise', 'confirmee');
    end if;
  end if;
end; $$;

-- ---- grants admin ----
grant execute on function public.admin_creer_client(text, text, text, text) to authenticated;
grant execute on function public.admin_lister_clients() to authenticated;
grant execute on function public.admin_statut_client(uuid, text, text) to authenticated;
grant execute on function public.admin_creer_code(uuid, date) to authenticated;
grant execute on function public.admin_lister_codes() to authenticated;
grant execute on function public.admin_revoquer_code(uuid) to authenticated;
grant execute on function public.admin_lister_avantages() to authenticated;
grant execute on function public.admin_regler_avantage(uuid, boolean, numeric, numeric, numeric, boolean) to authenticated;
grant execute on function public.admin_ajouter_bouteille(uuid, text, text, integer, numeric) to authenticated;
grant execute on function public.admin_supprimer_bouteille(uuid) to authenticated;
grant execute on function public.admin_basculer_bouteille(uuid, boolean) to authenticated;
grant execute on function public.admin_lister_reservations() to authenticated;
grant execute on function public.admin_traiter_reservation(uuid, text, text) to authenticated;
grant execute on function public.admin_lister_remboursements() to authenticated;
grant execute on function public.admin_declarer_depense(uuid, numeric) to authenticated;
grant execute on function public.admin_traiter_remboursement(uuid, text, text) to authenticated;
grant execute on function public.admin_lister_commissions() to authenticated;
grant execute on function public.admin_statut_commission(uuid, text) to authenticated;
grant execute on function public.admin_lister_signalements_clients() to authenticated;
grant execute on function public.admin_traiter_signalement_client(uuid, text, text) to authenticated;
