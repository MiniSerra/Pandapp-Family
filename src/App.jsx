import { useAuth } from './context/useAuth'
import Login from './pages/Login'
import Activitats from './pages/Activitats'

function App() {
  const { session, profile, loading, signOut } = useAuth()

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-paper">
        <p className="text-tinta/60">Carregant…</p>
      </div>
    )
  }

  if (!session) {
    return <Login />
  }

  return (
    <div className="flex min-h-screen flex-col bg-paper">
      <header className="flex items-center justify-between border-b border-vora bg-targeta px-4 py-3">
        <p className="font-display font-semibold text-tinta">
          {profile ? profile.nom : 'Pandapp'}
        </p>
        <button
          type="button"
          onClick={signOut}
          className="rounded-md px-2 py-1 text-sm text-tinta/60 hover:bg-vora"
        >
          Surt
        </button>
      </header>

      {profile ? (
        <Activitats />
      ) : (
        <p className="p-4 text-sm text-calent">No s'ha pogut carregar el teu perfil.</p>
      )}
    </div>
  )
}

export default App
