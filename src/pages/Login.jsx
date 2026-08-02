import { useState } from 'react'
import { useAuth } from '../context/useAuth'

const EMPTY_FIELDS_ERROR = "Introdueix l'email i la contrasenya."
const WRONG_CREDENTIALS_ERROR = 'Email o contrasenya incorrectes.'
const CONNECTION_ERROR = 'Error de connexió. Torna-ho a provar.'

export default function Login() {
  const { signIn } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function handleSubmit(event) {
    event.preventDefault()

    if (!email.trim() || !password) {
      setError(EMPTY_FIELDS_ERROR)
      return
    }

    setError('')
    setSubmitting(true)
    const { error: signInError } = await signIn(email.trim(), password)
    setSubmitting(false)

    if (signInError) {
      if (
        signInError.code === 'invalid_credentials' ||
        signInError.message === 'Invalid login credentials'
      ) {
        setError(WRONG_CREDENTIALS_ERROR)
      } else {
        setError(CONNECTION_ERROR)
      }
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-paper px-4">
      <div className="w-full max-w-sm">
        <h1 className="mb-8 text-center font-display text-3xl font-medium text-tinta">
          Pandapp
        </h1>
        <form
          onSubmit={handleSubmit}
          className="space-y-4 rounded-2xl border border-vora bg-targeta p-6 bisell"
          noValidate
        >
          <div>
            <label
              htmlFor="email"
              className="mb-1 block text-sm font-medium text-tinta-sec"
            >
              Email
            </label>
            <input
              id="email"
              type="email"
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-md border border-vora bg-paper px-3 py-2 text-base text-tinta focus:border-tinta-sec focus:outline-none"
            />
          </div>
          <div>
            <label
              htmlFor="password"
              className="mb-1 block text-sm font-medium text-tinta-sec"
            >
              Contrasenya
            </label>
            <input
              id="password"
              type="password"
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="w-full rounded-md border border-vora bg-paper px-3 py-2 text-base text-tinta focus:border-tinta-sec focus:outline-none"
            />
          </div>
          {error && <p className="text-sm text-calent">{error}</p>}
          <button
            type="submit"
            disabled={submitting}
            className="w-full rounded-md bg-panda px-4 py-2 text-sm font-medium text-paper disabled:opacity-50"
          >
            {submitting ? 'Entrant…' : 'Entra'}
          </button>
        </form>
      </div>
    </div>
  )
}
