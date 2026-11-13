-- ============================================================
--  DamUp : corrections « copine » (relecture)
--  1) lier_invitation_verifiee : prévient la copine à la vérification
--  2) invitation_copine_detail : retire les droits public/anon
-- ============================================================

-- 1) notifier la copine quand son compte est vérifié (arrivée par lien)
CREATE OR REPLACE FUNCTION public.lier_invitation_verifiee()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_code text;
  v_inv public.invitations_copine%rowtype;
  v_mission public.missions%rowtype;
  v_lieu text;
  v_prenom_marraine text;
begin
  if new.verifie and not coalesce(old.verifie, false) then
    select raw_user_meta_data->>'code_invitation' into v_code from auth.users where id = new.id;
    if v_code is not null and v_code <> '' then
      update public.invitations_copine
         set copine_id = new.id, statut = 'a_accepter'
       where code_invitation = v_code and statut = 'envoyee' and copine_id is null;

      select * into v_inv from public.invitations_copine
       where code_invitation = v_code and copine_id = new.id
       limit 1;

      if v_inv.id is not null then
        select * into v_mission from public.missions
          where id = (select mission_id from public.candidatures where id = v_inv.candidature_id);
        select nom into v_lieu from public.etablissements where id = v_mission.etablissement_id;
        select prenom into v_prenom_marraine from public.hotesses where id = v_inv.marraine_id;
        perform public.notifier_utilisateur(new.id, 'copine.proposee',
          jsonb_build_object('prenom', v_prenom_marraine, 'lieu', v_lieu, 'date', public.date_courte(v_mission.date, 'fr')));
      end if;
    end if;
  end if;
  return new;
end; $function$;

-- 2) invitation_copine_detail : réservée aux comptes connectés
revoke execute on function public.invitation_copine_detail(uuid) from public, anon;
grant execute on function public.invitation_copine_detail(uuid) to authenticated;
