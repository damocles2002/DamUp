-- ============================================================
--  A4 — Recettes avec nom du client (établissement ou hôtesse)
-- ============================================================
create or replace function public.admin_recettes()
returns table (id uuid, numero_recu text, mode text, montant numeric,
               periode_debut timestamptz, periode_fin timestamptz,
               created_at timestamptz, client text)
language sql stable security definer set search_path = public as $$
  select p.id, p.numero_recu, p.mode, p.montant, p.periode_debut, p.periode_fin, p.created_at,
         coalesce(e.nom, h.prenom, pr.email) as client
    from public.paiements p
    join public.profiles pr on pr.id = p.profil_id
    left join public.etablissements e on e.id = p.profil_id
    left join public.hotesses h on h.id = p.profil_id
   where public.is_admin()
   order by p.created_at desc;
$$;
revoke execute on function public.admin_recettes() from anon;
