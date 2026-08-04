import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { extreuRutaDesDeUrlSignada } from '../lib/fotos'
import { anullarCompletion } from '../lib/completions'
import TargetaFeed from '../components/TargetaFeed'
import TargetaEsdeveniment from '../components/TargetaEsdeveniment'
import PullToRefresh from '../components/PullToRefresh'

const BUCKET = 'fotos-tasques'
const BUCKET_AVATARS = 'avatars'
// Prou perquè es vegi mentre es té el feed obert; es torna a generar cada
// vegada que es carrega la pantalla (veure CLAUDE.md "Fotos").
const CADUCITAT_URL_SIGNADA_S = 60 * 60
const LIMIT_FEED = 50

export default function Feed() {
  const { profile } = useAuth()
  const [completions, setCompletions] = useState([])
  const [esdeveniments, setEsdeveniments] = useState([])
  const [perfils, setPerfils] = useState({})
  const [avatarUrls, setAvatarUrls] = useState({})
  const [fotosUrl, setFotosUrl] = useState({})
  const [carregant, setCarregant] = useState(true)
  const [error, setError] = useState('')

  const carregar = useCallback(async () => {
    if (!profile) return

    setCarregant(true)
    setError('')

    const [completionsRes, perfilsRes, esdevenimentsRes] = await Promise.all([
      supabase
        .from('completions')
        .select(
          'id, activitat_id, creada_per, punts_base_snapshot, pot_total, estat, foto_url, created_at, ' +
            'activitats(nom, emoji), participacions(usuari_id, punts_assignats, confirmat), likes(usuari_id), ' +
            'comentaris(id, usuari_id, resposta_a, text, created_at, comentari_likes(usuari_id))',
        )
        .eq('familia_id', profile.familia_id)
        .order('created_at', { ascending: false })
        .limit(LIMIT_FEED),
      supabase.from('profiles').select('id, nom, avatar_url'),
      supabase
        .from('esdeveniments')
        .select('id, tipus, usuari_id, dades, created_at')
        .eq('familia_id', profile.familia_id)
        .order('created_at', { ascending: false }),
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
    setEsdeveniments(esdevenimentsRes.data ?? [])
    setCarregant(false)

    const ambAvatar = perfilsRes.data.filter((p) => p.avatar_url)
    const entradesAvatars = await Promise.all(
      ambAvatar.map(async (p) => {
        const { data } = await supabase.storage
          .from(BUCKET_AVATARS)
          .createSignedUrl(p.avatar_url, CADUCITAT_URL_SIGNADA_S)
        return [p.id, data?.signedUrl ?? null]
      }),
    )
    setAvatarUrls(Object.fromEntries(entradesAvatars))

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

  // Confirmar la pròpia participació pot desencadenar la validació
  // automàtica de la completion (si cobreix tota la família) i canviar
  // punts/ratxa/monedes de tothom: es recarrega tot el feed en lloc de
  // provar d'endevinar l'estat resultant en local.
  async function handleConfirmarParticipacio(completionId) {
    const { error: rpcError } = await supabase.rpc('confirmar_participacio', {
      p_completion_id: completionId,
    })

    if (!rpcError) await carregar()

    return rpcError
  }

  // Retorna l'error (o null) perquè la targeta el mostri; si va bé, treu la
  // targeta del feed sense recarregar-lo tot.
  async function handleEliminar(completionId) {
    const { error: rpcError } = await anullarCompletion(completionId)

    if (!rpcError) {
      setCompletions((actual) => actual.filter((c) => c.id !== completionId))
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

  // Afegeix un comentari (o una resposta, si respostaA no és null) i
  // l'insereix en local sense recarregar tot el feed.
  async function handleAfegeixComentari(completionId, text, respostaA) {
    if (!profile) return 'sense-perfil'

    const { data, error: comentariError } = await supabase
      .from('comentaris')
      .insert({
        completion_id: completionId,
        usuari_id: profile.id,
        text,
        resposta_a: respostaA,
      })
      .select('id, usuari_id, resposta_a, text, created_at')
      .single()

    if (comentariError) return comentariError

    actualitzaCompletion(completionId, (c) => ({
      ...c,
      comentaris: [...(c.comentaris ?? []), { ...data, comentari_likes: [] }],
    }))

    return null
  }

  // Mateix patró d'actualització optimista que els likes d'una completion.
  async function handleAlternarLikeComentari(completionId, comentariId) {
    if (!profile) return

    const completion = completions.find((c) => c.id === completionId)
    const comentari = completion?.comentaris?.find((co) => co.id === comentariId)
    const jaLiked = (comentari?.comentari_likes ?? []).some(
      (like) => like.usuari_id === profile.id,
    )

    function aplica(afegeix) {
      actualitzaCompletion(completionId, (c) => ({
        ...c,
        comentaris: c.comentaris.map((co) =>
          co.id !== comentariId
            ? co
            : {
                ...co,
                comentari_likes: afegeix
                  ? [...co.comentari_likes, { usuari_id: profile.id }]
                  : co.comentari_likes.filter((like) => like.usuari_id !== profile.id),
              },
        ),
      }))
    }

    aplica(!jaLiked)

    const { error: likeError } = jaLiked
      ? await supabase
          .from('comentari_likes')
          .delete()
          .eq('comentari_id', comentariId)
          .eq('usuari_id', profile.id)
      : await supabase.from('comentari_likes').insert({
          comentari_id: comentariId,
          usuari_id: profile.id,
        })

    if (likeError) aplica(jaLiked)
  }

  // Barreja completions i esdeveniments de sistema en una sola línia de
  // temps, ordenats per created_at (veure CLAUDE.md "Objectiu col·lectiu").
  const elements = useMemo(() => {
    const marcades = [
      ...completions.map((c) => ({ tipus: 'completion', dataOrdre: c.created_at, item: c })),
      ...esdeveniments.map((e) => ({ tipus: 'esdeveniment', dataOrdre: e.created_at, item: e })),
    ]
    return marcades.sort((a, b) => new Date(b.dataOrdre) - new Date(a.dataOrdre))
  }, [completions, esdeveniments])

  if (carregant) {
    return (
      <PullToRefresh onRefrescar={carregar}>
        <div className="flex flex-1 items-center justify-center py-16">
          <p className="text-tinta-sec">Carregant el feed…</p>
        </div>
      </PullToRefresh>
    )
  }

  if (error) {
    return (
      <PullToRefresh onRefrescar={carregar}>
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
      </PullToRefresh>
    )
  }

  if (elements.length === 0) {
    return (
      <PullToRefresh onRefrescar={carregar}>
        <div className="flex flex-1 flex-col items-center gap-2 px-4 py-16 text-center">
          <p className="text-tinta">Encara no hi ha res al feed.</p>
          <p className="text-sm text-tinta-sec">
            Fes la teva primera tasca des de la pestanya Activitats!
          </p>
        </div>
      </PullToRefresh>
    )
  }

  return (
    <PullToRefresh onRefrescar={carregar}>
    <div className="space-y-3 px-4 py-3 pb-8">
      {elements.map(({ tipus, item }) =>
        tipus === 'esdeveniment' ? (
          <TargetaEsdeveniment
            key={`esdeveniment-${item.id}`}
            esdeveniment={item}
            perfils={perfils}
          />
        ) : (
          <TargetaFeed
            key={item.id}
            completion={item}
            nomAutor={perfils[item.creada_per] ?? 'algú'}
            fotoUrl={fotosUrl[item.id]}
            jo={profile?.id}
            perfils={perfils}
            avatarUrls={avatarUrls}
            onValidar={handleValidar}
            onAlternarLike={handleAlternarLike}
            onAfegeixComentari={handleAfegeixComentari}
            onAlternarLikeComentari={handleAlternarLikeComentari}
            onEliminar={handleEliminar}
            onConfirmarParticipacio={handleConfirmarParticipacio}
          />
        ),
      )}
    </div>
    </PullToRefresh>
  )
}
