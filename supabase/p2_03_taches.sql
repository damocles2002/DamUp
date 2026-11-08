-- ============================================================
--  P3 : Tâches automatiques (toutes les 15 minutes)
-- ============================================================
create extension if not exists pg_cron;

create or replace function public.taches_auto() returns void
language plpgsql security definer set search_path = public as $$
begin
  -- rappel quand il reste 1 h ou moins pour confirmer (un seul rappel par candidature)
  with a_rappeler as (
    update public.candidatures c set rappel_envoye = true
     where c.statut = 'acceptee' and not c.annulation and not c.rappel_envoye
       and c.confirme_a > now() and c.confirme_a - now() <= interval '1 hour'
    returning c.hotesse_id, c.confirme_a
  )
  insert into public.notifications (user_id, message)
  select hotesse_id, '⏳ Rappel : confirme ta venue avant '
         || to_char(confirme_a at time zone 'Europe/Paris', 'HH24"h"MI')
         || ', sinon ta place sera libérée.'
    from a_rappeler;

  -- acceptations non confirmées à temps
  update public.candidatures set statut = 'expiree'
   where statut = 'acceptee' and not annulation
     and confirme_a is not null and confirme_a < now();

  -- missions terminées
  update public.missions set statut = 'terminee'
   where statut in ('ouverte', 'cloturee', 'en_cours')
     and ((date + heure_fin + case when heure_fin <= heure_debut then interval '1 day' else interval '0' end)
          at time zone 'Europe/Paris') < now();
end; $$;
revoke execute on function public.taches_auto() from public, anon, authenticated;

select cron.unschedule('damup-taches-auto') where exists (select 1 from cron.job where jobname = 'damup-taches-auto');
select cron.schedule('damup-taches-auto', '*/15 * * * *', 'select public.taches_auto()');
