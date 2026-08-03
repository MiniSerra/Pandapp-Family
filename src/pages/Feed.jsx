import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import TargetaFeed from '../components/TargetaFeed'

const BUCKET = 'fotos-tasques'
// Prou perquè es vegi mentre es té el feed obert; es torna a generar cada
// vegada que es carrega la pantalla (veure CLAUDE.md "Fotos").
const CADUCITAT_URL_SIGNADA_S = 60 * 60
const LIMIT_FEED = 50

// `foto_url` guarda la URL signada que hi havia en el moment de reclamar
// (caduca als 60 min), no la ruta al bucket. Per poder-la tornar a signar
// cal recuperar la ruta original, que la URL ja conté abans del "?token=".
function extreuRutaDesDeUrlSignada(urlSignada, bucket) {
  try {
    const url = new URL(urlSignada)
    const prefix = `/storage/v1/object/sign/${bucket}/`
    const index = url.pathname.indexOf(prefix)
    if (index === -1) return null
    return decodeURIComponent(url.pathname.slice(index + prefix.length))
  } catch {
    return null
  }
}

export default function Feed() {
  const { profile } = useAuth()
  const [completions, setCompletions] = useState([])
  const [perfils, setPerfils] = useState({})
  const [fotosUrl, setFotosUrl] = useState({})
  const [carregant, setCarregant] = useState(true)
  const [error, setError] = useState('')

  const carregar = useCallback(async () => {
    if (!profile) return

    setCarregant(true)
    setError('')

    const [completionsRes, perfilsRes] = await Promise.all([
      supabase
        .from('completions')
        .select(
          'id, activitat_id, creada_per, punts_base_snapshot, estat, foto_url, created_at, ' +
            'activitats(nom, emoji), participacions(usuari_id, punts_assignats), likes(usuari_id)',
        )
        .eq('familia_id', profile.familia_id)
        .order('created_at', { ascending: false })
        .limit(LIMIT_FEED),
      supabase.from('profiles').select('id, nom'),
    ])

    if (completionsRes.error || perfilsRes.error) {
      setError("No s'ha pogut carregar el feed. Comprova la connexió.")
      setCarregant(false)
      return
    }

    const mapaPerfils = {}
    for (const p of perfilsRes.data) mapaPerfils[p.id] = p.nom

    setPerfils(mapaPerfils)
    setCompletions(completionsRes.data)
    setCarregant(false)

    const ambFoto = completionsRes.data.filter((c) => c.foto_url)
    const entrades = await Promise.all(
      ambFoto.map(async (c) => {
        const ruta = extreuRutaDesDeUrlSignada(c.foto_url, BUCKET)
        if (!ruta) return [c.id, null]
        const { data } = await supabase.storage
          .from(BUCKET)
          .createSignedUrl(ruta, CADUCITAT_URL_SIGNADA_S)
        return [c.id, data?.signedUrl ?? null]
      }),
    )
    setFotosUrl(Object.fromEntries(entrades))
  }, [profile])

  useEffect(() => {
    carregar()
  }, [carregar])

  function actualitzaCompletion(id, actualitza) {
    setCompletions((actual) => actual.map((c) => (c.id === id ? actualitza(c) : c)))
  }

  // Retorna l'error de Postgres (o null si tot ha anat bé) perquè la
  // targeta el mostri; actualitza l'estat en local sense recarregar tota
  // la llista.
  async function handleValidar(completionId) {
    const { data, error: rpcError } = await supabase.rpc('validar_completion', {
      p_completion_id: completionId,
    })

    if (!rpcError) {
      actualitzaCompletion(completionId, (c) => ({
        ...c,
        estat: data.estat,
        validada_per: data.validada_per,
      }))
    }

    return rpcError
  }

  // Actualització optimista: canvia la UI a l'instant i desfà-la si la
  // petició falla. Els likes no donen punts, no cal cap funció intermèdia.
  async function handleAlternarLike(completionId) {
    if (!profile) return

    const completion = completions.find((c) => c.id === completionId)
    const jaLiked = (completion?.likes ?? []).some((like) => like.usuari_id === profile.id)

    if (jaLiked) {
      actualitzaCompletion(completionId, (c) => ({
        ...c,
        likes: c.likes.filter((like) => like.usuari_id !== profile.id),
      }))

      const { error: likeError } = await supabase
        .from('likes')
        .delete()
        .eq('completion_id', completionId)
        .eq('usuari_id', profile.id)

      if (likeError) {
        actualitzaCompletion(completionId, (c) => ({
          ...c,
          likes: [...c.likes, { usuari_id: profile.id }],
        }))
      }
    } else {
      actualitzaCompletion(completionId, (c) => ({
        ...c,
        likes: [...c.likes, { usuari_id: profile.id }],
      }))

      const { error: likeError } = await supabase
        .from('likes')
        .insert({ completion_id: completionId, usuari_id: profile.id })

      if (likeError) {
        actualitzaCompletion(completionId, (c) => ({
          ...c,
          likes: c.likes.filter((like) => like.usuari_id !== profile.id),
        }))
      }
    }
  }

  if (carregant) {
    return (
      <div className="flex flex-1 items-center justify-center py-16">
        <p className="text-tinta-sec">Carregant el feed…</p>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex flex-1 flex-col items-center gap-3 py-16">
        <p className="text-sm text-calent">{error}</p>
        <button
          type="button"
          onClick={carregar}
          className="rounded-md bg-panda px-4 py-2 text-sm font-medium text-paper"
        >
          Torna-ho a provar
        </button>
      </div>
    )
  }

  if (completions.length === 0) {
    return (
      <div className="flex flex-1 flex-col items-center gap-2 px-4 py-16 text-center">
        <p className="text-tinta">Encara no hi ha res al feed.</p>
        <p className="text-sm text-tinta-sec">
          Fes la teva primera tasca des de la pestanya Activitats!
        </p>
      </div>
    )
  }

  return (
    <div className="space-y-3 px-4 py-3 pb-8">
      {completions.map((completion) => (
        <TargetaFeed
          key={completion.id}
          completion={completion}
          nomAutor={perfils[completion.creada_per] ?? 'algú'}
          fotoUrl={fotosUrl[completion.id]}
          jo={profile?.id}
          onValidar={handleValidar}
          onAlternarLike={handleAlternarLike}
        />
      ))}
    </div>
  )
}
