-- ============================================================
--  E2 : Appliquer les droits réels (remplace is_admin() par a_le_droit())
-- ============================================================

-- ---- Annuaires (voir_donnees) ----
drop function if exists public.admin_annuaire_hotesses();
create or replace function public.admin_annuaire_hotesses()
returns table (id uuid, prenom text, age int, ville text, email text, instagram text, telephone text,
               verifie boolean, suspendu boolean, note_moyenne numeric, nb_avis int, signes_negatifs int,
               missions_honorees bigint, inscrite_le timestamptz, tarif numeric, periode text, actif_jusqu_a timestamptz, photos jsonb)
language sql stable security definer set search_path = public as $$
  select h.id, h.prenom, h.age, h.ville, p.email, h.instagram, h.telephone,
         h.verifie, p.suspendu, h.note_moyenne, h.nb_avis, h.signes_negatifs,
         (select count(*) from public.candidatures c where c.hotesse_id = h.id and c.presente_a is not null),
         h.created_at, p.tarif, p.periode, p.actif_jusqu_a, h.photos
    from public.hotesses h join public.profiles p on p.id = h.id
   where public.a_le_droit('voir_donnees')
   order by h.created_at desc;
$$;

drop function if exists public.admin_annuaire_etablissements();
create or replace function public.admin_annuaire_etablissements()
returns table (id uuid, nom text, type text, ville text, adresse text, email text, siret text,
               verifie boolean, suspendu boolean, missions_publiees bigint, inscrit_le timestamptz,
               tarif numeric, periode text, actif_jusqu_a timestamptz, dernier_mode text, reference_virement text, photos jsonb, videos jsonb)
language sql stable security definer set search_path = public as $$
  select e.id, e.nom, e.type, e.ville, e.adresse, p.email, e.siret, e.verifie, p.suspendu,
         (select count(*) from public.missions m where m.etablissement_id = e.id),
         e.created_at, p.tarif, p.periode, p.actif_jusqu_a,
         (select pa.mode from public.paiements pa where pa.profil_id = e.id order by pa.created_at desc limit 1),
         p.reference_virement, e.photos, e.videos
    from public.etablissements e join public.profiles p on p.id = e.id
   where public.a_le_droit('voir_donnees')
   order by e.created_at desc;
$$;
revoke execute on function public.admin_annuaire_hotesses(), public.admin_annuaire_etablissements() from anon;

-- ---- Paiements (paiements) ----
create or replace function public.admin_enregistrer_paiement(
  p_profil uuid, p_mode text, p_periode text, p_montant numeric,
  p_date date default null, p_note text default null)
returns public.paiements language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('paiements') then raise exception 'Droit insuffisant.'; end if;
  if p_mode not in ('especes', 'virement', 'offert') then raise exception 'Mode non autorisé ici.'; end if;
  if p_periode not in ('hebdomadaire', 'mensuel') then raise exception 'Période invalide.'; end if;
  if p_mode in ('especes', 'virement') and (p_montant is null or p_montant <= 0) then raise exception 'Montant invalide.'; end if;
  perform public.journaliser('paiement_enregistre', 'profil', p_profil, jsonb_build_object('mode', p_mode, 'montant', p_montant));
  return public.prolonger_abonnement(
    p_profil, case when p_mode = 'offert' then 0 else p_montant end, p_mode, p_periode,
    coalesce(p_date::timestamp at time zone 'Europe/Paris', now()), null, p_note);
end; $$;
revoke execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) from public, anon;
grant execute on function public.admin_enregistrer_paiement(uuid, text, text, numeric, date, text) to authenticated;

create or replace function public.admin_annuler_paiement(p_id uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_p public.paiements%rowtype;
  v_facture public.factures%rowtype;
  v_avoir_id uuid;
begin
  if not public.a_le_droit('paiements') then raise exception 'Droit insuffisant.'; end if;
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
  perform public.journaliser('paiement_annule', 'profil', v_p.profil_id, jsonb_build_object('paiement', p_id));
end; $$;
revoke execute on function public.admin_annuler_paiement(uuid) from public, anon;
grant execute on function public.admin_annuler_paiement(uuid) to authenticated;

create or replace function public.admin_offrir_periode_groupe(p_type text, p_jours int) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.a_le_droit('paiements') then raise exception 'Droit insuffisant.'; end if;
  if p_type not in ('etablissement', 'hotesse') or p_jours not between 1 and 90 then raise exception 'Paramètres invalides.'; end if;
  update public.profiles set actif_jusqu_a = now() + make_interval(days => p_jours), rappel_fin_envoye_pour = null
   where type = p_type and (actif_jusqu_a is null or actif_jusqu_a < now());
  get diagnostics n = row_count;
  perform public.journaliser('periode_offerte_groupe', null, null, jsonb_build_object('type', p_type, 'jours', p_jours, 'n', n));
  return n;
end; $$;
revoke execute on function public.admin_offrir_periode_groupe(text, int) from public, anon;
grant execute on function public.admin_offrir_periode_groupe(text, int) to authenticated;

-- ---- Validation / refus (valider_profils) ----
create or replace function public.admin_refuser_profil(p_profil uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if not public.a_le_droit('valider_profils') then raise exception 'Droit insuffisant.'; end if;
  select type into v_type from public.profiles where id = p_profil;
  if v_type = 'hotesse' then
    update public.hotesses set verifie = false where id = p_profil;
  elsif v_type = 'etablissement' then
    update public.etablissements set verifie = false where id = p_profil;
  else
    raise exception 'Profil introuvable.';
  end if;
  perform public.journaliser('profil_refuse', 'profil', p_profil, jsonb_build_object('motif', p_motif));
  perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee', jsonb_build_object('motif', coalesce(p_motif, '')));
end; $$;
revoke execute on function public.admin_refuser_profil(uuid, text) from public, anon;
grant execute on function public.admin_refuser_profil(uuid, text) to authenticated;

create or replace function public.admin_valider_identite(p_profil uuid, p_type text, p_valide boolean, p_motif text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('valider_profils') then raise exception 'Droit insuffisant.'; end if;
  if p_type = 'hotesse' then
    update public.hotesses set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null where id = p_profil;
  else
    update public.etablissements set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null where id = p_profil;
  end if;
  perform public.journaliser(case when p_valide then 'identite_validee' else 'identite_refusee' end, 'profil', p_profil, jsonb_build_object('motif', p_motif));
  if not p_valide then
    perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee', jsonb_build_object('motif', coalesce(p_motif, '')));
  end if;
end; $$;
revoke execute on function public.admin_valider_identite(uuid, text, boolean, text) from public, anon;
grant execute on function public.admin_valider_identite(uuid, text, boolean, text) to authenticated;

-- validation simple (hôtesse / établissement)
create or replace function public.admin_valider_profil(p_profil uuid, p_type text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('valider_profils') then raise exception 'Droit insuffisant.'; end if;
  if p_type = 'hotesse' then
    update public.hotesses set verifie = true where id = p_profil;
  elsif p_type = 'etablissement' then
    update public.etablissements set verifie = true where id = p_profil;
  else
    raise exception 'Type invalide.';
  end if;
  perform public.journaliser('profil_valide', 'profil', p_profil);
end; $$;
revoke execute on function public.admin_valider_profil(uuid, text) from public, anon;
grant execute on function public.admin_valider_profil(uuid, text) to authenticated;

-- ---- Suspension (suspendre_utilisateurs) ----
create or replace function public.admin_suspendre_compte(p_profil uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('suspendre_utilisateurs') then raise exception 'Droit insuffisant.'; end if;
  update public.profiles set suspendu = true where id = p_profil;
  perform public.journaliser('compte_suspendu', 'profil', p_profil);
end; $$;
revoke execute on function public.admin_suspendre_compte(uuid) from public, anon;
grant execute on function public.admin_suspendre_compte(uuid) to authenticated;

create or replace function public.admin_reactiver_compte(p_profil uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('suspendre_utilisateurs') then raise exception 'Droit insuffisant.'; end if;
  update public.profiles set suspendu = false where id = p_profil;
  perform public.journaliser('compte_reactivé', 'profil', p_profil);
end; $$;
revoke execute on function public.admin_reactiver_compte(uuid) from public, anon;
grant execute on function public.admin_reactiver_compte(uuid) to authenticated;

-- ---- Annulation de mission (gerer_missions) ----
create or replace function public.admin_annuler_mission(p_mission uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  if not public.a_le_droit('gerer_missions') then raise exception 'Droit insuffisant.'; end if;
  update public.missions set statut = 'annulee' where id = p_mission;
  select etablissement_id into v_etab from public.missions where id = p_mission;
  if v_etab is null then raise exception 'Mission introuvable.'; end if;
  perform public.journaliser('mission_annulee', 'mission', p_mission, jsonb_build_object('motif', p_motif));
  perform public.notifier_utilisateur(v_etab, 'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, '')));
  insert into public.notifications (user_id, message, cle, params)
  select c.hotesse_id, public.traduire('notif.mission_annulee_admin', coalesce(p.langue, 'fr'), jsonb_build_object('motif', coalesce(p_motif, ''))),
         'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, ''))
    from public.candidatures c join public.profiles p on p.id = c.hotesse_id
   where c.mission_id = p_mission and c.statut in ('acceptee', 'confirmee') and not c.annulation;
end; $$;
revoke execute on function public.admin_annuler_mission(uuid, text) from public, anon;
grant execute on function public.admin_annuler_mission(uuid, text) to authenticated;

-- ---- Sanction (suspendre_utilisateurs) ----
create or replace function public.admin_annuler_sanction(p_candidature uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_c public.candidatures%rowtype;
  v_signes int;
begin
  if not public.a_le_droit('suspendre_utilisateurs') then raise exception 'Droit insuffisant.'; end if;
  if p_motif is null or trim(p_motif) = '' then raise exception 'Motif obligatoire.'; end if;
  select * into v_c from public.candidatures where id = p_candidature;
  if v_c.id is null then raise exception 'Candidature introuvable.'; end if;
  if v_c.sanction_annulee_le is not null then raise exception 'Cette sanction a déjà été annulée.'; end if;
  v_signes := coalesce(v_c.sanction_signes, 0);
  if v_signes <= 0 then raise exception 'Aucune sanction à annuler sur cette candidature.'; end if;
  update public.candidatures set sanction_annulee_le = now() where id = p_candidature;
  update public.hotesses set signes_negatifs = greatest(0, signes_negatifs - v_signes) where id = v_c.hotesse_id;
  perform public.journaliser('sanction_annulee', 'candidature', p_candidature, jsonb_build_object('motif', p_motif));
  perform public.notifier_utilisateur(v_c.hotesse_id, 'notif.sanction_annulee', jsonb_build_object('motif', p_motif));
end; $$;
revoke execute on function public.admin_annuler_sanction(uuid, text) from public, anon;
grant execute on function public.admin_annuler_sanction(uuid, text) to authenticated;

-- ---- Conversation (signalements) ----
create or replace function public.admin_lire_conversation(p_signalement uuid)
returns setof public.messages language plpgsql security definer set search_path = public as $$
declare
  v_mission uuid;
  v_signalant uuid;
  v_cible_type text;
  v_cible uuid;
begin
  if not public.a_le_droit('signalements') then raise exception 'Droit insuffisant.'; end if;
  select signalant_id, cible_type, cible_id into v_signalant, v_cible_type, v_cible from public.signalements where id = p_signalement;
  if v_signalant is null then raise exception 'Signalement introuvable.'; end if;
  if v_cible_type = 'mission' then v_mission := v_cible;
  elsif v_cible_type = 'hotesse' then
    select m.id into v_mission from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_signalant and c.hotesse_id = v_cible limit 1;
  else
    select m.id into v_mission from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_cible and c.hotesse_id = v_signalant limit 1;
  end if;
  if v_mission is null then return; end if;
  perform public.journaliser('conversation_lue', 'signalement', p_signalement);
  return query select * from public.messages where mission_id = v_mission order by created_at;
end; $$;
revoke execute on function public.admin_lire_conversation(uuid) from public, anon;
grant execute on function public.admin_lire_conversation(uuid) to authenticated;

-- ---- Factures (voir_finances) ----
create or replace function public.admin_renvoyer_facture(p_facture_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('voir_finances') then raise exception 'Droit insuffisant.'; end if;
  update public.factures set envoyee_le = null, envoi_erreur = null where id = p_facture_id;
  perform public.envoyer_facture(p_facture_id);
end; $$;
revoke execute on function public.admin_renvoyer_facture(uuid) from public, anon;
grant execute on function public.admin_renvoyer_facture(uuid) to authenticated;

-- ---- RLS : lecture paiements / factures (côté admin) ----
drop policy if exists "paiements_admin_lecture" on public.paiements;
create policy "paiements_admin_lecture" on public.paiements for select
  using (public.a_le_droit('voir_finances') or public.a_le_droit('paiements') or profil_id = auth.uid());

-- ---- Écriture dans settings : reglages ----
drop policy if exists "settings_ecriture_reglages" on public.settings;
create policy "settings_ecriture_reglages" on public.settings for update to authenticated
  using (public.a_le_droit('reglages'));

-- ---- Storage : documents (lecture admin -> valider_profils) ----
drop policy if exists "documents_lecture_admin" on storage.objects;
create policy "documents_lecture_admin" on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.a_le_droit('valider_profils'));

-- ---- hotesse_prive : voir_donnees (ou valider_profils sur les comptes en attente) ----
drop function if exists public.hotesse_prive(uuid);
create function public.hotesse_prive(p_id uuid)
returns table (telephone text, instagram text, signes_negatifs int, missions_honorees int, nb_retards int, nb_absences int)
language sql stable security definer set search_path = public as $$
  select h.telephone, h.instagram, h.signes_negatifs, h.missions_honorees, h.nb_retards, h.nb_absences
  from public.hotesses h
  where h.id = p_id and (p_id = auth.uid() or public.a_le_droit('voir_donnees')
                         or (public.a_le_droit('valider_profils') and not h.verifie));
$$;
