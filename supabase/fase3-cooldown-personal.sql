-- =====================================================================
-- Pandapp Family — fase 3: les activitats personals sempre són individuals
-- =====================================================================
-- Migració incremental per a la base de dades real. Segura de tornar a
-- executar sencera (CREATE OR REPLACE).
--
-- Bug: una activitat amb `es_personal = true` (llegir, meditar...) NOMÉS
-- quedava amb cooldown individual si a més tenia `cooldown_individual =
-- true`. En la pràctica cap activitat personal té aquest flag activat, així
-- que dos usuaris diferents es bloquejaven l'un a l'altre en reclamar la
-- mateixa activitat personal — quan una activitat personal és individual
-- per definició (que Joel llegeixi no pot bloquejar que Raquel llegeixi).
-- Ara `reclamar_activitat` fa servir cooldown individual quan
-- `cooldown_individual OR es_personal`.
-- =====================================================================

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

  -- cooldown_individual O es_personal: cada usuari té el seu propi cooldown
  -- (i, per tant, la seva pròpia escalada per oblit, que reutilitza aquest
  -- mateix v_ultima_completion més avall) en lloc de bloquejar-se per a
  -- tothom. Una activitat personal és individual per definició encara que
  -- cooldown_individual quedi a false.
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
  'Únic punt d''entrada per reclamar una activitat: comprova cooldown (individual si cooldown_individual o es_personal, compartit altrament) i foto obligatòria, calcula l''escalada per oblit i el límit personal diari amb el resultat, decideix l''estat inicial (validada si és personal, pendent altrament) i crea completion + participació en una sola transacció.';

revoke all on function public.reclamar_activitat(uuid, text, text) from public;
grant execute on function public.reclamar_activitat(uuid, text, text) to authenticated;
