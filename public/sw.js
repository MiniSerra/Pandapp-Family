// Service worker mínim de Pandapp Family: només existeix per rebre Web Push
// (veure CLAUDE.md "Notificacions push"). No fa cap caching ni treballa
// offline — no és l'abast d'aquesta peça.

self.addEventListener('install', () => {
  self.skipWaiting()
})

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim())
})

self.addEventListener('push', (event) => {
  let dades = {}
  try {
    dades = event.data ? event.data.json() : {}
  } catch {
    dades = { titol: 'Pandapp', cos: event.data ? event.data.text() : '' }
  }

  const titol = dades.titol || 'Pandapp'
  const opcions = {
    body: dades.cos || '',
    icon: dades.icona || '/favicon.svg',
    badge: dades.icona || '/favicon.svg',
    data: { url: dades.url || '/' },
  }

  event.waitUntil(self.registration.showNotification(titol, opcions))
})

self.addEventListener('notificationclick', (event) => {
  event.notification.close()
  const url = event.notification.data?.url || '/'

  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((finestres) => {
      for (const finestra of finestres) {
        if (finestra.url.includes(self.location.origin) && 'focus' in finestra) {
          finestra.navigate(url)
          return finestra.focus()
        }
      }
      if (self.clients.openWindow) return self.clients.openWindow(url)
    }),
  )
})
