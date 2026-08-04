import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.jsx'
import { AuthProvider } from './context/AuthContext.jsx'

// Necessari perquè hi hagi Web Push (veure CLAUDE.md "Notificacions push");
// sense service worker registrat, pushManager.subscribe() no existeix.
if ('serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').catch(() => {
      // Si falla el registre (navegador sense suport, mode privat...) l'app
      // segueix funcionant igual, només sense notificacions push.
    })
  })
}

createRoot(document.getElementById('root')).render(
  <StrictMode>
    <AuthProvider>
      <App />
    </AuthProvider>
  </StrictMode>,
)
