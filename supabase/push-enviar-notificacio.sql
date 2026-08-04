-- =====================================================================
-- Pandapp Family — funció enviar_notificacio_push (fase 4, notificacions)
-- =====================================================================
-- Punt d'entrada únic perquè triggers i jobs de pg_cron enviïn una
-- notificació push cridant l'edge function `enviar-push` via `pg_net`
-- (asíncron: no bloqueja la transacció esperant resposta HTTP).
--
-- Requereix, un cop executat aquest fitxer, UNA configuració manual que
-- NO es guarda a cap fitxer versionat perquè és un secret (mateix criteri
-- que la clau privada VAPID): executar, directament a l'SQL Editor,
--   alter database postgres set app.settings.push_webhook_secret = '<secret>';
-- amb el mateix valor que el secret `PUSH_WEBHOOK_SECRET` de l'edge
-- function. Sense això, aquesta funció no fa res (surt en silenci) —
-- perquè els entorns sense el secret configurat (per exemple, mentre es
-- desplega per primera vegada) no petin cap trigger.
--
-- L'URL de l'edge function NO és secreta (és el mateix domini públic que
-- `VITE_SUPABASE_URL`), així que és una constant amb valor per defecte —
-- `app.settings.push_function_url` només cal si mai canvia de projecte.
-- =====================================================================

create extension if not exists pg_net;

create or replace function public.enviar_notificacio_push(
  p_usuari_id uuid,
  p_titol text,
  p_cos text,
  p_url text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_secret       text := current_setting('app.settings.push_webhook_secret', true);
  v_function_url text := coalesce(
    current_setting('app.settings.push_function_url', true),
    'https://qndwjsowoucmncexmfih.supabase.co/functions/v1/enviar-push'
  );
begin
  if v_secret is null or v_secret = '' then
    return;
  end if;

  perform net.http_post(
    url := v_function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_secret
    ),
    body := jsonb_build_object(
      'usuari_id', p_usuari_id,
      'titol', p_titol,
      'cos', p_cos,
      'url', p_url
    )
  );
end;
$$;

comment on function public.enviar_notificacio_push(uuid, text, text, text) is
  'Envia una notificació push a un usuari via l''edge function enviar-push (pg_net, asíncron). No fa res si app.settings.push_webhook_secret no està configurat. Ús intern, no exposada via RPC.';

revoke all on function public.enviar_notificacio_push(uuid, text, text, text) from public;
