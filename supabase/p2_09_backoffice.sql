-- ============================================================
--  P9 : Suspension + validation imposées à la publication
-- ============================================================
create or replace function public.protege_mission() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'UPDATE' and new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'Modification non autorisée.';
    end if;
    if tg_op = 'INSERT' then
      if public.est_suspendu() then raise exception 'Ton compte est suspendu. Contacte DamUp.'; end if;
      if not exists (select 1 from public.etablissements e where e.id = auth.uid() and e.verifie) then
        raise exception 'Ton établissement doit être validé par DamUp avant de publier.';
      end if;
      if new.date < current_date then raise exception 'La date de la mission est déjà passée.'; end if;
      if new.nb_hotesses not between 1 and 50 then raise exception 'Le nombre d''hôtesses doit être entre 1 et 50.'; end if;
      new.statut := 'ouverte';
    end if;
  end if;
  return new;
end; $$;
