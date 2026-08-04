// Edge function enviar-push (fase 4, veure CLAUDE.md "Notificacions push").
//
// No la crida mai el client directament: només els triggers de la base de
// dades (via pg_net) i els jobs de pg_cron, sempre amb la capçalera
// x-webhook-secret. Per això es desplega amb "Verify JWT" desactivat des
// del tauler de Supabase — l'autenticació la fa aquesta capçalera, no un
// JWT d'usuari.
//
// Variables d'entorn necessàries (secrets de l'edge function, mai al
// client): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT,
// PUSH_WEBHOOK_SECRET. SUPABASE_URL i SUPABASE_SERVICE_ROLE_KEY ja les
// injecta Supabase automàticament a totes les edge functions.
import webpush from 'npm:web-push@3.6.7'
import { createClient } from 'npm:@supabase/supabase-js@2.111.0'

const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') ?? ''
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') ?? ''
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') ?? ''
const WEBHOOK_SECRET = Deno.env.get('PUSH_WEBHOOK_SECRET') ?? ''

const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY)

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Mètode no permès', { status: 405 })
  }

  if (!WEBHOOK_SECRET || req.headers.get('x-webhook-secret') !== WEBHOOK_SECRET) {
    return new Response('No autoritzat', { status: 401 })
  }

  let body
  try {
    body = await req.json()
  } catch {
    return new Response('JSON invàlid', { status: 400 })
  }

  const { usuari_id, titol, cos, url } = body
  if (!usuari_id || !titol || !cos) {
    return new Response('Falten camps obligatoris (usuari_id, titol, cos)', { status: 400 })
  }

  const { data: subscripcions, error } = await supabase
    .from('subscripcions_push')
    .select('id, endpoint, p256dh, auth')
    .eq('usuari_id', usuari_id)

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }

  const payload = JSON.stringify({ titol, cos, url: url ?? '/' })

  const resultats = await Promise.allSettled(
    (subscripcions ?? []).map(async (sub) => {
      const subscripcio = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth },
      }
      try {
        await webpush.sendNotification(subscripcio, payload)
      } catch (err) {
        // Subscripció caducada o revocada pel navegador (404/410): neteja-la
        // perquè no es torni a provar cada vegada.
        if (err?.statusCode === 404 || err?.statusCode === 410) {
          await supabase.from('subscripcions_push').delete().eq('id', sub.id)
        }
        throw err
      }
    }),
  )

  const enviats = resultats.filter((r) => r.status === 'fulfilled').length
  const fallits = resultats.length - enviats

  return new Response(JSON.stringify({ enviats, fallits, total: resultats.length }), {
    headers: { 'Content-Type': 'application/json' },
  })
})
