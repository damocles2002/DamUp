-- ============================================================
--  DamUp : bucket factures (privé) + politiques (s19)
--  Le client (anon) peut déposer une photo ; seul un compte
--  connecté (admin/établissement) peut la lire.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('factures', 'factures', false)
on conflict (id) do nothing;

drop policy if exists "factures_upload_anon" on storage.objects;
create policy "factures_upload_anon" on storage.objects
  for insert to anon with check (bucket_id = 'factures');

drop policy if exists "factures_read_auth" on storage.objects;
create policy "factures_read_auth" on storage.objects
  for select to authenticated using (bucket_id = 'factures');
