-- ============================================================
--  F3/F4 — Factures : renvoi admin + accès aux PDF (bucket privé)
-- ============================================================

-- renvoyer une facture (admin) : réinitialise l'état puis ré-envoie
create or replace function public.admin_renvoyer_facture(p_facture_id uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  update public.factures set envoyee_le = null, envoi_erreur = null where id = p_facture_id;
  perform public.envoyer_facture(p_facture_id);
end; $$;
revoke execute on function public.admin_renvoyer_facture(uuid) from public, anon;
grant execute on function public.admin_renvoyer_facture(uuid) to authenticated;

-- lecture du PDF : admin ou titulaire (dossier profil_id/)
drop policy if exists "factures_read_admin" on storage.objects;
create policy "factures_read_admin" on storage.objects for select
  using (bucket_id = 'factures' and auth.role() = 'authenticated' and public.is_admin());

drop policy if exists "factures_read_owner" on storage.objects;
create policy "factures_read_owner" on storage.objects for select
  using (bucket_id = 'factures' and auth.role() = 'authenticated'
         and (storage.foldername(name))[1] = auth.uid()::text);
