-- ============================================================
--  P6 — Signalements contrôlés (type/identité du signalant imposés)
-- ============================================================
create or replace function public.controle_signalement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- le type du signalant vient du profil, pas du navigateur
  select p.type into new.signalant_type from public.profiles p where p.id = auth.uid();
  if new.signalant_type is null or new.signalant_type not in ('hotesse', 'etablissement') then
    raise exception 'Signalement non autorisé.';
  end if;
  new.signalant_id := auth.uid();
  new.statut := 'nouveau';
  new.decision := null;
  if char_length(coalesce(new.motif, '')) > 1000 then raise exception 'Motif trop long (1000 caractères maximum).'; end if;
  if (select count(*) from public.signalements
       where signalant_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Trop de signalements aujourd''hui. Contacte DamUp directement.';
  end if;
  insert into public.notifications (user_id, message)
  select p.id, '🚩 Nouveau signalement à traiter.' from public.profiles p where p.type = 'admin';
  return new;
end; $$;
drop trigger if exists controle_signalement on public.signalements;
create trigger controle_signalement before insert on public.signalements
for each row execute function public.controle_signalement();
revoke execute on function public.controle_signalement() from public, anon, authenticated;
