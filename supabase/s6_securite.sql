-- ============================================================
--  DamUp : corrections de sécurité (audit) — étapes 1 à 7
--  Appliqué en une fois, puis réexport de schema_en_ligne.sql.
-- ============================================================

-- ============================================================
-- ÉTAPE 1 — CRITIQUE : contrôles à la publication d'une mission
-- ============================================================
create or replace function public.protege_mission() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'UPDATE' and new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'Modification non autorisée.';
    end if;

    if tg_op = 'INSERT' then
      if new.etablissement_id is distinct from auth.uid() then
        raise exception 'Modification non autorisée.';
      end if;
      if public.est_suspendu() then
        raise exception 'Ton compte est suspendu. Contacte DamUp.';
      end if;
      if not exists (
        select 1 from public.profiles p
        join public.etablissements e on e.id = p.id
        where p.id = auth.uid() and p.type = 'etablissement' and e.verifie
      ) then
        raise exception 'Ton établissement doit être validé par DamUp avant de publier.';
      end if;
      if not public.abonnement_ok(auth.uid()) then
        raise exception 'Ton abonnement est terminé : renouvelle-le pour publier de nouvelles missions.';
      end if;
      if new.date < current_date then
        raise exception 'La date de la mission est déjà passée.';
      end if;
      if new.nb_hotesses not between 1 and public.reglage_num('max_hotesses_mission', 50)::int then
        raise exception 'Le nombre d''hôtesses doit être entre 1 et %.',
          public.reglage_num('max_hotesses_mission', 50)::int;
      end if;
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
end; $$;

-- contrôle candidature : abonnement vérifié avant de postuler
create or replace function public.controle_candidature() returns trigger
language plpgsql as $$
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
    if not public.abonnement_ok(auth.uid()) then
      raise exception 'Ton abonnement est terminé : renouvelle-le pour postuler.';
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
end; $$;

-- ============================================================
-- ÉTAPE 2 — faille XSS : refuser les balises à la source
-- ============================================================
alter table public.etablissements
  add constraint etablissements_type_ok
  check (type is null or type in ('bar', 'restaurant', 'club', 'lounge'));

create or replace function public.refuse_balises() returns trigger
language plpgsql as $$
begin
  if tg_table_name = 'hotesses' then
    if concat_ws(' ', new.prenom, new.ville, new.instagram, new.telephone) ~ '[<>]' then
      raise exception 'Les caractères < et > ne sont pas autorisés.';
    end if;
  else
    if concat_ws(' ', new.nom, new.ville, new.adresse, new.responsable_nom, new.siret) ~ '[<>]' then
      raise exception 'Les caractères < et > ne sont pas autorisés.';
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists refuse_balises on public.hotesses;
create trigger refuse_balises before insert or update on public.hotesses
  for each row execute function public.refuse_balises();

drop trigger if exists refuse_balises on public.etablissements;
create trigger refuse_balises before insert or update on public.etablissements
  for each row execute function public.refuse_balises();

-- ============================================================
-- ÉTAPE 3 — photos des messages réservées aux participants
-- ============================================================
create or replace function public.participant_conversation_chemin(p_nom text) returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  d text[] := storage.foldername(p_nom);
  v_mission uuid;
  v_hotesse uuid;
begin
  begin
    v_mission := d[1]::uuid;
    v_hotesse := d[2]::uuid;
  exception when others then
    return false;
  end;
  return exists (
    select 1 from public.candidatures c
    join public.missions m on m.id = c.mission_id
    where c.mission_id = v_mission and c.hotesse_id = v_hotesse
      and c.statut in ('acceptee', 'confirmee')
      and (public.is_admin() or auth.uid() in (c.hotesse_id, m.etablissement_id))
  );
end; $$;
revoke execute on function public.participant_conversation_chemin(text) from public, anon;
grant execute on function public.participant_conversation_chemin(text) to authenticated;

drop policy if exists "messages_photos_select" on storage.objects;
create policy "messages_photos_select" on storage.objects for select to authenticated
  using (bucket_id = 'messages' and public.participant_conversation_chemin(name));

drop policy if exists "messages_photos_insert" on storage.objects;
create policy "messages_photos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'messages' and public.participant_conversation_chemin(name));

-- ============================================================
-- ÉTAPE 4 — champs bloqués après la vérification
-- ============================================================
create or replace function public.protege_hotesse() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.verifie_le is distinct from old.verifie_le
       or new.verifie_par is distinct from old.verifie_par
       or new.note_moyenne is distinct from old.note_moyenne
       or new.nb_avis is distinct from old.nb_avis
       or new.signes_negatifs is distinct from old.signes_negatifs
       or new.missions_honorees is distinct from old.missions_honorees
       or new.nb_retards is distinct from old.nb_retards
       or new.nb_absences is distinct from old.nb_absences
       or new.code_damup is distinct from old.code_damup
       or new.age is distinct from old.age then
      raise exception 'Modification non autorisée.';
    end if;
    -- une fois vérifiée, les pièces ne se remplacent plus
    if old.verifie and new.id_document is distinct from old.id_document then
      raise exception 'Modification non autorisée.';
    end if;
    -- un prénom modifié doit être revérifié
    if old.verifie and new.prenom is distinct from old.prenom then
      new.verifie := false;
    end if;
  end if;
  return new;
end; $$;

create or replace function public.protege_etablissement() returns trigger
language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.verifie_le is distinct from old.verifie_le
       or new.verifie_par is distinct from old.verifie_par
       or new.abonnement_actif is distinct from old.abonnement_actif then
      raise exception 'Modification non autorisée.';
    end if;
    if old.verifie and (new.id_document is distinct from old.id_document
                        or new.id_document_resp is distinct from old.id_document_resp) then
      raise exception 'Modification non autorisée.';
    end if;
    -- SIRET, nom ou responsable modifié : nouvelle vérification par l'admin
    if new.siret is distinct from old.siret
       or new.nom is distinct from old.nom
       or new.responsable_nom is distinct from old.responsable_nom then
      new.verifie := false;
    end if;
  end if;
  return new;
end; $$;

-- ============================================================
-- ÉTAPE 5 — fonctions internes retirées aux comptes connectés
-- ============================================================
revoke execute on function public.rappeler_verification() from public, anon, authenticated;
revoke execute on function public.notifier_presences_non_scannees() from public, anon, authenticated;
revoke execute on function public.expirer_invitations_copine() from public, anon, authenticated;
revoke execute on function public.admin_stats_membre(uuid) from public, anon, authenticated;

grant execute on function public.rappeler_verification() to service_role;
grant execute on function public.notifier_presences_non_scannees() to service_role;
grant execute on function public.expirer_invitations_copine() to service_role;
grant execute on function public.admin_stats_membre(uuid) to service_role;

-- ============================================================
-- ÉTAPE 6 — réglages privés cachés aux visiteurs
-- ============================================================
drop policy if exists "settings_select_anon" on public.settings;
create policy "settings_select_anon" on public.settings for select to anon
  using (key in ('annonce', 'contact_email', 'partenaire_nom', 'partenaire_lien',
                 'partenaire_logo', 'maintenance', 'villes', 'inscriptions_ouvertes'));

drop policy if exists "settings_select_auth" on public.settings;
create policy "settings_select_auth" on public.settings for select to authenticated
  using (
    key not in ('iban', 'bic', 'titulaire_iban', 'vendeur_nom', 'vendeur_adresse', 'vendeur_siret')
    or public.is_admin()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.type = 'etablissement')
  );

-- ============================================================
-- ÉTAPE 7 — anciennes règles photos (listage public retiré)
-- ============================================================
drop policy if exists "photos_lecture_publique" on storage.objects;
drop policy if exists "photos_upload_own" on storage.objects;
