create table if not exists public.email_erreurs (
  id bigint generated always as identity primary key,
  date timestamptz not null default now(),
  user_id uuid,
  raison text
);
alter table public.email_erreurs enable row level security;
drop policy if exists "email_erreurs_admin" on public.email_erreurs;
create policy "email_erreurs_admin" on public.email_erreurs for select using (public.is_admin());

create or replace function public.envoyer_email_notification()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_secret text;
  v_dest text;
  v_msg text;
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets where name = 'NOTIFIER_SECRET'
  order by created_at desc limit 1;
  if v_secret is null then
    insert into public.email_erreurs (user_id, raison) values (new.user_id, 'Secret NOTIFIER_SECRET introuvable');
    return new;
  end if;

  select email into v_dest from auth.users where id = new.user_id;
  if v_dest is null then
    insert into public.email_erreurs (user_id, raison) values (new.user_id, 'Adresse email introuvable');
    return new;
  end if;

  v_msg := replace(replace(replace(coalesce(new.message, ''), '&', '&amp;'), '<', '&lt;'), '>', '&gt;');

  begin
    perform net.http_post(
      url := 'https://bzoqpaldksrqixoxgsvf.supabase.co/functions/v1/notifier',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJ6b3FwYWxka3NycWl4b3hnc3ZmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5Mjc0NTksImV4cCI6MjEwOTUwMzQ1OX0.9A8gTkadIdEdK0k3RQvBE3oGa107TIht4SIEGr76G4Q',
        'x-damup-secret', v_secret
      ),
      body := jsonb_build_object(
        'to', v_dest,
        'subject', 'DamUp — Nouvelle notification',
        'html', '<p style="font-family:sans-serif">' || v_msg || '</p>'
      )
    );
  exception when others then
    insert into public.email_erreurs (user_id, raison) values (new.user_id, sqlerrm);
  end;
  return new;
end;
$$;
