-- ============================================================
--  P4 — Validation de présence (scan QR par l'établissement)
-- ============================================================
create or replace function public.valider_presence(p_code text) returns text
language plpgsql security definer set search_path = public as $$
declare
  c record;
  v_jour date := (now() at time zone 'Europe/Paris')::date;
begin
  select ca.id, ca.statut, ca.annulation, ca.presente_a, ca.hotesse_id,
         m.etablissement_id, m.date, h.prenom
    into c
    from public.candidatures ca
    join public.missions m on m.id = ca.mission_id
    join public.hotesses h on h.id = ca.hotesse_id
   where ca.qr_code = p_code;
  if c.id is null then raise exception 'QR code inconnu.'; end if;
  if c.etablissement_id is distinct from auth.uid() then
    raise exception 'Ce QR code concerne une mission d''un autre établissement.';
  end if;
  if c.statut <> 'confirmee' or c.annulation then raise exception 'Cette venue n''est pas confirmée.'; end if;
  if c.date not between v_jour - 1 and v_jour then raise exception 'Ce QR code n''est pas pour aujourd''hui.'; end if;
  if c.presente_a is not null then return c.prenom || ' est déjà enregistrée.'; end if;

  update public.candidatures set presente_a = now() where id = c.id;
  update public.hotesses set missions_honorees = missions_honorees + 1 where id = c.hotesse_id;
  -- 3 missions honorées = un signe négatif retiré
  update public.hotesses set signes_negatifs = signes_negatifs - 1, missions_honorees = 0
   where id = c.hotesse_id and missions_honorees >= 3 and signes_negatifs > 0;
  return '✅ ' || c.prenom || ' est bien arrivée.';
end; $$;
revoke execute on function public.valider_presence(text) from public, anon;
grant execute on function public.valider_presence(text) to authenticated;
