import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY

if (!supabaseUrl || !supabaseKey) {
  throw new Error(
    "Falten les variables d'entorn de Supabase (VITE_SUPABASE_URL i " +
      'VITE_SUPABASE_PUBLISHABLE_KEY). Revisa el fitxer .env.local.',
  )
}

export const supabase = createClient(supabaseUrl, supabaseKey)
