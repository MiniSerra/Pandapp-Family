-- =====================================================================
-- Pandapp Family — fase 3: les monedes es donen sempre, no només al
-- creuar el llindar diari
-- =====================================================================
-- Migració incremental per a la base de dades real. Segura de tornar a
-- executar sencera (create or replace).
--
-- BUG: processar_punts_validats només actuava (ratxa I monedes) quan la
-- completion feia creuar el llindar_diari — és a dir, la majoria de
-- reclamacions d'un dia normal no donaven cap moneda, només la que
-- justet arribava al llindar. Ara les MONEDES es donen sempre, 1 per
-- cada 10 punts de CADA completion validada ("es guanyen alhora que els
-- punts", CLAUDE.md "Dues monedes"). La RATXA es queda exactament igual
-- que abans (només un cop al dia, quan es creua el llindar).
--
-- anullar_completion també s'actualitza en conseqüència: reverteix les
-- monedes sempre (ja no només quan la completion esborrada era la que
-- creuava el llindar), mantenint la ratxa amb el mateix criteri d'abans.
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

  -- Monedes: 1 per cada 10 punts d'AQUESTA completion (arrodonit avall),
  -- SEMPRE — independent del llindar diari, a diferència de la ratxa de
  -- sota.
  v_monedes_guanyades := floor(v_punts_completion / 10.0)::integer;

  if v_monedes_guanyades > 0 then
    insert into public.monedes (usuari_id, saldo)
    values (p_usuari_id, v_monedes_guanyades)
    on conflict (usuari_id) do update
      set saldo = monedes.saldo + excluded.saldo;
  end if;

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
  'Es crida quan els punts d''una completion compten de veritat. Dona monedes sempre (1 per cada 10 punts d''aquesta completion); actualitza ratxa/escut només quan aquesta completion creua el llindar diari, i crea una completion "Bonus de ratxa" si escau. Ús intern, no exposada via RPC.';

revoke all on function public.processar_punts_validats(uuid, uuid, uuid) from public;

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

    select coalesce(sum(part.punts_assignats), 0) into v_punts_completion
    from public.participacions part
    where part.completion_id = p_completion_id and part.usuari_id = v_usuari_id;

    -- Monedes: exactament les que va donar aquesta completion, sempre
    -- (processar_punts_validats ja no les lliga al llindar diari).
    v_monedes_a_revertir := floor(v_punts_completion / 10.0)::integer;
    if v_monedes_a_revertir > 0 then
      update public.monedes
      set saldo = greatest(saldo - v_monedes_a_revertir, 0)
      where usuari_id = v_usuari_id;
    end if;

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

    if v_era_creuament and v_punts_avui_sense < v_llindar then
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

        if v_ratxa.escut_usat_mes = v_dia_local then
          update public.ratxes
          set escut_disponible = true,
              escut_usat_mes = null
          where usuari_id = v_usuari_id;
        end if;
      end if;
    end if;
  end if;

  delete from public.completions where id = p_completion_id;

  return query select v_completion.foto_url, v_completion.thumb_url;
end;
$$;

comment on function public.anullar_completion(uuid) is
  'Esborra una completion pròpia creada fa menys de 15 minuts (i la seva participació, en cascada), revertint sempre les monedes que hagués donat i la ratxa si era la que creuava el llindar diari. Retorna foto_url/thumb_url perquè el client esborri els fitxers del bucket.';

revoke all on function public.anullar_completion(uuid) from public;
grant execute on function public.anullar_completion(uuid) to authenticated;
