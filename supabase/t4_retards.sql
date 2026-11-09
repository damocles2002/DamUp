-- ============================================================
--  T4 : Retards (colonnes, seuils réglables, annonce, sanction)
-- ============================================================

alter table public.candidatures
  add column if not exists retard_annonce_min int check (retard_annonce_min between 5 and 180),
  add column if not exists retard_annonce_le timestamptz,
  add column if not exists retard_min int,
  add column if not exists absence_declaree_le timestamptz,
  add column if not exists sanction_annulee_le timestamptz;

alter table public.hotesses
  add column if not exists nb_retards int not null default 0,
  add column if not exists nb_absences int not null default 0;

insert into public.settings (key, value) values
  ('tolerance_retard_min', '15'),
  ('retard_sanction_min', '30'),
  ('annulation_tardive_h', '3'),
  ('signes_absence', '2')
on conflict (key) do nothing;

-- 1) les nouvelles colonnes ne se modifient que via les fonctions dédiées
create or replace function public.controle_candidature() returns trigger language plpgsql as $$
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
end; $$;

-- 2) nb_retards / nb_absences protégés (comme signes_negatifs)
create or replace function public.protege_hotesse() returns trigger language plpgsql as $$
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
end; $$;

-- 3) hotesse_prive expose aussi les compteurs retards/absences
drop function if exists public.hotesse_prive(uuid);
create function public.hotesse_prive(p_id uuid)
returns table (telephone text, instagram text, signes_negatifs int, missions_honorees int, nb_retards int, nb_absences int)
language sql stable security definer set search_path = public as $$
  select h.telephone, h.instagram, h.signes_negatifs, h.missions_honorees, h.nb_retards, h.nb_absences
  from public.hotesses h
  where h.id = p_id and (p_id = auth.uid() or public.is_admin());
$$;

-- 4) annoncer un retard (hôtesse, avant le début + tolérance)
create or replace function public.annoncer_retard(p_candidature uuid, p_minutes int) returns void
language plpgsql security definer set search_path = public as $$
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
end; $$;
revoke execute on function public.annoncer_retard(uuid, int) from public, anon;
grant execute on function public.annoncer_retard(uuid, int) to authenticated;

-- 5) valider_presence : calcul du retard + sanction éventuelle
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
end; $$;
revoke execute on function public.valider_presence(text) from public, anon;
grant execute on function public.valider_presence(text) to authenticated;
