-- ============================================================
--  DamUp — Schéma de la base EN LIGNE (export)
--  Généré automatiquement depuis Supabase (projet bzoqpaldksrqixoxgsvf)
-- ============================================================

-- TABLE abonnements
create table public.abonnements (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "etablissement_id" uuid NOT NULL,
  "plan" text NOT NULL,
  "prix" numeric NOT NULL,
  "processeur" text NOT NULL DEFAULT 'paddle'::text,
  "statut" text NOT NULL DEFAULT 'essai'::text,
  "debut" timestamp with time zone NOT NULL DEFAULT now(),
  "fin" timestamp with time zone,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE appareils_push
create table public.appareils_push (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "endpoint" text NOT NULL,
  "p256dh" text NOT NULL,
  "auth_cle" text NOT NULL,
  "appareil" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE avis
create table public.avis (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "mission_id" uuid NOT NULL,
  "etablissement_id" uuid NOT NULL,
  "hotesse_id" uuid NOT NULL,
  "note" integer NOT NULL,
  "criteres" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "commentaire" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE candidatures
create table public.candidatures (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "mission_id" uuid NOT NULL,
  "hotesse_id" uuid NOT NULL,
  "groupe_id" uuid,
  "statut" text NOT NULL DEFAULT 'en_attente'::text,
  "qr_code" text,
  "confirme_a" timestamp with time zone,
  "annulation" boolean NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "presente_a" timestamp with time zone,
  "rappel_envoye" boolean NOT NULL DEFAULT false,
  "retard_annonce_min" integer,
  "retard_annonce_le" timestamp with time zone,
  "retard_min" integer,
  "absence_declaree_le" timestamp with time zone,
  "sanction_annulee_le" timestamp with time zone
);

-- TABLE compteurs
create table public.compteurs (
  "nom" text NOT NULL,
  "annee" integer NOT NULL,
  "valeur" integer NOT NULL DEFAULT 0
);

-- TABLE email_erreurs
create table public.email_erreurs (
  "id" bigint NOT NULL,
  "date" timestamp with time zone NOT NULL DEFAULT now(),
  "user_id" uuid,
  "raison" text
);

-- TABLE equipe
create table public.equipe (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "nom" text,
  "role" text,
  "droits" jsonb NOT NULL DEFAULT '{}'::jsonb,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE etablissements
create table public.etablissements (
  "id" uuid NOT NULL,
  "nom" text NOT NULL,
  "type" text,
  "adresse" text,
  "ville" text,
  "siret" text,
  "responsable_nom" text,
  "id_document_resp" text,
  "photos" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "videos" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "verifie" boolean NOT NULL DEFAULT false,
  "abonnement_actif" boolean NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "id_document" jsonb,
  "verifie_le" timestamp with time zone,
  "verifie_par" uuid
);

-- TABLE factures
create table public.factures (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "numero" text NOT NULL,
  "type" text NOT NULL DEFAULT 'facture'::text,
  "paiement_id" uuid,
  "facture_origine" uuid,
  "profil_id" uuid NOT NULL,
  "date_emission" timestamp with time zone NOT NULL DEFAULT now(),
  "vendeur" jsonb NOT NULL,
  "client" jsonb NOT NULL,
  "lignes" jsonb NOT NULL,
  "total" numeric NOT NULL,
  "mode_paiement" text NOT NULL,
  "acquittee_le" timestamp with time zone,
  "pdf_chemin" text,
  "envoyee_le" timestamp with time zone,
  "envoi_erreur" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE hotesses
create table public.hotesses (
  "id" uuid NOT NULL,
  "prenom" text NOT NULL,
  "age" integer NOT NULL,
  "ville" text,
  "instagram" text,
  "photos" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "note_moyenne" numeric DEFAULT 5.0,
  "nb_avis" integer DEFAULT 0,
  "verifie" boolean NOT NULL DEFAULT false,
  "id_document" text,
  "signes_negatifs" integer DEFAULT 0,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "telephone" text,
  "missions_honorees" integer NOT NULL DEFAULT 0,
  "code_damup" text,
  "verifie_le" timestamp with time zone,
  "verifie_par" uuid,
  "nb_retards" integer NOT NULL DEFAULT 0,
  "nb_absences" integer NOT NULL DEFAULT 0
);

-- TABLE invitations_copine
create table public.invitations_copine (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "candidature_id" uuid NOT NULL,
  "marraine_id" uuid NOT NULL,
  "copine_id" uuid,
  "code_invitation" text NOT NULL DEFAULT replace((gen_random_uuid())::text, '-'::text, ''::text),
  "prenom_indique" text NOT NULL,
  "statut" text NOT NULL DEFAULT 'envoyee'::text,
  "expire_le" timestamp with time zone NOT NULL DEFAULT (now() + '7 days'::interval),
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE messages
create table public.messages (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "mission_id" uuid NOT NULL,
  "expediteur_type" text NOT NULL,
  "expediteur_id" uuid NOT NULL,
  "destinataire_type" text NOT NULL,
  "destinataire_id" uuid NOT NULL,
  "contenu" text,
  "photo_url" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "hotesse_id" uuid,
  "lu_a" timestamp with time zone
);

-- TABLE missions
create table public.missions (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "etablissement_id" uuid NOT NULL,
  "titre" text,
  "date" date NOT NULL,
  "heure_debut" time without time zone NOT NULL,
  "heure_fin" time without time zone NOT NULL,
  "adresse" text,
  "nb_hotesses" integer NOT NULL DEFAULT 1,
  "articles_offerts" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "medias" jsonb NOT NULL DEFAULT '[]'::jsonb,
  "repetable" boolean NOT NULL DEFAULT false,
  "statut" text NOT NULL DEFAULT 'ouverte'::text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "places_restantes" integer,
  "note" text
);

-- TABLE notifications
create table public.notifications (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "message" text NOT NULL,
  "lu" boolean NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "cle" text,
  "params" jsonb NOT NULL DEFAULT '{}'::jsonb
);

-- TABLE paiements
create table public.paiements (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "profil_id" uuid NOT NULL,
  "montant" numeric NOT NULL,
  "mode" text NOT NULL,
  "periode_debut" timestamp with time zone NOT NULL,
  "periode_fin" timestamp with time zone NOT NULL,
  "numero_recu" text NOT NULL DEFAULT ((('DU-'::text || to_char(now(), 'YYYY'::text)) || '-'::text) || lpad((nextval('recu_seq'::regclass))::text, 5, '0'::text)),
  "reference_externe" text,
  "note" text,
  "enregistre_par" uuid,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE preferences_notif
create table public.preferences_notif (
  "user_id" uuid NOT NULL,
  "push_actif" boolean NOT NULL DEFAULT true,
  "email_missions" boolean NOT NULL DEFAULT true,
  "email_messages" boolean NOT NULL DEFAULT false,
  "email_compte" boolean NOT NULL DEFAULT true,
  "updated_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE profiles
create table public.profiles (
  "id" uuid NOT NULL,
  "type" text NOT NULL,
  "email" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now(),
  "suspendu" boolean NOT NULL DEFAULT false,
  "tarif" numeric,
  "periode" text,
  "actif_jusqu_a" timestamp with time zone,
  "rappel_fin_envoye_pour" timestamp with time zone,
  "stripe_customer_id" text,
  "stripe_compte" text,
  "langue" text NOT NULL DEFAULT 'fr'::text,
  "reference_virement" text
);

-- TABLE settings
create table public.settings (
  "key" text NOT NULL,
  "value" jsonb NOT NULL
);

-- TABLE signalements
create table public.signalements (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "signalant_type" text NOT NULL,
  "signalant_id" uuid NOT NULL,
  "cible_type" text NOT NULL,
  "cible_id" uuid NOT NULL,
  "motif" text,
  "statut" text NOT NULL DEFAULT 'nouveau'::text,
  "decision" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE traductions
create table public.traductions (
  "cle" text NOT NULL,
  "langue" text NOT NULL,
  "texte" text NOT NULL
);


-- ============ FONCTIONS ============

CREATE OR REPLACE FUNCTION public.abonnement_ok(p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case p.type
    when 'etablissement' then not public.reglage_bool('paiement_etablissements_actif', false)
                              or coalesce(p.actif_jusqu_a > now(), false)
    when 'hotesse'       then not public.reglage_bool('paiement_hotesses_actif', false)
                              or coalesce(p.actif_jusqu_a > now(), false)
    else true end
  from public.profiles p where p.id = p_uid;
$function$;

CREATE OR REPLACE FUNCTION public.admin_annuaire_etablissements()
 RETURNS TABLE(id uuid, nom text, type text, ville text, adresse text, email text, siret text, verifie boolean, suspendu boolean, missions_publiees bigint, inscrit_le timestamp with time zone, tarif numeric, periode text, actif_jusqu_a timestamp with time zone, dernier_mode text, reference_virement text, photos jsonb, videos jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select e.id, e.nom, e.type, e.ville, e.adresse, p.email, e.siret, e.verifie, p.suspendu,
         (select count(*) from public.missions m where m.etablissement_id = e.id),
         e.created_at, p.tarif, p.periode, p.actif_jusqu_a,
         (select pa.mode from public.paiements pa where pa.profil_id = e.id order by pa.created_at desc limit 1),
         p.reference_virement, e.photos, e.videos
    from public.etablissements e join public.profiles p on p.id = e.id
   where public.is_admin()
   order by e.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.admin_annuaire_hotesses()
 RETURNS TABLE(id uuid, prenom text, age integer, ville text, email text, instagram text, telephone text, verifie boolean, suspendu boolean, note_moyenne numeric, nb_avis integer, signes_negatifs integer, missions_honorees bigint, inscrite_le timestamp with time zone, tarif numeric, periode text, actif_jusqu_a timestamp with time zone, photos jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select h.id, h.prenom, h.age, h.ville, p.email, h.instagram, h.telephone,
         h.verifie, p.suspendu, h.note_moyenne, h.nb_avis, h.signes_negatifs,
         (select count(*) from public.candidatures c where c.hotesse_id = h.id and c.presente_a is not null),
         h.created_at, p.tarif, p.periode, p.actif_jusqu_a, h.photos
    from public.hotesses h join public.profiles p on p.id = h.id
   where public.is_admin()
   order by h.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.admin_annuler_mission(p_mission uuid, p_motif text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_etab uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  update public.missions set statut = 'annulee' where id = p_mission;
  select etablissement_id into v_etab from public.missions where id = p_mission;
  if v_etab is null then raise exception 'Mission introuvable.'; end if;
  perform public.notifier_utilisateur(v_etab, 'notif.mission_annulee_admin',
    jsonb_build_object('motif', coalesce(p_motif, '')));
  insert into public.notifications (user_id, message, cle, params)
  select c.hotesse_id,
         public.traduire('notif.mission_annulee_admin', coalesce(p.langue, 'fr'),
           jsonb_build_object('motif', coalesce(p_motif, ''))),
         'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, ''))
    from public.candidatures c
    join public.profiles p on p.id = c.hotesse_id
   where c.mission_id = p_mission and c.statut in ('acceptee', 'confirmee') and not c.annulation;
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_annuler_paiement(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_enregistrer_paiement(p_profil uuid, p_mode text, p_periode text, p_montant numeric, p_date date DEFAULT NULL::date, p_note text DEFAULT NULL::text)
 RETURNS paiements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_mode not in ('especes', 'virement', 'offert') then raise exception 'Mode non autorisé ici.'; end if;
  if p_periode not in ('hebdomadaire', 'mensuel') then raise exception 'Période invalide.'; end if;
  if p_mode in ('especes', 'virement') and (p_montant is null or p_montant <= 0) then raise exception 'Montant invalide.'; end if;
  return public.prolonger_abonnement(
    p_profil, case when p_mode = 'offert' then 0 else p_montant end, p_mode, p_periode,
    coalesce(p_date::timestamp at time zone 'Europe/Paris', now()), null, p_note);
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_hotesses()
 RETURNS SETOF hotesses
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from public.hotesses where public.is_admin() order by created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.admin_lire_conversation(p_signalement uuid)
 RETURNS SETOF messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_mission uuid;
  v_signalant uuid;
  v_cible_type text;
  v_cible uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select signalant_id, cible_type, cible_id into v_signalant, v_cible_type, v_cible
    from public.signalements where id = p_signalement;
  if v_signalant is null then raise exception 'Signalement introuvable.'; end if;
  if v_cible_type = 'mission' then
    v_mission := v_cible;
  elsif v_cible_type = 'hotesse' then
    select m.id into v_mission
      from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_signalant and c.hotesse_id = v_cible
     limit 1;
  else
    select m.id into v_mission
      from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_cible and c.hotesse_id = v_signalant
     limit 1;
  end if;
  if v_mission is null then return; end if;
  return query select * from public.messages where mission_id = v_mission order by created_at;
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_offrir_periode_groupe(p_type text, p_jours integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_recettes()
 RETURNS TABLE(id uuid, numero_recu text, mode text, montant numeric, periode_debut timestamp with time zone, periode_fin timestamp with time zone, created_at timestamp with time zone, client text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select p.id, p.numero_recu, p.mode, p.montant, p.periode_debut, p.periode_fin, p.created_at,
         coalesce(e.nom, h.prenom, pr.email) as client
    from public.paiements p
    join public.profiles pr on pr.id = p.profil_id
    left join public.etablissements e on e.id = p.profil_id
    left join public.hotesses h on h.id = p.profil_id
   where public.is_admin()
   order by p.created_at desc;
$function$;

CREATE OR REPLACE FUNCTION public.admin_refuser_profil(p_profil uuid, p_motif text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_type text;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select type into v_type from public.profiles where id = p_profil;
  if v_type = 'hotesse' then
    update public.hotesses set verifie = false where id = p_profil;
  elsif v_type = 'etablissement' then
    update public.etablissements set verifie = false where id = p_profil;
  else
    raise exception 'Profil introuvable.';
  end if;
  perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee',
    jsonb_build_object('motif', coalesce(p_motif, '')));
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_renvoyer_facture(p_facture_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  update public.factures set envoyee_le = null, envoi_erreur = null where id = p_facture_id;
  perform public.envoyer_facture(p_facture_id);
end; $function$;

CREATE OR REPLACE FUNCTION public.admin_valider_identite(p_profil uuid, p_type text, p_valide boolean, p_motif text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_type = 'hotesse' then
    update public.hotesses set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null
     where id = p_profil;
  else
    update public.etablissements set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null
     where id = p_profil;
  end if;
  if not p_valide then
    perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee', jsonb_build_object('motif', coalesce(p_motif, '')));
  end if;
end; $function$;

CREATE OR REPLACE FUNCTION public.annoncer_retard(p_candidature uuid, p_minutes integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_c public.candidatures%rowtype;
  v_debut timestamptz;
  v_tol int;
  v_prenom text;
  v_lieu text;
  v_heure text;
begin
  select * into v_c from public.candidatures where id = p_candidature and hotesse_id = auth.uid();
  if v_c.id is null then raise exception 'Candidature introuvable.'; end if;
  if v_c.statut <> 'confirmee' or v_c.annulation then raise exception 'Cette mission n''est pas confirmée.'; end if;
  select (m.date + m.heure_debut) at time zone 'Europe/Paris' into v_debut from public.missions m where m.id = v_c.mission_id;
  v_tol := public.reglage_num('tolerance_retard_min', 15)::int;
  if now() >= v_debut + make_interval(mins => v_tol) then
    raise exception 'Il est trop tard pour annoncer un retard.';
  end if;
  if p_minutes < 5 or p_minutes > 180 then raise exception 'Retard invalide (5 à 180 minutes).'; end if;
  select prenom into v_prenom from public.hotesses where id = v_c.hotesse_id;
  select e.nom into v_lieu from public.missions m join public.etablissements e on e.id = m.etablissement_id where m.id = v_c.mission_id;
  v_heure := to_char((v_debut + make_interval(mins => p_minutes)) at time zone 'Europe/Paris', 'HH24:MI');
  update public.candidatures set retard_annonce_min = p_minutes, retard_annonce_le = now() where id = p_candidature;
  perform public.notifier_utilisateur(
    (select etablissement_id from public.missions where id = v_c.mission_id),
    'notif.retard_annonce',
    jsonb_build_object('prenom', v_prenom, 'minutes', p_minutes, 'heure', v_heure)
  );
end; $function$;

CREATE OR REPLACE FUNCTION public.apres_annulation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_signes int;
  v_etab uuid;
  v_date_m date;
  v_langue text;
begin
  if new.annulation and not old.annulation then
    if old.statut = 'confirmee' then
      update public.hotesses set signes_negatifs = signes_negatifs + 1, missions_honorees = 0
       where id = new.hotesse_id
       returning signes_negatifs into v_signes;
      if v_signes >= public.reglage_num('signes_avant_suspension', 3)::int then
        update public.profiles set suspendu = true where id = new.hotesse_id;
        perform public.notifier_utilisateur(new.hotesse_id, 'notif.suspension_hotesse',
          jsonb_build_object('n', v_signes));
        insert into public.notifications (user_id, message, cle, params)
        select p.id, public.traduire('notif.suspension_admin', 'fr', jsonb_build_object('n', v_signes)),
               'notif.suspension_admin', jsonb_build_object('n', v_signes)
          from public.profiles p where p.type = 'admin';
      end if;
    end if;
    select m.etablissement_id, m.date, coalesce(p.langue, 'fr') into v_etab, v_date_m, v_langue
      from public.missions m join public.profiles p on p.id = m.etablissement_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(v_etab, 'notif.annulation_etab',
      jsonb_build_object('date', public.date_courte(v_date_m, v_langue)));
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.bloque_infos_contact()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if coalesce(new.contenu,'') ~ '(\+33|0[1-9][ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2})' then
    raise exception 'Les numéros de téléphone ne sont pas autorisés dans la messagerie.';
  end if;
  if coalesce(new.contenu,'') ~ '(instagram\.com|facebook\.com|snapchat|tiktok|@[a-zA-Z0-9_.]{2,})' then
    raise exception 'Les comptes de réseaux sociaux ne sont pas autorisés dans la messagerie.';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.changer_langue(p_langue text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if p_langue not in ('fr', 'en', 'es', 'zh') then
    raise exception 'Langue non disponible.';
  end if;
  update public.profiles set langue = p_langue where id = auth.uid();
end; $function$;

CREATE OR REPLACE FUNCTION public.controle_candidature()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_m public.missions%rowtype;
  v_pris int;
  v_debut timestamptz;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then return new; end if;
  select * into v_m from public.missions where id = new.mission_id;
  v_debut := (v_m.date + v_m.heure_debut) at time zone 'Europe/Paris';

  if tg_op = 'INSERT' then
    if new.hotesse_id is distinct from auth.uid() then raise exception 'Modification non autorisée.'; end if;
    if public.est_suspendu() then raise exception 'Ton compte est suspendu. Contacte DamUp.'; end if;
    if not exists (select 1 from public.hotesses h where h.id = auth.uid() and h.verifie) then
      raise exception 'Ton profil doit être validé par DamUp avant de postuler.';
    end if;
    if v_m.statut <> 'ouverte' or v_debut <= now() then
      raise exception 'Cette mission n''accepte plus de candidatures.';
    end if;
    new.statut := 'en_attente'; new.qr_code := null; new.annulation := false;
    new.confirme_a := null; new.presente_a := null;
    return new;
  end if;

  if new.mission_id is distinct from old.mission_id or new.hotesse_id is distinct from old.hotesse_id
     or new.groupe_id is distinct from old.groupe_id or new.qr_code is distinct from old.qr_code
     or new.confirme_a is distinct from old.confirme_a or new.presente_a is distinct from old.presente_a
     or new.retard_annonce_min is distinct from old.retard_annonce_min
     or new.retard_annonce_le is distinct from old.retard_annonce_le
     or new.retard_min is distinct from old.retard_min
     or new.absence_declaree_le is distinct from old.absence_declaree_le
     or new.sanction_annulee_le is distinct from old.sanction_annulee_le then
    raise exception 'Modification non autorisée.';
  end if;

  if auth.uid() = v_m.etablissement_id then
    if new.annulation is distinct from old.annulation then raise exception 'Modification non autorisée.'; end if;
    if new.statut is distinct from old.statut then
      if not ((old.statut = 'en_attente' and new.statut in ('acceptee', 'refusee'))
              or (old.statut = 'acceptee' and new.statut = 'refusee')) then
        raise exception 'Changement de statut non autorisé.';
      end if;
      if new.statut = 'acceptee' then
        if v_debut <= now() then raise exception 'La mission a déjà commencé.'; end if;
        select count(*) into v_pris from public.candidatures
         where mission_id = new.mission_id and id <> new.id
           and statut in ('acceptee', 'confirmee') and not annulation;
        if v_pris >= v_m.nb_hotesses then
          raise exception 'Toutes les places de cette mission sont déjà prises.';
        end if;
        new.confirme_a := least(
          now() + case when v_debut - now() < interval '24 hours' then interval '3 hours' else interval '12 hours' end,
          v_debut);
      end if;
    end if;

  elsif auth.uid() = old.hotesse_id then
    if new.statut is distinct from old.statut then
      if not (old.statut = 'acceptee' and new.statut = 'confirmee') then
        raise exception 'Changement de statut non autorisé.';
      end if;
      if old.annulation then raise exception 'Cette candidature a été annulée.'; end if;
      if now() > coalesce(old.confirme_a, v_debut) then
        raise exception 'Le délai de confirmation est dépassé.';
      end if;
      new.qr_code := replace(gen_random_uuid()::text, '-', '');
    end if;
    if old.annulation and not new.annulation then raise exception 'Une annulation ne peut pas être retirée.'; end if;
    if new.annulation and not old.annulation and v_debut <= now() then
      raise exception 'La mission a déjà commencé, l''annulation n''est plus possible.';
    end if;

  else
    raise exception 'Modification non autorisée.';
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.controle_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.missions where id = new.mission_id;
  if auth.uid() = new.hotesse_id then
    new.expediteur_type := 'hotesse';   new.expediteur_id := auth.uid();
    new.destinataire_type := 'etablissement'; new.destinataire_id := v_etab;
  elsif auth.uid() = v_etab then
    new.expediteur_type := 'etablissement'; new.expediteur_id := auth.uid();
    new.destinataire_type := 'hotesse'; new.destinataire_id := new.hotesse_id;
  else
    raise exception 'Conversation non autorisée.' using hint = 'conversation_interdite';
  end if;
  if not public.conversation_ouverte(new.mission_id, new.hotesse_id) then
    raise exception 'Cette conversation est fermée.' using hint = 'conversation_fermee';
  end if;
  if char_length(coalesce(new.contenu, '')) > 1000 then
    raise exception 'Message trop long.' using hint = 'message_trop_long';
  end if;
  new.lu_a := null;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.controle_message_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.contenu is distinct from old.contenu
     or new.hotesse_id is distinct from old.hotesse_id
     or new.mission_id is distinct from old.mission_id
     or new.expediteur_id is distinct from old.expediteur_id
     or new.expediteur_type is distinct from old.expediteur_type
     or new.destinataire_id is distinct from old.destinataire_id
     or new.destinataire_type is distinct from old.destinataire_type
     or new.photo_url is distinct from old.photo_url then
    raise exception 'Seul le champ "lu" peut être modifié.' using hint = 'modification_interdite';
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.controle_signalement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  select p.type into new.signalant_type from public.profiles p where p.id = auth.uid();
  if new.signalant_type is null or new.signalant_type not in ('hotesse', 'etablissement') then
    raise exception 'Signalement non autorisé.';
  end if;
  new.signalant_id := auth.uid();
  new.statut := 'nouveau';
  new.decision := null;
  if char_length(coalesce(new.motif, '')) > 1000 then raise exception 'Motif trop long (1000 caractères maximum).'; end if;
  if (select count(*) from public.signalements
       where signalant_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Trop de signalements aujourd''hui. Contacte DamUp directement.';
  end if;
  insert into public.notifications (user_id, message, cle, params)
  select p.id, public.traduire('notif.signalement_admin', 'fr', '{}'::jsonb),
         'notif.signalement_admin', '{}'::jsonb
    from public.profiles p where p.type = 'admin';
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.conversation_ouverte(p_mission uuid, p_hotesse uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (
    select 1 from public.candidatures c
    join public.missions m on m.id = c.mission_id
    where c.mission_id = p_mission and c.hotesse_id = p_hotesse
      and c.statut in ('acceptee', 'confirmee') and not c.annulation
      and auth.uid() in (c.hotesse_id, m.etablissement_id)
      and now() < ((m.date + m.heure_fin
                     + case when m.heure_fin <= m.heure_debut then interval '1 day' else interval '0' end)
                    at time zone 'Europe/Paris') + interval '12 hours'
  );
$function$;

CREATE OR REPLACE FUNCTION public.creer_facture(p_paiement uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    'mention_tva', coalesce((select value from public.settings where key = 'mention_tva'), 'TVA non applicable, art. 293 B du CGI'),
    'iban', (select value from public.settings where key = 'iban'),
    'bic', (select value from public.settings where key = 'bic'),
    'titulaire_iban', (select value from public.settings where key = 'titulaire_iban')
  );
  if v_vendeur->>'nom' is null or v_vendeur->>'nom' = ''
     or v_vendeur->>'adresse' is null or v_vendeur->>'adresse' = '' then
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
end; $function$;

CREATE OR REPLACE FUNCTION public.creer_facture_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.mode <> 'offert' then
    perform public.creer_facture(new.id);
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.date_courte(p_d date, p_langue text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p_langue
    when 'zh' then to_char(p_d, 'FMMM') || '月' || to_char(p_d, 'FMDD') || '日'
    else to_char(p_d, 'DD/MM') end;
$function$;

CREATE OR REPLACE FUNCTION public.envoyer_email_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret text;
  v_anon text;
  v_cat text;
  v_autorise boolean;
begin
  if new.cle like 'notif.message.%' then v_cat := 'messages';
  elsif new.cle in ('notif.validation_refusee', 'notif.suspension_hotesse', 'notif.suspension_admin',
                    'notif.fin_abonnement', 'notif.fin_abonnement_admin', 'notif.paiement_recu',
                    'notif.paiement_offert', 'notif.paiement_echoue', 'notif.paiement_echoue_admin') then v_cat := 'compte';
  else v_cat := 'missions';
  end if;

  select case v_cat
    when 'messages' then coalesce(email_messages, false)
    when 'compte' then coalesce(email_compte, true)
    else coalesce(email_missions, true) end
    into v_autorise from public.preferences_notif where user_id = new.user_id;
  if v_autorise is null then v_autorise := (v_cat <> 'messages'); end if;
  if not v_autorise then return new; end if;

  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return new; end if;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('user_id', new.user_id::text, 'message', new.message)
  );
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.envoyer_facture(p_facture_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;

CREATE OR REPLACE FUNCTION public.est_suspendu()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select suspendu from public.profiles where id = auth.uid()), false);
$function$;

CREATE OR REPLACE FUNCTION public.expirer_invitations_copine()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.invitations_copine i set statut = 'expiree'
   where i.statut in ('envoyee', 'a_accepter')
     and (i.expire_le < now()
          or exists (select 1 from public.missions m
                      join public.candidatures c on c.mission_id = m.id
                     where c.id = i.candidature_id and m.date < current_date));
end; $function$;

CREATE OR REPLACE FUNCTION public.generer_code_damup()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.code_damup is null then
    new.code_damup := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r text;
  v_age int;
  v_villes jsonb;
begin
  if not public.reglage_bool('inscriptions_ouvertes', true) then
    raise exception 'Les inscriptions sont fermées pour le moment.';
  end if;

  if coalesce(new.raw_app_meta_data->>'role', '') = 'admin' then r := 'admin';
  elsif m->>'role' = 'etablissement' then r := 'etablissement';
  else r := 'hotesse';
  end if;

  insert into public.profiles (id, type, email, tarif, periode, actif_jusqu_a, langue)
  values (new.id, r, new.email,
    case when r = 'etablissement' then public.reglage_num('prix_defaut_etablissement', 79)
         when r = 'hotesse' then public.reglage_num('prix_defaut_hotesse', 0)
         else null end,
    case when r = 'admin' then null else 'mensuel' end,
    now() + make_interval(days => public.reglage_num('essai_jours', 7)::int),
    case when m->>'langue' in ('fr', 'en', 'es', 'zh') then m->>'langue' else 'fr' end)
  on conflict (id) do nothing;

  if r = 'hotesse' then
    -- champs obligatoires : prénom, ville, Instagram
    if coalesce(nullif(trim(m->>'prenom'), ''), '') = '' then
      raise exception 'Le prénom est obligatoire.';
    end if;
    v_age := nullif(m->>'age', '')::int;
    if v_age is null or v_age < 18 then
      raise exception 'Inscription réservée aux personnes de 18 ans et plus.';
    end if;
    if coalesce(nullif(trim(m->>'ville'), ''), '') = '' then
      raise exception 'La ville est obligatoire.';
    end if;
    if coalesce(nullif(trim(m->>'instagram'), ''), '') = '' then
      raise exception 'Le compte Instagram est obligatoire.';
    end if;
    v_villes := (select value from public.settings where key = 'villes');
    if v_villes is not null and jsonb_array_length(v_villes) > 0
       and not (coalesce(m->>'ville', '') = ANY (select jsonb_array_elements_text(v_villes))) then
      raise exception 'Cette ville n''est pas encore ouverte aux inscriptions.';
    end if;
    insert into public.hotesses (id, prenom, age, ville, instagram, telephone, photos)
    values (new.id, left(nullif(trim(m->>'prenom'), ''), 50), v_age,
            left(m->>'ville', 80), left(m->>'instagram', 60), left(m->>'telephone', 20), '[]'::jsonb)
    on conflict (id) do nothing;
  elsif r = 'etablissement' then
    if coalesce(nullif(trim(m->>'nom'), ''), '') = '' then
      raise exception 'Le nom de l''établissement est obligatoire.';
    end if;
    if coalesce(nullif(trim(m->>'siret'), ''), '') = '' then
      raise exception 'Le SIRET est obligatoire.';
    end if;
    insert into public.etablissements (id, nom, type, ville, adresse, siret, photos, videos)
    values (new.id, left(nullif(trim(m->>'nom'), ''), 100),
            case when m->>'type_etab' in ('bar','restaurant','club','lounge') then m->>'type_etab' end,
            left(m->>'ville', 80), left(m->>'adresse', 200),
            left(regexp_replace(coalesce(m->>'siret', ''), '\s', '', 'g'), 14), '[]'::jsonb, '[]'::jsonb)
    on conflict (id) do nothing;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.heure_courte(p_t timestamp with time zone, p_langue text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select case p_langue
    when 'fr' then to_char(p_t at time zone 'Europe/Paris', 'HH24"h"MI')
    else to_char(p_t at time zone 'Europe/Paris', 'HH24:MI') end;
$function$;

CREATE OR REPLACE FUNCTION public.hotesse_prive(p_id uuid)
 RETURNS TABLE(telephone text, instagram text, signes_negatifs integer, missions_honorees integer, nb_retards integer, nb_absences integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select h.telephone, h.instagram, h.signes_negatifs, h.missions_honorees, h.nb_retards, h.nb_absences
  from public.hotesses h
  where h.id = p_id and (p_id = auth.uid() or public.is_admin());
$function$;

CREATE OR REPLACE FUNCTION public.init_places_mission()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.places_restantes := coalesce(new.nb_hotesses, 1);
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select exists (select 1 from public.profiles where id = auth.uid() and type = 'admin');
$function$;

CREATE OR REPLACE FUNCTION public.lier_invitation_verifiee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_code text;
begin
  if new.verifie and not coalesce(old.verifie, false) then
    select raw_user_meta_data->>'code_invitation' into v_code from auth.users where id = new.id;
    if v_code is not null and v_code <> '' then
      update public.invitations_copine
         set copine_id = new.id, statut = 'a_accepter'
       where code_invitation = v_code and statut = 'envoyee' and copine_id is null;
    end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.maj_note_hotesse()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.hotesses h set
    note_moyenne = coalesce((select round(avg(a.note)::numeric, 1) from public.avis a where a.hotesse_id = new.hotesse_id), 5.0),
    nb_avis = (select count(*) from public.avis a where a.hotesse_id = new.hotesse_id)
  where h.id = new.hotesse_id;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.maj_places_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  update public.missions m
     set places_restantes = greatest(m.nb_hotesses - (
           select count(*) from public.candidatures c
            where c.mission_id = m.id and c.statut in ('acceptee','confirmee') and not c.annulation), 0)
   where m.id = new.mission_id;
  update public.missions
     set statut = case when places_restantes <= 0 and statut = 'ouverte' then 'cloturee'
                       when places_restantes > 0 and statut = 'cloturee' then 'ouverte'
                       else statut end
   where id = new.mission_id;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.nettoie_document_etab()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.verifie and coalesce(old.verifie, false) is distinct from new.verifie then
    new.id_document_resp := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.nettoie_document_hotesse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if new.verifie and coalesce(old.verifie, false) is distinct from new.verifie then
    new.id_document := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notifier_candidature()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lieu text;
  v_date_m date;
  v_langue text;
begin
  if old.statut is not distinct from new.statut then return new; end if;

  if new.statut = 'acceptee' then
    select e.nom, m.date, coalesce(p.langue, 'fr') into v_lieu, v_date_m, v_langue
      from public.missions m
      join public.etablissements e on e.id = m.etablissement_id
      join public.profiles p on p.id = new.hotesse_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(new.hotesse_id, 'notif.acceptee',
      jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, v_langue),
                         'heure', public.heure_courte(new.confirme_a, v_langue)));
  elsif new.statut = 'refusee' then
    select e.nom, m.date, coalesce(p.langue, 'fr') into v_lieu, v_date_m, v_langue
      from public.missions m
      join public.etablissements e on e.id = m.etablissement_id
      join public.profiles p on p.id = new.hotesse_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(new.hotesse_id, 'notif.refusee',
      jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, v_langue)));
  elsif new.statut = 'expiree' then
    select e.nom, m.date, coalesce(p.langue, 'fr') into v_lieu, v_date_m, v_langue
      from public.missions m
      join public.etablissements e on e.id = m.etablissement_id
      join public.profiles p on p.id = new.hotesse_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(new.hotesse_id, 'notif.expiree',
      jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, v_langue)));
  elsif new.statut = 'confirmee' then
    select m.date, coalesce(p.langue, 'fr') into v_date_m, v_langue
      from public.missions m join public.profiles p on p.id = m.etablissement_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(
      (select etablissement_id from public.missions where id = new.mission_id),
      'notif.confirmee_etab', jsonb_build_object('date', public.date_courte(v_date_m, v_langue)));
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notifier_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_dest uuid;
  v_nom text;
  v_langue text;
  v_non_lus int;
  v_message text;
begin
  if new.destinataire_type = 'hotesse' then
    v_dest := new.destinataire_id;
    select coalesce(e.nom, '') into v_nom from public.etablissements e where e.id = new.expediteur_id;
  else
    v_dest := new.destinataire_id;
    select coalesce(h.prenom, '') into v_nom from public.hotesses h where h.id = new.expediteur_id;
  end if;
  select count(*) into v_non_lus from public.messages
   where mission_id = new.mission_id and hotesse_id = new.hotesse_id
     and destinataire_id = v_dest and lu_a is null and id <> new.id;
  if v_non_lus > 0 then return new; end if;
  select langue into v_langue from public.profiles where id = v_dest;
  v_message := public.traduire('notif.message.nouveau', coalesce(v_langue, 'fr'), jsonb_build_object('nom', v_nom));
  insert into public.notifications (user_id, message, cle, params)
  values (v_dest, v_message, 'notif.message.nouveau', jsonb_build_object('nom', v_nom));
  perform public.notifier_push(v_dest, 'notif.message.nouveau', v_message);
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notifier_note_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_lieu text;
  v_date_m date;
begin
  if new.note is distinct from old.note and coalesce(new.note, '') <> '' then
    select e.nom, m.date into v_lieu, v_date_m
      from public.missions m join public.etablissements e on e.id = m.etablissement_id
     where m.id = new.id;
    insert into public.notifications (user_id, message, cle, params)
    select c.hotesse_id,
           public.traduire('notif.mission_note_modifiee', coalesce(p.langue, 'fr'),
             jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, coalesce(p.langue, 'fr')))),
           'notif.mission_note_modifiee',
           jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, coalesce(p.langue, 'fr')))
      from public.candidatures c
      join public.profiles p on p.id = c.hotesse_id
     where c.mission_id = new.id and c.statut in ('acceptee', 'confirmee') and not c.annulation;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notifier_nouvelle_candidature()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_prenom text;
  v_date_m date;
  v_langue text;
begin
  select h.prenom, m.date, coalesce(p.langue, 'fr') into v_prenom, v_date_m, v_langue
    from public.missions m
    join public.hotesses h on h.id = new.hotesse_id
    join public.profiles p on p.id = m.etablissement_id
   where m.id = new.mission_id;
  perform public.notifier_utilisateur(
    (select etablissement_id from public.missions where id = new.mission_id),
    'notif.nouvelle_candidature',
    jsonb_build_object('prenom', v_prenom, 'date', public.date_courte(v_date_m, v_langue)));
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.notifier_push(p_user uuid, p_cle text, p_message text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_push boolean;
  v_type text;
  v_url text;
  v_anon text;
  v_secret text;
begin
  select coalesce(push_actif, true) into v_push from public.preferences_notif where user_id = p_user;
  if v_push is null then v_push := true; end if;
  if not v_push then return; end if;

  select type into v_type from public.profiles where id = p_user;
  if p_cle like 'notif.message.%' then
    v_url := 'https://damup.fr/' || case when v_type = 'etablissement' then 'etablissement.html' else 'hotesse.html' end || '#messages';
  else
    v_url := 'https://damup.fr/' || case when v_type = 'etablissement' then 'etablissement.html' else 'hotesse.html' end;
  end if;

  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return; end if;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/envoyer-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('user_id', p_user::text, 'titre', 'DamUp', 'texte', p_message, 'url', v_url)
  );
end; $function$;

CREATE OR REPLACE FUNCTION public.notifier_utilisateur(p_user uuid, p_cle text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_langue text; v_message text;
begin
  select langue into v_langue from public.profiles where id = p_user;
  v_message := public.traduire(p_cle, coalesce(v_langue, 'fr'), p_params);
  insert into public.notifications (user_id, message, cle, params)
  values (p_user, v_message, p_cle, p_params);
  perform public.notifier_push(p_user, p_cle, v_message);
end; $function$;

CREATE OR REPLACE FUNCTION public.prochain_numero(p_nom text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;

CREATE OR REPLACE FUNCTION public.prolonger_abonnement(p_profil uuid, p_montant numeric, p_mode text, p_periode text, p_date timestamp with time zone, p_ref text, p_note text)
 RETURNS paiements
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_debut timestamptz;
  v_fin timestamptz;
  v_p public.paiements;
  v_langue text;
begin
  select greatest(coalesce(actif_jusqu_a, p_date), p_date) into v_debut
    from public.profiles where id = p_profil for update;
  if v_debut is null then raise exception 'Compte introuvable.'; end if;
  v_fin := v_debut + case p_periode when 'hebdomadaire' then interval '7 days' else interval '1 month' end;

  insert into public.paiements (profil_id, montant, mode, periode_debut, periode_fin, reference_externe, note, enregistre_par)
  values (p_profil, p_montant, p_mode, v_debut, v_fin, p_ref, p_note, auth.uid())
  returning * into v_p;

  update public.profiles set actif_jusqu_a = v_fin, rappel_fin_envoye_pour = null where id = p_profil;
  select coalesce(langue, 'fr') into v_langue from public.profiles where id = p_profil;
  if p_mode = 'offert' then
    perform public.notifier_utilisateur(p_profil, 'notif.paiement_offert',
      jsonb_build_object('date', public.date_courte(v_fin::date, v_langue)));
  else
    perform public.notifier_utilisateur(p_profil, 'notif.paiement_recu',
      jsonb_build_object('date', public.date_courte(v_fin::date, v_langue)));
  end if;
  return v_p;
end; $function$;

CREATE OR REPLACE FUNCTION public.proposer_copine(p_candidature uuid, p_code_damup text, p_prenom text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_cand public.candidatures%rowtype;
  v_mission public.missions%rowtype;
  v_marraine uuid;
  v_copine public.hotesses%rowtype;
  v_lieu text;
  v_code text;
  v_prenom_marraine text;
begin
  select * into v_cand from public.candidatures where id = p_candidature and hotesse_id = auth.uid();
  if v_cand.id is null then raise exception 'Candidature introuvable.'; end if;
  select * into v_mission from public.missions where id = v_cand.mission_id;
  if v_mission.statut <> 'ouverte' then raise exception 'Cette mission n''est plus ouverte.'; end if;
  if exists (select 1 from public.invitations_copine where candidature_id = p_candidature) then
    raise exception 'Tu as déjà proposé une copine pour cette mission.';
  end if;
  v_marraine := auth.uid();
  select nom into v_lieu from public.etablissements where id = v_mission.etablissement_id;
  select prenom into v_prenom_marraine from public.hotesses where id = v_marraine;

  if p_code_damup is not null and trim(p_code_damup) <> '' then
    select * into v_copine from public.hotesses where upper(code_damup) = upper(trim(p_code_damup));
    if v_copine.id is null then raise exception 'Code DamUp introuvable.'; end if;
    if v_copine.id = v_marraine then raise exception 'Tu ne peux pas te proposer toi-même.'; end if;
    if not v_copine.verifie then raise exception 'Cette hôtesse n''est pas encore vérifiée.'; end if;
    if exists (select 1 from public.profiles where id = v_copine.id and suspendu) then
      raise exception 'Cette hôtesse est suspendue.';
    end if;
    if exists (select 1 from public.candidatures where mission_id = v_mission.id and hotesse_id = v_copine.id) then
      raise exception 'Cette hôtesse a déjà postulé à cette mission.';
    end if;
    insert into public.invitations_copine (candidature_id, marraine_id, copine_id, prenom_indique, statut)
    values (p_candidature, v_marraine, v_copine.id, coalesce(nullif(trim(p_prenom), ''), v_copine.prenom), 'a_accepter');
    perform public.notifier_utilisateur(v_copine.id, 'copine.proposee',
      jsonb_build_object('prenom', v_prenom_marraine, 'lieu', v_lieu, 'date', public.date_courte(v_mission.date, 'fr')));
    return null;
  else
    insert into public.invitations_copine (candidature_id, marraine_id, prenom_indique, statut)
    values (p_candidature, v_marraine, p_prenom, 'envoyee')
    returning code_invitation into v_code;
    return v_code;
  end if;
end; $function$;

CREATE OR REPLACE FUNCTION public.protege_etablissement()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.abonnement_actif is distinct from old.abonnement_actif then
      raise exception 'Modification non autorisée.';
    end if;
    -- un SIRET modifié doit être revérifié par l'admin
    if new.siret is distinct from old.siret then new.verifie := false; end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.protege_hotesse()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.note_moyenne is distinct from old.note_moyenne
       or new.nb_avis is distinct from old.nb_avis
       or new.signes_negatifs is distinct from old.signes_negatifs
       or new.missions_honorees is distinct from old.missions_honorees
       or new.nb_retards is distinct from old.nb_retards
       or new.nb_absences is distinct from old.nb_absences then
      raise exception 'Modification non autorisée.';
    end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.protege_mission()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'UPDATE' and new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'Modification non autorisée.';
    end if;
    if tg_op = 'INSERT' then
      if new.date < current_date then raise exception 'La date de la mission est déjà passée.'; end if;
      if new.nb_hotesses not between 1 and 50 then raise exception 'Le nombre d''hôtesses doit être entre 1 et 50.'; end if;
      new.statut := 'ouverte';
    end if;
    if coalesce(new.note, '') ~ '(\+33|0[1-9][ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2})' then
      raise exception 'Les numéros de téléphone ne sont pas autorisés dans la note.' using hint = 'note_coordonnees';
    end if;
    if coalesce(new.note, '') ~ '(instagram\.com|facebook\.com|snapchat|tiktok|@[a-zA-Z0-9_.]{2,})' then
      raise exception 'Les comptes de réseaux sociaux ne sont pas autorisés dans la note.' using hint = 'note_coordonnees';
    end if;
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.rappeler_verification()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.notifications (user_id, message, cle, params)
  select h.id, public.traduire('verif.rappel', coalesce(p.langue, 'fr')), 'verif.rappel', '{}'::jsonb
    from public.hotesses h join public.profiles p on p.id = h.id
   where h.id_document is null and not h.verifie
     and h.created_at < now() - interval '48 hours'
     and not exists (select 1 from public.notifications n
                      where n.user_id = h.id and n.cle = 'verif.rappel');
end; $function$;

CREATE OR REPLACE FUNCTION public.reference_virement(p_uid uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end; $function$;

CREATE OR REPLACE FUNCTION public.reglage_bool(p_cle text, p_defaut boolean)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (s.value #>> '{}')::boolean from public.settings s where s.key = p_cle), p_defaut);
$function$;

CREATE OR REPLACE FUNCTION public.reglage_num(p_cle text, p_defaut numeric)
 RETURNS numeric
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select (s.value #>> '{}')::numeric from public.settings s where s.key = p_cle), p_defaut);
$function$;

CREATE OR REPLACE FUNCTION public.repondre_invitation(p_invitation uuid, p_accepte boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invitations_copine%rowtype;
  v_mission public.missions%rowtype;
  v_groupe uuid;
  v_prenom_marraine text;
  v_lieu text;
begin
  select * into v_inv from public.invitations_copine where id = p_invitation and copine_id = auth.uid();
  if v_inv.id is null then raise exception 'Invitation introuvable.'; end if;
  select * into v_mission from public.missions
    where id = (select mission_id from public.candidatures where id = v_inv.candidature_id);
  select prenom into v_prenom_marraine from public.hotesses where id = v_inv.marraine_id;
  select nom into v_lieu from public.etablissements where id = v_mission.etablissement_id;

  if not p_accepte then
    update public.invitations_copine set statut = 'refusee' where id = p_invitation;
    perform public.notifier_utilisateur(v_inv.marraine_id, 'copine.refusee',
      jsonb_build_object('prenom', (select prenom from public.hotesses where id = v_inv.copine_id)));
    return;
  end if;

  if v_mission.statut <> 'ouverte' then
    raise exception 'Cette mission n''est plus ouverte.';
  end if;
  if exists (select 1 from public.candidatures where mission_id = v_mission.id and hotesse_id = auth.uid()) then
    raise exception 'Tu as déjà postulé à cette mission.';
  end if;

  -- groupe_id commun avec la marraine
  select groupe_id into v_groupe from public.candidatures where id = v_inv.candidature_id;
  if v_groupe is null then
    v_groupe := gen_random_uuid();
    update public.candidatures set groupe_id = v_groupe where id = v_inv.candidature_id;
  end if;

  insert into public.candidatures (mission_id, hotesse_id, groupe_id, statut)
  values (v_mission.id, auth.uid(), v_groupe, 'en_attente');

  update public.invitations_copine set statut = 'acceptee' where id = p_invitation;
  perform public.notifier_utilisateur(v_inv.marraine_id, 'copine.acceptee',
    jsonb_build_object('prenom', (select prenom from public.hotesses where id = auth.uid()), 'lieu', v_lieu));
  perform public.notifier_utilisateur(v_mission.etablissement_id, 'copine.candidate',
    jsonb_build_object('prenom', v_prenom_marraine));
end; $function$;

CREATE OR REPLACE FUNCTION public.taches_auto()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- rappel quand il reste 1 h ou moins pour confirmer
  with a_rappeler as (
    update public.candidatures c set rappel_envoye = true
     where c.statut = 'acceptee' and not c.annulation and not c.rappel_envoye
       and c.confirme_a > now() and c.confirme_a - now() <= interval '1 hour'
    returning c.hotesse_id, c.confirme_a
  )
  insert into public.notifications (user_id, message, cle, params)
  select r.hotesse_id,
         public.traduire('notif.rappel_confirmation', coalesce(p.langue, 'fr'),
           jsonb_build_object('heure', public.heure_courte(r.confirme_a, coalesce(p.langue, 'fr')))),
         'notif.rappel_confirmation',
         jsonb_build_object('heure', public.heure_courte(r.confirme_a, coalesce(p.langue, 'fr')))
    from a_rappeler r join public.profiles p on p.id = r.hotesse_id;

  -- acceptations non confirmées à temps
  update public.candidatures set statut = 'expiree'
   where statut = 'acceptee' and not annulation
     and confirme_a is not null and confirme_a < now();

  -- rappels de fin d'abonnement (3 jours avant)
  with a_prevenir as (
    update public.profiles p set rappel_fin_envoye_pour = p.actif_jusqu_a
     where p.actif_jusqu_a between now() and now() + interval '3 days'
       and p.rappel_fin_envoye_pour is distinct from p.actif_jusqu_a
       and ((p.type = 'etablissement' and public.reglage_bool('paiement_etablissements_actif', false))
         or (p.type = 'hotesse' and public.reglage_bool('paiement_hotesses_actif', false)))
    returning p.id, p.actif_jusqu_a, p.langue
  )
  insert into public.notifications (user_id, message, cle, params)
  select a.id,
         public.traduire('notif.fin_abonnement', a.langue,
           jsonb_build_object('date', public.date_courte(a.actif_jusqu_a::date, a.langue))),
         'notif.fin_abonnement',
         jsonb_build_object('date', public.date_courte(a.actif_jusqu_a::date, a.langue))
    from a_prevenir a
  union all
  select ad.id,
         public.traduire('notif.fin_abonnement_admin', 'fr', jsonb_build_object('n', (select count(*) from a_prevenir))),
         'notif.fin_abonnement_admin',
         jsonb_build_object('n', (select count(*) from a_prevenir))
    from public.profiles ad
   where ad.type = 'admin' and exists (select 1 from a_prevenir);

  -- missions terminées
  update public.missions set statut = 'terminee'
   where statut in ('ouverte', 'cloturee', 'en_cours')
     and ((date + heure_fin + case when heure_fin <= heure_debut then interval '1 day' else interval '0' end)
          at time zone 'Europe/Paris') < now();

  -- invitations copine expirées
  perform public.expirer_invitations_copine();
end; $function$;

CREATE OR REPLACE FUNCTION public.traduire(p_cle text, p_langue text, p_params jsonb DEFAULT '{}'::jsonb)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v text;
  k text;
begin
  select texte into v from public.traductions where cle = p_cle and langue = coalesce(p_langue, 'fr');
  if v is null then select texte into v from public.traductions where cle = p_cle and langue = 'fr'; end if;
  if v is null then return p_cle; end if;
  for k in select jsonb_object_keys(coalesce(p_params, '{}'::jsonb)) loop
    v := replace(v, '{' || k || '}', coalesce(p_params ->> k, ''));
  end loop;
  return v;
end; $function$;

CREATE OR REPLACE FUNCTION public.valider_presence(p_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  c record;
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_retard_min int := 0;
  v_tol int;
  v_sanction int;
  v_prevenu boolean;
  v_sanctionne boolean := false;
  v_heure text;
begin
  select ca.id, ca.statut, ca.annulation, ca.presente_a, ca.hotesse_id,
         m.etablissement_id, m.date, m.heure_debut,
         h.prenom, h.photos, ca.retard_annonce_min
    into c
    from public.candidatures ca
    join public.missions m on m.id = ca.mission_id
    join public.hotesses h on h.id = ca.hotesse_id
   where ca.qr_code = p_code;

  if c.id is null then
    return jsonb_build_object('statut', 'erreur', 'message', 'QR code inconnu.');
  end if;
  if c.etablissement_id is distinct from auth.uid() then
    return jsonb_build_object('statut', 'erreur', 'message', 'Ce QR code concerne une mission d''un autre établissement.');
  end if;
  if c.statut <> 'confirmee' or c.annulation then
    return jsonb_build_object('statut', 'erreur', 'message', 'Cette venue n''est pas confirmée.');
  end if;
  if c.date not between v_jour - 1 and v_jour then
    return jsonb_build_object('statut', 'erreur', 'message', 'Ce QR est pour le ' || to_char(c.date, 'DD/MM') || '.');
  end if;
  if c.presente_a is not null then
    return jsonb_build_object(
      'statut', 'deja', 'prenom', c.prenom, 'photo', c.photos[1],
      'heure_arrivee', to_char(c.presente_a at time zone 'Europe/Paris', 'HH24:MI'),
      'date_mission', to_char(c.date, 'DD/MM/YYYY'),
      'message', c.prenom || ' est déjà enregistrée.');
  end if;

  v_retard_min := greatest(0, round(extract(epoch from (now() - (c.date + c.heure_debut) at time zone 'Europe/Paris')) / 60))::int;
  v_tol := public.reglage_num('tolerance_retard_min', 15)::int;
  v_sanction := public.reglage_num('retard_sanction_min', 30)::int;
  v_prevenu := c.retard_annonce_min is not null;

  update public.candidatures set presente_a = now(), retard_min = v_retard_min where id = c.id;

  if v_retard_min > v_tol then
    update public.hotesses set nb_retards = nb_retards + 1 where id = c.hotesse_id;
    if not v_prevenu and v_retard_min > v_sanction then
      update public.hotesses set signes_negatifs = signes_negatifs + 1, missions_honorees = 0 where id = c.hotesse_id;
      v_sanctionne := true;
      perform public.notifier_utilisateur(c.hotesse_id, 'notif.retard_sanction', jsonb_build_object('minutes', v_retard_min));
    end if;
  end if;

  -- mission honorée : compte pour le retrait des signes, SAUF si sanctionnée
  if not v_sanctionne then
    update public.hotesses set missions_honorees = missions_honorees + 1 where id = c.hotesse_id;
    update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
     where id = c.hotesse_id and missions_honorees >= 3 and signes_negatifs > 0;
  end if;

  v_heure := to_char(now() at time zone 'Europe/Paris', 'HH24:MI');

  return jsonb_build_object(
    'statut', case when v_retard_min > 0 then 'retard' else 'ok' end,
    'prenom', c.prenom,
    'photo', c.photos[1],
    'heure_arrivee', v_heure,
    'retard_min', v_retard_min,
    'retard_prevenu', v_prevenu,
    'date_mission', to_char(c.date, 'DD/MM/YYYY'),
    'message', case when v_retard_min > 0
                    then c.prenom || ' est arrivée avec ' || v_retard_min || ' min de retard (' || case when v_prevenu then 'prévenu' else 'non prévenu' end || ').'
                    else 'Bienvenue ' || c.prenom || ' !' end
  );
end; $function$;

CREATE OR REPLACE FUNCTION public.verifie_medias_mission()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if coalesce(jsonb_array_length(new.medias), 0) = 0 then
    raise exception 'Une mission doit avoir au moins une photo ou vidéo.';
  end if;
  if coalesce(new.adresse, '') = '' then
    raise exception 'Une mission doit avoir une adresse.';
  end if;
  return new;
end;
$function$;


-- ============ TRIGGERS ============

-- avis: maj_note_hotesse
CREATE TRIGGER maj_note_hotesse AFTER INSERT ON public.avis FOR EACH ROW EXECUTE FUNCTION maj_note_hotesse();

-- candidatures: apres_annulation
CREATE TRIGGER apres_annulation AFTER UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION apres_annulation();

-- candidatures: controle_candidature
CREATE TRIGGER controle_candidature BEFORE INSERT OR UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION controle_candidature();

-- candidatures: maj_places_mission_trigger
CREATE TRIGGER maj_places_mission_trigger AFTER UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION maj_places_mission();

-- candidatures: notifier_candidature_trigger
CREATE TRIGGER notifier_candidature_trigger AFTER UPDATE ON public.candidatures FOR EACH ROW EXECUTE FUNCTION notifier_candidature();

-- candidatures: notifier_nouvelle_candidature_trigger
CREATE TRIGGER notifier_nouvelle_candidature_trigger AFTER INSERT ON public.candidatures FOR EACH ROW EXECUTE FUNCTION notifier_nouvelle_candidature();

-- etablissements: nettoie_document_etab
CREATE TRIGGER nettoie_document_etab BEFORE UPDATE ON public.etablissements FOR EACH ROW EXECUTE FUNCTION nettoie_document_etab();

-- etablissements: protege_etablissement
CREATE TRIGGER protege_etablissement BEFORE UPDATE ON public.etablissements FOR EACH ROW EXECUTE FUNCTION protege_etablissement();

-- hotesses: generer_code_damup
CREATE TRIGGER generer_code_damup BEFORE INSERT ON public.hotesses FOR EACH ROW EXECUTE FUNCTION generer_code_damup();

-- hotesses: lier_invitation_verifiee
CREATE TRIGGER lier_invitation_verifiee AFTER UPDATE ON public.hotesses FOR EACH ROW EXECUTE FUNCTION lier_invitation_verifiee();

-- hotesses: nettoie_document_hotesse
CREATE TRIGGER nettoie_document_hotesse BEFORE UPDATE ON public.hotesses FOR EACH ROW EXECUTE FUNCTION nettoie_document_hotesse();

-- hotesses: protege_hotesse
CREATE TRIGGER protege_hotesse BEFORE UPDATE ON public.hotesses FOR EACH ROW EXECUTE FUNCTION protege_hotesse();

-- messages: bloque_infos_contact
CREATE TRIGGER bloque_infos_contact BEFORE INSERT OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION bloque_infos_contact();

-- messages: controle_message
CREATE TRIGGER controle_message BEFORE INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION controle_message();

-- messages: controle_message_update
CREATE TRIGGER controle_message_update BEFORE UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION controle_message_update();

-- messages: notifier_message
CREATE TRIGGER notifier_message AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION notifier_message();

-- missions: init_places_mission_trigger
CREATE TRIGGER init_places_mission_trigger BEFORE INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION init_places_mission();

-- missions: notifier_note_mission
CREATE TRIGGER notifier_note_mission AFTER UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION notifier_note_mission();

-- missions: protege_mission
CREATE TRIGGER protege_mission BEFORE INSERT OR UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION protege_mission();

-- missions: verifie_medias_mission_trigger
CREATE TRIGGER verifie_medias_mission_trigger BEFORE INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION verifie_medias_mission();

-- notifications: envoyer_email_notification
CREATE TRIGGER envoyer_email_notification AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION envoyer_email_notification();

-- paiements: creer_facture_trigger
CREATE TRIGGER creer_facture_trigger AFTER INSERT ON public.paiements FOR EACH ROW EXECUTE FUNCTION creer_facture_trigger();

-- signalements: controle_signalement
CREATE TRIGGER controle_signalement BEFORE INSERT ON public.signalements FOR EACH ROW EXECUTE FUNCTION controle_signalement();


-- ============ POLICIES ============

-- abonnements.abonnements_insert_admin (INSERT, to {)
  with check (is_admin())

-- abonnements.abonnements_select_own (SELECT, to {)
  using (((etablissement_id = auth.uid()) OR is_admin()))

-- appareils_push.appareils_push_perso (ALL, to {)
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()))

-- avis.avis_insert_etab (INSERT, to {)
  with check (((etablissement_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM (missions m
     JOIN candidatures c ON ((c.mission_id = m.id)))
  WHERE ((m.id = avis.mission_id) AND (m.etablissement_id = auth.uid()) AND (c.hotesse_id = avis.hotesse_id) AND (c.statut = 'confirmee'::text) AND (NOT c.annulation) AND (m.date <= CURRENT_DATE))))))

-- avis.avis_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- candidatures.candidatures_insert_own (INSERT, to {)
  with check ((hotesse_id = auth.uid()))

-- candidatures.candidatures_select (SELECT, to {)
  using (((hotesse_id = auth.uid()) OR is_admin() OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = candidatures.mission_id) AND (m.etablissement_id = auth.uid()))))))

-- candidatures.candidatures_update (UPDATE, to {)
  using (((hotesse_id = auth.uid()) OR is_admin() OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = candidatures.mission_id) AND (m.etablissement_id = auth.uid()))))))

-- email_erreurs.email_erreurs_admin (SELECT, to {)
  using (is_admin())

-- equipe.equipe_all_admin (ALL, to {)
  using (is_admin())
  with check (is_admin())

-- etablissements.etablissements_insert_own (INSERT, to {)
  with check ((id = auth.uid()))

-- etablissements.etablissements_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- etablissements.etablissements_update_own (UPDATE, to {)
  using (((id = auth.uid()) OR is_admin()))

-- factures.factures_lecture (SELECT, to {)
  using (((profil_id = auth.uid()) OR is_admin()))

-- hotesses.hotesses_insert_own (INSERT, to {)
  with check ((id = auth.uid()))

-- hotesses.hotesses_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- hotesses.hotesses_update_own (UPDATE, to {)
  using (((id = auth.uid()) OR is_admin()))

-- invitations_copine.invitations_lecture (SELECT, to {)
  using (((marraine_id = auth.uid()) OR (copine_id = auth.uid())))

-- messages.messages_ecriture (INSERT, to {)
  with check ((auth.uid() IS NOT NULL))

-- messages.messages_lecture (SELECT, to {)
  using (((expediteur_id = auth.uid()) OR (destinataire_id = auth.uid())))

-- messages.messages_marquer_lu (UPDATE, to {)
  using ((destinataire_id = auth.uid()))
  with check ((destinataire_id = auth.uid()))

-- missions.missions_insert_own (INSERT, to {)
  with check ((etablissement_id = auth.uid()))

-- missions.missions_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- missions.missions_update_own (UPDATE, to {)
  using (((etablissement_id = auth.uid()) OR is_admin()))

-- notifications.notifications_delete_own (DELETE, to {)
  using ((user_id = auth.uid()))

-- notifications.notifications_own (SELECT, to {)
  using ((user_id = auth.uid()))

-- notifications.notifications_select_own (SELECT, to {)
  using ((user_id = auth.uid()))

-- notifications.notifications_update_own (UPDATE, to {)
  using ((user_id = auth.uid()))

-- paiements.paiements_select (SELECT, to {)
  using (((profil_id = auth.uid()) OR is_admin()))

-- preferences_notif.preferences_notif_perso (ALL, to {)
  using ((user_id = auth.uid()))
  with check ((user_id = auth.uid()))

-- profiles.profiles_select_own (SELECT, to {)
  using (((id = auth.uid()) OR is_admin()))

-- profiles.profiles_update_admin (UPDATE, to {)
  using (is_admin())

-- settings.settings_select_anon (SELECT, to {)
  using (true)

-- settings.settings_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- settings.settings_write_admin (ALL, to {)
  using (is_admin())
  with check (is_admin())

-- signalements.signalements_insert_auth (INSERT, to {)
  with check ((signalant_id = auth.uid()))

-- signalements.signalements_select_admin (SELECT, to {)
  using (is_admin())

-- signalements.signalements_update_admin (UPDATE, to {)
  using (is_admin())

-- traductions.traductions_lecture (SELECT, to {)
  using (true)
