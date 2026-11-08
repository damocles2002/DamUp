-- ============================================================
--  Q3 : Faire respecter l'abonnement + rappels + tarif à l'inscription
-- ============================================================

-- 1) publication bloquée si abonnement expiré
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
      if not public.abonnement_ok(auth.uid()) then
        raise exception 'Ton abonnement est terminé : renouvelle-le pour publier de nouvelles missions.';
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

-- 2) candidature bloquée si abonnement expiré (sans effet tant que paiement hôtesses éteint)
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

-- 3) tâches auto : rappels de fin d'abonnement + le reste
create or replace function public.taches_auto() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- rappels de fin d'abonnement (3 jours avant)
  with a_prevenir as (
    update public.profiles p set rappel_fin_envoye_pour = p.actif_jusqu_a
     where p.actif_jusqu_a between now() and now() + interval '3 days'
       and p.rappel_fin_envoye_pour is distinct from p.actif_jusqu_a
       and ((p.type = 'etablissement' and public.reglage_bool('paiement_etablissements_actif', false))
         or (p.type = 'hotesse' and public.reglage_bool('paiement_hotesses_actif', false)))
    returning p.id, p.actif_jusqu_a
  )
  insert into public.notifications (user_id, message)
  select id, '⏳ Ton abonnement DamUp se termine le '
             || to_char(actif_jusqu_a at time zone 'Europe/Paris', 'DD/MM') || '. Pense à le renouveler.'
    from a_prevenir
  union all
  select ad.id, '💶 ' || (select count(*) from a_prevenir) || ' abonnement(s) se terminent dans moins de 3 jours.'
    from public.profiles ad
   where ad.type = 'admin' and exists (select 1 from a_prevenir);

  -- rappel confirmation
  with a_rappeler as (
    update public.candidatures c set rappel_envoye = true
     where c.statut = 'acceptee' and not c.annulation and not c.rappel_envoye
       and c.confirme_a > now() and c.confirme_a - now() <= interval '1 hour'
    returning c.hotesse_id, c.confirme_a
  )
  insert into public.notifications (user_id, message)
  select hotesse_id, '⏳ Rappel : confirme ta venue avant '
         || to_char(confirme_a at time zone 'Europe/Paris', 'HH24"h"MI')
         || ', sinon ta place sera libérée.'
    from a_rappeler;

  -- acceptations non confirmées à temps
  update public.candidatures set statut = 'expiree'
   where statut = 'acceptee' and not annulation
     and confirme_a is not null and confirme_a < now();

  -- missions terminées
  update public.missions set statut = 'terminee'
   where statut in ('ouverte', 'cloturee', 'en_cours')
     and ((date + heure_fin + case when heure_fin <= heure_debut then interval '1 day' else interval '0' end)
          at time zone 'Europe/Paris') < now();
end; $$;

-- 4) inscription : tarif, période et essai par défaut
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

  insert into public.profiles (id, type, email, tarif, periode, actif_jusqu_a)
  values (new.id, r, new.email,
    case when r = 'etablissement' then public.reglage_num('prix_defaut_etablissement', 79)
         when r = 'hotesse' then public.reglage_num('prix_defaut_hotesse', 0)
         else null end,
    case when r = 'admin' then null else 'mensuel' end,
    now() + make_interval(days => public.reglage_num('essai_jours', 7)::int))
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
