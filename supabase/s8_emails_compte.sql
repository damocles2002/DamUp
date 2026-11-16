-- ============================================================
--  DamUp : e-mails de suspension / suppression (s8)
--  + correctif du format d'e-mail des notifications
-- ============================================================

-- 1) helper : envoi d'un e-mail direct via l'Edge notifier (to/subject/html)
create or replace function public.envoyer_email(p_email text, p_objet text, p_html text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_anon text;
begin
  if p_email is null or p_email = '' then return; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return; end if;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;
  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('to', p_email, 'subject', p_objet, 'html', p_html)
  );
end; $$;

revoke execute on function public.envoyer_email(text, text, text) from public, anon, authenticated;
grant execute on function public.envoyer_email(text, text, text) to service_role;

-- 2) e-mail automatique quand un compte est suspendu ou réactivé
--    (déclenché dès que profiles.suspendu change, quel que soit le chemin :
--     action admin, suspension automatique, membre de l'équipe...)
create or replace function public.envoyer_email_suspension()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.suspendu is distinct from new.suspendu then
    if new.suspendu then
      perform public.envoyer_email(new.email, 'Ton compte DamUp a été suspendu',
        '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#2A1120">'
        || '<h2 style="color:#2A1120;margin:0 0 16px">Ton compte DamUp a été suspendu</h2>'
        || '<p style="font-size:15px;line-height:1.6">Bonjour, ton compte DamUp a été suspendu. Tu ne peux plus te connecter pour le moment.</p>'
        || '<p style="font-size:15px;line-height:1.6">Pour en savoir plus, écris-nous à <a href="mailto:damotrader2025@gmail.com">damotrader2025@gmail.com</a>.</p>'
        || '<p style="color:#8A6D3B;font-size:13px">L''équipe DamUp</p></div>');
    else
      perform public.envoyer_email(new.email, 'Ton compte DamUp a été réactivé',
        '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#2A1120">'
        || '<h2 style="color:#2A1120;margin:0 0 16px">Ton compte DamUp a été réactivé</h2>'
        || '<p style="font-size:15px;line-height:1.6">Bonjour, ton compte DamUp a été réactivé. Tu peux à nouveau te connecter.</p>'
        || '<p style="color:#8A6D3B;font-size:13px">L''équipe DamUp</p></div>');
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists envoyer_email_suspension on public.profiles;
create trigger envoyer_email_suspension after update on public.profiles
  for each row execute function public.envoyer_email_suspension();

-- 3) correctif : l'e-mail de notification partait au mauvais format
--    (l'Edge notifier attend to/subject/html, pas user_id/message)
create or replace function public.envoyer_email_notification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret text;
  v_anon text;
  v_cat text;
  v_autorise boolean;
begin
  if new.cle like 'notif.message.%' then v_cat := 'messages';
  elsif new.cle in ('notif.validation_refusee', 'notif.suspension_hotesse', 'notif.suspension_admin',
                    'notif.fin_abonnement', 'notif.fin_abonnement_admin', 'notif.paiement_recu',
                    'notif.paiement_offert', 'notif.paiement_echoue', 'notif.paiement_echoue_admin') then v_cat := 'compte';
  elsif new.cle in ('notif.inscription_hotesse_admin', 'notif.inscription_etablissement_admin',
                    'notif.verification_admin', 'notif.mission_admin') then v_cat := 'equipe';
  else v_cat := 'missions';
  end if;

  select case v_cat
    when 'messages' then coalesce(email_messages, false)
    when 'compte' then coalesce(email_compte, true)
    when 'equipe' then coalesce(email_equipe, true)
    else coalesce(email_missions, true) end
    into v_autorise from public.preferences_notif where user_id = new.user_id;
  if v_autorise is null then v_autorise := (v_cat <> 'messages'); end if;
  if not v_autorise then return new; end if;

  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return new; end if;
  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object(
      'to', (select email from public.profiles where id = new.user_id),
      'subject', 'DamUp',
      'html', '<div style="font-family:Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#2A1120"><p style="font-size:15px;line-height:1.6">' || new.message || '</p><p style="color:#8A6D3B;font-size:13px">L''équipe DamUp</p></div>'
    )
  );
  return new;
end; $$;
