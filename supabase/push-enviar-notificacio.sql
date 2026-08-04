-- =====================================================================
-- Pandapp Family — funció enviar_notificacio_push (fase 4, notificacions)
-- =====================================================================
-- Punt d'entrada únic perquè triggers i jobs de pg_cron enviïn una
-- notificació push cridant l'edge function `enviar-push` via `pg_net`
-- (asíncron: no bloqueja la transacció esperant resposta HTTP).
--
-- Requereix, un cop executat aquest fitxer, UNA configuració manual que NO
-- es guarda a cap fitxer versionat perquè és un secret (mateix criteri que
-- la clau privada VAPID): guardar el mateix valor que `PUSH_WEBHOOK_SECRET`
-- de l'edge function dins de Supabase Vault, directament a l'SQL Editor:
--   select vault.create_secret(
--     '<el mateix valor que PUSH_WEBHOOK_SECRET>',
--     'push_webhook_secret'
--   );
-- (Vault, no un paràmetre de base de dades: el rol amb què s'executa l'SQL
-- Editor de Supabase no té prou privilegis per a `alter database ... set`
-- en un paràmetre personalitzat — Vault és la via pensada per a això.)
-- Sense el secret a Vault, aquesta funció no fa res (surt en silenci) —
-- perquè els entorns sense el secret configurat (per exemple, mentre es
-- desplega per primera vegada) no petin cap trigger.
--
-- L'URL de l'edge function NO és secreta (és el mateix domini públic que
-- `VITE_SUPABASE_URL`), així que és una constant amb valor per defecte.
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
  v_secret       text;
  v_function_url text := 'https://qndwjsowoucmncexmfih.supabase.co/functions/v1/enviar-push';
begin
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'push_webhook_secret'
  limit 1;

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
  'Envia una notificació push a un usuari via l''edge function enviar-push (pg_net, asíncron). Llegeix el secret compartit de Supabase Vault (nom "push_webhook_secret"); no fa res si encara no hi és. Ús intern, no exposada via RPC.';

revoke all on function public.enviar_notificacio_push(uuid, text, text, text) from public;
