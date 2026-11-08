-- ============================================================
--  P2 : Candidatures : délai, QR, annulation, comptes validés
-- ============================================================

-- 1) contrôle des candidatures (phase 1 + délai/QR/annulation/validation)
create or replace function public.controle_candidature() returns trigger language plpgsql as $$
declare
  v_m public.missions%rowtype;
  v_pris int;
  v_debut timestamptz;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then return new; end if;
  select * into v_m from public.missions where id = new.mission_id;
  v_debut := (v_m.date + v_m.heure_debut) at time zone 'Europe/Paris';

  if tg_op = 'INSERT' then
    if new.hotesse_id is distinct from auth.uid() then raise exception 'Modification non autorisée.'; end if;
    if public.est_suspendu() then raise exception 'Ton compte est suspendu. Contacte DamUp.'; end if;
    if not exists (select 1 from public.hotesses h where h.id = auth.uid() and h.verifie) then
      raise exception 'Ton profil doit être validé par DamUp avant de postuler.';
    end if;
    if v_m.statut <> 'ouverte' or v_debut <= now() then
      raise exception 'Cette mission n''accepte plus de candidatures.';
    end if;
    new.statut := 'en_attente'; new.qr_code := null; new.annulation := false;
    new.confirme_a := null; new.presente_a := null;
    return new;
  end if;

  if new.mission_id is distinct from old.mission_id or new.hotesse_id is distinct from old.hotesse_id
     or new.groupe_id is distinct from old.groupe_id or new.qr_code is distinct from old.qr_code
     or new.confirme_a is distinct from old.confirme_a or new.presente_a is distinct from old.presente_a then
    raise exception 'Modification non autorisée.';
  end if;

  if auth.uid() = v_m.etablissement_id then
    if new.annulation is distinct from old.annulation then raise exception 'Modification non autorisée.'; end if;
    if new.statut is distinct from old.statut then
      if not ((old.statut = 'en_attente' and new.statut in ('acceptee', 'refusee'))
              or (old.statut = 'acceptee' and new.statut = 'refusee')) then
        raise exception 'Changement de statut non autorisé.';
      end if;
      if new.statut = 'acceptee' then
        if v_debut <= now() then raise exception 'La mission a déjà commencé.'; end if;
        select count(*) into v_pris from public.candidatures
         where mission_id = new.mission_id and id <> new.id
           and statut in ('acceptee', 'confirmee') and not annulation;
        if v_pris >= v_m.nb_hotesses then
          raise exception 'Toutes les places de cette mission sont déjà prises.';
        end if;
        new.confirme_a := least(
          now() + case when v_debut - now() < interval '24 hours' then interval '3 hours' else interval '12 hours' end,
          v_debut);
      end if;
    end if;

  elsif auth.uid() = old.hotesse_id then
    if new.statut is distinct from old.statut then
      if not (old.statut = 'acceptee' and new.statut = 'confirmee') then
        raise exception 'Changement de statut non autorisé.';
      end if;
      if old.annulation then raise exception 'Cette candidature a été annulée.'; end if;
      if now() > coalesce(old.confirme_a, v_debut) then
        raise exception 'Le délai de confirmation est dépassé.';
      end if;
      new.qr_code := replace(gen_random_uuid()::text, '-', '');
    end if;
    if old.annulation and not new.annulation then raise exception 'Une annulation ne peut pas être retirée.'; end if;
    if new.annulation and not old.annulation and v_debut <= now() then
      raise exception 'La mission a déjà commencé, l''annulation n''est plus possible.';
    end if;

  else
    raise exception 'Modification non autorisée.';
  end if;
  return new;
end; $$;

-- 2) signe négatif + notification à l'annulation
create or replace function public.apres_annulation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.annulation and not old.annulation then
    if old.statut = 'confirmee' then
      update public.hotesses set signes_negatifs = signes_negatifs + 1, missions_honorees = 0
       where id = new.hotesse_id;
    end if;
    insert into public.notifications (user_id, message)
    select m.etablissement_id, '⚠️ Une hôtesse a annulé sa venue : une place se libère sur ta mission du '
           || to_char(m.date, 'DD/MM') || '.'
      from public.missions m where m.id = new.mission_id;
  end if;
  return new;
end; $$;
drop trigger if exists apres_annulation on public.candidatures;
create trigger apres_annulation after update on public.candidatures
for each row execute function public.apres_annulation();
revoke execute on function public.apres_annulation() from public, anon, authenticated;

-- 3) notifications de candidature (avec heure limite + cas expiree)
create or replace function public.notifier_candidature() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_lieu text;
  v_date text;
begin
  if old.statut is not distinct from new.statut then return new; end if;
  select e.nom, to_char(m.date, 'DD/MM') into v_lieu, v_date
    from public.missions m join public.etablissements e on e.id = m.etablissement_id
   where m.id = new.mission_id;

  if new.statut = 'acceptee' then
    insert into public.notifications (user_id, message) values (new.hotesse_id,
      '🎉 Tu as été acceptée chez ' || v_lieu || ' pour le ' || v_date
      || ' ! Confirme ta venue avant le '
      || to_char(new.confirme_a at time zone 'Europe/Paris', 'DD/MM à HH24"h"MI')
      || ', sinon ta place sera libérée.');
  elsif new.statut = 'refusee' then
    insert into public.notifications (user_id, message) values (new.hotesse_id,
      'Ta candidature chez ' || v_lieu || ' pour le ' || v_date || ' n''a pas été retenue.');
  elsif new.statut = 'expiree' then
    insert into public.notifications (user_id, message) values (new.hotesse_id,
      '⏰ Tu n''as pas confirmé à temps ta mission chez ' || v_lieu || ' du ' || v_date
      || ' : ta place a été libérée.');
  elsif new.statut = 'confirmee' then
    insert into public.notifications (user_id, message)
    select m.etablissement_id, '✅ Une hôtesse a confirmé sa venue pour ta mission du ' || v_date || '.'
      from public.missions m where m.id = new.mission_id;
  end if;
  return new;
end; $$;
revoke execute on function public.notifier_candidature() from public, anon, authenticated;
