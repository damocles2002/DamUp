-- ============================================================
--  T7 : Fiabilité (sanction_signes + admin_annuler_sanction)
-- ============================================================

alter table public.candidatures add column if not exists sanction_signes int;

-- enregistre le nombre de signes appliqués à chaque sanction (pour pouvoir l'annuler)
create or replace function public.declarer_absence(p_candidature uuid, p_venue boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_c public.candidatures%rowtype;
  v_m public.missions%rowtype;
  v_fin timestamptz;
  v_debut timestamptz;
  v_n int;
  v_prenom text;
  v_lieu text;
begin
  select * into v_c from public.candidatures where id = p_candidature;
  if v_c.id is null then raise exception 'Candidature introuvable.'; end if;
  select * into v_m from public.missions where id = v_c.mission_id;
  if v_m.etablissement_id is distinct from auth.uid() then
    raise exception 'Réservé à l''établissement de la mission.';
  end if;
  if v_c.statut <> 'confirmee' or v_c.annulation then raise exception 'Cette venue n''est pas confirmée.'; end if;
  if v_c.presente_a is not null or v_c.absence_declaree_le is not null then
    raise exception 'Cette venue a déjà été traitée.';
  end if;
  v_fin := (v_m.date + v_m.heure_fin + case when v_m.heure_fin <= v_m.heure_debut then interval '1 day' else interval '0' end) at time zone 'Europe/Paris';
  if now() < v_fin then raise exception 'La mission n''est pas encore terminée.'; end if;
  if now() > v_fin + interval '24 hours' then raise exception 'Délai de déclaration dépassé (24 h).'; end if;

  if p_venue then
    v_debut := (v_m.date + v_m.heure_debut) at time zone 'Europe/Paris';
    update public.candidatures set presente_a = v_debut, retard_min = 0 where id = p_candidature;
    update public.hotesses set missions_honorees = missions_honorees + 1 where id = v_c.hotesse_id;
    update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
     where id = v_c.hotesse_id and missions_honorees >= 3 and signes_negatifs > 0;
  else
    v_n := public.reglage_num('signes_absence', 2)::int;
    select prenom into v_prenom from public.hotesses where id = v_c.hotesse_id;
    select nom into v_lieu from public.etablissements where id = v_m.etablissement_id;
    update public.candidatures set absence_declaree_le = now(), sanction_signes = v_n where id = p_candidature;
    update public.hotesses set nb_absences = nb_absences + 1, signes_negatifs = signes_negatifs + v_n, missions_honorees = 0
     where id = v_c.hotesse_id;
    perform public.notifier_utilisateur(v_c.hotesse_id, 'notif.absence_declaree',
      jsonb_build_object('lieu', v_lieu, 'date', to_char(v_m.date, 'DD/MM'), 'n', v_n));
    insert into public.notifications (user_id, message, cle, params)
    select p.id, public.traduire('notif.absence_declaree_admin', 'fr',
             jsonb_build_object('prenom', v_prenom, 'date', to_char(v_m.date, 'DD/MM'), 'lieu', v_lieu)),
           'notif.absence_declaree_admin',
           jsonb_build_object('prenom', v_prenom, 'date', to_char(v_m.date, 'DD/MM'), 'lieu', v_lieu)
      from public.profiles p where p.type = 'admin';
  end if;
end; $$;
revoke execute on function public.declarer_absence(uuid, boolean) from public, anon;
grant execute on function public.declarer_absence(uuid, boolean) to authenticated;

create or replace function public.apres_annulation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_debut timestamptz;
  v_h int;
  v_signes int := 1;
begin
  if new.annulation and not old.annulation then
    if old.statut = 'confirmee' then
      select (m.date + m.heure_debut) at time zone 'Europe/Paris' into v_debut
        from public.missions m where m.id = new.mission_id;
      v_h := public.reglage_num('annulation_tardive_h', 3)::int;
      if v_debut - now() < make_interval(hours => v_h) then v_signes := 2; end if;
      update public.hotesses set signes_negatifs = signes_negatifs + v_signes, missions_honorees = 0
       where id = new.hotesse_id;
      update public.candidatures set sanction_signes = v_signes where id = new.id;
      perform public.notifier_utilisateur(new.hotesse_id, 'notif.annulation_sanction',
        jsonb_build_object('n', v_signes));
    end if;
    insert into public.notifications (user_id, message)
    select m.etablissement_id, '⚠️ Une hôtesse a annulé sa venue : une place se libère sur ta mission du '
           || to_char(m.date, 'DD/MM') || '.'
      from public.missions m where m.id = new.mission_id;
  end if;
  return new;
end; $$;
revoke execute on function public.apres_annulation() from public, anon, authenticated;

create or replace function public.valider_presence(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
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
  v_sanctionne := (v_retard_min > v_tol and not v_prevenu and v_retard_min > v_sanction);

  update public.candidatures set presente_a = now(), retard_min = v_retard_min,
    sanction_signes = case when v_sanctionne then 1 else null end
  where id = c.id;

  if v_retard_min > v_tol then
    update public.hotesses set nb_retards = nb_retards + 1 where id = c.hotesse_id;
    if v_sanctionne then
      update public.hotesses set signes_negatifs = signes_negatifs + 1, missions_honorees = 0 where id = c.hotesse_id;
      perform public.notifier_utilisateur(c.hotesse_id, 'notif.retard_sanction', jsonb_build_object('minutes', v_retard_min));
    end if;
  end if;

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
end; $$;
revoke execute on function public.valider_presence(text) from public, anon;
grant execute on function public.valider_presence(text) to authenticated;

-- admin : annuler une sanction (retire les signes correspondants)
create or replace function public.admin_annuler_sanction(p_candidature uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_c public.candidatures%rowtype;
  v_signes int;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_motif is null or trim(p_motif) = '' then raise exception 'Motif obligatoire.'; end if;
  select * into v_c from public.candidatures where id = p_candidature;
  if v_c.id is null then raise exception 'Candidature introuvable.'; end if;
  if v_c.sanction_annulee_le is not null then raise exception 'Cette sanction a déjà été annulée.'; end if;
  v_signes := coalesce(v_c.sanction_signes, 0);
  if v_signes <= 0 then raise exception 'Aucune sanction à annuler sur cette candidature.'; end if;
  update public.candidatures set sanction_annulee_le = now() where id = p_candidature;
  update public.hotesses set signes_negatifs = greatest(0, signes_negatifs - v_signes) where id = v_c.hotesse_id;
  perform public.notifier_utilisateur(v_c.hotesse_id, 'notif.sanction_annulee', jsonb_build_object('motif', p_motif));
end; $$;
revoke execute on function public.admin_annuler_sanction(uuid, text) from public, anon;
grant execute on function public.admin_annuler_sanction(uuid, text) to authenticated;
