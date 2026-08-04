-- =====================================================================
-- Pandapp Family — notificació push: algú fa una activitat (fase 4)
-- =====================================================================
-- Requereix haver executat abans push-subscripcions.sql i
-- push-enviar-notificacio.sql. Trigger AFTER INSERT a `completions`
-- (no AFTER UPDATE: `validar_completion` no l'ha de tornar a disparar,
-- la notificació és pel moment de FER la tasca, no de validar-la).
-- Notifica tots els membres de la família excepte qui l'ha feta.
-- =====================================================================

create or replace function public.notificar_activitat_feta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activitat public.activitats%rowtype;
  v_autor_nom text;
  v_cos       text;
  v_membre    record;
begin
  select * into v_activitat from public.activitats where id = new.activitat_id;
  select nom into v_autor_nom from public.profiles where id = new.creada_per;

  v_cos := format(
    '%s %s ha fet %s (+%s)',
    v_activitat.emoji, v_autor_nom, v_activitat.nom, new.punts_base_snapshot
  );

  for v_membre in
    select id
    from public.profiles
    where familia_id = new.familia_id and id <> new.creada_per
  loop
    perform public.enviar_notificacio_push(v_membre.id, 'Nova activitat', v_cos);
  end loop;

  return new;
end;
$$;

comment on function public.notificar_activitat_feta() is
  'Trigger AFTER INSERT a completions: notifica tota la família (excepte qui l''ha feta) que s''ha completat una activitat.';

drop trigger if exists completions_notificar_activitat_feta on public.completions;

create trigger completions_notificar_activitat_feta
  after insert on public.completions
  for each row
  execute function public.notificar_activitat_feta();
