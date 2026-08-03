-- =====================================================================
-- Pandapp Family — taula likes (fase 2, feed)
-- =====================================================================
-- Els likes NO donen punts (CLAUDE.md "Feed social"): només alimenten un
-- comptador visual ("aplaudiments"). Per això, a diferència de
-- completions/participacions, el client SÍ insereix i esborra
-- directament amb polítiques RLS normals — no cal cap funció security
-- definer intermèdia, ja que no hi ha cap regla de negoci a protegir.
-- =====================================================================

create table public.likes (
  completion_id uuid not null references public.completions (id) on delete cascade,
  usuari_id     uuid not null references public.profiles (id) on delete cascade,
  created_at    timestamptz not null default now(),

  primary key (completion_id, usuari_id)
);

comment on table public.likes is
  'Aplaudiments a una completion del feed. No donen punts, només compten. El client hi insereix/esborra directament (RLS), sense passar per cap funció.';

-- comptar/llistar likes d'una completion des del feed.
create index idx_likes_completion on public.likes (completion_id);

alter table public.likes enable row level security;

-- Es poden veure els likes de completions de la pròpia família.
create policy "likes: veure la família" on public.likes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.completions c
      where c.id = likes.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );

-- Només es pot donar like en nom propi, i únicament a completions de la
-- pròpia família.
create policy "likes: donar like en nom propi" on public.likes
  for insert
  to authenticated
  with check (
    usuari_id = auth.uid()
    and exists (
      select 1
      from public.completions c
      where c.id = likes.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );

-- Només es pot treure el propi like (tocar el cor un altre cop el desfà).
create policy "likes: treure el propi like" on public.likes
  for delete
  to authenticated
  using (
    usuari_id = auth.uid()
    and exists (
      select 1
      from public.completions c
      where c.id = likes.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );
