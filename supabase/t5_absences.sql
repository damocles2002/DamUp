-- ============================================================
--  T5 : Absences (déclaration par l'établissement)
-- ============================================================

-- notifier l'établissement des hôtesses non scannées (mission terminée), une fois par candidature
create or replace function public.notifier_presences_non_scannees() returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select c.id as candidature, c.hotesse_id, m.etablissement_id, m.date, h.prenom
      from public.candidatures c
      join public.missions m on m.id = c.mission_id
      join public.hotesses h on h.id = c.hotesse_id
     where c.statut = 'confirmee' and not c.annulation
       and c.presente_a is null and c.absence_declaree_le is null
       and m.statut = 'terminee'
       and not exists (
         select 1 from public.notifications n
          where n.user_id = m.etablissement_id and n.cle = 'notif.verifier_presence'
            and (n.params->>'candidature') = c.id::text
       )
  loop
    perform public.notifier_utilisateur(r.etablissement_id, 'notif.verifier_presence',
      jsonb_build_object('prenom', r.prenom, 'date', to_char(r.date, 'DD/MM'), 'candidature', r.candidature));
  end loop;
end; $$;
revoke execute on function public.notifier_presences_non_scannees() from public, anon;

-- déclarer l'absence (ou la présence oubliée) : réservée à l'établissement, fin de mission -> +24 h
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
    -- elle est venue, scan oublié : présence à l'heure de début, sans retard
    v_debut := (v_m.date + v_m.heure_debut) at time zone 'Europe/Paris';
    update public.candidatures set presente_a = v_debut, retard_min = 0 where id = p_candidature;
    update public.hotesses set missions_honorees = missions_honorees + 1 where id = v_c.hotesse_id;
    update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
     where id = v_c.hotesse_id and missions_honorees >= 3 and signes_negatifs > 0;
  else
    -- absence : +signes_absence signes négatifs
    v_n := public.reglage_num('signes_absence', 2)::int;
    select prenom into v_prenom from public.hotesses where id = v_c.hotesse_id;
    select nom into v_lieu from public.etablissements where id = v_m.etablissement_id;
    update public.candidatures set absence_declaree_le = now() where id = p_candidature;
    update public.hotesses set nb_absences = nb_absences + 1, signes_negatifs = signes_negatifs + v_n, missions_honorees = 0
     where id = v_c.hotesse_id;
    perform public.notifier_utilisateur(v_c.hotesse_id, 'notif.absence_declaree',
      jsonb_build_object('lieu', v_lieu, 'date', to_char(v_m.date, 'DD/MM'), 'n', v_n));
    insert into public.notifications (user_id, message, cle, params)
    select e.user_id, public.traduire('notif.absence_declaree_admin', 'fr',
             jsonb_build_object('prenom', v_prenom, 'date', to_char(v_m.date, 'DD/MM'), 'lieu', v_lieu)),
           'notif.absence_declaree_admin',
           jsonb_build_object('prenom', v_prenom, 'date', to_char(v_m.date, 'DD/MM'), 'lieu', v_lieu)
      from public.equipe e join public.profiles p on p.id = e.user_id
     where p.type = 'admin' and not e.suspendu and not p.suspendu
       and (e.proprietaire or coalesce((e.droits->>'suspendre_utilisateurs')::boolean, false));
  end if;
end; $$;
revoke execute on function public.declarer_absence(uuid, boolean) from public, anon;
grant execute on function public.declarer_absence(uuid, boolean) to authenticated;
