-- ============================================================
--  DamUp — i18n L4 : langue enregistrée dans le compte
-- ============================================================

-- colonne langue sur profiles (valeur par défaut : français)
alter table public.profiles
  add column if not exists langue text not null default 'fr'
  check (langue in ('fr', 'en', 'es', 'zh'));

-- chacun change SA langue (profiles n'est modifiable que par l'admin)
create or replace function public.changer_langue(p_langue text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_langue not in ('fr', 'en', 'es', 'zh') then
    raise exception 'Langue non disponible.';
  end if;
  update public.profiles set langue = p_langue where id = auth.uid();
end; $$;
revoke execute on function public.changer_langue(text) from public, anon;
grant execute on function public.changer_langue(text) to authenticated;

-- handle_new_user : enregistre la langue fournie à l'inscription (sinon 'fr')
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r text;
  v_age int;
  v_villes jsonb;
begin
  if not public.reglage_bool('inscriptions_ouvertes', true) then
    raise exception 'Les inscriptions sont fermées pour le moment.';
  end if;

  if coalesce(new.raw_app_meta_data->>'role', '') = 'admin' then r := 'admin';
  elsif m->>'role' = 'etablissement' then r := 'etablissement';
  else r := 'hotesse';
  end if;

  insert into public.profiles (id, type, email, tarif, periode, actif_jusqu_a, langue)
  values (new.id, r, new.email,
    case when r = 'etablissement' then public.reglage_num('prix_defaut_etablissement', 79)
         when r = 'hotesse' then public.reglage_num('prix_defaut_hotesse', 0)
         else null end,
    case when r = 'admin' then null else 'mensuel' end,
    now() + make_interval(days => public.reglage_num('essai_jours', 7)::int),
    case when m->>'langue' in ('fr', 'en', 'es', 'zh') then m->>'langue' else 'fr' end)
  on conflict (id) do nothing;

  if r = 'hotesse' then
    v_age := nullif(m->>'age', '')::int;
    if v_age is null or v_age < 18 then
      raise exception 'Inscription réservée aux personnes de 18 ans et plus.';
    end if;
    v_villes := (select value from public.settings where key = 'villes');
    if v_villes is not null and jsonb_array_length(v_villes) > 0
       and not (coalesce(m->>'ville', '') = ANY (select jsonb_array_elements_text(v_villes))) then
      raise exception 'Cette ville n''est pas encore ouverte aux inscriptions.';
    end if;
    insert into public.hotesses (id, prenom, age, ville, instagram, telephone, photos)
    values (new.id, left(coalesce(nullif(trim(m->>'prenom'), ''), '?'), 50), v_age,
            left(m->>'ville', 80), left(m->>'instagram', 60), left(m->>'telephone', 20), '[]'::jsonb)
    on conflict (id) do nothing;
  elsif r = 'etablissement' then
    insert into public.etablissements (id, nom, type, ville, adresse, siret, photos, videos)
    values (new.id, left(coalesce(nullif(trim(m->>'nom'), ''), '?'), 100),
            case when m->>'type_etab' in ('bar','restaurant','club','lounge') then m->>'type_etab' end,
            left(m->>'ville', 80), left(m->>'adresse', 200),
            left(regexp_replace(coalesce(m->>'siret', ''), '\s', '', 'g'), 14), '[]'::jsonb, '[]'::jsonb)
    on conflict (id) do nothing;
  end if;
  return new;
end; $$;
