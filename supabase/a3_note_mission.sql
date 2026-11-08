-- ============================================================
--  A3 : Note libre sur les missions
--  Colonne note + blocage des coordonnées + notification
--  quand la note change (hôtesses acceptées/confirmées).
-- ============================================================

alter table public.missions add column if not exists note text;
alter table public.missions drop constraint if exists missions_note_longueur;
alter table public.missions add constraint missions_note_longueur
  check (char_length(coalesce(note, '')) <= 500);

-- protege_mission : applique à la note le même blocage que la messagerie
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
    if coalesce(new.note, '') ~ '(\+33|0[1-9][ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2})' then
      raise exception 'Les numéros de téléphone ne sont pas autorisés dans la note.' using hint = 'note_coordonnees';
    end if;
    if coalesce(new.note, '') ~ '(instagram\.com|facebook\.com|snapchat|tiktok|@[a-zA-Z0-9_.]{2,})' then
      raise exception 'Les comptes de réseaux sociaux ne sont pas autorisés dans la note.' using hint = 'note_coordonnees';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists protege_mission on public.missions;
create trigger protege_mission before insert or update on public.missions
for each row execute function public.protege_mission();

-- notification quand la note d'une mission publiée est modifiée
create or replace function public.notifier_note_mission() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_lieu text;
  v_date_m date;
begin
  if new.note is distinct from old.note and coalesce(new.note, '') <> '' then
    select e.nom, m.date into v_lieu, v_date_m
      from public.missions m join public.etablissements e on e.id = m.etablissement_id
     where m.id = new.id;
    insert into public.notifications (user_id, message, cle, params)
    select c.hotesse_id,
           public.traduire('notif.mission_note_modifiee', coalesce(p.langue, 'fr'),
             jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, coalesce(p.langue, 'fr')))),
           'notif.mission_note_modifiee',
           jsonb_build_object('lieu', v_lieu, 'date', public.date_courte(v_date_m, coalesce(p.langue, 'fr')))
      from public.candidatures c
      join public.profiles p on p.id = c.hotesse_id
     where c.mission_id = new.id and c.statut in ('acceptee', 'confirmee') and not c.annulation;
  end if;
  return new;
end; $$;
drop trigger if exists notifier_note_mission on public.missions;
create trigger notifier_note_mission after update on public.missions
for each row execute function public.notifier_note_mission();
revoke execute on function public.notifier_note_mission() from public, anon, authenticated;
