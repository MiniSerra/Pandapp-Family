-- =====================================================================
-- Pandapp Family — fase 3, peça: anullar_completion reverteix monedes/ratxa
-- =====================================================================
-- Migració incremental per a la base de dades real. Segur de tornar a
-- executar sencer (CREATE OR REPLACE).
--
-- Fins ara `anullar_completion` esborrava la completion però no revertia
-- les monedes ni la ratxa que hagués sumat `processar_punts_validats` si la
-- completion ja estava 'validada'. Amb aquest canvi, si aquesta completion
-- va ser la que va fer creuar el llindar diari, es resta el que havia
-- donat. Exclou explícitament les completions de "Bonus de ratxa" (mai són
-- elles les que creuen el llindar). Veure el comentari de la funció a
-- schema.sql per als detalls (aproximació de fase 3 en casos límit).
-- =====================================================================

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
