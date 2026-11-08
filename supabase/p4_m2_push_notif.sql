-- ============================================================
--  M2 — Notifications push : envoi + préférences (e-mail)
-- ============================================================

-- envoie une notification push (si push_actif) via la fonction Edge envoyer-push
create or replace function public.notifier_push(p_user uuid, p_cle text, p_message text) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_push boolean;
  v_type text;
  v_url text;
  v_anon text;
  v_secret text;
begin
  select coalesce(push_actif, true) into v_push from public.preferences_notif where user_id = p_user;
  if v_push is null then v_push := true; end if;
  if not v_push then return; end if;

  select type into v_type from public.profiles where id = p_user;
  if p_cle like 'notif.message.%' then
    v_url := 'https://damup.fr/' || case when v_type = 'etablissement' then 'etablissement.html' else 'hotesse.html' end || '#messages';
  else
    v_url := 'https://damup.fr/' || case when v_type = 'etablissement' then 'etablissement.html' else 'hotesse.html' end;
  end if;

  select decrypted_secret into v_anon from vault.decrypted_secrets where name = 'SUPABASE_ANON_KEY' order by created_at desc limit 1;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'NOTIFIER_SECRET' order by created_at desc limit 1;
  if v_secret is null or v_secret = '' then return; end if;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/envoyer-push',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || coalesce(v_anon, ''),
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object('user_id', p_user::text, 'titre', 'DamUp', 'texte', p_message, 'url', v_url)
  );
end; $$;
revoke execute on function public.notifier_push(uuid, text, text) from public, anon, authenticated;
grant execute on function public.notifier_push(uuid, text, text) to service_role;

-- notifier_utilisateur : insère la notification ET déclenche le push
create or replace function public.notifier_utilisateur(p_user uuid, p_cle text, p_params jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_langue text; v_message text;
begin
  select langue into v_langue from public.profiles where id = p_user;
  v_message := public.traduire(p_cle, coalesce(v_langue, 'fr'), p_params);
  insert into public.notifications (user_id, message, cle, params)
  values (p_user, v_message, p_cle, p_params);
  perform public.notifier_push(p_user, p_cle, v_message);
end; $$;
revoke execute on function public.notifier_utilisateur(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.notifier_utilisateur(uuid, text, jsonb) to service_role;

-- e-mail : respecte les préférences (email_missions / email_messages / email_compte)
create or replace function public.envoyer_email_notification() returns trigger
language plpgsql security definer set search_path = public as $$
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
  else v_cat := 'missions';
  end if;

  select case v_cat
    when 'messages' then coalesce(email_messages, false)
    when 'compte' then coalesce(email_compte, true)
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
    body := jsonb_build_object('user_id', new.user_id::text, 'message', new.message)
  );
  return new;
end; $$;
revoke execute on function public.envoyer_email_notification() from public, anon, authenticated;
