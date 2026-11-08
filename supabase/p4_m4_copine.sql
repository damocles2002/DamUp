-- ============================================================
--  M4 — Proposer une copine
-- ============================================================

alter table public.hotesses add column if not exists code_damup text unique;
update public.hotesses set code_damup = upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6))
 where code_damup is null;

create table if not exists public.invitations_copine (
  id               uuid primary key default gen_random_uuid(),
  candidature_id   uuid not null references public.candidatures(id) on delete cascade,
  marraine_id      uuid not null references public.hotesses(id) on delete cascade,
  copine_id        uuid references public.hotesses(id) on delete set null,
  code_invitation  text not null unique default replace(gen_random_uuid()::text, '-', ''),
  prenom_indique   text not null check (char_length(prenom_indique) between 1 and 50),
  statut           text not null default 'envoyee'
                   check (statut in ('envoyee', 'a_accepter', 'acceptee', 'refusee', 'expiree')),
  expire_le        timestamptz not null default now() + interval '7 days',
  created_at       timestamptz not null default now(),
  unique (candidature_id)
);
alter table public.invitations_copine enable row level security;
drop policy if exists "invitations_lecture" on public.invitations_copine;
create policy "invitations_lecture" on public.invitations_copine for select
  using (marraine_id = auth.uid() or copine_id = auth.uid());

-- 1. proposer une copine (avec code DamUp ou par lien)
create or replace function public.proposer_copine(p_candidature uuid, p_code_damup text, p_prenom text) returns text
language plpgsql security definer set search_path = public as $$
declare
  v_cand public.candidatures%rowtype;
  v_mission public.missions%rowtype;
  v_marraine uuid;
  v_copine public.hotesses%rowtype;
  v_lieu text;
  v_code text;
  v_prenom_marraine text;
begin
  select * into v_cand from public.candidatures where id = p_candidature and hotesse_id = auth.uid();
  if v_cand.id is null then raise exception 'Candidature introuvable.'; end if;
  select * into v_mission from public.missions where id = v_cand.mission_id;
  if v_mission.statut <> 'ouverte' then raise exception 'Cette mission n''est plus ouverte.'; end if;
  if exists (select 1 from public.invitations_copine where candidature_id = p_candidature) then
    raise exception 'Tu as déjà proposé une copine pour cette mission.';
  end if;
  v_marraine := auth.uid();
  select nom into v_lieu from public.etablissements where id = v_mission.etablissement_id;
  select prenom into v_prenom_marraine from public.hotesses where id = v_marraine;

  if p_code_damup is not null and trim(p_code_damup) <> '' then
    select * into v_copine from public.hotesses where upper(code_damup) = upper(trim(p_code_damup));
    if v_copine.id is null then raise exception 'Code DamUp introuvable.'; end if;
    if v_copine.id = v_marraine then raise exception 'Tu ne peux pas te proposer toi-même.'; end if;
    if not v_copine.verifie then raise exception 'Cette hôtesse n''est pas encore vérifiée.'; end if;
    if exists (select 1 from public.profiles where id = v_copine.id and suspendu) then
      raise exception 'Cette hôtesse est suspendue.';
    end if;
    if exists (select 1 from public.candidatures where mission_id = v_mission.id and hotesse_id = v_copine.id) then
      raise exception 'Cette hôtesse a déjà postulé à cette mission.';
    end if;
    insert into public.invitations_copine (candidature_id, marraine_id, copine_id, prenom_indique, statut)
    values (p_candidature, v_marraine, v_copine.id, coalesce(nullif(trim(p_prenom), ''), v_copine.prenom), 'a_accepter');
    perform public.notifier_utilisateur(v_copine.id, 'copine.proposee',
      jsonb_build_object('prenom', v_prenom_marraine, 'lieu', v_lieu, 'date', public.date_courte(v_mission.date, 'fr')));
    return null;
  else
    insert into public.invitations_copine (candidature_id, marraine_id, prenom_indique, statut)
    values (p_candidature, v_marraine, p_prenom, 'envoyee')
    returning code_invitation into v_code;
    return v_code;
  end if;
end; $$;
revoke execute on function public.proposer_copine(uuid, text, text) from public, anon;
grant execute on function public.proposer_copine(uuid, text, text) to authenticated;

-- 2. répondre à une invitation (réservée à la copine)
create or replace function public.repondre_invitation(p_invitation uuid, p_accepte boolean) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_inv public.invitations_copine%rowtype;
  v_mission public.missions%rowtype;
  v_groupe uuid;
  v_prenom_marraine text;
  v_lieu text;
begin
  select * into v_inv from public.invitations_copine where id = p_invitation and copine_id = auth.uid();
  if v_inv.id is null then raise exception 'Invitation introuvable.'; end if;
  select * into v_mission from public.missions
    where id = (select mission_id from public.candidatures where id = v_inv.candidature_id);
  select prenom into v_prenom_marraine from public.hotesses where id = v_inv.marraine_id;
  select nom into v_lieu from public.etablissements where id = v_mission.etablissement_id;

  if not p_accepte then
    update public.invitations_copine set statut = 'refusee' where id = p_invitation;
    perform public.notifier_utilisateur(v_inv.marraine_id, 'copine.refusee',
      jsonb_build_object('prenom', (select prenom from public.hotesses where id = v_inv.copine_id)));
    return;
  end if;

  if v_mission.statut <> 'ouverte' then
    raise exception 'Cette mission n''est plus ouverte.';
  end if;
  if exists (select 1 from public.candidatures where mission_id = v_mission.id and hotesse_id = auth.uid()) then
    raise exception 'Tu as déjà postulé à cette mission.';
  end if;

  -- groupe_id commun avec la marraine
  select groupe_id into v_groupe from public.candidatures where id = v_inv.candidature_id;
  if v_groupe is null then
    v_groupe := gen_random_uuid();
    update public.candidatures set groupe_id = v_groupe where id = v_inv.candidature_id;
  end if;

  insert into public.candidatures (mission_id, hotesse_id, groupe_id, statut)
  values (v_mission.id, auth.uid(), v_groupe, 'en_attente');

  update public.invitations_copine set statut = 'acceptee' where id = p_invitation;
  perform public.notifier_utilisateur(v_inv.marraine_id, 'copine.acceptee',
    jsonb_build_object('prenom', (select prenom from public.hotesses where id = auth.uid()), 'lieu', v_lieu));
  perform public.notifier_utilisateur(v_mission.etablissement_id, 'copine.candidate',
    jsonb_build_object('prenom', v_prenom_marraine));
end; $$;
revoke execute on function public.repondre_invitation(uuid, boolean) from public, anon;
grant execute on function public.repondre_invitation(uuid, boolean) to authenticated;

-- 3. expiration des invitations dans taches_auto
create or replace function public.expirer_invitations_copine() returns void
language plpgsql security definer set search_path = public as $$
begin
  update public.invitations_copine i set statut = 'expiree'
   where i.statut in ('envoyee', 'a_accepter')
     and (i.expire_le < now()
          or exists (select 1 from public.missions m
                      join public.candidatures c on c.mission_id = m.id
                     where c.id = i.candidature_id and m.date < current_date));
end; $$;
revoke execute on function public.expirer_invitations_copine() from public, anon;

-- code DamUp généré automatiquement à l'inscription
create or replace function public.generer_code_damup() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.code_damup is null then
    new.code_damup := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  end if;
  return new;
end; $$;
drop trigger if exists generer_code_damup on public.hotesses;
create trigger generer_code_damup before insert on public.hotesses
for each row execute function public.generer_code_damup();

-- à la vérification par l'admin : lie l'invitation (si code_invitation en user_metadata)
create or replace function public.lier_invitation_verifiee() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_code text;
begin
  if new.verifie and not coalesce(old.verifie, false) then
    select raw_user_meta_data->>'code_invitation' into v_code from auth.users where id = new.id;
    if v_code is not null and v_code <> '' then
      update public.invitations_copine
         set copine_id = new.id, statut = 'a_accepter'
       where code_invitation = v_code and statut = 'envoyee' and copine_id is null;
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists lier_invitation_verifiee on public.hotesses;
create trigger lier_invitation_verifiee after update on public.hotesses
for each row execute function public.lier_invitation_verifiee();
