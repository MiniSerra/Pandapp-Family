-- =====================================================================
-- Pandapp Family — fase 2, peça 2: validació creuada
-- =====================================================================
-- Migració incremental per a la base de dades real. Cal haver aplicat
-- `fase2-escalada.sql` abans (aquest fitxer reemplaça `reclamar_activitat`
-- una altra vegada, ara afegint-hi també l'estat inicial de validació).
-- Segur de tornar a executar sencer.
--
-- - `completions` neix 'pendent' (validar_completion la passa a
--   'validada'), excepte les activitats personals, que neixen 'validada'
--   directament perquè ningú més les pot confirmar.
-- - `validar_completion(p_completion_id)`: qui valida no pot ser qui ha
--   creat la completion, ha de ser de la mateixa família, i la completion
--   ha d'estar encara 'pendent'.
-- - No calen polítiques d'UPDATE noves per a `authenticated`: totes dues
--   funcions són security definer i salten la RLS.
-- - Els punts d'una completion 'pendent' no compten al progrés diari ni
--   als rànquings: això es filtra al client (Activitats.jsx, ranquing.js),
--   no aquí.
-- =====================================================================

alter table public.completions alter column estat set default 'pendent';

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

  return v_completion;
end;
$$;

comment on function public.validar_completion(uuid) is
  'Valida una completion pendent creada per un altre membre de la família (el creador no es pot autovalidar). Posa estat = ''validada'' i validada_per = auth.uid().';

revoke all on function public.validar_completion(uuid) from public;
grant execute on function public.validar_completion(uuid) to authenticated;
