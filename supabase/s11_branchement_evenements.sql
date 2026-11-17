-- ============================================================
--  DamUp : branchement des événements sur les modèles (s11)
--  Inscription, validation d'identité, candidatures, missions,
--  copine : chaque événement envoie son e-mail pro.
-- ============================================================

-- 1) envoyer_mail enrichi : injecte aussi {nom_etablissement}
create or replace function public.envoyer_mail(p_evenement text, p_destinataire uuid, p_variables jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_anon text;
  v_email text;
  v_type text;
  v_role text;
  v_prenom text;
begin
  select email, type into v_email, v_type from public.profiles where id = p_destinataire;
  if v_email is null or v_email = '' then return; end if;
  v_role := case when v_type = 'etablissement' then 'etablissement' else 'hotesse' end;

  v_prenom := coalesce(
    (select prenom from public.hotesses where id = p_destinataire),
    (select nullif(responsable_nom, '') from public.etablissements where id = p_destinataire),
    (select nom from public.etablissements where id = p_destinataire),
    ''
  );
  if not (p_variables ? 'prenom') then
    p_variables := p_variables || jsonb_build_object('prenom', v_prenom);
  end if;
  if v_type = 'etablissement' and not (p_variables ? 'nom_etablissement') then
    p_variables := p_variables || jsonb_build_object('nom_etablissement',
      (select nom from public.etablissements where id = p_destinataire));
  end if;

  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return; end if;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('evenement', p_evenement, 'email', v_email, 'role', v_role, 'variables', p_variables)
  );
end; $$;

revoke execute on function public.envoyer_mail(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.envoyer_mail(text, uuid, jsonb) to service_role;

-- 2) inscription → 1.1 / 1.2
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
    perform public.envoyer_mail('inscription', new.id, jsonb_build_object('lien', 'https://damup.fr/hotesse-profil.html'));
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
    perform public.envoyer_mail('inscription', new.id, jsonb_build_object('lien', 'https://damup.fr/etablissement.html'));
  end if;
  return new;
end; $$;

-- 3) validation / refus d'identité → 1.4 / 1.5 / 1.6
create or replace function public.admin_valider_identite(p_profil uuid, p_type text, p_valide boolean, p_motif text DEFAULT NULL::text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('valider_profils') then raise exception 'Droit insuffisant.'; end if;
  if p_type = 'hotesse' then
    update public.hotesses set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null where id = p_profil;
  else
    update public.etablissements set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null where id = p_profil;
  end if;
  perform public.journaliser(case when p_valide then 'identite_validee' else 'identite_refusee' end, 'profil', p_profil, jsonb_build_object('motif', p_motif));
  if p_valide then
    if p_type = 'hotesse' then
      perform public.envoyer_mail('identite_validee', p_profil, jsonb_build_object('lien', 'https://damup.fr/hotesse.html'));
    else
      perform public.envoyer_mail('etablissement_valide', p_profil, jsonb_build_object('lien', 'https://damup.fr/etablissement.html'));
    end if;
  else
    perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee', jsonb_build_object('motif', coalesce(p_motif, '')));
    if p_type = 'hotesse' then
      perform public.envoyer_mail('identite_refusee', p_profil, jsonb_build_object('motif', coalesce(p_motif, ''), 'lien', 'https://damup.fr/hotesse-profil.html'));
    else
      perform public.envoyer_mail('etablissement_refuse', p_profil, jsonb_build_object('motif', coalesce(p_motif, '')));
    end if;
  end if;
end; $$;

-- 4) candidature acceptée / refusée + présence confirmée → 3.2 / 3.3 / 4.3
create or replace function public.notifier_candidature()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lieu text;
  v_date_m date;
  v_langue text;
  v_m public.missions%rowtype;
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
    select * into v_m from public.missions where id = new.mission_id;
    perform public.envoyer_mail('candidature_acceptee', new.hotesse_id,
      jsonb_build_object('nom_etablissement', v_lieu, 'titre_mission', v_m.titre,
        'date_mission', public.date_courte(v_date_m, v_langue),
        'horaires', public.heure_courte(v_m.heure_debut, v_langue) || ' - ' || public.heure_courte(v_m.heure_fin, v_langue),
        'adresse', coalesce(v_m.adresse, ''), 'avantages', coalesce(v_m.articles_offerts, ''),
        'lien', 'https://damup.fr/hotesse.html'));
  elsif new.statut = 'refusee' then
    select e.nom, m.date, coalesce(p.langue, 'fr') into v_lieu, v_date_m, v_langue
      from public.missions m
      join public.etablissements e on e.id = m.etablissement_id
      join public.profiles p on p.id = new.hotesse_id
     where m.id = new.mission_id;
    perform public.notifier_utilisateur(new.hotesse_id, 'notif.refusee',
      jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, v_langue)));
    select * into v_m from public.missions where id = new.mission_id;
    perform public.envoyer_mail('candidature_refusee', new.hotesse_id,
      jsonb_build_object('nom_etablissement', v_lieu, 'titre_mission', v_m.titre, 'lien', 'https://damup.fr/hotesse.html'));
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
    -- 4.3 présence confirmée (à l'établissement)
    select * into v_m from public.missions where id = new.mission_id;
    perform public.envoyer_mail('presence_confirmee', v_m.etablissement_id,
      jsonb_build_object('titre_mission', v_m.titre, 'date_mission', public.date_courte(v_date_m, v_langue),
        'horaires', public.heure_courte(v_m.heure_debut, v_langue) || ' - ' || public.heure_courte(v_m.heure_fin, v_langue),
        'prenom_hotesse', coalesce((select prenom from public.hotesses where id = new.hotesse_id), ''),
        'lien', 'https://damup.fr/etablissement.html'));
  end if;
  return new;
end; $$;

-- 5) mission publiée → 4.1 (à l'établissement)
create or replace function public.alerte_mission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_etab text;
begin
  select nom into v_etab from public.etablissements where id = new.etablissement_id;
  perform public.notifier_equipe('missions', 'notif.mission_admin',
    jsonb_build_object('etablissement', coalesce(v_etab, ''), 'date', public.date_courte(new.date, 'fr'), 'nb', new.nb_hotesses, 'id', new.id));
  perform public.envoyer_mail('mission_publiee', new.etablissement_id,
    jsonb_build_object('titre_mission', new.titre, 'date_mission', public.date_courte(new.date, 'fr'),
      'lien', 'https://damup.fr/etablissement.html'));
  return new;
end; $$;

-- 6) mission annulée → 3.5 (à chaque hôtesse retenue)
create or replace function public.admin_annuler_mission(p_mission uuid, p_motif text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_m public.missions%rowtype;
  v_lieu text;
begin
  if not public.a_le_droit('gerer_missions') then raise exception 'Droit insuffisant.'; end if;
  update public.missions set statut = 'annulee' where id = p_mission;
  select etablissement_id into v_etab from public.missions where id = p_mission;
  if v_etab is null then raise exception 'Mission introuvable.'; end if;
  select * into v_m from public.missions where id = p_mission;
  select nom into v_lieu from public.etablissements where id = v_etab;
  perform public.journaliser('mission_annulee', 'mission', p_mission, jsonb_build_object('motif', p_motif));
  perform public.notifier_utilisateur(v_etab, 'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, '')));
  insert into public.notifications (user_id, message, cle, params)
  select c.hotesse_id, public.traduire('notif.mission_annulee_admin', coalesce(p.langue, 'fr'), jsonb_build_object('motif', coalesce(p_motif, ''))),
         'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, ''))
    from public.candidatures c join public.profiles p on p.id = c.hotesse_id
   where c.mission_id = p_mission and c.statut in ('acceptee', 'confirmee') and not c.annulation;
  -- e-mail pro à chaque hôtesse retenue
  perform public.envoyer_mail('mission_annulee', c.hotesse_id,
    jsonb_build_object('nom_etablissement', v_lieu, 'titre_mission', v_m.titre,
      'date_mission', public.date_courte(v_m.date, 'fr'), 'lien', 'https://damup.fr/hotesse.html'))
    from public.candidatures c
   where c.mission_id = p_mission and c.statut in ('acceptee', 'confirmee') and not c.annulation;
end; $$;

-- 7) copine proposée (via code DamUp) → 3.7
create or replace function public.proposer_copine(p_candidature uuid, p_code_damup text, p_prenom text)
returns text
language plpgsql
security definer
set search_path = public
as $$
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
    perform public.envoyer_mail('copine_invitee', v_copine.id,
      jsonb_build_object('prenom', v_prenom_marraine, 'lien', 'https://damup.fr/login.html?mode=inscription&role=hotesse'));
    return null;
  else
    insert into public.invitations_copine (candidature_id, marraine_id, prenom_indique, statut)
    values (p_candidature, v_marraine, p_prenom, 'envoyee')
    returning code_invitation into v_code;
    return v_code;
  end if;
end; $$;
