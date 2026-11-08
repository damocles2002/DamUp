-- ============================================================
--  B2 : Empêcher une hôtesse/établissement de modifier ses
--  champs "officiels" (verifie, note, abonnement, etc.)
-- ============================================================
create or replace function public.protege_hotesse() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.note_moyenne is distinct from old.note_moyenne
       or new.nb_avis is distinct from old.nb_avis
       or new.signes_negatifs is distinct from old.signes_negatifs then
      raise exception 'Modification non autorisée.';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists protege_hotesse on public.hotesses;
create trigger protege_hotesse before update on public.hotesses
for each row execute function public.protege_hotesse();

create or replace function public.protege_etablissement() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.abonnement_actif is distinct from old.abonnement_actif then
      raise exception 'Modification non autorisée.';
    end if;
    -- un SIRET modifié doit être revérifié par l'admin
    if new.siret is distinct from old.siret then new.verifie := false; end if;
  end if;
  return new;
end; $$;
drop trigger if exists protege_etablissement on public.etablissements;
create trigger protege_etablissement before update on public.etablissements
for each row execute function public.protege_etablissement();

create or replace function public.protege_mission() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'UPDATE' and new.etablissement_id is distinct from old.etablissement_id then
      raise exception 'Modification non autorisée.';
    end if;
    if tg_op = 'INSERT' then
      if new.date < current_date then raise exception 'La date de la mission est déjà passée.'; end if;
      if new.nb_hotesses not between 1 and 50 then raise exception 'Le nombre d''hôtesses doit être entre 1 et 50.'; end if;
      new.statut := 'ouverte';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists protege_mission on public.missions;
create trigger protege_mission before insert or update on public.missions
for each row execute function public.protege_mission();
