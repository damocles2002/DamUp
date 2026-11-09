-- ============================================================
--  T2 : valider_presence renvoie un objet JSON (écran de scan)
-- ============================================================
drop function if exists public.valider_presence(text);

create or replace function public.valider_presence(p_code text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  c record;
  v_jour date := (now() at time zone 'Europe/Paris')::date;
  v_retard_min int := 0;
  v_heure text;
begin
  select ca.id, ca.statut, ca.annulation, ca.presente_a, ca.hotesse_id,
         m.etablissement_id, m.date, m.heure_debut,
         h.prenom, h.photos
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
      'statut', 'deja',
      'prenom', c.prenom,
      'photo', c.photos[1],
      'heure_arrivee', to_char(c.presente_a at time zone 'Europe/Paris', 'HH24:MI'),
      'date_mission', to_char(c.date, 'DD/MM/YYYY'),
      'message', c.prenom || ' est déjà enregistrée.'
    );
  end if;

  -- retard en minutes (0 si à l'heure)
  v_retard_min := greatest(0, round(extract(epoch from (now() - (c.date + c.heure_debut) at time zone 'Europe/Paris')) / 60))::int;

  update public.candidatures set presente_a = now() where id = c.id;
  update public.hotesses set missions_honorees = missions_honorees + 1 where id = c.hotesse_id;
  update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
   where id = c.hotesse_id and missions_honorees >= 3 and signes_negatifs > 0;

  v_heure := to_char(now() at time zone 'Europe/Paris', 'HH24:MI');

  return jsonb_build_object(
    'statut', case when v_retard_min > 0 then 'retard' else 'ok' end,
    'prenom', c.prenom,
    'photo', c.photos[1],
    'heure_arrivee', v_heure,
    'retard_min', v_retard_min,
    'retard_prevenu', false,
    'date_mission', to_char(c.date, 'DD/MM/YYYY'),
    'message', case when v_retard_min > 0
                    then c.prenom || ' est arrivée avec ' || v_retard_min || ' min de retard (non prévenu).'
                    else 'Bienvenue ' || c.prenom || ' !' end
  );
end; $$;
revoke execute on function public.valider_presence(text) from public, anon;
grant execute on function public.valider_presence(text) to authenticated;
