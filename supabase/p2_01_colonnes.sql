-- ============================================================
--  P1 : Colonnes et statuts
-- ============================================================
alter table public.candidatures add column if not exists presente_a timestamptz;
alter table public.candidatures add column if not exists rappel_envoye boolean not null default false;
alter table public.candidatures drop constraint if exists candidatures_statut_check;
alter table public.candidatures add constraint candidatures_statut_check
  check (statut in ('en_attente', 'acceptee', 'refusee', 'confirmee', 'expiree'));

alter table public.hotesses add column if not exists missions_honorees int not null default 0;
alter table public.profiles add column if not exists suspendu boolean not null default false;

alter table public.avis drop constraint if exists avis_commentaire_longueur;
alter table public.avis add constraint avis_commentaire_longueur
  check (char_length(coalesce(commentaire, '')) <= 500);

create or replace function public.est_suspendu() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select suspendu from public.profiles where id = auth.uid()), false);
$$;

-- missions_honorees devient protégé (comme signes_negatifs)
create or replace function public.protege_hotesse() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon') and not public.is_admin() then
    if new.id is distinct from old.id
       or new.verifie is distinct from old.verifie
       or new.note_moyenne is distinct from old.note_moyenne
       or new.nb_avis is distinct from old.nb_avis
       or new.signes_negatifs is distinct from old.signes_negatifs
       or new.missions_honorees is distinct from old.missions_honorees then
      raise exception 'Modification non autorisée.';
    end if;
  end if;
  return new;
end; $$;

-- missions_honorees lisible par l'hôtesse elle-même / l'admin uniquement
drop function if exists public.hotesse_prive(uuid);
create function public.hotesse_prive(p_id uuid)
returns table (telephone text, instagram text, signes_negatifs int, missions_honorees int)
language sql stable security definer set search_path = public as $$
  select h.telephone, h.instagram, h.signes_negatifs, h.missions_honorees from public.hotesses h
  where h.id = p_id and (p_id = auth.uid() or public.is_admin());
$$;
