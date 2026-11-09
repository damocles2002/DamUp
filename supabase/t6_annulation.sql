-- ============================================================
--  T6 : Annulation tardive (2 signes au lieu de 1)
-- ============================================================
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
