import { supabase } from './supabase'

const VAPID_PUBLIC_KEY = import.meta.env.VITE_VAPID_PUBLIC_KEY

// El navegador exigeix la clau del servidor com a Uint8Array, però VAPID la
// dona en base64url (com totes les claus públiques d'aquest projecte).
function base64UrlAUint8Array(base64Url) {
  const padding = '='.repeat((4 - (base64Url.length % 4)) % 4)
  const base64 = (base64Url + padding).replace(/-/g, '+').replace(/_/g, '/')
  const cru = atob(base64)
  return Uint8Array.from([...cru].map((caracter) => caracter.charCodeAt(0)))
}

export function suportaNotificacionsPush() {
  return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window
}

// Demana permís, subscriu aquest dispositiu a Web Push i guarda la
// subscripció a `subscripcions_push`. Retorna { error } (null si tot ha
// anat bé); `error` és sempre un missatge en català ja llest per mostrar.
export async function activarNotificacions(usuariId) {
  if (!suportaNotificacionsPush()) {
    return { error: 'Aquest navegador no admet notificacions push.' }
  }

  if (!VAPID_PUBLIC_KEY) {
    return { error: "Falta la configuració de notificacions push de l'aplicació." }
  }

  const permis = await Notification.requestPermission()
  if (permis !== 'granted') {
    return { error: 'Cal donar permís de notificacions per activar-les.' }
  }

  try {
    const registration = await navigator.serviceWorker.ready
    const subscripcioExistent = await registration.pushManager.getSubscription()
    const subscripcio =
      subscripcioExistent ??
      (await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: base64UrlAUint8Array(VAPID_PUBLIC_KEY),
      }))

    const { endpoint, keys } = subscripcio.toJSON()

    const { error } = await supabase.from('subscripcions_push').upsert(
      {
        usuari_id: usuariId,
        endpoint,
        p256dh: keys.p256dh,
        auth: keys.auth,
      },
      { onConflict: 'usuari_id,endpoint' },
    )

    if (error) return { error: 'Error de connexió. Torna-ho a provar.' }

    return { error: null }
  } catch {
    return { error: "No s'ha pogut activar la subscripció. Torna-ho a provar." }
  }
}
