import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { comprimirImatge } from '../lib/fotos'
import IndicadorsJugador from '../components/IndicadorsJugador'

const BUCKET_AVATARS = 'avatars'
// Prou perquè es vegi mentre es té la pantalla oberta; es torna a generar
// cada vegada que es carrega (veure CLAUDE.md "Fotos").
const CADUCITAT_URL_SIGNADA_S = 60 * 60

function inicials(nom) {
  if (!nom) return '?'
  return nom
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('')
}

export default function Perfil() {
  const { profile } = useAuth()
  const fitxerInputRef = useRef(null)

  const [ratxa, setRatxa] = useState(null)
  const [monedes, setMonedes] = useState(null)
  const [avatarUrl, setAvatarUrl] = useState(null)
  const [pujantAvatar, setPujantAvatar] = useState(false)
  const [errorAvatar, setErrorAvatar] = useState('')

  const carregaCapcalera = useCallback(async () => {
    if (!profile) return

    const [ratxaRes, monedesRes] = await Promise.all([
      supabase.from('ratxes').select('dies_seguits').eq('usuari_id', profile.id).maybeSingle(),
      supabase.from('monedes').select('saldo').eq('usuari_id', profile.id).maybeSingle(),
    ])

    setRatxa(ratxaRes.data ?? { dies_seguits: 0 })
    setMonedes(monedesRes.data ?? { saldo: 0 })

    if (profile.avatar_url) {
      const { data } = await supabase.storage
        .from(BUCKET_AVATARS)
        .createSignedUrl(profile.avatar_url, CADUCITAT_URL_SIGNADA_S)
      setAvatarUrl(data?.signedUrl ?? null)
    } else {
      setAvatarUrl(null)
    }
  }, [profile])

  useEffect(() => {
    carregaCapcalera()
  }, [carregaCapcalera])

  async function handleTriaFoto(event) {
    const fitxer = event.target.files?.[0]
    event.target.value = ''
    if (!fitxer || !profile) return

    setErrorAvatar('')
    setPujantAvatar(true)

    try {
      // Només cal el thumb (300px): un avatar no necessita l'original de
      // 1080px que sí té sentit per a les fotos de tasques.
      const { thumb, tipus } = await comprimirImatge(fitxer)
      const ruta = `${profile.familia_id}/${profile.id}.webp`

      const { error: pujaError } = await supabase.storage
        .from(BUCKET_AVATARS)
        .upload(ruta, thumb, { contentType: tipus, upsert: true })

      if (pujaError) {
        setErrorAvatar('Error de connexió. Torna-ho a provar.')
        return
      }

      const { error: perfilError } = await supabase
        .from('profiles')
        .update({ avatar_url: ruta })
        .eq('id', profile.id)

      if (perfilError) {
        setErrorAvatar('Error de connexió. Torna-ho a provar.')
        return
      }

      const { data } = await supabase.storage
        .from(BUCKET_AVATARS)
        .createSignedUrl(ruta, CADUCITAT_URL_SIGNADA_S)
      setAvatarUrl(data?.signedUrl ?? null)
    } catch {
      setErrorAvatar("No s'ha pogut preparar la foto. Torna-ho a provar.")
    } finally {
      setPujantAvatar(false)
    }
  }

  if (!profile) {
    return (
      <div className="flex flex-1 items-center justify-center py-16">
        <p className="text-tinta-sec">Carregant perfil…</p>
      </div>
    )
  }

  return (
    <div className="space-y-6 px-4 py-6 pb-8">
      <div className="flex flex-col items-center gap-3 text-center">
        <button
          type="button"
          onClick={() => fitxerInputRef.current?.click()}
          disabled={pujantAvatar}
          aria-label="Canviar foto de perfil"
          className="bisell relative h-24 w-24 overflow-hidden rounded-full border border-vora bg-targeta disabled:opacity-50"
        >
          {avatarUrl ? (
            <img src={avatarUrl} alt="" className="h-full w-full object-cover" />
          ) : (
            <span className="flex h-full w-full items-center justify-center font-display text-2xl font-bold text-tinta">
              {inicials(profile.nom)}
            </span>
          )}
          {pujantAvatar && (
            <span className="absolute inset-0 flex items-center justify-center bg-paper/70 font-body text-xs text-tinta">
              Pujant…
            </span>
          )}
        </button>
        <input
          ref={fitxerInputRef}
          type="file"
          accept="image/*"
          capture="user"
          onChange={handleTriaFoto}
          className="hidden"
        />

        <h1 className="font-display text-2xl font-bold text-tinta">{profile.nom}</h1>

        <IndicadorsJugador
          diesSeguits={ratxa?.dies_seguits ?? 0}
          saldoMonedes={monedes?.saldo ?? 0}
        />

        {errorAvatar && <p className="text-sm text-calent">{errorAvatar}</p>}
      </div>

      {/* TODO fase 4: resum personal generat amb Gemini, es llegirà de la taula
          `resums` un cop existeixi el cron nocturn. De moment, no mostris res
          aquí. */}
    </div>
  )
}
