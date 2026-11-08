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
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
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
  "telephone" text
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
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
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
  "places_restantes" integer
);

-- TABLE notifications
create table public.notifications (
  "id" uuid NOT NULL DEFAULT gen_random_uuid(),
  "user_id" uuid NOT NULL,
  "message" text NOT NULL,
  "lu" boolean NOT NULL DEFAULT false,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
);

-- TABLE profiles
create table public.profiles (
  "id" uuid NOT NULL,
  "type" text NOT NULL,
  "email" text,
  "created_at" timestamp with time zone NOT NULL DEFAULT now()
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


-- ============ FONCTIONS ============

CREATE OR REPLACE FUNCTION public.admin_hotesses()
 RETURNS SETOF hotesses
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select * from public.hotesses where public.is_admin() order by created_at desc;
$function$;

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

CREATE OR REPLACE FUNCTION public.controle_candidature()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_m public.missions%rowtype;
  v_pris int;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then return new; end if;
  select * into v_m from public.missions where id = new.mission_id;

  if tg_op = 'INSERT' then
    if new.hotesse_id is distinct from auth.uid() then raise exception 'Modification non autorisée.'; end if;
    if v_m.statut <> 'ouverte' or v_m.date < current_date then
      raise exception 'Cette mission n''accepte plus de candidatures.';
    end if;
    new.statut := 'en_attente'; new.qr_code := null; new.annulation := false; new.confirme_a := null;
    return new;
  end if;

  if new.mission_id is distinct from old.mission_id or new.hotesse_id is distinct from old.hotesse_id
     or new.groupe_id is distinct from old.groupe_id or new.qr_code is distinct from old.qr_code
     or new.confirme_a is distinct from old.confirme_a then
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
        select count(*) into v_pris from public.candidatures
         where mission_id = new.mission_id and id <> new.id
           and statut in ('acceptee', 'confirmee') and not annulation;
        if v_pris >= v_m.nb_hotesses then
          raise exception 'Toutes les places de cette mission sont déjà prises.';
        end if;
      end if;
    end if;
  elsif auth.uid() = old.hotesse_id then
    if new.statut is distinct from old.statut
       and not (old.statut = 'acceptee' and new.statut = 'confirmee') then
      raise exception 'Changement de statut non autorisé.';
    end if;
    if old.annulation and not new.annulation then raise exception 'Une annulation ne peut pas être retirée.'; end if;
  else
    raise exception 'Modification non autorisée.';
  end if;
  return new;
end; $function$;

CREATE OR REPLACE FUNCTION public.envoyer_email_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_secret text;
  v_dest text;
begin
  -- secret lu dans le Vault Supabase
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'NOTIFIER_SECRET'
  order by created_at desc limit 1;
  if v_secret is null then return new; end if;

  select email into v_dest from auth.users where id = new.user_id;
  if v_dest is null then return new; end if;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object(
      'to', v_dest,
      'subject', 'DamUp — Nouvelle notification',
      'html', '<p style="font-family:sans-serif">' || new.message || '</p>'
    )
  );
  return new;
end;
$function$;

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
begin
  if coalesce(new.raw_app_meta_data->>'role', '') = 'admin' then r := 'admin';
  elsif m->>'role' = 'etablissement' then r := 'etablissement';
  else r := 'hotesse';
  end if;

  insert into public.profiles (id, type, email) values (new.id, r, new.email)
  on conflict (id) do nothing;

  if r = 'hotesse' then
    v_age := nullif(m->>'age', '')::int;
    if v_age is null or v_age < 18 then
      raise exception 'Inscription réservée aux personnes de 18 ans et plus.';
    end if;
    insert into public.hotesses (id, prenom, age, ville, instagram, telephone, photos)
    values (new.id, left(coalesce(nullif(trim(m->>'prenom'), ''), '?'), 50), v_age,
            left(m->>'ville', 80), left(m->>'instagram', 60), left(m->>'telephone', 20), '[]'::jsonb)
    on conflict (id) do nothing;
  elsif r = 'etablissement' then
    insert into public.etablissements (id, nom, type, ville, adresse, siret, photos, videos)
    values (new.id, left(coalesce(nullif(trim(m->>'nom'), ''), '?'), 100),
            case when m->>'type_etab' in ('bar','restaurant','club','lounge') then m->>'type_etab' end,
            left(m->>'ville', 80), left(m->>'adresse', 200),
            left(regexp_replace(coalesce(m->>'siret', ''), '\s', '', 'g'), 14), '[]'::jsonb, '[]'::jsonb)
    on conflict (id) do nothing;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.hotesse_prive(p_id uuid)
 RETURNS TABLE(telephone text, instagram text, signes_negatifs integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select h.telephone, h.instagram, h.signes_negatifs from public.hotesses h
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

CREATE OR REPLACE FUNCTION public.maj_places_mission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if new.statut in ('acceptee','confirmee') and old.statut is distinct from new.statut then
    update public.missions
    set places_restantes = greatest(coalesce(places_restantes, 0) - 1, 0)
    where id = new.mission_id;

    update public.missions
    set statut = 'cloturee'
    where id = new.mission_id and places_restantes <= 0;
  end if;
  return new;
end;
$function$;

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
begin
  if new.statut in ('acceptee','refusee') and old.statut is distinct from new.statut then
    insert into public.notifications (user_id, message)
    values (new.hotesse_id,
      case when new.statut = 'acceptee' then '🎉 Tu as été acceptée à une mission !'
           else 'Ta candidature a été refusée.' end);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notifier_nouvelle_candidature()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  insert into public.notifications (user_id, message)
  select m.etablissement_id, '📩 Nouvelle candidature reçue pour ta mission.'
  from public.missions m where m.id = new.mission_id;
  return new;
end;
$function$;

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
       or new.signes_negatifs is distinct from old.signes_negatifs then
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
  end if;
  return new;
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

-- hotesses: nettoie_document_hotesse
CREATE TRIGGER nettoie_document_hotesse BEFORE UPDATE ON public.hotesses FOR EACH ROW EXECUTE FUNCTION nettoie_document_hotesse();

-- hotesses: protege_hotesse
CREATE TRIGGER protege_hotesse BEFORE UPDATE ON public.hotesses FOR EACH ROW EXECUTE FUNCTION protege_hotesse();

-- messages: bloque_infos_contact
CREATE TRIGGER bloque_infos_contact BEFORE INSERT OR UPDATE ON public.messages FOR EACH ROW EXECUTE FUNCTION bloque_infos_contact();

-- missions: init_places_mission_trigger
CREATE TRIGGER init_places_mission_trigger BEFORE INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION init_places_mission();

-- missions: protege_mission
CREATE TRIGGER protege_mission BEFORE INSERT OR UPDATE ON public.missions FOR EACH ROW EXECUTE FUNCTION protege_mission();

-- missions: verifie_medias_mission_trigger
CREATE TRIGGER verifie_medias_mission_trigger BEFORE INSERT ON public.missions FOR EACH ROW EXECUTE FUNCTION verifie_medias_mission();

-- notifications: envoyer_email_notification
CREATE TRIGGER envoyer_email_notification AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION envoyer_email_notification();


-- ============ POLICIES ============

-- abonnements.abonnements_insert_admin (INSERT, to {)
  with check (is_admin())

-- abonnements.abonnements_select_own (SELECT, to {)
  using (((etablissement_id = auth.uid()) OR is_admin()))

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

-- equipe.equipe_all_admin (ALL, to {)
  using (is_admin())
  with check (is_admin())

-- etablissements.etablissements_insert_own (INSERT, to {)
  with check ((id = auth.uid()))

-- etablissements.etablissements_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- etablissements.etablissements_update_own (UPDATE, to {)
  using (((id = auth.uid()) OR is_admin()))

-- hotesses.hotesses_insert_own (INSERT, to {)
  with check ((id = auth.uid()))

-- hotesses.hotesses_select_auth (SELECT, to {)
  using ((auth.role() = 'authenticated'::text))

-- hotesses.hotesses_update_own (UPDATE, to {)
  using (((id = auth.uid()) OR is_admin()))

-- messages.messages_insert_participant (INSERT, to {)
  with check ((expediteur_id = auth.uid()))

-- messages.messages_select_participant (SELECT, to {)
  using (((expediteur_id = auth.uid()) OR (destinataire_id = auth.uid()) OR is_admin()))

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

-- profiles.profiles_select_own (SELECT, to {)
  using (((id = auth.uid()) OR is_admin()))

-- profiles.profiles_update_admin (UPDATE, to {)
  using (is_admin())

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
