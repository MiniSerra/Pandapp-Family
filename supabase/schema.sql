-- =====================================================================
-- Pandapp Family — esquema Fase 1
-- =====================================================================
-- Taules incloses: families, profiles, activitats, completions,
-- participacions, monedes, ratxes. La taula `likes` viu a
-- supabase/likes.sql (fase 2, sense cap dependència d'aquest fitxer).
--
-- Fora d'abast en aquest fitxer (fases posteriors): propostes, vots,
-- torns, recompenses, bescanvis, resums.
--
-- Decisions de disseny rellevants (veure CLAUDE.md):
--   - RLS activat a totes les taules; regla base: només la teva família.
--   - Validació creuada (fase 2): `completions` neix `'pendent'`, excepte
--     les personals que neixen `'validada'` a l'instant (ningú més les pot
--     confirmar). `validar_completion` la posa a `'validada'` — sempre algú
--     diferent de qui l'ha creat. Els punts d'una completion `'pendent'`
--     no compten al progrés diari ni als rànquings (filtrat al client).
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
  -- premi real si s'assoleix l'objectiu setmanal (text lliure, p. ex.
  -- "Pizza tots junts divendres"). Editable només via SQL Editor de
  -- moment, no hi ha interfície per canviar-lo.
  premi_setmanal          text,
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
-- `cooldown_individual` (fase 3): per a tasques on cadascú té el seu
-- propi "exemplar" (el llit, l'habitació pròpia) i que una altra persona
-- la faci no hauria de bloquejar-la ni desescalar-la per a mi.
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
  -- hores durant les quals la tasca queda bloquejada després de
  -- reclamar-se (comprovat dins de reclamar_activitat). Per a qui queda
  -- bloquejada depèn de `cooldown_individual` O `es_personal` (qualsevol
  -- dels dos activa el mode individual, veure comentari sota i a
  -- reclamar_activitat).
  cooldown_h          numeric not null default 0 check (cooldown_h >= 0),
  -- false (per defecte): el cooldown és de la tasca, no de la persona —
  -- si algú neteja el sorral, queda bloquejada per a tothom (recurs
  -- compartit). true: cada usuari té el seu propi cooldown i la seva
  -- pròpia escalada per oblit, independents dels altres — per a tasques
  -- on cadascú té el seu propi "exemplar" (el llit, l'habitació...) i que
  -- una altra persona faci la seva no hauria de bloquejar ni desescalar
  -- la meva. Les activitats `es_personal` són sempre individuals per
  -- definició encara que aquest flag quedi a false — reclamar_activitat
  -- combina els dos amb un OR.
  cooldown_individual boolean not null default false,
  -- hores dins de les quals es paga punts_base sense escalada.
  periode_normal_h    numeric not null default 24 check (periode_normal_h >= 0),
  -- % de pujada per dia passat el període normal (fase 2).
  k_dia               numeric not null default 0 check (k_dia >= 0),
  -- multiplicador màxim sobre punts_base (fase 2).
  sostre              numeric not null default 1 check (sostre >= 1),

  -- --- flags de comportament ---
  -- Ja no bloqueja res a reclamar_activitat ni a la interfície: qualsevol
  -- activitat es pot compartir. Es manté la columna per si es fa servir
  -- més endavant per suggerir quines val la pena compartir.
  compartible         boolean not null default false,
  -- Ja no bloqueja res a reclamar_activitat ni a la interfície: la foto
  -- sempre és opcional, per a totes les activitats (veure CLAUDE.md
  -- "Validació de tasques"). Es manté la columna per si es fa servir més
  -- endavant per suggerir quan convé posar-ne.
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
  -- total de punts del pot abans de repartir-se entre participants. Igual
  -- a punts_base_snapshot si ningú més hi participa; si és una tasca
  -- compartida (fase 3), ja inclou el multiplicador de grup.
  pot_total             integer not null check (pot_total >= 0),
  foto_url              text,
  thumb_url             text,
  -- qui ha validat l'entrada (fase 2: via validar_completion). Sempre algú
  -- diferent de creada_per.
  validada_per          uuid references public.profiles (id) on delete set null,
  -- neix 'pendent' (validar_completion la passa a 'validada'), excepte les
  -- activitats personals, que neixen 'validada' directament perquè ningú
  -- més les pot confirmar.
  estat                 text not null default 'pendent' check (
    estat in ('pendent', 'validada')
  ),
  -- el timestamp el posa el servidor (default now()), mai el mòbil.
  created_at            timestamptz not null default now()
);

comment on table public.completions is
  'Una reclamació d''una activitat feta en un moment concret. Neix ''pendent'' (''validada'' si és personal) fins que validar_completion la valida. S''insereix/esborra únicament via reclamar_activitat / anullar_completion.';

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
-- TAULA: monedes
-- =====================================================================
-- Segona moneda (fase 3, veure CLAUDE.md "Dues monedes"): es guanya
-- alhora que els punts i es gastarà en recompenses reals (peça
-- posterior). El client MAI hi escriu directament: només es modifica
-- des de `processar_punts_validats`.
create table public.monedes (
  usuari_id uuid primary key references public.profiles (id) on delete cascade,
  saldo     integer not null default 0 check (saldo >= 0)
);

comment on table public.monedes is
  'Saldo de monedes bescanviables (fase 3). Només es modifica des de processar_punts_validats; el client no hi insereix ni actualitza directament.';

-- =====================================================================
-- TAULA: ratxes
-- =====================================================================
-- Ratxa de dies complerts per usuari (fase 3, veure CLAUDE.md "Ratxes").
-- Igual que `monedes`, el client MAI hi escriu directament.
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

-- =====================================================================
-- TAULA: esdeveniments
-- =====================================================================
-- Esdeveniments de sistema que surten al feed barrejats amb les
-- completions però no en són (sense foto, avatars, like ni comentaris) —
-- objectiu_setmanal (fase 3, veure CLAUDE.md "Objectiu col·lectiu") i
-- bescanvi (fase 3, veure CLAUDE.md "Recompenses"). El client MAI hi
-- escriu directament: només `comprovar_objectiu_setmanal` i
-- `bescanviar_recompensa` (totes dues security definer).
create table public.esdeveniments (
  id         uuid primary key default gen_random_uuid(),
  familia_id uuid not null references public.families (id) on delete cascade,
  -- qui protagonitza l'esdeveniment; null als esdeveniments de tota la
  -- família (objectiu_setmanal), que no són d'una sola persona.
  usuari_id  uuid references public.profiles (id) on delete set null,
  tipus      text not null check (tipus in ('objectiu_setmanal', 'bescanvi')),
  -- data (local Europe/Madrid) del dilluns que comença la setmana —
  -- només s'omple a objectiu_setmanal, la clau que evita duplicar-lo la
  -- mateixa setmana (veure l'índex únic parcial de sota). null a bescanvi,
  -- que es pot repetir tantes vegades com es vulgui.
  setmana    date,
  dades      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

comment on table public.esdeveniments is
  'Esdeveniments de sistema al feed (fase 3): objectiu_setmanal i bescanvi. L''índex únic parcial evita duplicar objectiu_setmanal la mateixa setmana; bescanvi no té aquesta restricció. Només s''hi escriu des de comprovar_objectiu_setmanal i bescanviar_recompensa.';

create index idx_esdeveniments_familia on public.esdeveniments (familia_id);

-- Només objectiu_setmanal necessita ser únic per setmana (protegeix contra
-- duplicar-lo si dues validacions el creuen gairebé alhora: `insert ... on
-- conflict do nothing` sobre aquest índex és atòmic a nivell de base de
-- dades, a diferència d'una comprovació prèvia amb un select, que sempre
-- tindria una finestra de carrera entre dues transaccions concurrents).
-- bescanvi es pot repetir tantes vegades com es vulgui, per això l'índex
-- és parcial (`where tipus = 'objectiu_setmanal'`) i no una restricció de
-- taula sencera.
create unique index idx_esdeveniments_objectiu_setmanal_unic
  on public.esdeveniments (familia_id, setmana)
  where tipus = 'objectiu_setmanal';

-- =====================================================================
-- TAULA: recompenses
-- =====================================================================
-- Catàleg de recompenses bescanviables amb monedes (fase 3, veure
-- CLAUDE.md "Recompenses"). Igual que `activitats` a fase 1: de només
-- lectura per als usuaris, es gestiona via SQL Editor de moment — no hi ha
-- política d'INSERT/UPDATE/DELETE per a `authenticated`.
create table public.recompenses (
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

create index idx_recompenses_familia on public.recompenses (familia_id);

-- =====================================================================
-- TAULA: bescanvis
-- =====================================================================
-- Un bescanvi d'una recompensa concreta per un usuari concret (fase 3).
-- `cost_pagat` congela el cost en el moment de bescanviar (com
-- `punts_base_snapshot` a completions): si el cost de la recompensa canvia
-- més endavant, l'històric no s'ha de recalcular sol. `familia_id` és
-- denormalitzat (com a `completions`) perquè el feed no calgui fer JOIN a
-- `recompenses` per saber de quina família és cada bescanvi. El client MAI
-- hi escriu directament: només `bescanviar_recompensa` (security definer).
create table public.bescanvis (
  id            uuid primary key default gen_random_uuid(),
  recompensa_id uuid not null references public.recompenses (id) on delete restrict,
  usuari_id     uuid not null references public.profiles (id) on delete cascade,
  familia_id    uuid not null references public.families (id) on delete cascade,
  cost_pagat    integer not null check (cost_pagat > 0),
  created_at    timestamptz not null default now()
);

comment on table public.bescanvis is
  'Bescanvis de recompenses amb monedes (fase 3). cost_pagat congela el cost en el moment de bescanviar. S''insereix únicament via bescanviar_recompensa.';

create index idx_bescanvis_familia on public.bescanvis (familia_id);
create index idx_bescanvis_usuari on public.bescanvis (usuari_id);

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
-- FUNCIÓ AUXILIAR: processar_punts_validats
-- =====================================================================
-- Es crida sempre que els punts d'una completion passen a comptar de
-- veritat: al final de `reclamar_activitat` quan neix ja 'validada'
-- (activitats personals), i al final de `validar_completion` quan un
-- altre membre la valida. Gestiona la ratxa/escut i les monedes de QUI HA
-- FET la tasca (`creada_per`), no de qui l'ha validat. Funció interna:
-- no s'exposa via RPC (no hi ha `grant ... to authenticated`), només la
-- criden altres funcions security definer.
--
-- Lògica (veure CLAUDE.md "Ratxes"): només actua quan aquesta completion
-- és la que fa arribar la suma de punts validats d'avui al
-- `llindar_diari` per primera vegada avui. Si `ultim_dia_complert` és
-- ahir, la ratxa continua; si és avui mateix, no fa res (ja processat);
-- si no és cap dels dos, es trenca (dies_seguits = 1) tret que hi hagi
-- escut disponible, que la manté i es gasta. El primer dia complert de
-- sempre (ultim_dia_complert null) tampoc gasta escut.
create or replace function public.processar_punts_validats(
  p_usuari_id uuid,
  p_familia_id uuid,
  p_completion_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_llindar                integer;
  v_punts_completion        integer;
  v_punts_avui_total        integer;
  v_punts_avui_abans        integer;
  v_avui                    date;
  v_ahir                    date;
  v_ratxa                   public.ratxes%rowtype;
  v_dies_seguits_nous        integer;
  v_monedes_guanyades        integer;
  v_bonus_ratxa              integer;
  v_bonus_fita               integer;
  v_bonus_total              integer;
  v_activitat_bonus_id       uuid;
  v_activitat_bonus_versio   integer;
  v_completion_bonus         public.completions%rowtype;
begin
  v_avui := (now() at time zone 'Europe/Madrid')::date;
  v_ahir := v_avui - 1;

  select coalesce(sum(punts_assignats), 0) into v_punts_completion
  from public.participacions
  where completion_id = p_completion_id and usuari_id = p_usuari_id;

  select llindar_diari into v_llindar
  from public.profiles
  where id = p_usuari_id;

  select coalesce(sum(part.punts_assignats), 0) into v_punts_avui_total
  from public.participacions part
  join public.completions comp on comp.id = part.completion_id
  where part.usuari_id = p_usuari_id
    and comp.estat = 'validada'
    and comp.created_at >= public.inici_periode_local('day');

  v_punts_avui_abans := v_punts_avui_total - v_punts_completion;

  -- Només actua si aquesta completion és la que creua el llindar avui.
  if not (v_punts_avui_abans < v_llindar and v_punts_avui_total >= v_llindar) then
    return;
  end if;

  insert into public.ratxes (usuari_id) values (p_usuari_id)
  on conflict (usuari_id) do nothing;

  select * into v_ratxa
  from public.ratxes
  where usuari_id = p_usuari_id
  for update;

  -- Reset mensual de l'escut (sense cron encara: es comprova aquí mateix,
  -- abans de decidir si es fa servir més avall).
  if v_ratxa.escut_usat_mes is not null
     and v_ratxa.escut_usat_mes < date_trunc('month', v_avui)::date then
    v_ratxa.escut_disponible := true;
  end if;

  if v_ratxa.ultim_dia_complert = v_avui then
    return; -- ja processat avui (no hauria de passar; evita duplicar-ho).
  elsif v_ratxa.ultim_dia_complert = v_ahir then
    v_dies_seguits_nous := v_ratxa.dies_seguits + 1;
  elsif v_ratxa.ultim_dia_complert is null then
    v_dies_seguits_nous := 1;
  elsif v_ratxa.escut_disponible then
    v_dies_seguits_nous := v_ratxa.dies_seguits + 1;
    v_ratxa.escut_disponible := false;
    v_ratxa.escut_usat_mes := v_avui;
  else
    v_dies_seguits_nous := 1;
  end if;

  update public.ratxes
  set dies_seguits = v_dies_seguits_nous,
      ultim_dia_complert = v_avui,
      escut_disponible = v_ratxa.escut_disponible,
      escut_usat_mes = v_ratxa.escut_usat_mes
  where usuari_id = p_usuari_id;

  -- Monedes: 1 per cada 10 punts d'AQUESTA completion (arrodonit avall).
  v_monedes_guanyades := floor(v_punts_completion / 10.0)::integer;

  if v_monedes_guanyades > 0 then
    insert into public.monedes (usuari_id, saldo)
    values (p_usuari_id, v_monedes_guanyades)
    on conflict (usuari_id) do update
      set saldo = monedes.saldo + excluded.saldo;
  end if;

  -- Bonus de ratxa (suma fixa, mai multiplicador) + fites del CLAUDE.md.
  v_bonus_ratxa := least(5 * v_dies_seguits_nous, 50);
  v_bonus_fita := case v_dies_seguits_nous
    when 7 then 100
    when 14 then 200
    when 30 then 500
    else 0
  end;
  v_bonus_total := v_bonus_ratxa + v_bonus_fita;

  if v_bonus_total > 0 then
    -- Activitat de sistema per registrar el bonus com a completion: es
    -- crea una vegada per família (idempotent via l'unique existent a
    -- activitats) i es queda 'retirada' perquè no aparegui al catàleg ni
    -- es pugui reclamar a mà.
    insert into public.activitats (
      familia_id, categoria, nom, emoji, descripcio,
      punts_base, cooldown_h, periode_normal_h, k_dia, sostre,
      compartible, requereix_foto, es_personal, es_torn, estat
    ) values (
      p_familia_id, 'personals', 'Bonus de ratxa', '🔥',
      'Bonus automàtic per mantenir la ratxa o assolir una fita. El crea el sistema; no es pot reclamar a mà.',
      1, 0, 0, 0, 1, false, false, true, false, 'retirada'
    )
    on conflict (familia_id, nom) do nothing;

    select id, versio into v_activitat_bonus_id, v_activitat_bonus_versio
    from public.activitats
    where familia_id = p_familia_id and nom = 'Bonus de ratxa';

    insert into public.completions (
      activitat_id, familia_id, creada_per,
      versio_punts, punts_base_snapshot, pot_total,
      foto_url, thumb_url, estat
    ) values (
      v_activitat_bonus_id, p_familia_id, p_usuari_id,
      v_activitat_bonus_versio, v_bonus_total, v_bonus_total,
      null, null, 'validada'
    )
    returning * into v_completion_bonus;

    insert into public.participacions (
      completion_id, usuari_id, punts_assignats, confirmat, es_qui_puja
    ) values (
      v_completion_bonus.id, p_usuari_id, v_bonus_total, true, true
    );
  end if;
end;
$$;

comment on function public.processar_punts_validats(uuid, uuid, uuid) is
  'Es crida quan els punts d''una completion compten de veritat. Actualitza ratxa/escut i monedes de qui ha fet la tasca, i crea una completion "Bonus de ratxa" si escau. Ús intern, no exposada via RPC.';

revoke all on function public.processar_punts_validats(uuid, uuid, uuid) from public;

-- =====================================================================
-- FUNCIÓ: comprovar_objectiu_setmanal
-- =====================================================================
-- Es crida sempre que una completion passa a 'validada' (reclamar_activitat
-- quan neix ja validada perquè és personal, validar_completion,
-- confirmar_participacio quan es valida sola): recalcula la suma de
-- pot_total de la setmana en curs i, si arriba a objectiu_setmanal,
-- registra l'esdeveniment (fase 3, veure CLAUDE.md "Objectiu col·lectiu").
-- Suma el POT SENCER de cada completion, no punts_assignats individuals
-- (l'objectiu és de tota la família, no depèn de qui ha confirmat què).
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

  -- `on conflict do nothing` sobre l'índex únic parcial és atòmic: encara
  -- que dues validacions creuin el llindar gairebé alhora, només una de
  -- les dues transaccions guanya la inserció.
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

-- =====================================================================
-- FUNCIÓ: reclamar_activitat
-- =====================================================================
-- Únic punt d'entrada per crear una completion. Tota la lògica de
-- negoci (cooldown, límit personal diari, càlcul de l'escalada per
-- oblit, tasques compartides, estat inicial de validació) viu aquí, mai
-- al client, perquè és l'únic lloc
-- on es pot garantir atomicitat (bloqueig de fila) i que ningú se salti
-- les regles cridant directament la taula.
--
-- Tasques compartides (fase 3, veure CLAUDE.md "Tasques compartides"):
-- p_participants_ids són els MEMBRES ETIQUETATS a més de qui reclama (mai
-- cal incloure's un mateix). Es filtren els que no pertanyin a la família
-- o coincideixin amb qui reclama — per tant és segur passar-hi qualsevol
-- llista sense pre-validar-la al client. Amb participants vàlids, el pot
-- (punts_base_snapshot, ja amb l'escalada aplicada) es multiplica segons
-- el nombre total de participants (multiplicador = 1 + 0.4×(n-1): 1→x1,
-- 2→x1.4, 3→x1.8, 4→x2.2) i es reparteix a parts iguals arrodonint AVALL;
-- el residu se l'emporta qui reclama. Els participants etiquetats neixen
-- amb `confirmat = false` — veure `confirmar_participacio`.
--
-- S'afegeix un 4t paràmetre (p_participants_ids) a una signatura que ja
-- existia: `create or replace` NO substitueix una funció amb una signatura
-- diferent, en crearia una de sobrecarregada a part. Cal eliminar
-- explícitament la versió antiga de 3 paràmetres.
drop function if exists public.reclamar_activitat(uuid, text, text);

create or replace function public.reclamar_activitat(
  p_activitat_id uuid,
  p_foto_url text default null,
  p_thumb_url text default null,
  p_participants_ids uuid[] default null
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
  v_participants_valids  uuid[];
  v_n_participants       integer;
  v_multiplicador_grup   numeric;
  v_pot_total            integer;
  v_punts_per_persona    integer;
  v_residu               integer;
  v_participant_id       uuid;
  v_estat_inicial        text;
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

  -- cooldown_individual O es_personal: cada usuari té el seu propi cooldown
  -- (i, per tant, la seva pròpia escalada per oblit, que reutilitza aquest
  -- mateix v_ultima_completion més avall) en lloc de bloquejar-se per a
  -- tothom. Una activitat personal (llegir, meditar...) és individual per
  -- definició — que Joel llegeixi no pot bloquejar que Raquel llegeixi.
  if v_activitat.cooldown_individual or v_activitat.es_personal then
    select max(created_at) into v_ultima_completion
    from public.completions
    where activitat_id = p_activitat_id
      and creada_per = v_usuari_id;
  else
    select max(created_at) into v_ultima_completion
    from public.completions
    where activitat_id = p_activitat_id;
  end if;

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

  -- Tasques compartides: qualsevol activitat es pot compartir. Es filtren
  -- de p_participants_ids els ids que no pertanyin a la família o que
  -- coincideixin amb qui reclama (mai cal que el client ho faci bé).
  if p_participants_ids is not null and array_length(p_participants_ids, 1) > 0 then
    select array_agg(id) into v_participants_valids
    from public.profiles
    where familia_id = v_familia_id
      and id = any(p_participants_ids)
      and id <> v_usuari_id;
  end if;

  v_n_participants := 1 + coalesce(array_length(v_participants_valids, 1), 0);
  v_multiplicador_grup := 1 + 0.4 * (v_n_participants - 1);
  v_pot_total := round(v_punts_calculats * v_multiplicador_grup)::integer;
  v_punts_per_persona := floor(v_pot_total::numeric / v_n_participants)::integer;
  v_residu := v_pot_total - (v_punts_per_persona * v_n_participants);

  -- Validació creuada (fase 2): les personals es validen soles a l'instant
  -- (ningú més les pot confirmar, mai són compartides); la resta neix
  -- 'pendent' fins que tots els participants etiquetats confirmin i,
  -- si entre tots cobreixen la família sencera, es validi sola (veure
  -- `confirmar_participacio`), o fins que algú extern la valida amb
  -- `validar_completion`.
  v_estat_inicial := case when v_activitat.es_personal then 'validada' else 'pendent' end;

  insert into public.completions (
    activitat_id, familia_id, creada_per,
    versio_punts, punts_base_snapshot, pot_total,
    foto_url, thumb_url, estat
  ) values (
    v_activitat.id, v_familia_id, v_usuari_id,
    v_activitat.versio, v_punts_calculats, v_pot_total,
    p_foto_url, p_thumb_url, v_estat_inicial
  )
  returning * into v_completion;

  insert into public.participacions (
    completion_id, usuari_id, punts_assignats, confirmat, es_qui_puja
  ) values (
    v_completion.id, v_usuari_id, v_punts_per_persona + v_residu, true, true
  );

  if v_participants_valids is not null then
    foreach v_participant_id in array v_participants_valids loop
      insert into public.participacions (
        completion_id, usuari_id, punts_assignats, confirmat, es_qui_puja
      ) values (
        v_completion.id, v_participant_id, v_punts_per_persona, false, false
      );
    end loop;
  end if;

  if v_estat_inicial = 'validada' then
    perform public.processar_punts_validats(v_usuari_id, v_familia_id, v_completion.id);
    perform public.comprovar_objectiu_setmanal(v_familia_id);
  end if;

  return v_completion;
end;
$$;

comment on function public.reclamar_activitat(uuid, text, text, uuid[]) is
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown (individual si cooldown_individual o es_personal, compartit altrament), calcula l''escalada per oblit i el límit personal diari amb el resultat, reparteix el pot entre els participants si n''hi ha (tasques compartides), decideix l''estat inicial (validada si és personal, pendent altrament) i crea completion + participacions en una sola transacció. La foto és sempre opcional.';

revoke all on function public.reclamar_activitat(uuid, text, text, uuid[]) from public;
grant execute on function public.reclamar_activitat(uuid, text, text, uuid[]) to authenticated;

-- =====================================================================
-- FUNCIÓ: validar_completion
-- =====================================================================
-- Valida una completion 'pendent' (fase 2). El validador no pot ser cap
-- PARTICIPANT (ni qui l'ha creat ni cap etiquetat, encara no hagi
-- confirmat o ja ho hagi fet) — en una tasca compartida (fase 3) que
-- cobreixi tota la família ja no cal ningú extern: es valida sola en
-- confirmar l'últim (veure `confirmar_participacio`). Security definer
-- perquè el client no necessita (ni té) una política d'UPDATE directa
-- sobre `completions`: tota escriptura de validació passa per aquí.
create or replace function public.validar_completion(p_completion_id uuid)
returns public.completions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id  uuid := auth.uid();
  v_completion public.completions%rowtype;
  v_participant record;
begin
  if v_usuari_id is null then
    raise exception 'Cal estar autenticat per validar una reclamació.';
  end if;

  select * into v_completion
  from public.completions
  where id = p_completion_id
  for update;

  if not found then
    raise exception 'Aquesta reclamació no existeix.';
  end if;

  if v_completion.familia_id <> public.familia_id_actual() then
    raise exception 'Aquesta reclamació no pertany a la teva família.';
  end if;

  if exists (
    select 1 from public.participacions
    where completion_id = p_completion_id and usuari_id = v_usuari_id
  ) then
    raise exception 'No pots validar una reclamació on ets participant.';
  end if;

  if v_completion.estat <> 'pendent' then
    raise exception 'Aquesta reclamació ja no està pendent de validació.';
  end if;

  update public.completions
  set estat = 'validada',
      validada_per = v_usuari_id
  where id = p_completion_id
  returning * into v_completion;

  -- Ratxa/escut/monedes són de cada participant CONFIRMAT (mai de qui
  -- valida): en una tasca compartida en pot haver-hi més d'un. Els
  -- participants encara no confirmats en aquest moment rebran el seu quan
  -- confirmin (confirmar_participacio ho gestiona per a una completion ja
  -- validada).
  for v_participant in
    select usuari_id from public.participacions
    where completion_id = v_completion.id and confirmat = true
  loop
    perform public.processar_punts_validats(
      v_participant.usuari_id, v_completion.familia_id, v_completion.id
    );
  end loop;

  perform public.comprovar_objectiu_setmanal(v_completion.familia_id);

  return v_completion;
end;
$$;

comment on function public.validar_completion(uuid) is
  'Valida una completion pendent creada per un altre membre de la família (cap participant es pot autovalidar). Posa estat = ''validada'' i validada_per = auth.uid(), i processa ratxa/monedes de cada participant ja confirmat.';

revoke all on function public.validar_completion(uuid) from public;
grant execute on function public.validar_completion(uuid) to authenticated;

-- =====================================================================
-- FUNCIÓ: confirmar_participacio
-- =====================================================================
-- Un membre etiquetat com a participant d'una tasca compartida (fase 3)
-- confirma "sí, hi era" perquè els seus punts comptin. Dos casos:
--   1. La completion encara és 'pendent': si amb aquesta confirmació TOTS
--      els participants ja han confirmat i, entre tots, cobreixen la
--      família sencera, no cal ningú extern — es valida sola aquí mateix
--      (validada_per = qui acaba de confirmar) i es processa ratxa/monedes
--      de tots els participants (cap n'havia rebut encara, la completion
--      no era 'validada'). Si no cobreixen tota la família, es queda
--      'pendent': algú que no hi participi l'haurà de validar amb
--      `validar_completion` com sempre.
--   2. La completion ja era 'validada' (algú extern l'ha validat mentre
--      aquest participant encara no havia confirmat): només cal processar
--      la ratxa/monedes d'aquest participant ara, ja que és el primer
--      moment en què els seus punts compten de veritat.
create or replace function public.confirmar_participacio(p_completion_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id       uuid := auth.uid();
  v_completion      public.completions%rowtype;
  v_participacio    public.participacions%rowtype;
  v_pendents        integer;
  v_participants    integer;
  v_membres_familia integer;
  v_participant     record;
begin
  if v_usuari_id is null then
    raise exception 'Cal estar autenticat per confirmar una participació.';
  end if;

  select * into v_completion
  from public.completions
  where id = p_completion_id
  for update;

  if not found then
    raise exception 'Aquesta reclamació no existeix.';
  end if;

  if v_completion.familia_id <> public.familia_id_actual() then
    raise exception 'Aquesta reclamació no pertany a la teva família.';
  end if;

  select * into v_participacio
  from public.participacions
  where completion_id = p_completion_id and usuari_id = v_usuari_id
  for update;

  if not found then
    raise exception 'No estàs etiquetat com a participant d''aquesta reclamació.';
  end if;

  if v_participacio.confirmat then
    raise exception 'Ja havies confirmat aquesta participació.';
  end if;

  update public.participacions
  set confirmat = true
  where completion_id = p_completion_id and usuari_id = v_usuari_id;

  -- Cas 2: la completion ja comptava de veritat (algú extern ja l'havia
  -- validada). Ara és el primer moment en què els punts d'aquest
  -- participant compten.
  if v_completion.estat = 'validada' then
    perform public.processar_punts_validats(v_usuari_id, v_completion.familia_id, p_completion_id);
    return;
  end if;

  -- Cas 1: encara 'pendent'. Comprova si ja no queda ningú per confirmar.
  select count(*) into v_pendents
  from public.participacions
  where completion_id = p_completion_id and confirmat = false;

  if v_pendents > 0 then
    return;
  end if;

  select count(*) into v_participants
  from public.participacions
  where completion_id = p_completion_id;

  select count(*) into v_membres_familia
  from public.profiles
  where familia_id = v_completion.familia_id;

  -- Els participants (tots confirmats ara) no cobreixen tota la família:
  -- queda algú de fora que l'ha de validar com sempre.
  if v_participants < v_membres_familia then
    return;
  end if;

  update public.completions
  set estat = 'validada',
      validada_per = v_usuari_id
  where id = p_completion_id;

  for v_participant in
    select usuari_id from public.participacions where completion_id = p_completion_id
  loop
    perform public.processar_punts_validats(
      v_participant.usuari_id, v_completion.familia_id, p_completion_id
    );
  end loop;

  perform public.comprovar_objectiu_setmanal(v_completion.familia_id);
end;
$$;

comment on function public.confirmar_participacio(uuid) is
  'Un participant etiquetat confirma "hi era" en una tasca compartida. Si això completa la confirmació de tots els participants i cobreixen tota la família, valida la completion sola (sense caldre ningú extern) i processa ratxa/monedes de tothom; si la completion ja estava validada, només processa la ratxa/monedes d''aquest participant.';

revoke all on function public.confirmar_participacio(uuid) from public;
grant execute on function public.confirmar_participacio(uuid) to authenticated;

-- =====================================================================
-- FUNCIÓ: bescanviar_recompensa
-- =====================================================================
-- Bescanvia una recompensa del catàleg amb monedes (fase 3, veure
-- CLAUDE.md "Recompenses"). Comprova que la recompensa és de la meva
-- família i està activa, que el saldo és suficient, resta el cost del
-- saldo i registra el bescanvi i l'esdeveniment al feed. `for update` a
-- `monedes` evita que dos bescanvis simultanis del mateix usuari deixin
-- el saldo negatiu (mateix motiu que els `for update` de
-- reclamar_activitat/confirmar_participacio).
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

-- =====================================================================
-- FUNCIÓ: anullar_completion
-- =====================================================================
-- Permet desfer una reclamació feta per error, només dins d'una finestra
-- curta. Esborra la completion (i, en cascada, la seva participació) i
-- retorna les rutes de la foto/miniatura perquè el frontend les esborri
-- del bucket de Storage (des de SQL no es pot tocar Storage). Els 15
-- minuts valen igual tant si la completion és 'pendent' com 'validada'
-- (no hi ha cap comprovació d'estat, expressament).
--
-- Si la completion ja estava 'validada' (processar_punts_validats ja s'hi
-- havia executat), cal revertir monedes/ratxa abans d'esborrar-la, si no
-- l'usuari es queda amb monedes o dies de ratxa que ja no corresponen a cap
-- completion real. Es recalcula, amb l'estat actual (encara inclou aquesta
-- completion), si aquesta era la que feia creuar el llindar diari — igual
-- que fa processar_punts_validats, excloent-hi sempre les completions de
-- "Bonus de ratxa" (no són feina real feta, no han de comptar ni per
-- decidir el creuament ni per revertir-lo). Aproximació de fase 3 (veure
-- CLAUDE.md "Validació de tasques"): dins la finestra de 15 minuts és
-- raonable assumir que no ha canviat res més des de la validació, però
-- casos límit (dos creuaments el mateix dia, escut gastat en un dia
-- anterior) es resolen amb la millor aproximació, mai deixant saldo de
-- monedes ni dies_seguits negatius.
create or replace function public.anullar_completion(p_completion_id uuid)
returns table (foto_url text, thumb_url text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id          uuid := auth.uid();
  v_completion         public.completions%rowtype;
  v_llindar            integer;
  v_dia_local          date;
  v_punts_completion   integer;
  v_punts_avui_total   integer;
  v_punts_avui_abans   integer;
  v_punts_avui_sense   integer;
  v_era_creuament      boolean;
  v_monedes_a_revertir integer;
  v_ratxa              public.ratxes%rowtype;
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

  -- Les completions de "Bonus de ratxa" (creades pel sistema, no per una
  -- reclamació real) ja s'exclouen dels sumatoris de sota, així que mai
  -- poden ser "les que creuen el llindar" per a cap ALTRA completion — però
  -- sense aquest tall, esborrar el bonus mateix es podria confondre amb un
  -- creuament seu propi (v_punts_completion sense excloure). No té sentit
  -- revertir res quan s'esborra un bonus: mai és ell qui fa arribar algú al
  -- llindar.
  if v_completion.estat = 'validada'
     and not exists (
       select 1 from public.activitats act
       where act.id = v_completion.activitat_id and act.nom = 'Bonus de ratxa'
     )
  then
    select llindar_diari into v_llindar
    from public.profiles
    where id = v_usuari_id;

    v_dia_local := (v_completion.created_at at time zone 'Europe/Madrid')::date;

    select coalesce(sum(part.punts_assignats), 0) into v_punts_avui_total
    from public.participacions part
    join public.completions comp on comp.id = part.completion_id
    where part.usuari_id = v_usuari_id
      and comp.estat = 'validada'
      and comp.created_at >= public.inici_periode_local('day', v_completion.created_at)
      and comp.created_at < public.inici_periode_local('day', v_completion.created_at) + interval '1 day'
      and not exists (
        select 1 from public.activitats act
        where act.id = comp.activitat_id and act.nom = 'Bonus de ratxa'
      );

    select coalesce(sum(part.punts_assignats), 0) into v_punts_completion
    from public.participacions part
    where part.completion_id = p_completion_id and part.usuari_id = v_usuari_id;

    select coalesce(sum(part.punts_assignats), 0) into v_punts_avui_sense
    from public.participacions part
    join public.completions comp on comp.id = part.completion_id
    where part.usuari_id = v_usuari_id
      and comp.estat = 'validada'
      and comp.id <> p_completion_id
      and comp.created_at >= public.inici_periode_local('day', v_completion.created_at)
      and comp.created_at < public.inici_periode_local('day', v_completion.created_at) + interval '1 day'
      and not exists (
        select 1 from public.activitats act
        where act.id = comp.activitat_id and act.nom = 'Bonus de ratxa'
      );

    v_punts_avui_abans := v_punts_avui_total - v_punts_completion;
    v_era_creuament := v_punts_avui_abans < v_llindar and v_punts_avui_total >= v_llindar;

    if v_era_creuament then
      -- Monedes: exactament les que va donar aquesta completion.
      v_monedes_a_revertir := floor(v_punts_completion / 10.0)::integer;
      if v_monedes_a_revertir > 0 then
        update public.monedes
        set saldo = greatest(saldo - v_monedes_a_revertir, 0)
        where usuari_id = v_usuari_id;
      end if;

      -- Ratxa: només si sense aquesta completion el dia ja no arriba al
      -- llindar (si hi arribava igualment per unes altres, no la toquem).
      if v_punts_avui_sense < v_llindar then
        select * into v_ratxa from public.ratxes where usuari_id = v_usuari_id for update;

        if v_ratxa.ultim_dia_complert = v_dia_local then
          if v_ratxa.dies_seguits <= 1 then
            update public.ratxes
            set dies_seguits = 0,
                ultim_dia_complert = null
            where usuari_id = v_usuari_id;
          else
            update public.ratxes
            set dies_seguits = dies_seguits - 1,
                ultim_dia_complert = v_dia_local - 1
            where usuari_id = v_usuari_id;
          end if;

          -- Si l'escut es va gastar precisament aquest dia, torna'l a
          -- deixar disponible.
          if v_ratxa.escut_usat_mes = v_dia_local then
            update public.ratxes
            set escut_disponible = true,
                escut_usat_mes = null
            where usuari_id = v_usuari_id;
          end if;
        end if;
      end if;
    end if;
  end if;

  delete from public.completions where id = p_completion_id;

  return query select v_completion.foto_url, v_completion.thumb_url;
end;
$$;

comment on function public.anullar_completion(uuid) is
  'Esborra una completion pròpia creada fa menys de 15 minuts (i la seva participació, en cascada), revertint les monedes/ratxa que hagués sumat (aproximació de fase 3). Retorna foto_url/thumb_url perquè el client esborri els fitxers del bucket.';

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
alter table public.monedes enable row level security;
alter table public.ratxes enable row level security;
alter table public.esdeveniments enable row level security;
alter table public.recompenses enable row level security;
alter table public.bescanvis enable row level security;

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
-- creació passa per `reclamar_activitat`, l'anul·lació per
-- `anullar_completion` i la validació (fase 2) per `validar_completion`
-- — totes tres security definer, salten la RLS. El client mai actualitza
-- `completions` directament.

-- ---- esdeveniments -------------------------------------------------------
-- Es poden veure els esdeveniments de la pròpia família. No hi ha política
-- d'INSERT per a `authenticated`: només hi escriu comprovar_objectiu_setmanal.
create policy "esdeveniments: veure la família" on public.esdeveniments
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

-- ---- recompenses -------------------------------------------------------
-- Fase 3: el catàleg és de només lectura per als usuaris (es gestiona via
-- SQL Editor, com el catàleg d'activitats a fase 1). No hi ha política
-- d'INSERT/UPDATE/DELETE per a `authenticated`.
create policy "recompenses: veure la família" on public.recompenses
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

-- ---- bescanvis -------------------------------------------------------
-- Es poden veure els bescanvis de la pròpia família (necessari per al
-- feed). No hi ha política d'INSERT per a `authenticated`: només hi
-- escriu bescanviar_recompensa.
create policy "bescanvis: veure la família" on public.bescanvis
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

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

-- ---- monedes -------------------------------------------------------
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

-- No hi ha política d'INSERT ni UPDATE per a `authenticated`: només
-- `processar_punts_validats` (security definer) hi escriu.

-- ---- ratxes -------------------------------------------------------
-- Es pot veure la ratxa de qualsevol membre de la família.
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

-- No hi ha política d'INSERT ni UPDATE per a `authenticated`: només
-- `processar_punts_validats` (security definer) hi escriu.
