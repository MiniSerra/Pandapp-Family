-- =====================================================================
-- Pandapp Family — taula ratxes (fase 3)
-- =====================================================================
-- Ratxa de dies complerts per usuari (veure CLAUDE.md "Ratxes"). Igual
-- que `monedes`, el client MAI hi escriu directament: només es modifica
-- des de `processar_punts_validats` (security definer, veure
-- supabase/fase3-ratxes-monedes.sql).
-- =====================================================================

create table public.ratxes (
  usuari_id           uuid primary key references public.profiles (id) on delete cascade,
  dies_seguits        integer not null default 0 check (dies_seguits >= 0),
  -- data local (Europe/Madrid), NO timestamptz: una ratxa és per dies de
  -- calendari, no per instants. Null si encara no s'ha completat mai cap dia.
  ultim_dia_complert  date,
  -- un dia de gràcia al mes que evita perdre la ratxa si es trenca.
  escut_disponible    boolean not null default true,
  -- data local del dia en què es va gastar l'escut (per saber quan
  -- resetejar-lo al canviar de mes). Null si encara no s'ha gastat mai.
  escut_usat_mes      date
);

comment on table public.ratxes is
  'Ratxa de dies complerts per usuari (fase 3). ultim_dia_complert i escut_usat_mes són dates locals d''Europe/Madrid. Només es modifica des de processar_punts_validats.';

alter table public.ratxes enable row level security;

-- Es pot veure la ratxa de qualsevol membre de la família (per mostrar-la
-- al perfil de tothom, no només el propi).
create policy "ratxes: veure la família" on public.ratxes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.profiles p
      where p.id = ratxes.usuari_id
        and p.familia_id = public.familia_id_actual()
    )
  );

-- No hi ha política d'INSERT ni UPDATE per a `authenticated`.
