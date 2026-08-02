import { useContext } from 'react'
import { AuthContext } from './auth-context.js'

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error("useAuth s'ha d'utilitzar dins d'un <AuthProvider>.")
  }
  return context
}
