-- ============================================================
--  Q2 — Les fonctions lisent les réglages (plus de valeurs en dur)
-- ============================================================

-- 1) délais de confirmation lisibles depuis les réglages
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
     or new.confirme_a is distinct from old.confirme_a or new.presente_a is distinct from old.presente_a then
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
          now() + case when v_debut - now() < interval '24 hours'
            then make_interval(hours => public.reglage_num('delai_confirmation_court_h', 3)::int)
            else make_interval(hours => public.reglage_num('delai_confirmation_h', 12)::int) end,
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

-- 2) nombre maximum d'hôtesses lisible depuis les réglages
create or replace function public.protege_mission() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'UPDATE' and new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'Modification non autorisée.';
    end if;
    if tg_op = 'INSERT' then
      if public.est_suspendu() then raise exception 'Ton compte est suspendu. Contacte DamUp.'; end if;
      if not exists (select 1 from public.etablissements e where e.id = auth.uid() and e.verifie) then
        raise exception 'Ton établissement doit être validé par DamUp avant de publier.';
      end if;
      if new.date < current_date then raise exception 'La date de la mission est déjà passée.'; end if;
      if new.nb_hotesses not between 1 and public.reglage_num('max_hotesses_mission', 50)::int then
        raise exception 'Le nombre d''hôtesses doit être entre 1 et %.', public.reglage_num('max_hotesses_mission', 50)::int;
      end if;
      new.statut := 'ouverte';
    end if;
  end if;
  return new;
end; $$;

-- 3) seuil de missions honorées lisible depuis les réglages
create or replace function public.valider_presence(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare
  c record;
  v_jour date := (now() at time zone 'Europe/Paris')::date;
begin
  select ca.id, ca.statut, ca.annulation, ca.presente_a, ca.hotesse_id,
         m.etablissement_id, m.date, h.prenom
    into c
    from public.candidatures ca
    join public.missions m on m.id = ca.mission_id
    join public.hotesses h on h.id = ca.hotesse_id
   where ca.qr_code = p_code;
  if c.id is null then raise exception 'QR code inconnu.'; end if;
  if c.etablissement_id is distinct from auth.uid() then
    raise exception 'Ce QR code concerne une mission d''un autre établissement.';
  end if;
  if c.statut <> 'confirmee' or c.annulation then raise exception 'Cette venue n''est pas confirmée.'; end if;
  if c.date not between v_jour - 1 and v_jour then raise exception 'Ce QR code n''est pas pour aujourd''hui.'; end if;
  if c.presente_a is not null then return c.prenom || ' est déjà enregistrée.'; end if;

  update public.candidatures set presente_a = now() where id = c.id;
  update public.hotesses set missions_honorees = missions_honorees + 1 where id = c.hotesse_id;
  update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
   where id = c.hotesse_id
     and missions_honorees >= public.reglage_num('missions_pour_retirer_signe', 3)::int
     and signes_negatifs > 0;
  return '✅ ' || c.prenom || ' est bien arrivée.';
end; $$;

-- 4) suspension automatique après N annulations
create or replace function public.apres_annulation() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_signes int;
begin
  if new.annulation and not old.annulation then
    if old.statut = 'confirmee' then
      update public.hotesses set signes_negatifs = signes_negatifs + 1, missions_honorees = 0
       where id = new.hotesse_id
       returning signes_negatifs into v_signes;
      if v_signes >= public.reglage_num('signes_avant_suspension', 3)::int then
        update public.profiles set suspendu = true where id = new.hotesse_id;
        insert into public.notifications (user_id, message) values (new.hotesse_id,
          '🚫 Compte suspendu automatiquement après ' || v_signes || ' annulations. Contacte DamUp.');
        insert into public.notifications (user_id, message)
        select p.id, '🚫 Une hôtesse a été suspendue automatiquement (' || v_signes || ' annulations).'
          from public.profiles p where p.type = 'admin';
      end if;
    end if;
    insert into public.notifications (user_id, message)
    select m.etablissement_id, '⚠️ Une hôtesse a annulé sa venue : une place se libère sur ta mission du '
           || to_char(m.date, 'DD/MM') || '.'
      from public.missions m where m.id = new.mission_id;
  end if;
  return new;
end; $$;

-- 5) inscriptions ouvertes/fermées + villes autorisées
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
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

  insert into public.profiles (id, type, email) values (new.id, r, new.email)
  on conflict (id) do nothing;

  if r = 'hotesse' then
    v_age := nullif(m->>'age', '')::int;
    if v_age is null or v_age < 18 then
      raise exception 'Inscription réservée aux personnes de 18 ans et plus.';
    end if;
    v_villes := (select value from public.settings where key = 'villes');
    if v_villes is not null and jsonb_array_length(v_villes) > 0
       and not (coalesce(m->>'ville', '') = ANY (select jsonb_array_elements_text(v_villes))) then
      raise exception 'Cette ville n''est pas encore ouverte aux inscriptions.';
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
end; $$;
