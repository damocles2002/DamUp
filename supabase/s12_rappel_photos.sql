-- ============================================================
--  DamUp : rappel photos (s12)
--  Envoie l'e-mail de rappel aux hôtesses sans assez de photos.
--  p_profil = null → toutes les hôtesses concernées (retourne le nombre).
-- ============================================================

create or replace function public.admin_rappeler_photos(p_profil uuid default null)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_h record;
  v_n int := 0;
begin
  if not public.a_le_droit('valider_profils') then raise exception 'Droit insuffisant.'; end if;

  if p_profil is not null then
    perform public.envoyer_mail('rappel_photos', p_profil,
      jsonb_build_object('lien', 'https://damup.fr/hotesse-profil.html'));
    return 1;
  end if;

  for v_h in
    select h.id
      from public.hotesses h
      join public.profiles p on p.id = h.id
     where coalesce(jsonb_array_length(h.photos), 0) < 4
       and not p.suspendu
  loop
    perform public.envoyer_mail('rappel_photos', v_h.id,
      jsonb_build_object('lien', 'https://damup.fr/hotesse-profil.html'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end; $$;

grant execute on function public.admin_rappeler_photos(uuid) to authenticated;
