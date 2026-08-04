-- =====================================================================
-- Pandapp Family — fase 3, peça 1: lògica de ratxes i monedes
-- =====================================================================
-- Migració incremental per a la base de dades real. Cal haver aplicat
-- `monedes.sql` i `ratxes.sql` abans (aquest fitxer no crea taules).
-- Segur de tornar a executar sencer (CREATE OR REPLACE).
--
-- Afegeix `processar_punts_validats` (funció interna, no exposada via
-- RPC) i hi afegeix una crida des de `reclamar_activitat` (quan la
-- completion neix ja validada, és a dir personal) i des de
-- `validar_completion` (quan es valida). Veure comentaris de cada funció
-- i CLAUDE.md "Ratxes" / "Dues monedes" per a la lògica completa.
-- =====================================================================

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

  select max(created_at) into v_ultima_completion
  from public.completions
  where activitat_id = p_activitat_id;

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

  v_estat_inicial := case when v_activitat.es_personal then 'validada' else 'pendent' end;

  insert into public.completions (
    activitat_id, familia_id, creada_per,
    versio_punts, punts_base_snapshot, pot_total,
    foto_url, thumb_url, estat
  ) values (
    v_activitat.id, v_familia_id, v_usuari_id,
    v_activitat.versio, v_punts_calculats, v_punts_calculats,
    p_foto_url, p_thumb_url, v_estat_inicial
  )
  returning * into v_completion;

  insert into public.participacions (
    completion_id, usuari_id, punts_assignats, confirmat, es_qui_puja
  ) values (
    v_completion.id, v_usuari_id, v_punts_calculats, true, true
  );

  if v_estat_inicial = 'validada' then
    perform public.processar_punts_validats(v_usuari_id, v_familia_id, v_completion.id);
  end if;

  return v_completion;
end;
$$;

comment on function public.reclamar_activitat(uuid, text, text) is
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown i foto obligatòria, calcula l''escalada per oblit i el límit personal diari amb el resultat, decideix l''estat inicial (validada si és personal, pendent altrament) i crea completion + participació en una sola transacció.';

revoke all on function public.reclamar_activitat(uuid, text, text) from public;
grant execute on function public.reclamar_activitat(uuid, text, text) to authenticated;

create or replace function public.validar_completion(p_completion_id uuid)
returns public.completions
language plpgsql
security definer
set search_path = public
as $$
declare
  v_usuari_id  uuid := auth.uid();
  v_completion public.completions%rowtype;
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

  if v_completion.creada_per = v_usuari_id then
    raise exception 'No pots validar una reclamació que has creat tu mateix.';
  end if;

  if v_completion.estat <> 'pendent' then
    raise exception 'Aquesta reclamació ja no està pendent de validació.';
  end if;

  update public.completions
  set estat = 'validada',
      validada_per = v_usuari_id
  where id = p_completion_id
  returning * into v_completion;

  -- Ratxa/escut/monedes són de qui ha FET la tasca (creada_per), no de qui
  -- l'ha validat.
  perform public.processar_punts_validats(
    v_completion.creada_per, v_completion.familia_id, v_completion.id
  );

  return v_completion;
end;
$$;

comment on function public.validar_completion(uuid) is
  'Valida una completion pendent creada per un altre membre de la família (el creador no es pot autovalidar). Posa estat = ''validada'' i validada_per = auth.uid().';

revoke all on function public.validar_completion(uuid) from public;
grant execute on function public.validar_completion(uuid) to authenticated;
