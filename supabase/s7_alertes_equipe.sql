-- ============================================================
--  DamUp : alertes équipe (s7)
--  Nouvelles inscriptions, pièces d'identité, nouvelles missions
-- ============================================================

-- 1) Réglage e-mail par membre : alertes d'inscription et de mission
alter table public.preferences_notif
  add column if not exists email_equipe boolean not null default true;

-- 2) Fonction commune : notifier l'équipe (droit + propriétaire)
create or replace function public.notifier_equipe(p_droit text, p_cle text, p_params jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_message text;
begin
  v_message := public.traduire(p_cle, 'fr', p_params);
  for r in
    select e.user_id
    from public.equipe e
    join public.profiles p on p.id = e.user_id
    where p.type = 'admin' and not e.suspendu and not p.suspendu
      and (e.proprietaire or coalesce((e.droits ->> p_droit)::boolean, false))
  loop
    insert into public.notifications (user_id, message, cle, params)
    values (r.user_id, v_message, p_cle, p_params);
  end loop;
end; $$;

revoke execute on function public.notifier_equipe(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.notifier_equipe(text, text, jsonb) to service_role;

-- 3) Triggers « inscription »
create or replace function public.alerte_inscription_hotesse() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notifier_equipe('valider_profils', 'notif.inscription_hotesse_admin',
    jsonb_build_object('prenom', new.prenom, 'ville', new.ville, 'id', new.id));
  return new;
end; $$;

create or replace function public.alerte_inscription_etablissement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform public.notifier_equipe('valider_profils', 'notif.inscription_etablissement_admin',
    jsonb_build_object('nom', new.nom, 'type', new.type, 'ville', new.ville, 'id', new.id));
  return new;
end; $$;

drop trigger if exists alerte_inscription_hotesse on public.hotesses;
create trigger alerte_inscription_hotesse after insert on public.hotesses
  for each row execute function public.alerte_inscription_hotesse();

drop trigger if exists alerte_inscription_etablissement on public.etablissements;
create trigger alerte_inscription_etablissement after insert on public.etablissements
  for each row execute function public.alerte_inscription_etablissement();

-- 4) Triggers « pièce d'identité envoyée » (une seule fois)
create or replace function public.alerte_verification_hotesse() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.id_document is null and new.id_document is not null then
    perform public.notifier_equipe('valider_profils', 'notif.verification_admin',
      jsonb_build_object('nom', new.prenom, 'id', new.id));
  end if;
  return new;
end; $$;

create or replace function public.alerte_verification_etablissement() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- première pièce arrivée (les deux étaient vides avant)
  if (old.id_document is null and old.id_document_resp is null)
     and (new.id_document is not null or new.id_document_resp is not null) then
    perform public.notifier_equipe('valider_profils', 'notif.verification_admin',
      jsonb_build_object('nom', new.nom, 'id', new.id));
  end if;
  return new;
end; $$;

drop trigger if exists alerte_verification_hotesse on public.hotesses;
create trigger alerte_verification_hotesse after update on public.hotesses
  for each row execute function public.alerte_verification_hotesse();

drop trigger if exists alerte_verification_etablissement on public.etablissements;
create trigger alerte_verification_etablissement after update on public.etablissements
  for each row execute function public.alerte_verification_etablissement();

-- 5) Trigger « nouvelle mission publiée »
create or replace function public.alerte_mission() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_etab text;
begin
  select nom into v_etab from public.etablissements where id = new.etablissement_id;
  perform public.notifier_equipe('missions', 'notif.mission_admin',
    jsonb_build_object('etablissement', coalesce(v_etab, ''), 'date', public.date_courte(new.date, 'fr'), 'nb', new.nb_hotesses, 'id', new.id));
  return new;
end; $$;

drop trigger if exists alerte_mission on public.missions;
create trigger alerte_mission after insert on public.missions
  for each row execute function public.alerte_mission();

-- 6) E-mails : les 4 clés suivent le réglage email_equipe
create or replace function public.envoyer_email_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    body := jsonb_build_object('user_id', new.user_id::text, 'message', new.message)
  );
  return new;
end; $function$;

-- 7) Traductions (table traductions, 4 langues)
delete from public.traductions
 where cle in ('notif.inscription_hotesse_admin', 'notif.inscription_etablissement_admin',
               'notif.verification_admin', 'notif.mission_admin');
insert into public.traductions (cle, langue, texte) values
('notif.inscription_hotesse_admin', 'fr', '🆕 Nouvelle hôtesse : {prenom}, {ville}'),
('notif.inscription_hotesse_admin', 'en', '🆕 New hostess: {prenom}, {ville}'),
('notif.inscription_hotesse_admin', 'es', '🆕 Nueva azafata: {prenom}, {ville}'),
('notif.inscription_hotesse_admin', 'zh', '🆕 新女招待：{prenom}，{ville}'),
('notif.inscription_etablissement_admin', 'fr', '🆕 Nouvel établissement : {nom} ({type}), {ville}'),
('notif.inscription_etablissement_admin', 'en', '🆕 New venue: {nom} ({type}), {ville}'),
('notif.inscription_etablissement_admin', 'es', '🆕 Nuevo establecimiento: {nom} ({type}), {ville}'),
('notif.inscription_etablissement_admin', 'zh', '🆕 新场所：{nom}（{type}），{ville}'),
('notif.verification_admin', 'fr', '🪪 {nom} a envoyé sa pièce d''identité : profil à valider'),
('notif.verification_admin', 'en', '🪪 {nom} submitted an ID: profile to validate'),
('notif.verification_admin', 'es', '🪪 {nom} envió su documento: perfil por validar'),
('notif.verification_admin', 'zh', '🪪 {nom} 已发送身份证件：待验证资料'),
('notif.mission_admin', 'fr', '📢 {etablissement} a publié une mission le {date} ({nb} hôtesses)'),
('notif.mission_admin', 'en', '📢 {etablissement} posted a mission on {date} ({nb} hostesses)'),
('notif.mission_admin', 'es', '📢 {etablissement} publicó una misión el {date} ({nb} azafatas)'),
('notif.mission_admin', 'zh', '📢 {etablissement} 发布了 {date} 的任务（{nb} 名女招待）');
