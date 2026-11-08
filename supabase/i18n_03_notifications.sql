-- ============================================================
--  DamUp — i18n L5 : migration des notifications vers notifier_utilisateur()
--  (messages produits dans la langue du destinataire)
-- ============================================================

-- 1) notifier_candidature (acceptée / refusée / expirée / confirmée)
create or replace function public.notifier_candidature() returns trigger
language plpgsql security definer set search_path = public as $$
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
end; $$;
revoke execute on function public.notifier_candidature() from public, anon, authenticated;

-- 2) apres_annulation (signe négatif, suspension, place libérée)
create or replace function public.apres_annulation() returns trigger
language plpgsql security definer set search_path = public as $$
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
end; $$;
drop trigger if exists apres_annulation on public.candidatures;
create trigger apres_annulation after update on public.candidatures
for each row execute function public.apres_annulation();
revoke execute on function public.apres_annulation() from public, anon, authenticated;

-- 3) taches_auto (rappel confirmation + fin d'abonnement)
create or replace function public.taches_auto() returns void
language plpgsql security definer set search_path = public as $$
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
end; $$;
revoke execute on function public.taches_auto() from public, anon, authenticated;

-- 4) prolonger_abonnement (paiement reçu / offert)
create or replace function public.prolonger_abonnement(
  p_profil uuid, p_montant numeric, p_mode text, p_periode text,
  p_date timestamptz, p_ref text, p_note text)
returns public.paiements language plpgsql security definer set search_path = public as $$
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
end; $$;
revoke execute on function public.prolonger_abonnement(uuid, numeric, text, text, timestamptz, text, text)
  from public, anon, authenticated;
grant execute on function public.prolonger_abonnement(uuid, numeric, text, text, timestamptz, text, text)
  to service_role;

-- 5) controle_signalement (notification admin)
create or replace function public.controle_signalement() returns trigger
language plpgsql security definer set search_path = public as $$
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
end; $$;
drop trigger if exists controle_signalement on public.signalements;
create trigger controle_signalement before insert on public.signalements
for each row execute function public.controle_signalement();
revoke execute on function public.controle_signalement() from public, anon, authenticated;
