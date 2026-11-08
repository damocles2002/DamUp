-- ============================================================
--  DamUp : renfort sécurité (RGPD + messagerie)
--  Deux axes : protéger les données personnelles (pièces
--  d'identité) et empêcher les contacts hors plateforme.
-- ============================================================

-- 1) Suppression automatique de la pièce d'identité une fois le
--    profil validé. Exigence RGPD : la pièce n'est conservée que
--    le temps de la validation, puis effacée.
create or replace function public.nettoie_document_hotesse()
returns trigger language plpgsql as $$
begin
  if new.verifie and coalesce(old.verifie, false) is distinct from new.verifie then
    new.id_document := null;
  end if;
  return new;
end;
$$;

create or replace function public.nettoie_document_etab()
returns trigger language plpgsql as $$
begin
  if new.verifie and coalesce(old.verifie, false) is distinct from new.verifie then
    new.id_document_resp := null;
  end if;
  return new;
end;
$$;

drop trigger if exists nettoie_document_hotesse on public.hotesses;
create trigger nettoie_document_hotesse
before update on public.hotesses
for each row execute function public.nettoie_document_hotesse();

drop trigger if exists nettoie_document_etab on public.etablissements;
create trigger nettoie_document_etab
before update on public.etablissements
for each row execute function public.nettoie_document_etab();

-- 2) Messagerie : interdire les numéros de téléphone et les comptes
--    de réseaux sociaux (règle du cahier des charges). Le message est
--    rejeté AVANT insertion.
create or replace function public.bloque_infos_contact()
returns trigger language plpgsql as $$
begin
  if coalesce(new.contenu,'') ~ '(\+33|0[1-9][ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2}[ .\-]?[0-9]{2})' then
    raise exception 'Les numéros de téléphone ne sont pas autorisés dans la messagerie.';
  end if;
  if coalesce(new.contenu,'') ~ '(instagram\.com|facebook\.com|snapchat|tiktok|@[a-zA-Z0-9_.]{2,})' then
    raise exception 'Les comptes de réseaux sociaux ne sont pas autorisés dans la messagerie.';
  end if;
  return new;
end;
$$;

drop trigger if exists bloque_infos_contact on public.messages;
create trigger bloque_infos_contact
before insert or update on public.messages
for each row execute function public.bloque_infos_contact();

-- 3) Index pour retrouver rapidement les signalements non traités.
create index if not exists idx_signalements_statut on public.signalements(statut);
