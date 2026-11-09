-- ============================================================
--  S2 : double vérification (TOTP) obligatoire pour l'équipe
--  a_le_droit / is_admin / est_proprietaire exigent un jeton aal2
-- ============================================================

create or replace function public.a_le_droit(p_droit text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.equipe e
    join public.profiles p on p.id = e.user_id
    where e.user_id = auth.uid() and p.type = 'admin' and not e.suspendu and not p.suspendu
      and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
      and (e.proprietaire or coalesce((e.droits ->> p_droit)::boolean, false))
  );
$$;

create or replace function public.est_proprietaire() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.equipe
                  where user_id = auth.uid() and proprietaire and not suspendu
                    and coalesce(auth.jwt() ->> 'aal', '') = 'aal2');
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles p join public.equipe e on e.user_id = p.id
    where p.id = auth.uid() and p.type = 'admin' and not p.suspendu and not e.suspendu
      and coalesce(auth.jwt() ->> 'aal', '') = 'aal2'
  );
$$;
