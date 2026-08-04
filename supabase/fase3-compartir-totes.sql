-- =====================================================================
-- Pandapp Family — fase 3: qualsevol activitat es pot compartir
-- =====================================================================
-- Migració incremental per a la base de dades real. Segura de tornar a
-- executar sencera (create or replace).
--
-- `reclamar_activitat` ja no exigeix `activitats.compartible = true` per
-- acceptar participants etiquetats — es manté la columna (com
-- `requereix_foto`) sense fer-hi res, per si es fa servir més endavant
-- per suggerir quines val la pena compartir.
-- =====================================================================

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
  end if;

  return v_completion;
end;
$$;

comment on function public.reclamar_activitat(uuid, text, text, uuid[]) is
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown (individual si cooldown_individual o es_personal, compartit altrament), calcula l''escalada per oblit i el límit personal diari amb el resultat, reparteix el pot entre els participants si n''hi ha (tasques compartides, qualsevol activitat), decideix l''estat inicial (validada si és personal, pendent altrament) i crea completion + participacions en una sola transacció. La foto és sempre opcional.';

revoke all on function public.reclamar_activitat(uuid, text, text, uuid[]) from public;
grant execute on function public.reclamar_activitat(uuid, text, text, uuid[]) to authenticated;
