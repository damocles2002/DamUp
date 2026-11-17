-- ============================================================
--  DamUp : branchement des modèles d'e-mails (s10)
--  - envoyer_mail injecte automatiquement {prenom} (nom affiché)
--  - suspension/réactivation passent par les modèles pro
-- ============================================================

-- 1) envoyer_mail enrichi : injecte {prenom} depuis le profil si absent
create or replace function public.envoyer_mail(p_evenement text, p_destinataire uuid, p_variables jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_anon text;
  v_email text;
  v_type text;
  v_role text;
  v_prenom text;
begin
  select email, type into v_email, v_type from public.profiles where id = p_destinataire;
  if v_email is null or v_email = '' then return; end if;
  v_role := case when v_type = 'etablissement' then 'etablissement' else 'hotesse' end;

  -- nom affiché : prénom (hôtesse) ou responsable/nom (établissement)
  v_prenom := coalesce(
    (select prenom from public.hotesses where id = p_destinataire),
    (select nullif(responsable_nom, '') from public.etablissements where id = p_destinataire),
    (select nom from public.etablissements where id = p_destinataire),
    ''
  );
  if not (p_variables ? 'prenom') then
    p_variables := p_variables || jsonb_build_object('prenom', v_prenom);
  end if;

  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return; end if;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/email',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('evenement', p_evenement, 'email', v_email, 'role', v_role, 'variables', p_variables)
  );
end; $$;

revoke execute on function public.envoyer_mail(text, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.envoyer_mail(text, uuid, jsonb) to service_role;

-- 2) suspension / réactivation → modèles pro
create or replace function public.envoyer_email_suspension()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.suspendu is distinct from new.suspendu then
    if new.suspendu then
      perform public.envoyer_mail('suspension', new.id,
        jsonb_build_object('motif', 'manquement aux conditions d''utilisation'));
    else
      perform public.envoyer_mail('reactivation', new.id,
        jsonb_build_object('lien', 'https://damup.fr'));
    end if;
  end if;
  return new;
end; $$;
