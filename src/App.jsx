import { useState } from 'react'
import { useAuth } from './context/useAuth'
import Login from './pages/Login'
import Activitats from './pages/Activitats'
import Feed from './pages/Feed'
import Rancing from './pages/Rancing'
import Perfil from './pages/Perfil'

function IconaActivitats() {
  return (
    <svg
      viewBox="0 0 20 20"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <path d="M4 5.5l1.5 1.5L8 4" />
      <line x1="10" y1="5.5" x2="16" y2="5.5" />
      <path d="M4 10.5l1.5 1.5L8 9" />
      <line x1="10" y1="10.5" x2="16" y2="10.5" />
      <path d="M4 15.5l1.5 1.5L8 14" />
      <line x1="10" y1="15.5" x2="16" y2="15.5" />
    </svg>
  )
}

function IconaRanquing() {
  return (
    <svg
      viewBox="0 0 20 20"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
    >
      <line x1="4" y1="16" x2="4" y2="11" />
      <line x1="10" y1="16" x2="10" y2="4" />
      <line x1="16" y1="16" x2="16" y2="8" />
    </svg>
  )
}

function IconaFeed() {
  return (
    <svg
      viewBox="0 0 20 20"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <rect x="3" y="4" width="14" height="12" rx="2" />
      <circle cx="7.5" cy="8.5" r="1.5" />
      <path d="M3 14l4-4 3 3 3-3 4 4" />
    </svg>
  )
}

function IconaPerfil() {
  return (
    <svg
      viewBox="0 0 20 20"
      width="20"
      height="20"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <circle cx="10" cy="7" r="3" />
      <path d="M4 16.5c0-2.8 2.7-4.5 6-4.5s6 1.7 6 4.5" />
    </svg>
  )
}

const PESTANYES = [
  { id: 'activitats', nom: 'Activitats', Icona: IconaActivitats },
  { id: 'feed', nom: 'Feed', Icona: IconaFeed },
  { id: 'ranquing', nom: 'Rànquing', Icona: IconaRanquing },
  { id: 'perfil', nom: 'Perfil', Icona: IconaPerfil },
]

function BarraNavegacio({ pestanya, onCanvia }) {
  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 flex gap-2 border-t border-vora bg-targeta px-4 py-2">
      {PESTANYES.map(({ id, nom, Icona }) => {
        const activa = pestanya === id
        return (
          <button
            key={id}
            type="button"
            onClick={() => onCanvia(id)}
            className={`flex flex-1 flex-col items-center gap-0.5 rounded-xl px-3 py-2 transition-colors ${
              activa ? 'bisell border border-vora bg-vora text-panda' : 'text-tinta-sec'
            }`}
          >
            <Icona />
            <span className="font-body text-xs">{nom}</span>
          </button>
        )
      })}
    </nav>
  )
}

function App() {
  const { session, profile, loading, signOut } = useAuth()
  const [pestanya, setPestanya] = useState('activitats')

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-paper">
        <p className="text-tinta-sec">Carregant…</p>
      </div>
    )
  }

  if (!session) {
    return <Login />
  }

  return (
    <div className="flex min-h-screen flex-col bg-paper">
      <header className="flex items-center justify-between border-b border-vora bg-targeta px-4 py-3">
        <p className="font-display font-medium text-tinta">
          {profile ? profile.nom : 'Pandapp'}
        </p>
        <button
          type="button"
          onClick={signOut}
          className="rounded-md px-2 py-1 text-sm text-tinta-sec hover:bg-vora"
        >
          Surt
        </button>
      </header>

      <main className="flex-1 pb-16">
        {profile ? (
          <>
            {pestanya === 'activitats' && <Activitats />}
            {pestanya === 'feed' && <Feed />}
            {pestanya === 'ranquing' && <Rancing />}
            {pestanya === 'perfil' && <Perfil />}
          </>
        ) : (
          <p className="p-4 text-sm text-calent">No s'ha pogut carregar el teu perfil.</p>
        )}
      </main>

      {profile && <BarraNavegacio pestanya={pestanya} onCanvia={setPestanya} />}
    </div>
  )
}

export default App
