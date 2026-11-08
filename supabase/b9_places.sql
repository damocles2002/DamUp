-- ============================================================
--  B9 : Compteur de places : recalcul à partir des candidatures
--  (plus de double décompte ; places rendues en cas de refus)
-- ============================================================

-- 1) la contrainte de statut accepte 'cloturee'
alter table public.missions drop constraint if exists missions_statut_check;
alter table public.missions add constraint missions_statut_check
  check (statut = any (array['ouverte','en_cours','terminee','annulee','cloturee']));

-- 2) recalcul des places à chaque changement de candidature
create or replace function public.maj_places_mission()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.missions m
     set places_restantes = greatest(m.nb_hotesses - (
           select count(*) from public.candidatures c
            where c.mission_id = m.id and c.statut in ('acceptee','confirmee') and not c.annulation), 0)
   where m.id = new.mission_id;
  update public.missions
     set statut = case when places_restantes <= 0 and statut = 'ouverte' then 'cloturee'
                       when places_restantes > 0 and statut = 'cloturee' then 'ouverte'
                       else statut end
   where id = new.mission_id;
  return new;
end; $$;

-- 3) recalcul des missions existantes
update public.missions m
   set places_restantes = greatest(m.nb_hotesses - (
         select count(*) from public.candidatures c
          where c.mission_id = m.id and c.statut in ('acceptee','confirmee') and not c.annulation), 0);
