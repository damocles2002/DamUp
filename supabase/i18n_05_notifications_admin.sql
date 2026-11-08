-- ============================================================
--  DamUp — i18n tâche 0 : notifications traduites restantes
--  1) notifier_nouvelle_candidature via notifier_utilisateur()
--  2) admin_refuser_profil (refus de validation + notification)
--  3) admin_annuler_mission (annulation admin + notifications)
-- ============================================================

-- 1) nouvelle candidature : localisée (prénom + date)
create or replace function public.notifier_nouvelle_candidature() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_prenom text;
  v_date_m date;
  v_langue text;
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
  return new;
end; $$;
revoke execute on function public.notifier_nouvelle_candidature() from public, anon, authenticated;

-- 2) refus de validation (admin) : met verifie=false + notification localisée
create or replace function public.admin_refuser_profil(p_profil uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare v_type text;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select type into v_type from public.profiles where id = p_profil;
  if v_type = 'hotesse' then
    update public.hotesses set verifie = false where id = p_profil;
  elsif v_type = 'etablissement' then
    update public.etablissements set verifie = false where id = p_profil;
  else
    raise exception 'Profil introuvable.';
  end if;
  perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee',
    jsonb_build_object('motif', coalesce(p_motif, '')));
end; $$;
revoke execute on function public.admin_refuser_profil(uuid, text) from public, anon;
grant execute on function public.admin_refuser_profil(uuid, text) to authenticated;

-- 3) annulation d'une mission par l'admin : prévient l'établissement + hôtesses acceptées/confirmées
create or replace function public.admin_annuler_mission(p_mission uuid, p_motif text) returns void
language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  update public.missions set statut = 'annulee' where id = p_mission;
  select etablissement_id into v_etab from public.missions where id = p_mission;
  if v_etab is null then raise exception 'Mission introuvable.'; end if;
  perform public.notifier_utilisateur(v_etab, 'notif.mission_annulee_admin',
    jsonb_build_object('motif', coalesce(p_motif, '')));
  insert into public.notifications (user_id, message, cle, params)
  select c.hotesse_id,
         public.traduire('notif.mission_annulee_admin', coalesce(p.langue, 'fr'),
           jsonb_build_object('motif', coalesce(p_motif, ''))),
         'notif.mission_annulee_admin', jsonb_build_object('motif', coalesce(p_motif, ''))
    from public.candidatures c
    join public.profiles p on p.id = c.hotesse_id
   where c.mission_id = p_mission and c.statut in ('acceptee', 'confirmee') and not c.annulation;
end; $$;
revoke execute on function public.admin_annuler_mission(uuid, text) from public, anon;
grant execute on function public.admin_annuler_mission(uuid, text) to authenticated;
