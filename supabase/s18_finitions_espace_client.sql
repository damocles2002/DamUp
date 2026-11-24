-- ============================================================
--  DamUp : finitions espace client (s18)
--  client_id dans les réservations (pour le signalement) + exposer les noms.
-- ============================================================

create or replace function public.admin_lister_reservations()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.a_le_droit('voir_donnees') then raise exception 'Droit insuffisant.'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
    'id', r.id, 'date_soiree', r.date_soiree, 'heure_arrivee', r.heure_arrivee, 'nb_personnes', r.nb_personnes,
    'statut', r.statut, 'motif_refus', r.motif_refus, 'message_client', r.message_client,
    'client_id', r.client_id,
    'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients where id = r.client_id),
    'etablissement', (select nom from public.etablissements where id = r.etablissement_id),
    'etablissement_type', (select type from public.etablissements where id = r.etablissement_id),
    'bouteille', (select nom from public.bouteilles where id = r.bouteille_id),
    'bouteille_prix', (select prix_eur from public.bouteilles where id = r.bouteille_id)
  ) order by r.date_creation desc) from public.reservations r), '[]'::jsonb);
end; $$;

-- le signalement est aussi ouvert aux établissements connectés (depuis leur vue)
grant execute on function public.signaler_client(uuid, uuid, text, text) to authenticated;
