-- ============================================================
--  DamUp : Tableau de bord établissement (s17)
--  Deux fonctions serveur (établissement depuis la session).
-- ============================================================

-- Bloc 1 : hôtesses appelées sur la semaine
create or replace function public.stats_hotesses_semaine(p_debut_semaine date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_fin date := p_debut_semaine + 6;
  v_appelees int; v_soirees int; v_presences int; v_absences int; v_missions int;
  v_prev int; v_evolution int;
begin
  select id into v_etab from public.profiles where id = auth.uid() and type = 'etablissement';
  if v_etab is null then raise exception 'Non autorisé.'; end if;

  select count(distinct cd.hotesse_id) into v_appelees
    from public.candidatures cd join public.missions m on m.id = cd.mission_id
   where m.etablissement_id = v_etab and m.date between p_debut_semaine and v_fin
     and m.statut <> 'annulee' and cd.statut = 'confirmee' and not cd.annulation;

  select count(*) into v_soirees
    from public.candidatures cd join public.missions m on m.id = cd.mission_id
   where m.etablissement_id = v_etab and m.date between p_debut_semaine and v_fin
     and m.statut <> 'annulee' and cd.statut = 'confirmee' and not cd.annulation;

  select count(*) into v_presences
    from public.candidatures cd join public.missions m on m.id = cd.mission_id
   where m.etablissement_id = v_etab and m.date between p_debut_semaine and v_fin
     and cd.statut = 'confirmee' and not cd.annulation and cd.presente_a is not null;

  -- absences : soirées - présences, missions déjà passées seulement
  select coalesce(sum(case when m.date < current_date then 1 else 0 end) - sum(case when m.date < current_date and cd.presente_a is not null then 1 else 0 end), 0)
    into v_absences
    from public.candidatures cd join public.missions m on m.id = cd.mission_id
   where m.etablissement_id = v_etab and m.date between p_debut_semaine and v_fin
     and cd.statut = 'confirmee' and not cd.annulation;

  select count(*) into v_missions
    from public.missions where etablissement_id = v_etab and date between p_debut_semaine and v_fin and statut <> 'annulee';

  select count(distinct cd.hotesse_id) into v_prev
    from public.candidatures cd join public.missions m on m.id = cd.mission_id
   where m.etablissement_id = v_etab and m.date between (p_debut_semaine - 7) and (p_debut_semaine - 1)
     and m.statut <> 'annulee' and cd.statut = 'confirmee' and not cd.annulation;
  v_evolution := v_appelees - coalesce(v_prev, 0);

  return jsonb_build_object(
    'appelees', v_appelees, 'soirees', v_soirees, 'presences', v_presences,
    'absences', v_absences, 'missions', v_missions, 'evolution', v_evolution,
    'missions_detail', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', m.id, 'date', m.date, 'titre', m.titre, 'heure_debut', m.heure_debut,
        'hotesses', coalesce((select jsonb_agg(jsonb_build_object(
          'prenom', h.prenom, 'photo', h.photos->0, 'presente', cd.presente_a is not null))
          from public.candidatures cd join public.hotesses h on h.id = cd.hotesse_id
         where cd.mission_id = m.id and cd.statut = 'confirmee' and not cd.annulation), '[]'::jsonb)
      ) order by m.date)
      from public.missions m where m.etablissement_id = v_etab and m.date between p_debut_semaine and v_fin and m.statut <> 'annulee'
    ), '[]'::jsonb),
    'graphique', coalesce((
      select jsonb_agg(jsonb_build_object('debut_semaine', s.d, 'appelees', (
        select count(distinct cd.hotesse_id)
          from public.candidatures cd join public.missions m2 on m2.id = cd.mission_id
         where m2.etablissement_id = v_etab and m2.date between s.d and (s.d + 6)
           and m2.statut <> 'annulee' and cd.statut = 'confirmee' and not cd.annulation)))
      from generate_series(p_debut_semaine - 7*7, p_debut_semaine, interval '7 days') as s(d)
    ), '[]'::jsonb)
  );
end; $$;

-- Bloc 2 : chiffres DamUp du mois
create or replace function public.stats_damup_mois(p_mois date)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_etab uuid;
  v_fin date := (p_mois + interval '1 month' - interval '1 day')::date;
  v_ca numeric := 0; v_tables int := 0; v_clients int := 0; v_couverts int := 0;
  v_panier numeric := 0; v_bouteilles int := 0; v_bouteilles_total numeric := 0;
  v_a_venir int := 0; v_commission numeric := 0; v_commission_statut text := '';
  v_ca_prev numeric := 0; v_evolution numeric := 0;
begin
  select id into v_etab from public.profiles where id = auth.uid() and type = 'etablissement';
  if v_etab is null then raise exception 'Non autorisé.'; end if;

  select coalesce(sum(rb.montant_retenu), 0) into v_ca
    from public.reservations r join public.remboursements rb on rb.reservation_id = r.id
   where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin;

  select count(*) into v_tables
    from public.reservations r where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin;

  select count(distinct r.client_id) into v_clients
    from public.reservations r where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin;

  select coalesce(sum(r.nb_personnes), 0) into v_couverts
    from public.reservations r where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin;

  select coalesce(round(v_ca / nullif((select count(*) from public.reservations r where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin and exists (select 1 from public.remboursements rb where rb.reservation_id = r.id and rb.montant_retenu is not null)), 0)), 0) into v_panier;

  select coalesce(count(*), 0), coalesce(sum(b.prix_eur), 0) into v_bouteilles, v_bouteilles_total
    from public.reservations r join public.bouteilles b on b.id = r.bouteille_id
   where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between p_mois and v_fin;

  select count(*) into v_a_venir
    from public.reservations r where r.etablissement_id = v_etab and r.statut = 'confirmee' and r.date_soiree >= current_date and r.date_soiree <= v_fin;

  select coalesce(sum(c.montant_commission), 0) into v_commission
    from public.commissions c join public.reservations r on r.id = c.reservation_id
   where r.etablissement_id = v_etab and r.date_soiree between p_mois and v_fin;

  select coalesce((select c.statut from public.commissions c join public.reservations r on r.id = c.reservation_id
    where r.etablissement_id = v_etab and r.date_soiree between p_mois and v_fin order by c.created_at desc limit 1), '') into v_commission_statut;

  -- évolution vs mois précédent (même période)
  select coalesce(sum(rb.montant_retenu), 0) into v_ca_prev
    from public.reservations r join public.remboursements rb on rb.reservation_id = r.id
   where r.etablissement_id = v_etab and r.statut = 'terminee' and r.date_soiree between (p_mois - interval '1 month') and (v_fin - interval '1 month');
  v_evolution := case when v_ca_prev > 0 then round((v_ca - v_ca_prev) / v_ca_prev * 100) else null end;

  return jsonb_build_object(
    'ca', v_ca, 'tables', v_tables, 'clients', v_clients, 'couverts', v_couverts,
    'panier_moyen', v_panier, 'bouteilles', v_bouteilles, 'bouteilles_total', v_bouteilles_total,
    'a_venir', v_a_venir, 'evolution', v_evolution, 'commission', v_commission, 'commission_statut', v_commission_statut,
    'tables_detail', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', r.id, 'date', r.date_soiree, 'client', (select prenom || ' ' || left(nom, 1) || '.' from public.clients where id = r.client_id),
        'couverts', r.nb_personnes, 'bouteille', (select nom from public.bouteilles where id = r.bouteille_id),
        'montant', (select montant_retenu from public.remboursements where reservation_id = r.id),
        'statut', r.statut, 'commission', (select montant_commission from public.commissions where reservation_id = r.id)
      ) order by r.date_soiree desc)
      from public.reservations r where r.etablissement_id = v_etab and r.date_soiree between p_mois and v_fin and r.statut in ('terminee','no_show','confirmee')
    ), '[]'::jsonb),
    'graphique', coalesce((
      select jsonb_agg(jsonb_build_object('mois', s.d, 'ca', (
        select coalesce(sum(rb.montant_retenu), 0)
          from public.reservations r2 join public.remboursements rb on rb.reservation_id = r2.id
         where r2.etablissement_id = v_etab and r2.statut = 'terminee'
           and r2.date_soiree between s.d and (s.d + interval '1 month' - interval '1 day')::date)))
      from generate_series((p_mois - interval '11 months')::date, p_mois, interval '1 month') as s(d)
    ), '[]'::jsonb)
  );
end; $$;

grant execute on function public.stats_hotesses_semaine(date) to authenticated;
grant execute on function public.stats_damup_mois(date) to authenticated;
