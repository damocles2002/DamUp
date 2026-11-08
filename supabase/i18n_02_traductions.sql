-- ============================================================
--  DamUp : i18n L5 : traductions + notifications multilingues
-- ============================================================

-- table des traductions (clé + langue → texte)
create table if not exists public.traductions (
  cle    text not null,
  langue text not null check (langue in ('fr', 'en', 'es', 'zh')),
  texte  text not null,
  primary key (cle, langue)
);
alter table public.traductions enable row level security;
drop policy if exists "traductions_lecture" on public.traductions;
create policy "traductions_lecture" on public.traductions for select using (true);

-- notifications : clé + paramètres pour pouvoir retraduire côté client
alter table public.notifications
  add column if not exists cle text,
  add column if not exists params jsonb not null default '{}'::jsonb;

-- remplace {nom} par la valeur du paramètre ; repli sur le français si la traduction manque
create or replace function public.traduire(p_cle text, p_langue text, p_params jsonb default '{}'::jsonb)
returns text language plpgsql stable security definer set search_path = public as $$
declare
  v text;
  k text;
begin
  select texte into v from public.traductions where cle = p_cle and langue = coalesce(p_langue, 'fr');
  if v is null then select texte into v from public.traductions where cle = p_cle and langue = 'fr'; end if;
  if v is null then return p_cle; end if;
  for k in select jsonb_object_keys(coalesce(p_params, '{}'::jsonb)) loop
    v := replace(v, '{' || k || '}', coalesce(p_params ->> k, ''));
  end loop;
  return v;
end; $$;

-- crée une notification dans la langue du destinataire (à utiliser partout à la place des insert directs)
create or replace function public.notifier_utilisateur(p_user uuid, p_cle text, p_params jsonb default '{}'::jsonb)
returns void language plpgsql security definer set search_path = public as $$
declare v_langue text;
begin
  select langue into v_langue from public.profiles where id = p_user;
  insert into public.notifications (user_id, message, cle, params)
  values (p_user, public.traduire(p_cle, coalesce(v_langue, 'fr'), p_params), p_cle, p_params);
end; $$;
revoke execute on function public.notifier_utilisateur(uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.notifier_utilisateur(uuid, text, jsonb) to service_role;

-- dates et heures dans les messages, selon la langue
create or replace function public.date_courte(p_d date, p_langue text) returns text
language sql immutable as $$
  select case p_langue
    when 'zh' then to_char(p_d, 'FMMM') || '月' || to_char(p_d, 'FMDD') || '日'
    else to_char(p_d, 'DD/MM') end;
$$;

create or replace function public.heure_courte(p_t timestamptz, p_langue text) returns text
language sql stable as $$
  select case p_langue
    when 'fr' then to_char(p_t at time zone 'Europe/Paris', 'HH24"h"MI')
    else to_char(p_t at time zone 'Europe/Paris', 'HH24:MI') end;
$$;
