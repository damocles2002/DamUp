-- ============================================================
--  B4 — Les données privées des hôtesses ne sont plus lisibles
--  par tout le monde (on limite les colonnes lisibles)
-- ============================================================
revoke select on public.hotesses from anon, authenticated;
grant select (id, prenom, age, ville, photos, note_moyenne, nb_avis, verifie, created_at)
  on public.hotesses to authenticated;

revoke select on public.etablissements from anon, authenticated;
grant select (id, nom, type, adresse, ville, siret, photos, videos, verifie, abonnement_actif, created_at)
  on public.etablissements to authenticated;

-- l'hôtesse elle-même, ou l'admin, lit les champs privés via cette fonction
create or replace function public.hotesse_prive(p_id uuid)
returns table (telephone text, instagram text, signes_negatifs int)
language sql stable security definer set search_path = public as $$
  select h.telephone, h.instagram, h.signes_negatifs from public.hotesses h
  where h.id = p_id and (p_id = auth.uid() or public.is_admin());
$$;

-- liste complète pour le back-office (admin uniquement)
create or replace function public.admin_hotesses()
returns setof public.hotesses
language sql stable security definer set search_path = public as $$
  select * from public.hotesses where public.is_admin() order by created_at desc;
$$;
revoke execute on function public.hotesse_prive(uuid), public.admin_hotesses() from anon;

-- bucket photos : envoi et suppression limités au dossier de l'utilisateur
drop policy if exists "photos_insert_perso" on storage.objects;
create policy "photos_insert_perso" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "photos_delete_perso" on storage.objects;
create policy "photos_delete_perso" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
