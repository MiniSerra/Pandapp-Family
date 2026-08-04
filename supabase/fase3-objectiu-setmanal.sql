-- =====================================================================
-- Pandapp Family — fase 3: objectiu col·lectiu setmanal de veritat
-- =====================================================================
-- Migració incremental per a la base de dades real. Segura de tornar a
-- executar sencera (add column if not exists, create table if not
-- exists, create or replace).
--
-- families.objectiu_setmanal ja existia; s'hi afegeix premi_setmanal
-- (text lliure, editable només via SQL Editor). Taula esdeveniments nova
-- per registrar quan s'assoleix l'objectiu (fase 3, veure CLAUDE.md
-- "Objectiu col·lectiu"). Nova funció comprovar_objectiu_setmanal,
-- cridada des de reclamar_activitat (personal), validar_completion i
-- confirmar_participacio (quan es valida sola).
-- =====================================================================

alter table public.families
  add column if not exists premi_setmanal text;

comment on column public.families.premi_setmanal is
  'Premi real si s''assoleix l''objectiu setmanal (text lliure). Editable només via SQL Editor de moment.';

create table if not exists public.esdeveniments (
  id         uuid primary key default gen_random_uuid(),
  familia_id uuid not null references public.families (id) on delete cascade,
  tipus      text not null check (tipus in ('objectiu_setmanal')),
  setmana    date not null,
  dades      jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),

  unique (familia_id, tipus, setmana)
);

comment on table public.esdeveniments is
  'Esdeveniments de sistema al feed (fase 3): de moment només objectiu_setmanal. unique (familia_id, tipus, setmana) evita duplicar-lo. Només s''hi escriu des de comprovar_objectiu_setmanal.';

create index if not exists idx_esdeveniments_familia on public.esdeveniments (familia_id);

alter table public.esdeveniments enable row level security;

drop policy if exists "esdeveniments: veure la família" on public.esdeveniments;
create policy "esdeveniments: veure la família" on public.esdeveniments
  for select
  to authenticated
  using (familia_id = public.familia_id_actual());

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
  on conflict (familia_id, tipus, setmana) do nothing;
end;
$$;

comment on function public.comprovar_objectiu_setmanal(uuid) is
  'Recalcula la suma setmanal de pot_total i registra l''esdeveniment objectiu_setmanal (com a molt un cop per setmana) si s''arriba a objectiu_setmanal. Ús intern, no exposada via RPC.';

revoke all on function public.comprovar_objectiu_setmanal(uuid) from public;

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
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown (individual si cooldown_individual o es_personal, compartit altrament), calcula l''escalada per oblit i el límit personal diari amb el resultat, reparteix el pot entre els participants si n''hi ha (tasques compartides, qualsevol activitat), decideix l''estat inicial (validada si és personal, pendent altrament) i crea completion + participacions en una sola transacció. La foto és sempre opcional.';

revoke all on function public.reclamar_activitat(uuid, text, text, uuid[]) from public;
grant execute on function public.reclamar_activitat(uuid, text, text, uuid[]) to authenticated;

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

  if v_completion.estat = 'validada' then
    perform public.processar_punts_validats(v_usuari_id, v_completion.familia_id, p_completion_id);
    return;
  end if;

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
