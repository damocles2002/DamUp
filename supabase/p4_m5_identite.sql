-- ============================================================
--  M5 — Vérification d'identité (manuelle, gratuite)
-- ============================================================

-- bucket privé pour les pièces d'identité et selfies
insert into storage.buckets (id, name, public) values ('documents', 'documents', false)
on conflict (id) do update set public = false;

drop policy if exists "documents_depot_perso" on storage.objects;
create policy "documents_depot_perso" on storage.objects for insert to authenticated
  with check (bucket_id = 'documents' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists "documents_lecture_admin" on storage.objects;
create policy "documents_lecture_admin" on storage.objects for select to authenticated
  using (bucket_id = 'documents' and public.is_admin());
drop policy if exists "documents_suppression_admin" on storage.objects;
create policy "documents_suppression_admin" on storage.objects for delete to authenticated
  using (bucket_id = 'documents' and public.is_admin());

-- colonnes de suivi de la vérification d'identité
alter table public.hotesses add column if not exists id_document jsonb;
alter table public.hotesses add column if not exists verifie_le timestamptz;
alter table public.hotesses add column if not exists verifie_par uuid;
alter table public.etablissements add column if not exists id_document jsonb;
alter table public.etablissements add column if not exists verifie_le timestamptz;
alter table public.etablissements add column if not exists verifie_par uuid;

-- rappel automatique si aucun document 48 h après l'inscription
create or replace function public.rappeler_verification() returns void
language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications (user_id, message, cle, params)
  select h.id, public.traduire('verif.rappel', coalesce(p.langue, 'fr')), 'verif.rappel', '{}'::jsonb
    from public.hotesses h join public.profiles p on p.id = h.id
   where h.id_document is null and not h.verifie
     and h.created_at < now() - interval '48 hours'
     and not exists (select 1 from public.notifications n
                      where n.user_id = h.id and n.cle = 'verif.rappel');
end; $$;
revoke execute on function public.rappeler_verification() from public, anon;

-- admin : valider/refuser l'identité (supprime la référence aux documents)
create or replace function public.admin_valider_identite(p_profil uuid, p_type text, p_valide boolean, p_motif text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  if p_type = 'hotesse' then
    update public.hotesses set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null
     where id = p_profil;
  else
    update public.etablissements set verifie = p_valide, verifie_le = now(), verifie_par = auth.uid(), id_document = null
     where id = p_profil;
  end if;
  if not p_valide then
    perform public.notifier_utilisateur(p_profil, 'notif.validation_refusee', jsonb_build_object('motif', coalesce(p_motif, '')));
  end if;
end; $$;
revoke execute on function public.admin_valider_identite(uuid, text, boolean, text) from public, anon;
grant execute on function public.admin_valider_identite(uuid, text, boolean, text) to authenticated;
