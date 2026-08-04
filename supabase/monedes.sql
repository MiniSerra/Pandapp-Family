-- =====================================================================
-- Pandapp Family — taula monedes (fase 3)
-- =====================================================================
-- Segona moneda: es guanya alhora que els punts (veure CLAUDE.md "Dues
-- monedes") i es gastarà en recompenses reals (fase 3, peça posterior).
-- Igual que `completions`/`participacions`, el client MAI hi escriu
-- directament: el saldo només es modifica des de
-- `processar_punts_validats` (security definer, veure
-- supabase/fase3-ratxes-monedes.sql).
-- =====================================================================

create table public.monedes (
  usuari_id uuid primary key references public.profiles (id) on delete cascade,
  saldo     integer not null default 0 check (saldo >= 0)
);

comment on table public.monedes is
  'Saldo de monedes bescanviables (fase 3). Només es modifica des de processar_punts_validats; el client no hi insereix ni actualitza directament.';

alter table public.monedes enable row level security;

-- Es pot veure el saldo de qualsevol membre de la família (útil per a
-- recompenses compartides, fase 3).
create policy "monedes: veure la família" on public.monedes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = monedes.usuari_id
        and p.familia_id = public.familia_id_actual()
    )
  );

-- No hi ha política d'INSERT ni UPDATE per a `authenticated`.
