-- ============================================================
--  B6 — Déclencheur qui envoie un email via la fonction Edge
--  "notifier", avec l'en-tête x-damup-secret (secret du Vault).
--  À exécuter une seule fois : activer pg_net et ranger le secret.
-- ============================================================
create extension if not exists pg_net;

-- Ranger le secret dans le Vault (jamais dans le dépôt) :
--   select vault.create_secret('NOTIFIER_SECRET', '<secret>');

create or replace function public.envoyer_email_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_dest text;
begin
  -- secret lu dans le Vault Supabase
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'NOTIFIER_SECRET'
  order by created_at desc limit 1;
  if v_secret is null then return new; end if;

  select email into v_dest from auth.users where id = new.user_id;
  if v_dest is null then return new; end if;

  perform net.http_post(
    url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-damup-secret', v_secret
    ),
    body := jsonb_build_object(
      'to', v_dest,
      'subject', 'DamUp — Nouvelle notification',
      'html', '<p style="font-family:sans-serif">' || new.message || '</p>'
    )
  );
  return new;
end;
$$;

drop trigger if exists envoyer_email_notification on public.notifications;
create trigger envoyer_email_notification after insert on public.notifications
for each row execute function public.envoyer_email_notification();
