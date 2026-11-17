-- ============================================================
--  DamUp : branchement des derniers événements (s13)
--  Candidature envoyée, nouvelle candidature, désistement,
--  signalement reçu, mission terminée + rappel d'avis, fin d'essai.
-- ============================================================

-- 1) candidature : 3.1 (envoyée à l'hôtesse) + 4.2 (nouvelle à l'établissement)
create or replace function public.notifier_nouvelle_candidature()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prenom text;
  v_date_m date;
  v_langue text;
  v_m public.missions%rowtype;
  v_lieu text;
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
  select * into v_m from public.missions where id = new.mission_id;
  select nom into v_lieu from public.etablissements where id = v_m.etablissement_id;
  -- 4.2 nouvelle candidature → l'établissement
  perform public.envoyer_mail('nouvelle_candidature', v_m.etablissement_id,
    jsonb_build_object('titre_mission', v_m.titre, 'date_mission', public.date_courte(v_date_m, v_langue),
      'lien', 'https://damup.fr/etablissement.html'));
  -- 3.1 candidature envoyée → l'hôtesse
  perform public.envoyer_mail('candidature_envoyee', new.hotesse_id,
    jsonb_build_object('titre_mission', v_m.titre, 'nom_etablissement', v_lieu,
      'date_mission', public.date_courte(v_date_m, v_langue),
      'lien', 'https://damup.fr/hotesse.html'));
  return new;
end; $$;

-- 2) désistement d'une hôtesse → 4.4 (à l'établissement)
create or replace function public.apres_annulation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_debut timestamptz;
  v_h int;
  v_signes int := 1;
  v_signes_final int;
  v_m public.missions%rowtype;
begin
  if new.annulation and not old.annulation then
    if old.statut = 'confirmee' then
      select (m.date + m.heure_debut) at time zone 'Europe/Paris' into v_debut
        from public.missions m where m.id = new.mission_id;
      v_h := public.reglage_num('annulation_tardive_h', 3)::int;
      if v_debut - now() < make_interval(hours => v_h) then v_signes := 2; end if;
      update public.hotesses set signes_negatifs = signes_negatifs + v_signes, missions_honorees = 0
       where id = new.hotesse_id
       returning signes_negatifs into v_signes_final;
      if v_signes_final >= public.reglage_num('signes_avant_suspension', 3)::int then
        update public.profiles set suspendu = true where id = new.hotesse_id;
        perform public.notifier_utilisateur(new.hotesse_id, 'notif.suspension_hotesse',
          jsonb_build_object('n', v_signes_final));
        insert into public.notifications (user_id, message, cle, params)
        select e.user_id, public.traduire('notif.suspension_admin', 'fr', jsonb_build_object('n', v_signes_final)),
               'notif.suspension_admin', jsonb_build_object('n', v_signes_final)
          from public.equipe e join public.profiles p on p.id = e.user_id
         where p.type = 'admin' and not e.suspendu and not p.suspendu
           and (e.proprietaire or coalesce((e.droits->>'suspendre_utilisateurs')::boolean, false));
      end if;
      update public.candidatures set sanction_signes = v_signes where id = new.id;
      perform public.notifier_utilisateur(new.hotesse_id, 'notif.annulation_sanction',
        jsonb_build_object('n', v_signes));
    end if;
    insert into public.notifications (user_id, message)
    select m.etablissement_id, '⚠️ Une hôtesse a annulé sa venue : une place se libère sur ta mission du '
           || to_char(m.date, 'DD/MM') || '.'
      from public.missions m where m.id = new.mission_id;
    -- 4.4 désistement → e-mail pro à l'établissement
    select * into v_m from public.missions where id = new.mission_id;
    perform public.envoyer_mail('desistement', v_m.etablissement_id,
      jsonb_build_object('titre_mission', v_m.titre,
        'date_mission', public.date_courte(v_m.date, 'fr'),
        'prenom_hotesse', coalesce((select prenom from public.hotesses where id = new.hotesse_id), ''),
        'lien', 'https://damup.fr/etablissement.html'));
  end if;
  return new;
end; $$;

-- 3) signalement reçu → 5.5 (accusé de réception à l'auteur)
create or replace function public.controle_signalement()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
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
  select e.user_id, public.traduire('notif.signalement_admin', 'fr', '{}'::jsonb),
         'notif.signalement_admin', '{}'::jsonb
    from public.equipe e join public.profiles p on p.id = e.user_id
   where p.type = 'admin' and not e.suspendu and not p.suspendu
     and (e.proprietaire or coalesce((e.droits->>'signalements')::boolean, false));
  perform public.envoyer_mail('signalement_recu', auth.uid(),
    jsonb_build_object('objet_signalement', coalesce(nullif(new.motif, ''), 'un comportement signalé')));
  return new;
end; $$;

-- 4) mission terminée → 3.6 (hôtesses) + 4.5 (rappel d'avis à l'établissement)
create or replace function public.apres_mission_terminee()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lieu text;
begin
  if new.statut = 'terminee' and old.statut is distinct from 'terminee' then
    select nom into v_lieu from public.etablissements where id = new.etablissement_id;
    perform public.envoyer_mail('mission_terminee', c.hotesse_id,
      jsonb_build_object('nom_etablissement', v_lieu, 'titre_mission', new.titre,
        'lien', 'https://damup.fr/hotesse.html'))
      from public.candidatures c
     where c.mission_id = new.id and c.statut = 'confirmee' and not c.annulation;
    perform public.envoyer_mail('rappel_avis', new.etablissement_id,
      jsonb_build_object('titre_mission', new.titre,
        'prenom_hotesse', coalesce((select h.prenom from public.hotesses h
                                     join public.candidatures c on c.hotesse_id = h.id
                                    where c.mission_id = new.id and c.statut = 'confirmee' limit 1), ''),
        'lien', 'https://damup.fr/etablissement.html'));
  end if;
  return new;
end; $$;

drop trigger if exists apres_mission_terminee on public.missions;
create trigger apres_mission_terminee after update on public.missions
  for each row execute function public.apres_mission_terminee();

-- 5) fin d'essai (établissements) → 4.6
create or replace function public.taches_auto()
returns void
language plpgsql
security definer
set search_path = public
as $$
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

  -- e-mail pro : fin d'essai des établissements (3 jours avant)
  perform public.envoyer_mail('fin_essai', p.id,
    jsonb_build_object('date_fin_essai', public.date_courte(p.actif_jusqu_a::date, coalesce(p.langue, 'fr')),
      'lien', 'https://damup.fr/etablissement.html'))
    from public.profiles p
   where p.type = 'etablissement'
     and p.actif_jusqu_a between now() and now() + interval '3 days'
     and p.rappel_fin_envoye_pour is distinct from p.actif_jusqu_a
     and public.reglage_bool('paiement_etablissements_actif', false);

  -- rappels de fin d'abonnement (3 jours avant)
  with a_prevenir as (
    update public.profiles p set rappel_fin_envoye_pour = p.actif_jusqu_a
     where p.actif_jusqu_a between now() and now() + interval '3 days'
       and p.rappel_fin_envoye_pour is distinct from p.actif_jusqu_a
       and ((p.type = 'etablissement' and public.reglage_bool('paiement_etablissements_actif', false))
         or (p.type = 'hotesse' and public.reglage_bool('paiement_hotesses_actif', false)))
    returning p.id, p.actif_jusqu_a, p.langue, p.type
  )
  insert into public.notifications (user_id, message, cle, params)
  select a.id,
         public.traduire('notif.fin_abonnement', a.langue,
           jsonb_build_object('date', public.date_courte(a.actif_jusqu_a::date, a.langue))),
         'notif.fin_abonnement',
         jsonb_build_object('date', public.date_courte(a.actif_jusqu_a::date, a.langue))
    from a_prevenir a
  union all
  select e.user_id,
         public.traduire('notif.fin_abonnement_admin', 'fr', jsonb_build_object('n', (select count(*) from a_prevenir))),
         'notif.fin_abonnement_admin',
         jsonb_build_object('n', (select count(*) from a_prevenir))
    from public.equipe e join public.profiles p on p.id = e.user_id
   where p.type = 'admin' and not e.suspendu and not p.suspendu
     and (e.proprietaire or coalesce((e.droits->>'voir_finances')::boolean, false) or coalesce((e.droits->>'paiements')::boolean, false))
     and exists (select 1 from a_prevenir);

  -- missions terminées
  update public.missions set statut = 'terminee'
   where statut in ('ouverte', 'cloturee', 'en_cours')
     and ((date + heure_fin + case when heure_fin <= heure_debut then interval '1 day' else interval '0' end)
          at time zone 'Europe/Paris') < now();

  -- hôtesses non scannées : notifier l'établissement (une fois par candidature)
  perform public.notifier_presences_non_scannees();

  -- invitations copine expirées
  perform public.expirer_invitations_copine();
end; $$;
