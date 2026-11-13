-- ============================================================
--  DamUp : détail d'une invitation « copine » pour l'écran
--  (sécurité definer : la copine ne peut pas lire la candidature
--   de sa marraine via RLS, donc on expose le détail ici).
-- ============================================================
CREATE OR REPLACE FUNCTION public.invitation_copine_detail(p_invitation uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_inv public.invitations_copine%rowtype;
  v_mission public.missions%rowtype;
  v_etab public.etablissements%rowtype;
  v_marraine text;
  v_copine text;
begin
  select * into v_inv from public.invitations_copine
   where id = p_invitation and (marraine_id = auth.uid() or copine_id = auth.uid());
  if v_inv.id is null then raise exception 'Invitation introuvable.'; end if;

  select * into v_mission from public.missions
   where id = (select mission_id from public.candidatures where id = v_inv.candidature_id);
  select * into v_etab from public.etablissements where id = v_mission.etablissement_id;
  select prenom into v_marraine from public.hotesses where id = v_inv.marraine_id;
  select prenom into v_copine from public.hotesses where id = v_inv.copine_id;

  return jsonb_build_object(
    'marraine_prenom', coalesce(v_marraine, v_inv.prenom_indique),
    'copine_prenom', coalesce(v_copine, v_inv.prenom_indique),
    'statut', v_inv.statut,
    'mission', jsonb_build_object(
      'id', v_mission.id,
      'date', v_mission.date,
      'heure_debut', v_mission.heure_debut,
      'heure_fin', v_mission.heure_fin,
      'adresse', v_mission.adresse,
      'note', v_mission.note,
      'articles_offerts', coalesce(v_mission.articles_offerts, '[]'::jsonb),
      'etablissement', jsonb_build_object('nom', v_etab.nom, 'ville', v_etab.ville, 'type', v_etab.type)
    )
  );
end; $function$;

grant execute on function public.invitation_copine_detail(uuid) to authenticated;
