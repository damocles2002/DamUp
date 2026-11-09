-- ============================================================
--  E5 : masquer les champs sensibles sans droit (côté serveur)
-- ============================================================

-- annuaire établissements : champs finance = null sans voir_finances/paiements
drop function if exists public.admin_annuaire_etablissements();
create or replace function public.admin_annuaire_etablissements()
returns table (id uuid, nom text, type text, ville text, adresse text, email text, siret text,
               verifie boolean, suspendu boolean, missions_publiees bigint, inscrit_le timestamptz,
               tarif numeric, periode text, actif_jusqu_a timestamptz, dernier_mode text, reference_virement text, photos jsonb, videos jsonb)
language sql stable security definer set search_path = public as $$
  select e.id, e.nom, e.type, e.ville, e.adresse, p.email, e.siret, e.verifie, p.suspendu,
         (select count(*) from public.missions m where m.etablissement_id = e.id),
         e.created_at,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.tarif else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.periode else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.actif_jusqu_a else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements')
              then (select pa.mode from public.paiements pa where pa.profil_id = e.id order by pa.created_at desc limit 1) else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.reference_virement else null end,
         e.photos, e.videos
    from public.etablissements e join public.profiles p on p.id = e.id
   where public.a_le_droit('voir_donnees')
   order by e.created_at desc;
$$;

-- annuaire hôtesses : champs finance = null sans voir_finances/paiements
drop function if exists public.admin_annuaire_hotesses();
create or replace function public.admin_annuaire_hotesses()
returns table (id uuid, prenom text, age int, ville text, email text, instagram text, telephone text,
               verifie boolean, suspendu boolean, note_moyenne numeric, nb_avis int, signes_negatifs int,
               missions_honorees bigint, inscrite_le timestamptz, tarif numeric, periode text, actif_jusqu_a timestamptz, photos jsonb)
language sql stable security definer set search_path = public as $$
  select h.id, h.prenom, h.age, h.ville, p.email, h.instagram, h.telephone,
         h.verifie, p.suspendu, h.note_moyenne, h.nb_avis, h.signes_negatifs,
         (select count(*) from public.candidatures c where c.hotesse_id = h.id and c.presente_a is not null),
         h.created_at,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.tarif else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.periode else null end,
         case when public.a_le_droit('voir_finances') or public.a_le_droit('paiements') then p.actif_jusqu_a else null end,
         h.photos
    from public.hotesses h join public.profiles p on p.id = h.id
   where public.a_le_droit('voir_donnees')
   order by h.created_at desc;
$$;
revoke execute on function public.admin_annuaire_hotesses(), public.admin_annuaire_etablissements() from anon;

-- modifier le tarif (droit paiements + journalisation)
create or replace function public.admin_modifier_tarif(p_profil uuid, p_tarif numeric, p_periode text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.a_le_droit('paiements') then raise exception 'Droit insuffisant.'; end if;
  update public.profiles set tarif = p_tarif, periode = p_periode where id = p_profil;
  perform public.journaliser('tarif_modifie', 'profil', p_profil, jsonb_build_object('tarif', p_tarif, 'periode', p_periode));
end; $$;
revoke execute on function public.admin_modifier_tarif(uuid, numeric, text) from public, anon;
grant execute on function public.admin_modifier_tarif(uuid, numeric, text) to authenticated;
