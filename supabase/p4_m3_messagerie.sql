-- ============================================================
--  M3 — Messagerie : une conversation par mission entre
--  l'établissement et chaque hôtesse acceptée/confirmée.
-- ============================================================

alter table public.messages add column if not exists hotesse_id uuid references public.hotesses(id);
alter table public.messages add column if not exists lu_a timestamptz;

-- l'appelant peut-il écrire dans la conversation (mission, hôtesse) ?
create or replace function public.conversation_ouverte(p_mission uuid, p_hotesse uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.candidatures c
    join public.missions m on m.id = c.mission_id
    where c.mission_id = p_mission and c.hotesse_id = p_hotesse
      and c.statut in ('acceptee', 'confirmee') and not c.annulation
      and auth.uid() in (c.hotesse_id, m.etablissement_id)
      and now() < ((m.date + m.heure_fin
                     + case when m.heure_fin <= m.heure_debut then interval '1 day' else interval '0' end)
                    at time zone 'Europe/Paris') + interval '12 hours'
  );
$$;

-- contrôle à l'insertion : qui écrit, conversation ouverte, longueur
create or replace function public.controle_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_etab uuid;
begin
  select etablissement_id into v_etab from public.missions where id = new.mission_id;
  if auth.uid() = new.hotesse_id then
    new.expediteur_type := 'hotesse';   new.expediteur_id := auth.uid();
    new.destinataire_type := 'etablissement'; new.destinataire_id := v_etab;
  elsif auth.uid() = v_etab then
    new.expediteur_type := 'etablissement'; new.expediteur_id := auth.uid();
    new.destinataire_type := 'hotesse'; new.destinataire_id := new.hotesse_id;
  else
    raise exception 'Conversation non autorisée.' using hint = 'conversation_interdite';
  end if;
  if not public.conversation_ouverte(new.mission_id, new.hotesse_id) then
    raise exception 'Cette conversation est fermée.' using hint = 'conversation_fermee';
  end if;
  if char_length(coalesce(new.contenu, '')) > 1000 then
    raise exception 'Message trop long.' using hint = 'message_trop_long';
  end if;
  new.lu_a := null;
  return new;
end; $$;
drop trigger if exists controle_message on public.messages;
create trigger controle_message before insert on public.messages
for each row execute function public.controle_message();
revoke execute on function public.controle_message() from public, anon, authenticated;

-- le destinataire ne peut modifier que lu_a
create or replace function public.controle_message_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.contenu is distinct from old.contenu
     or new.hotesse_id is distinct from old.hotesse_id
     or new.mission_id is distinct from old.mission_id
     or new.expediteur_id is distinct from old.expediteur_id
     or new.expediteur_type is distinct from old.expediteur_type
     or new.destinataire_id is distinct from old.destinataire_id
     or new.destinataire_type is distinct from old.destinataire_type
     or new.photo_url is distinct from old.photo_url then
    raise exception 'Seul le champ "lu" peut être modifié.' using hint = 'modification_interdite';
  end if;
  return new;
end; $$;
drop trigger if exists controle_message_update on public.messages;
create trigger controle_message_update before update on public.messages
for each row execute function public.controle_message_update();

drop policy if exists "messages_select_participant" on public.messages;
drop policy if exists "messages_insert_participant" on public.messages;
drop policy if exists "messages_lecture" on public.messages;
drop policy if exists "messages_ecriture" on public.messages;
drop policy if exists "messages_marquer_lu" on public.messages;
create policy "messages_lecture" on public.messages for select
  using (expediteur_id = auth.uid() or destinataire_id = auth.uid());
create policy "messages_ecriture" on public.messages for insert
  with check (auth.uid() is not null);   -- le déclencheur fait les vrais contrôles
create policy "messages_marquer_lu" on public.messages for update
  using (destinataire_id = auth.uid()) with check (destinataire_id = auth.uid());

-- admin : lire la conversation liée à un signalement uniquement
create or replace function public.admin_lire_conversation(p_signalement uuid)
returns setof public.messages language plpgsql security definer set search_path = public as $$
declare
  v_mission uuid;
  v_signalant uuid;
  v_cible_type text;
  v_cible uuid;
begin
  if not public.is_admin() then raise exception 'Réservé à l''administrateur.'; end if;
  select signalant_id, cible_type, cible_id into v_signalant, v_cible_type, v_cible
    from public.signalements where id = p_signalement;
  if v_signalant is null then raise exception 'Signalement introuvable.'; end if;
  if v_cible_type = 'mission' then
    v_mission := v_cible;
  elsif v_cible_type = 'hotesse' then
    select m.id into v_mission
      from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_signalant and c.hotesse_id = v_cible
     limit 1;
  else
    select m.id into v_mission
      from public.missions m join public.candidatures c on c.mission_id = m.id
     where m.etablissement_id = v_cible and c.hotesse_id = v_signalant
     limit 1;
  end if;
  if v_mission is null then return; end if;
  return query select * from public.messages where mission_id = v_mission order by created_at;
end; $$;
revoke execute on function public.admin_lire_conversation(uuid) from public, anon;
grant execute on function public.admin_lire_conversation(uuid) to authenticated;

-- bucket privé pour les photos de messages
insert into storage.buckets (id, name, public) values ('messages', 'messages', false)
on conflict (id) do nothing;

-- accès Storage aux photos de messages (participants ; la vraie vérification est faite côté app)
drop policy if exists "messages_photos_select" on storage.objects;
create policy "messages_photos_select" on storage.objects for select to authenticated
  using (bucket_id = 'messages');
drop policy if exists "messages_photos_insert" on storage.objects;
create policy "messages_photos_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'messages');

-- notification d'un nouveau message (une seule par conversation tant que non lu)
create or replace function public.notifier_message() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_dest uuid;
  v_nom text;
  v_langue text;
  v_non_lus int;
  v_message text;
begin
  if new.destinataire_type = 'hotesse' then
    v_dest := new.destinataire_id;
    select coalesce(e.nom, '') into v_nom from public.etablissements e where e.id = new.expediteur_id;
  else
    v_dest := new.destinataire_id;
    select coalesce(h.prenom, '') into v_nom from public.hotesses h where h.id = new.expediteur_id;
  end if;
  select count(*) into v_non_lus from public.messages
   where mission_id = new.mission_id and hotesse_id = new.hotesse_id
     and destinataire_id = v_dest and lu_a is null and id <> new.id;
  if v_non_lus > 0 then return new; end if;
  select langue into v_langue from public.profiles where id = v_dest;
  v_message := public.traduire('notif.message.nouveau', coalesce(v_langue, 'fr'), jsonb_build_object('nom', v_nom));
  insert into public.notifications (user_id, message, cle, params)
  values (v_dest, v_message, 'notif.message.nouveau', jsonb_build_object('nom', v_nom));
  perform public.notifier_push(v_dest, 'notif.message.nouveau', v_message);
  return new;
end; $$;
drop trigger if exists notifier_message on public.messages;
create trigger notifier_message after insert on public.messages
for each row execute function public.notifier_message();
revoke execute on function public.notifier_message() from public, anon, authenticated;
