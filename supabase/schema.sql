-- =====================================================================
-- Pandapp Family — esquema Fase 1
-- =====================================================================
-- Taules incloses: families, profiles, activitats, completions,
-- participacions.
--
-- Fora d'abast en aquest fitxer (fases posteriors): likes, propostes,
-- vots, torns, monedes, recompenses, bescanvis, resums.
--
-- Decisions de disseny rellevants (veure CLAUDE.md):
--   - RLS activat a totes les taules; regla base: només la teva família.
--   - `completions.estat` es queda a 'validada' per defecte en fase 1
--     (no hi ha validació creuada fins la fase 2); les columnes `estat`
--     i `validada_per` ja existeixen des d'ara per no migrar després.
--   - El cooldown per activitat SÍ entra en fase 1, però NO es comprova
--     al client: es fa sempre dins de la funció `reclamar_activitat`,
--     en la mateixa transacció que crea la completion.
--   - L'escalada per oblit (k_dia, sostre) es calcula dins de
--     `reclamar_activitat` (fase 2): mai al client, i el resultat ja
--     arrodonit es guarda a `punts_base_snapshot`, que per tant deixa de
--     ser `activitats.punts_base` pla.
--   - Els punts es guarden a `participacions`, mai al pot de `completions`.
--   - El client MAI insereix directament a `completions`/`participacions`:
--     només pot cridar `reclamar_activitat` (i, per anul·lar, `anullar_completion`).
--     No hi ha polítiques d'INSERT per a `authenticated` en aquestes taules.
--   - Totes les agrupacions per dia/setmana/mes (límit personal diari,
--     i els futurs rànquings) es calculen en hora local d'Espanya
--     (Europe/Madrid) via `inici_periode_local`, mai en UTC.
-- =====================================================================

create extension if not exists pgcrypto;

-- =====================================================================
-- TAULA: families
-- =====================================================================
-- Una fila per unitat familiar. Arrel de tot l'aïllament de dades (RLS):
-- cada usuari pertany a una família i només veu el que hi pertany.
create table public.families (
  id                      uuid primary key default gen_random_uuid(),
  nom                     text not null,
  -- llindar de punts per considerar un dia "complet", valor per defecte
  -- per a nous perfils de la família (cada perfil el pot sobreescriure).
  llindar_diari_defecte   integer not null default 100 check (llindar_diari_defecte > 0),
  -- objectiu de punts setmanals de tota la família (barra de progrés
  -- col·lectiva); ~1500-1800 per a una família de 4 segons CLAUDE.md.
  objectiu_setmanal       integer not null default 1650 check (objectiu_setmanal > 0),
  created_at              timestamptz not null default now()
);

comment on table public.families is
  'Unitat familiar: arrel de l''aïllament de dades. Cada usuari pertany a una sola família.';

-- =====================================================================
-- TAULA: profiles
-- =====================================================================
-- Extensió d'auth.users amb les dades pròpies de l'app. Es crea sola
-- via trigger (handle_new_user) quan un admin dona d'alta un usuari des
-- del panell de Supabase — no hi ha registre públic.
create table public.profiles (
  id              uuid primary key references auth.users (id) on delete cascade,
  familia_id      uuid not null references public.families (id) on delete restrict,
  nom             text not null,
  avatar_url      text,
  -- llindar diari propi; per defecte el de la família (100), configurable
  -- per persona.
  llindar_diari   integer not null default 100 check (llindar_diari > 0),
  created_at      timestamptz not null default now()
);

comment on table public.profiles is
  'Dades d''usuari dins de l''app (1 a 1 amb auth.users). Creada automàticament pel trigger on_auth_user_created.';

create index idx_profiles_familia on public.profiles (familia_id);

-- =====================================================================
-- TAULA: activitats
-- =====================================================================
-- Catàleg de tasques que es poden reclamar. Els 5 paràmetres de punts i
-- tots els flags es creen des de la fase 1 encara que alguns (k_dia,
-- sostre, es_torn, el flux de proposta/votació) no s'utilitzin fins a
-- fases posteriors — així s'evita haver d'alterar la taula més endavant.
create table public.activitats (
  id                  uuid primary key default gen_random_uuid(),
  familia_id          uuid not null references public.families (id) on delete cascade,
  categoria           text not null check (
    categoria in (
      'casa', 'cuina', 'bany', 'roba', 'panda',
      'compres', 'manteniment', 'personals', 'familiars'
    )
  ),
  nom                 text not null,
  emoji               text not null,
  descripcio          text,

  -- --- paràmetres de punts (veure "Sistema de punts" a CLAUDE.md) ---
  punts_base          integer not null check (punts_base > 0),
  -- hores durant les quals la tasca queda bloquejada per a tothom
  -- després de reclamar-se (comprovat dins de reclamar_activitat).
  cooldown_h          numeric not null default 0 check (cooldown_h >= 0),
  -- hores dins de les quals es paga punts_base sense escalada.
  periode_normal_h    numeric not null default 24 check (periode_normal_h >= 0),
  -- % de pujada per dia passat el període normal (fase 2).
  k_dia               numeric not null default 0 check (k_dia >= 0),
  -- multiplicador màxim sobre punts_base (fase 2).
  sostre              numeric not null default 1 check (sostre >= 1),

  -- --- flags de comportament ---
  compartible         boolean not null default false,
  requereix_foto      boolean not null default true,
  es_personal         boolean not null default false,
  es_torn             boolean not null default false,

  -- --- cicle de vida del catàleg (flux complet a fase 4) ---
  estat               text not null default 'activa' check (
    estat in ('proposta', 'activa', 'retirada')
  ),
  versio              integer not null default 1 check (versio > 0),
  proposada_per       uuid references public.profiles (id) on delete set null,
  activa_des_de       timestamptz not null default now(),

  created_at          timestamptz not null default now(),

  constraint activitats_nom_unic_per_familia unique (familia_id, nom)
);

comment on table public.activitats is
  'Catàleg de tasques reclamables d''una família, amb els paràmetres que en defineixen els punts.';

create index idx_activitats_familia on public.activitats (familia_id);
create index idx_activitats_familia_estat on public.activitats (familia_id, estat);

-- =====================================================================
-- TAULA: completions
-- =====================================================================
-- Una reclamació d'una activitat en un moment donat. El "pot" de punts
-- es reparteix entre els participants a `participacions`; aquí no hi ha
-- cap columna de punts individuals.
--
-- `familia_id` i `creada_per` estan denormalitzats des de `activitats`
-- perquè les polítiques RLS i les consultes de feed/rànquing no calgui
-- que facin JOIN a `activitats` per saber de qui/de quina família és
-- cada fila. Sempre s'omplen dins de `reclamar_activitat`.
create table public.completions (
  id                    uuid primary key default gen_random_uuid(),
  activitat_id          uuid not null references public.activitats (id) on delete restrict,
  familia_id            uuid not null references public.families (id) on delete cascade,
  creada_per            uuid not null references public.profiles (id) on delete restrict,
  -- congela activitats.versio en el moment de completar-se, perquè un
  -- canvi de punts a mitja temporada no alteri l'històric.
  versio_punts          integer not null check (versio_punts > 0),
  -- punts reals atorgats en el moment de completar-se, amb l'escalada per
  -- oblit ja aplicada (fase 2): NO és activitats.punts_base pla, és
  -- punts_base × multiplicador d'escalada, ja arrodonit. Es calcula dins
  -- de reclamar_activitat i mai es recalcula després.
  punts_base_snapshot   integer not null check (punts_base_snapshot > 0),
  -- total de punts del pot abans de repartir-se entre participants
  -- (ja inclourà el multiplicador de grup quan les tasques compartides
  -- arribin a la fase 3; de moment sempre és igual a punts_base_snapshot).
  pot_total             integer not null check (pot_total >= 0),
  foto_url              text,
  thumb_url             text,
  -- fase 2: qui ha validat l'entrada des del feed.
  validada_per          uuid references public.profiles (id) on delete set null,
  -- fase 1: es queda sempre a 'validada' en crear-se (no hi ha
  -- validació creuada fins la fase 2).
  estat                 text not null default 'validada' check (
    estat in ('pendent', 'validada')
  ),
  -- el timestamp el posa el servidor (default now()), mai el mòbil.
  created_at            timestamptz not null default now()
);

comment on table public.completions is
  'Una reclamació d''una activitat feta en un moment concret. Fase 1: estat sempre ''validada'' en crear-se. S''insereix/esborra únicament via reclamar_activitat / anullar_completion.';

-- data de creació: rànquings diari/setmanal/mensual filtren per rang de dates.
create index idx_completions_created_at on public.completions (created_at);
-- activitat + data: cerca de "última completació d'aquesta activitat" per al cooldown.
create index idx_completions_activitat_created on public.completions (activitat_id, created_at desc);
-- família: lectures de feed/rànquing filtrades per família sense JOIN a activitats.
create index idx_completions_familia on public.completions (familia_id);

-- =====================================================================
-- TAULA: participacions
-- =====================================================================
-- Qui s'emporta punts d'una completion i quants. ELS PUNTS VIUEN AQUÍ,
-- MAI AL POT DE `completions` (si es guardessin al pot, cada consulta de
-- rànquing hauria de dividir i apareixerien errors d'arrodoniment).
create table public.participacions (
  completion_id     uuid not null references public.completions (id) on delete cascade,
  usuari_id         uuid not null references public.profiles (id) on delete restrict,
  punts_assignats   integer not null check (punts_assignats >= 0),
  -- fase 3: cal que la persona etiquetada confirmi "sí, hi era" perquè
  -- els punts s'abonin en tasques compartides. Fase 1: sempre true
  -- (encara no hi ha etiquetat d'altres persones).
  confirmat         boolean not null default true,
  -- qui ha pujat la foto (rep el residu de l'arrodoniment del pot).
  es_qui_puja       boolean not null default false,
  created_at        timestamptz not null default now(),

  primary key (completion_id, usuari_id)
);

comment on table public.participacions is
  'Repartiment de punts d''una completion entre els seus participants. Els punts de rànquing viuen aquí, no a completions. S''insereix únicament via reclamar_activitat (i s''esborra en cascada des d''anullar_completion).';

-- usuari: els rànquings agreguen punts per usuari i rang de dates.
create index idx_participacions_usuari on public.participacions (usuari_id);

-- =====================================================================
-- FUNCIÓ AUXILIAR: familia_id de l'usuari autenticat
-- =====================================================================
-- SECURITY DEFINER perquè les polítiques RLS d'altres taules (i de la
-- mateixa `profiles`) la puguin cridar sense provocar recursió sobre la
-- RLS de `profiles`. search_path fixat per seguretat.
create or replace function public.familia_id_actual()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select familia_id
  from public.profiles
  where id = auth.uid()
$$;

comment on function public.familia_id_actual() is
  'Retorna la familia_id del perfil de l''usuari autenticat. Ús exclusiu en polítiques RLS.';

revoke all on function public.familia_id_actual() from public;
grant execute on function public.familia_id_actual() to authenticated;

-- =====================================================================
-- FUNCIÓ AUXILIAR: inici d'un període en hora local d'Espanya
-- =====================================================================
-- now() i created_at es guarden en UTC (timestamptz). Si es trunca
-- directament amb date_trunc('day', now()) el dia comença a les 2h (o
-- 1h a l'hivern) hora d'Espanya, no a mitjanit. Aquesta funció converteix
-- primer a hora local, trunca, i torna a convertir a timestamptz.
--
-- p_unitat accepta qualsevol valor vàlid de date_trunc: 'day', 'week' o
-- 'month'. Reutilitzada pel límit personal diari (reclamar_activitat) i
-- pensada perquè els tres rànquings (diari/setmanal/mensual) la facin
-- servir quan es construeixin.
create or replace function public.inici_periode_local(
  p_unitat text,
  p_moment timestamptz default now()
)
returns timestamptz
language sql
stable
as $$
  select date_trunc(p_unitat, p_moment at time zone 'Europe/Madrid') at time zone 'Europe/Madrid'
$$;

comment on function public.inici_periode_local(text, timestamptz) is
  'Inici (en timestamptz) del dia/setmana/mes local d''Europe/Madrid que conté p_moment. Fes-la servir sempre en lloc de date_trunc(..., now()) per no agrupar en UTC.';

revoke all on function public.inici_periode_local(text, timestamptz) from public;
grant execute on function public.inici_periode_local(text, timestamptz) to authenticated;

-- =====================================================================
-- TRIGGER: crear profile automàticament en donar d'alta un usuari
-- =====================================================================
-- No hi ha registre públic: els comptes es creen manualment des del
-- panell de Supabase (o via l'API d'admin). Si en crear l'usuari es passa
-- `familia_id` a user_metadata, s'utilitza aquesta; si no ve, s'assigna la
-- família més antiga que existeixi (pensat per al cas d'una sola família
-- a l'app). Si encara no existeix cap família, la inserció falla per la
-- restricció NOT NULL i cal crear-ne una abans de donar d'alta usuaris.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_familia_id uuid;
begin
  v_familia_id := (new.raw_user_meta_data ->> 'familia_id')::uuid;

  if v_familia_id is null then
    select id into v_familia_id
    from public.families
    order by created_at
    limit 1;
  end if;

  insert into public.profiles (id, familia_id, nom, avatar_url, llindar_diari)
  values (
    new.id,
    v_familia_id,
    coalesce(new.raw_user_meta_data ->> 'nom', split_part(new.email, '@', 1)),
    new.raw_user_meta_data ->> 'avatar_url',
    coalesce((new.raw_user_meta_data ->> 'llindar_diari')::integer, 100)
  );
  return new;
end;
$$;

comment on function public.handle_new_user() is
  'Crea la fila de profiles en donar d''alta un usuari a auth.users. Si no hi ha familia_id a user_metadata, agafa la família més antiga.';

revoke all on function public.handle_new_user() from public;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- FUNCIÓ: reclamar_activitat
-- =====================================================================
-- Únic punt d'entrada per crear una completion. Tota la lògica de
-- negoci (cooldown, límit personal diari, foto obligatòria, càlcul de
-- l'escalada per oblit) viu aquí, mai al client, perquè és l'únic lloc
-- on es pot garantir atomicitat (bloqueig de fila) i que ningú se salti
-- les regles cridant directament la taula.
create or replace function public.reclamar_activitat(
  p_activitat_id uuid,
  p_foto_url text default null,
  p_thumb_url text default null
)
returns public.completions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id            uuid := auth.uid();
  v_familia_id           uuid;
  v_activitat            public.activitats%rowtype;
  v_ultima_completion    timestamptz;
  v_punts_personals_avui integer;
  v_hores_des_ultima     numeric;
  v_dies_passats_periode numeric;
  v_multiplicador        numeric;
  v_punts_calculats      integer;
  v_completion           public.completions%rowtype;
begin
  if v_usuari_id is null then
    raise exception 'Cal estar autenticat per reclamar una activitat.';
  end if;

  v_familia_id := public.familia_id_actual();
  if v_familia_id is null then
    raise exception 'El teu usuari no té cap família assignada.';
  end if;

  -- Bloqueja només aquesta fila d'activitats. FOR UPDATE no afecta les
  -- lectures normals (SELECT sense FOR UPDATE/FOR SHARE) d'altres
  -- sessions: navegar el catàleg no es bloqueja mai. Només serialitza
  -- dues crides a reclamar_activitat amb el mateix p_activitat_id, que
  -- és exactament el que volem evitar (dos dispositius reclamant alhora).
  select * into v_activitat
  from public.activitats
  where id = p_activitat_id
  for update;

  if not found then
    raise exception 'Aquesta activitat no existeix.';
  end if;

  if v_activitat.familia_id <> v_familia_id then
    raise exception 'Aquesta activitat no pertany a la teva família.';
  end if;

  if v_activitat.estat <> 'activa' then
    raise exception 'Aquesta activitat no està activa i no es pot reclamar.';
  end if;

  select max(created_at) into v_ultima_completion
  from public.completions
  where activitat_id = p_activitat_id;

  if v_ultima_completion is not null
     and v_ultima_completion > now() - (v_activitat.cooldown_h * interval '1 hour') then
    raise exception 'Aquesta activitat encara està en temps de refredament. Torna-ho a provar més tard.';
  end if;

  -- Escalada per oblit (veure CLAUDE.md "Sistema de punts"): passat
  -- periode_normal_h des de l'última completació, els punts pugen de
  -- manera contínua per dia, limitats per sostre. Si encara no ha passat
  -- periode_normal_h, o l'activitat no s'havia fet mai, són punts_base
  -- plans. Arrodoniment normal (no cap amunt: això és per al repartiment
  -- de tasques compartides, fase 3).
  if v_ultima_completion is null then
    v_punts_calculats := v_activitat.punts_base;
  else
    v_hores_des_ultima := extract(epoch from (now() - v_ultima_completion)) / 3600.0;
    v_dies_passats_periode := greatest(0, (v_hores_des_ultima - v_activitat.periode_normal_h) / 24.0);
    v_multiplicador := least(v_activitat.sostre, 1 + v_activitat.k_dia * v_dies_passats_periode);
    v_punts_calculats := round(v_activitat.punts_base * v_multiplicador)::integer;
  end if;

  if v_activitat.requereix_foto and p_foto_url is null then
    raise exception 'Aquesta activitat requereix una foto per poder reclamar-la.';
  end if;

  if v_activitat.es_personal then
    select coalesce(sum(p.punts_assignats), 0) into v_punts_personals_avui
    from public.participacions p
    join public.completions c on c.id = p.completion_id
    join public.activitats a on a.id = c.activitat_id
    where p.usuari_id = v_usuari_id
      and a.es_personal
      and c.created_at >= public.inici_periode_local('day');

    if v_punts_personals_avui + v_punts_calculats > 60 then
      raise exception 'Has arribat al límit de 60 punts personals per avui.';
    end if;
  end if;

  insert into public.completions (
    activitat_id, familia_id, creada_per,
    versio_punts, punts_base_snapshot, pot_total,
    foto_url, thumb_url
  ) values (
    v_activitat.id, v_familia_id, v_usuari_id,
    v_activitat.versio, v_punts_calculats, v_punts_calculats,
    p_foto_url, p_thumb_url
  )
  returning * into v_completion;

  insert into public.participacions (
    completion_id, usuari_id, punts_assignats, confirmat, es_qui_puja
  ) values (
    v_completion.id, v_usuari_id, v_punts_calculats, true, true
  );

  return v_completion;
end;
$$;

comment on function public.reclamar_activitat(uuid, text, text) is
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown i foto obligatòria, calcula l''escalada per oblit i el límit personal diari amb el resultat, i crea completion + participació en una sola transacció.';

revoke all on function public.reclamar_activitat(uuid, text, text) from public;
grant execute on function public.reclamar_activitat(uuid, text, text) to authenticated;

-- =====================================================================
-- FUNCIÓ: anullar_completion
-- =====================================================================
-- Permet desfer una reclamació feta per error, només dins d'una finestra
-- curta. Esborra la completion (i, en cascada, la seva participació) i
-- retorna les rutes de la foto/miniatura perquè el frontend les esborri
-- del bucket de Storage (des de SQL no es pot tocar Storage).
create or replace function public.anullar_completion(p_completion_id uuid)
returns table (foto_url text, thumb_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id  uuid := auth.uid();
  v_completion public.completions%rowtype;
begin
  if v_usuari_id is null then
    raise exception 'Cal estar autenticat per anul·lar una reclamació.';
  end if;

  select * into v_completion
  from public.completions
  where id = p_completion_id;

  if not found then
    raise exception 'Aquesta reclamació no existeix.';
  end if;

  if v_completion.familia_id <> public.familia_id_actual() then
    raise exception 'Aquesta reclamació no pertany a la teva família.';
  end if;

  if v_completion.creada_per <> v_usuari_id then
    raise exception 'Només pots anul·lar reclamacions que hagis creat tu mateix.';
  end if;

  if v_completion.created_at < now() - interval '15 minutes' then
    raise exception 'Ja no es pot anul·lar: han passat més de 15 minuts des que es va crear.';
  end if;

  delete from public.completions where id = p_completion_id;

  return query select v_completion.foto_url, v_completion.thumb_url;
end;
$$;

comment on function public.anullar_completion(uuid) is
  'Esborra una completion pròpia creada fa menys de 15 minuts (i la seva participació, en cascada). Retorna foto_url/thumb_url perquè el client esborri els fitxers del bucket.';

revoke all on function public.anullar_completion(uuid) from public;
grant execute on function public.anullar_completion(uuid) to authenticated;

-- =====================================================================
-- RLS
-- =====================================================================

alter table public.families enable row level security;
alter table public.profiles enable row level security;
alter table public.activitats enable row level security;
alter table public.completions enable row level security;
alter table public.participacions enable row level security;

-- ---- families -------------------------------------------------------
-- Només es pot llegir la pròpia família. La creació/edició de families
-- no s'exposa als usuaris (es fa amb service_role des del panell), per
-- això no hi ha polítiques d'INSERT/UPDATE/DELETE per a `authenticated`.
create policy "families: veure la pròpia" on public.families
  for select
  to authenticated
  using (id = public.familia_id_actual());

-- ---- profiles --------------------------------------------------------
-- Es poden veure tots els perfils de la mateixa família (necessari per
-- mostrar noms/avatars als rànquings i al feed).
create policy "profiles: veure la família" on public.profiles
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

-- Cadascú només pot editar el seu propi perfil, i no pot canviar-se de
-- família des del client.
create policy "profiles: editar el propi" on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid() and familia_id = public.familia_id_actual());

-- No hi ha política d'INSERT per a `authenticated`: les files les crea
-- únicament el trigger handle_new_user (via security definer).

-- ---- activitats -------------------------------------------------------
-- Fase 1: el catàleg és de només lectura per als usuaris (es carrega amb
-- el seed / eines d'admin amb service_role). L'escriptura des del client
-- arribarà amb el flux de propostes i votacions (fase 4).
create policy "activitats: veure la família" on public.activitats
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

-- ---- completions -------------------------------------------------------
-- Es poden veure les completions de la pròpia família.
create policy "completions: veure la família" on public.completions
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

-- No hi ha política d'INSERT, UPDATE ni DELETE per a `authenticated`: la
-- creació passa sempre per `reclamar_activitat` i l'anul·lació per
-- `anullar_completion` (totes dues security definer, salten la RLS). El
-- flux de validació (fase 2) es dissenyarà més endavant.

-- ---- participacions -------------------------------------------------------
-- Es poden veure les participacions de completions de la pròpia família
-- (necessari per calcular els rànquings de tots els membres).
create policy "participacions: veure la família" on public.participacions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.completions c
      where c.id = participacions.completion_id
        and c.familia_id = public.familia_id_actual()
    )
  );

-- No hi ha política d'INSERT ni DELETE per a `authenticated`: la creació
-- passa sempre per `reclamar_activitat` i l'esborrat en cascada per
-- `anullar_completion` (security definer, salten la RLS).
