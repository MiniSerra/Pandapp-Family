import { supabase } from './supabase'
import { extreuRutaDesDeUrlSignada } from './fotos'

const BUCKET = 'fotos-tasques'

// Desfà una reclamació pròpia (anullar_completion al servidor, dins la
// finestra de 15 minuts) i esborra del bucket les fotos que hagués pujat.
// Compartit entre Feed.jsx i Perfil.jsx. Retorna { error } (null si tot ha
// anat bé).
export async function anullarCompletion(completionId) {
  const { data, error } = await supabase.rpc('anullar_completion', {
    p_completion_id: completionId,
  })

  if (error) return { error }

  const fila = Array.isArray(data) ? data[0] : data
  const rutes = [fila?.foto_url, fila?.thumb_url]
    .map((url) => (url ? extreuRutaDesDeUrlSignada(url, BUCKET) : null))
    .filter(Boolean)

  if (rutes.length > 0) {
    await supabase.storage.from(BUCKET).remove(rutes)
  }

  return { error: null }
}
