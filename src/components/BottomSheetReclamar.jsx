import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { comprimirImatge } from '../lib/fotos'
import { useAuth } from '../context/useAuth'
import AvatarUsuari from './AvatarUsuari'

const BUCKET = 'fotos-tasques'
// Prou perquè el frontend passi la URL a reclamar_activitat just després de
// pujar la foto; el feed/perfil ja en generarà una de nova en cada
// visualització futura (veure CLAUDE.md "Fotos").
const CADUCITAT_URL_SIGNADA_S = 60 * 60
const ERROR_CONNEXIO = 'Error de connexió. Torna-ho a provar.'

export default function BottomSheetReclamar({
  activitat,
  membresFamilia,
  avatarUrls,
  onTancar,
  onExit,
}) {
  const { profile } = useAuth()
  // 'idle' | 'comprimint' | 'pujant'
  const [fase, setFase] = useState('idle')
  const [error, setError] = useState('')
  const [imatge, setImatge] = useState(null)
  const [previsualitzacio, setPrevisualitzacio] = useState(null)
  const [compartida, setCompartida] = useState(false)
  const [participantsSeleccionats, setParticipantsSeleccionats] = useState([])

  useEffect(() => {
    return () => {
      if (previsualitzacio) URL.revokeObjectURL(previsualitzacio)
    }
  }, [previsualitzacio])

  const enviant = fase !== 'idle'

  function handleAlternarParticipant(id) {
    setParticipantsSeleccionats((actual) =>
      actual.includes(id) ? actual.filter((p) => p !== id) : [...actual, id],
    )
  }

  async function handleFitxer(event) {
    const fitxer = event.target.files?.[0]
    if (!fitxer) return

    setError('')
    setImatge(null)
    setPrevisualitzacio((actual) => {
      if (actual) URL.revokeObjectURL(actual)
      return URL.createObjectURL(fitxer)
    })

    setFase('comprimint')
    try {
      const resultat = await comprimirImatge(fitxer)
      setImatge(resultat)
    } catch {
      setError("No s'ha pogut preparar la foto. Torna-ho a provar.")
    } finally {
      setFase('idle')
    }
  }

  async function handleReclamar() {
    setError('')

    let fotoUrl = null
    let thumbUrl = null
    let rutaOriginal = null
    let rutaThumb = null

    if (imatge) {
      setFase('pujant')

      const carpeta = `${profile.familia_id}/pendent-${crypto.randomUUID()}`
      rutaOriginal = `${carpeta}/original.${imatge.extensio}`
      rutaThumb = `${carpeta}/thumb.${imatge.extensio}`

      const pujaOriginal = await supabase.storage
        .from(BUCKET)
        .upload(rutaOriginal, imatge.original, { contentType: imatge.tipus })
      if (pujaOriginal.error) {
        setError(ERROR_CONNEXIO)
        setFase('idle')
        return
      }

      const pujaThumb = await supabase.storage
        .from(BUCKET)
        .upload(rutaThumb, imatge.thumb, { contentType: imatge.tipus })
      if (pujaThumb.error) {
        await supabase.storage.from(BUCKET).remove([rutaOriginal])
        setError(ERROR_CONNEXIO)
        setFase('idle')
        return
      }

      const [signadaOriginal, signadaThumb] = await Promise.all([
        supabase.storage.from(BUCKET).createSignedUrl(rutaOriginal, CADUCITAT_URL_SIGNADA_S),
        supabase.storage.from(BUCKET).createSignedUrl(rutaThumb, CADUCITAT_URL_SIGNADA_S),
      ])

      if (signadaOriginal.error || signadaThumb.error) {
        await supabase.storage.from(BUCKET).remove([rutaOriginal, rutaThumb])
        setError(ERROR_CONNEXIO)
        setFase('idle')
        return
      }

      fotoUrl = signadaOriginal.data.signedUrl
      thumbUrl = signadaThumb.data.signedUrl
    } else {
      setFase('pujant')
    }

    const { error: rpcError } = await supabase.rpc('reclamar_activitat', {
      p_activitat_id: activitat.id,
      p_foto_url: fotoUrl,
      p_thumb_url: thumbUrl,
      p_participants_ids: compartida && participantsSeleccionats.length > 0
        ? participantsSeleccionats
        : null,
    })

    if (rpcError) {
      if (rutaOriginal) {
        await supabase.storage.from(BUCKET).remove([rutaOriginal, rutaThumb])
      }
      setError(rpcError.message)
      setFase('idle')
      return
    }

    onExit(activitat.id)
  }

  const textBoto =
    fase === 'comprimint' ? 'Comprimint…' : fase === 'pujant' ? 'Pujant…' : 'Ho he fet'

  return (
    <div
      className="fixed inset-0 z-50 flex items-end bg-paper/70"
      onClick={onTancar}
    >
      <div
        className="bisell w-full rounded-t-2xl border border-vora bg-targeta p-6 pb-8"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-4 flex items-center gap-3">
          <span className="text-4xl">{activitat.emoji}</span>
          <div className="min-w-0">
            <h2 className="font-display text-xl font-medium text-tinta">
              {activitat.nom}
            </h2>
            {activitat.descripcio && (
              <p className="mt-0.5 font-body text-sm text-tinta-sec">
                {activitat.descripcio}
              </p>
            )}
          </div>
        </div>

        <div className="mb-4">
          <label
            htmlFor="foto"
            className="mb-1 block text-sm font-medium text-tinta-sec"
          >
            Afegir foto (opcional)
          </label>
          <input
            id="foto"
            type="file"
            accept="image/*"
            onChange={handleFitxer}
            className="block w-full text-sm text-tinta"
          />
          {previsualitzacio && (
            <div className="mt-3 flex items-center gap-3">
              <img
                src={previsualitzacio}
                alt=""
                className="bisell h-16 w-16 rounded-lg border border-vora object-cover"
              />
              {fase === 'comprimint' && (
                <span className="text-sm text-tinta-sec">Comprimint…</span>
              )}
            </div>
          )}
        </div>

        {!activitat.es_personal && membresFamilia?.length > 0 && (
          <div className="bisell mb-4 rounded-xl border border-vora bg-targeta p-3">
            <button
              type="button"
              onClick={() => {
                setCompartida((actual) => !actual)
                setParticipantsSeleccionats([])
              }}
              className="flex w-full items-center justify-between"
            >
              <span className="flex items-center gap-2 text-sm font-medium text-tinta">
                <span className="text-lg">👥</span>
                Activitat compartida
              </span>
              <span
                role="switch"
                aria-checked={compartida}
                className={`relative h-6 w-11 shrink-0 rounded-full transition-colors ${
                  compartida ? 'bg-panda' : 'bg-vora'
                }`}
              >
                <span
                  className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full bg-tinta shadow transition-transform ${
                    compartida ? 'translate-x-5' : 'translate-x-0'
                  }`}
                />
              </span>
            </button>

            {compartida && (
              <div className="mt-3 border-t border-vora pt-3">
                <p className="mb-2 font-body text-xs text-tinta-sec">
                  Qui més hi era? ({participantsSeleccionats.length} seleccionat
                  {participantsSeleccionats.length === 1 ? '' : 's'})
                </p>
                <div className="grid grid-cols-3 gap-2">
                  {membresFamilia.map((membre) => {
                    const seleccionat = participantsSeleccionats.includes(membre.id)
                    return (
                      <button
                        key={membre.id}
                        type="button"
                        onClick={() => handleAlternarParticipant(membre.id)}
                        className={`bisell flex flex-col items-center gap-1.5 rounded-xl border px-2 py-3 transition-colors ${
                          seleccionat ? 'border-panda bg-panda/10' : 'border-vora bg-paper'
                        }`}
                      >
                        <div className="relative">
                          <AvatarUsuari url={avatarUrls?.[membre.id]} nom={membre.nom} mida="sm" />
                          {seleccionat && (
                            <span className="absolute -right-1 -bottom-1 flex h-4 w-4 items-center justify-center rounded-full bg-panda text-[10px] text-paper">
                              ✓
                            </span>
                          )}
                        </div>
                        <span
                          className={`truncate font-body text-xs ${
                            seleccionat ? 'text-tinta' : 'text-tinta-sec'
                          }`}
                        >
                          {membre.nom}
                        </span>
                      </button>
                    )
                  })}
                </div>
              </div>
            )}
          </div>
        )}

        {error && <p className="mb-3 text-sm text-calent">{error}</p>}

        <button
          type="button"
          onClick={handleReclamar}
          disabled={enviant}
          className="w-full rounded-md bg-panda px-4 py-3 text-base font-medium text-paper disabled:opacity-50"
        >
          {textBoto}
        </button>
      </div>
    </div>
  )
}
