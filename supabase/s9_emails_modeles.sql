-- ============================================================
--  DamUp : helper d'envoi d'e-mails selon modèles (s9)
--  envoyer_mail(evenement, destinataire, variables) lit le rôle
--  du destinataire et délègue à l'Edge Function "email".
-- ============================================================

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
begin
  select email, type into v_email, v_type from public.profiles where id = p_destinataire;
  if v_email is null or v_email = '' then return; end if;
  -- rôle normalisé : établissement → vouvoiement, les autres → tutoiement
  v_role := case when v_type = 'etablissement' then 'etablissement' else 'hotesse' end;

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
