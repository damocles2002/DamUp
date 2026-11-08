-- ============================================================
--  B3 : Candidatures : chacun ne fait que ce que son rôle permet
-- ============================================================
create or replace function public.controle_candidature() returns trigger language plpgsql as $$
declare
  v_m public.missions%rowtype;
  v_pris int;
begin
  if current_user not in ('authenticated', 'anon') or public.is_admin() then return new; end if;
  select * into v_m from public.missions where id = new.mission_id;

  if tg_op = 'INSERT' then
    if new.hotesse_id is distinct from auth.uid() then raise exception 'Modification non autorisée.'; end if;
    if v_m.statut <> 'ouverte' or v_m.date < current_date then
      raise exception 'Cette mission n''accepte plus de candidatures.';
    end if;
    new.statut := 'en_attente'; new.qr_code := null; new.annulation := false; new.confirme_a := null;
    return new;
  end if;

  if new.mission_id is distinct from old.mission_id or new.hotesse_id is distinct from old.hotesse_id
     or new.groupe_id is distinct from old.groupe_id or new.qr_code is distinct from old.qr_code
     or new.confirme_a is distinct from old.confirme_a then
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
        select count(*) into v_pris from public.candidatures
         where mission_id = new.mission_id and id <> new.id
           and statut in ('acceptee', 'confirmee') and not annulation;
        if v_pris >= v_m.nb_hotesses then
          raise exception 'Toutes les places de cette mission sont déjà prises.';
        end if;
      end if;
    end if;
  elsif auth.uid() = old.hotesse_id then
    if new.statut is distinct from old.statut
       and not (old.statut = 'acceptee' and new.statut = 'confirmee') then
      raise exception 'Changement de statut non autorisé.';
    end if;
    if old.annulation and not new.annulation then raise exception 'Une annulation ne peut pas être retirée.'; end if;
  else
    raise exception 'Modification non autorisée.';
  end if;
  return new;
end; $$;
drop trigger if exists controle_candidature on public.candidatures;
create trigger controle_candidature before insert or update on public.candidatures
for each row execute function public.controle_candidature();
