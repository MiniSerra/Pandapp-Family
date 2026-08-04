-- =====================================================================
-- Pandapp Family — fase 3: menú de recompenses
-- =====================================================================
-- Migració incremental per a la base de dades real. Segura de tornar a
-- executar sencera (drop/add constraint if exists, create table/index if
-- not exists, create or replace).
--
-- Amplia `esdeveniments` (creada a fase3-objectiu-setmanal.sql) perquè
-- també accepti el tipus 'bescanvi': hi afegeix `usuari_id` (qui
-- protagonitza l'esdeveniment; objectiu_setmanal no en té perquè és de
-- tota la família), fa `setmana` opcional (només objectiu_setmanal la fa
-- servir) i substitueix la restricció `unique (familia_id, tipus,
-- setmana)` per un índex únic parcial (`where tipus = 'objectiu_setmanal'`)
-- perquè bescanvi es pugui repetir sense xocar-hi.
--
-- Taules noves `recompenses` (catàleg, només lectura per als usuaris) i
-- `bescanvis` (un bescanvi = un cost_pagat congelat + un esdeveniment al
-- feed), i la funció `bescanviar_recompensa`.
-- =====================================================================

alter table public.esdeveniments
  drop constraint if exists esdeveniments_familia_id_tipus_setmana_key;

alter table public.esdeveniments
  add column if not exists usuari_id uuid references public.profiles (id) on delete set null;

alter table public.esdeveniments
  alter column setmana drop not null;

alter table public.esdeveniments
  drop constraint if exists esdeveniments_tipus_check;

alter table public.esdeveniments
  add constraint esdeveniments_tipus_check check (tipus in ('objectiu_setmanal', 'bescanvi'));

create unique index if not exists idx_esdeveniments_objectiu_setmanal_unic
  on public.esdeveniments (familia_id, setmana)
  where tipus = 'objectiu_setmanal';

comment on table public.esdeveniments is
  'Esdeveniments de sistema al feed (fase 3): objectiu_setmanal i bescanvi. L''índex únic parcial evita duplicar objectiu_setmanal la mateixa setmana; bescanvi no té aquesta restricció. Només s''hi escriu des de comprovar_objectiu_setmanal i bescanviar_recompensa.';

create or replace function public.comprovar_objectiu_setmanal(p_familia_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inici_setmana timestamptz := public.inici_periode_local('week');
  v_suma          integer;
  v_objectiu      integer;
  v_premi         text;
begin
  select objectiu_setmanal, premi_setmanal into v_objectiu, v_premi
  from public.families
  where id = p_familia_id;

  select coalesce(sum(pot_total), 0) into v_suma
  from public.completions
  where familia_id = p_familia_id
    and estat = 'validada'
    and created_at >= v_inici_setmana;

  if v_suma < v_objectiu then
    return;
  end if;

  insert into public.esdeveniments (familia_id, tipus, setmana, dades)
  values (
    p_familia_id, 'objectiu_setmanal', v_inici_setmana::date,
    jsonb_build_object('suma', v_suma, 'objectiu', v_objectiu, 'premi', v_premi)
  )
  on conflict (familia_id, setmana) where tipus = 'objectiu_setmanal' do nothing;
end;
$$;

comment on function public.comprovar_objectiu_setmanal(uuid) is
  'Recalcula la suma setmanal de pot_total i registra l''esdeveniment objectiu_setmanal (com a molt un cop per setmana) si s''arriba a objectiu_setmanal. Ús intern, no exposada via RPC.';

revoke all on function public.comprovar_objectiu_setmanal(uuid) from public;

create table if not exists public.recompenses (
  id         uuid primary key default gen_random_uuid(),
  familia_id uuid not null references public.families (id) on delete cascade,
  nom        text not null,
  emoji      text not null,
  cost       integer not null check (cost > 0),
  activa     boolean not null default true,
  created_at timestamptz not null default now()
);

comment on table public.recompenses is
  'Catàleg de recompenses bescanviables amb monedes (fase 3). De només lectura per als usuaris; es gestiona via SQL Editor.';

create index if not exists idx_recompenses_familia on public.recompenses (familia_id);

create table if not exists public.bescanvis (
  id            uuid primary key default gen_random_uuid(),
  recompensa_id uuid not null references public.recompenses (id) on delete restrict,
  usuari_id     uuid not null references public.profiles (id) on delete cascade,
  familia_id    uuid not null references public.families (id) on delete cascade,
  cost_pagat    integer not null check (cost_pagat > 0),
  created_at    timestamptz not null default now()
);

comment on table public.bescanvis is
  'Bescanvis de recompenses amb monedes (fase 3). cost_pagat congela el cost en el moment de bescanviar. S''insereix únicament via bescanviar_recompensa.';

create index if not exists idx_bescanvis_familia on public.bescanvis (familia_id);
create index if not exists idx_bescanvis_usuari on public.bescanvis (usuari_id);

alter table public.recompenses enable row level security;
alter table public.bescanvis enable row level security;

drop policy if exists "recompenses: veure la família" on public.recompenses;
create policy "recompenses: veure la família" on public.recompenses
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

drop policy if exists "bescanvis: veure la família" on public.bescanvis;
create policy "bescanvis: veure la família" on public.bescanvis
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

create or replace function public.bescanviar_recompensa(p_recompensa_id uuid)
returns public.bescanvis
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id  uuid := auth.uid();
  v_familia_id uuid;
  v_recompensa public.recompenses%rowtype;
  v_saldo      integer;
  v_bescanvi   public.bescanvis%rowtype;
begin
  if v_usuari_id is null then
    raise exception 'Cal estar autenticat per bescanviar una recompensa.';
  end if;

  v_familia_id := public.familia_id_actual();
  if v_familia_id is null then
    raise exception 'El teu usuari no té cap família assignada.';
  end if;

  select * into v_recompensa
  from public.recompenses
  where id = p_recompensa_id;

  if not found then
    raise exception 'Aquesta recompensa no existeix.';
  end if;

  if v_recompensa.familia_id <> v_familia_id then
    raise exception 'Aquesta recompensa no pertany a la teva família.';
  end if;

  if not v_recompensa.activa then
    raise exception 'Aquesta recompensa ja no està disponible.';
  end if;

  select saldo into v_saldo
  from public.monedes
  where usuari_id = v_usuari_id
  for update;

  if v_saldo is null or v_saldo < v_recompensa.cost then
    raise exception 'No tens prou monedes per bescanviar aquesta recompensa.';
  end if;

  update public.monedes
  set saldo = saldo - v_recompensa.cost
  where usuari_id = v_usuari_id;

  insert into public.bescanvis (recompensa_id, usuari_id, familia_id, cost_pagat)
  values (p_recompensa_id, v_usuari_id, v_familia_id, v_recompensa.cost)
  returning * into v_bescanvi;

  insert into public.esdeveniments (familia_id, usuari_id, tipus, dades)
  values (
    v_familia_id, v_usuari_id, 'bescanvi',
    jsonb_build_object('recompensa', v_recompensa.nom, 'emoji', v_recompensa.emoji, 'cost', v_recompensa.cost)
  );

  return v_bescanvi;
end;
$$;

comment on function public.bescanviar_recompensa(uuid) is
  'Bescanvia una recompensa activa de la pròpia família amb monedes: comprova saldo suficient, el resta, i registra el bescanvi i l''esdeveniment al feed.';

revoke all on function public.bescanviar_recompensa(uuid) from public;
grant execute on function public.bescanviar_recompensa(uuid) to authenticated;
