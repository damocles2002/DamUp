-- ============================================================
--  P5 — Note moyenne de l'hôtesse recalculée après un avis
-- ============================================================
create or replace function public.maj_note_hotesse() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update public.hotesses h set
    note_moyenne = coalesce((select round(avg(a.note)::numeric, 1) from public.avis a where a.hotesse_id = new.hotesse_id), 5.0),
    nb_avis = (select count(*) from public.avis a where a.hotesse_id = new.hotesse_id)
  where h.id = new.hotesse_id;
  return new;
end; $$;
drop trigger if exists maj_note_hotesse on public.avis;
create trigger maj_note_hotesse after insert on public.avis
for each row execute function public.maj_note_hotesse();
revoke execute on function public.maj_note_hotesse() from public, anon, authenticated;
