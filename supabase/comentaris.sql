-- =====================================================================
-- Pandapp Family — comentaris al feed (fase 3)
-- =====================================================================
-- Igual que `likes`, els comentaris no donen punts ni afecten cap regla
-- de negoci: el client hi insereix directament amb polítiques RLS
-- normals, sense cap funció security definer intermèdia.
--
-- `resposta_a` permet respostes, però només a UN nivell: una resposta
-- sempre apunta a un comentari "arrel" (resposta_a és null en el pare),
-- mai a una altra resposta. La interfície només ofereix "Respon" als
-- comentaris arrel; respondre dins d'un fil s'enganxa igualment a sota.
-- =====================================================================

create table public.comentaris (
  id            uuid primary key default gen_random_uuid(),
  completion_id uuid not null references public.completions (id) on delete cascade,
  usuari_id     uuid not null references public.profiles (id) on delete cascade,
  resposta_a    uuid references public.comentaris (id) on delete cascade,
  text          text not null check (char_length(btrim(text)) between 1 and 500),
  created_at    timestamptz not null default now()
);

comment on table public.comentaris is
  'Comentaris i respostes (un sol nivell) a una completion del feed. No donen punts. El client hi insereix directament (RLS).';

-- llistar els comentaris d'una completion des del feed.
create index idx_comentaris_completion on public.comentaris (completion_id);

alter table public.comentaris enable row level security;

-- Es poden veure els comentaris de completions de la pròpia família.
create policy "comentaris: veure la família" on public.comentaris
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.completions c
      where c.id = comentaris.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );

-- Només es pot comentar en nom propi, i únicament a completions de la
-- pròpia família.
create policy "comentaris: comentar en nom propi" on public.comentaris
  for insert
  to authenticated
  with check (
    usuari_id = auth.uid()
    and exists (
      select 1
      from public.completions c
      where c.id = comentaris.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );

-- Només es pot esborrar el propi comentari.
create policy "comentaris: esborrar el propi" on public.comentaris
  for delete
  to authenticated
  using (usuari_id = auth.uid());

-- =====================================================================
-- TAULA: comentari_likes
-- =====================================================================
-- Mateix patró que `likes`, però sobre comentaris en lloc de completions.
create table public.comentari_likes (
  comentari_id uuid not null references public.comentaris (id) on delete cascade,
  usuari_id    uuid not null references public.profiles (id) on delete cascade,
  created_at   timestamptz not null default now(),

  primary key (comentari_id, usuari_id)
);

comment on table public.comentari_likes is
  'Likes a un comentari del feed. No donen punts. El client hi insereix/esborra directament (RLS).';

alter table public.comentari_likes enable row level security;

create policy "comentari_likes: veure la família" on public.comentari_likes
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.comentaris co
      join public.completions c on c.id = co.completion_id
      where co.id = comentari_likes.comentari_id
        and c.familia_id = public.familia_id_actual()
    )
  );

create policy "comentari_likes: donar like en nom propi" on public.comentari_likes
  for insert
  to authenticated
  with check (
    usuari_id = auth.uid()
    and exists (
      select 1
      from public.comentaris co
      join public.completions c on c.id = co.completion_id
      where co.id = comentari_likes.comentari_id
        and c.familia_id = public.familia_id_actual()
    )
  );

create policy "comentari_likes: treure el propi like" on public.comentari_likes
  for delete
  to authenticated
  using (usuari_id = auth.uid());
