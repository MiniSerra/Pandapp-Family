import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { inicials } from '../lib/text'
import IndicadorsJugador from './IndicadorsJugador'
import TargetaHistorial from './TargetaHistorial'

const BUCKET_AVATARS = 'avatars'
const CADUCITAT_URL_SIGNADA_S = 60 * 60
const MIDA_PAGINA_HISTORIAL = 20

// Full inferior de només lectura amb el perfil d'un altre membre de la
// família: mateixa informació que la pestanya Perfil (avatar, nom, ratxa,
// monedes, historial paginat) però sense cap possibilitat de modificar-la.
export default function PerfilMembre({ usuariId, onTancar }) {
  const [perfil, setPerfil] = useState(null)
  const [ratxa, setRatxa] = useState(null)
  const [monedes, setMonedes] = useState(null)
  const [avatarUrl, setAvatarUrl] = useState(null)
  const [carregant, setCarregant] = useState(true)
  const [error, setError] = useState('')

  const [historial, setHistorial] = useState([])
  const [carregantHistorial, setCarregantHistorial] = useState(true)
  const [carregantMes, setCarregantMes] = useState(false)
  const [errorHistorial, setErrorHistorial] = useState('')
  const [hiHaMesHistorial, setHiHaMesHistorial] = useState(true)

  const carrega = useCallback(async () => {
    setCarregant(true)
    setError('')

    const [perfilRes, ratxaRes, monedesRes] = await Promise.all([
      supabase.from('profiles').select('id, nom, avatar_url').eq('id', usuariId).single(),
      supabase.from('ratxes').select('dies_seguits').eq('usuari_id', usuariId).maybeSingle(),
      supabase.from('monedes').select('saldo').eq('usuari_id', usuariId).maybeSingle(),
    ])

    if (perfilRes.error) {
      setError("No s'ha pogut carregar aquest perfil.")
      setCarregant(false)
      return
    }

    setPerfil(perfilRes.data)
    setRatxa(ratxaRes.data ?? { dies_seguits: 0 })
    setMonedes(monedesRes.data ?? { saldo: 0 })

    if (perfilRes.data.avatar_url) {
      const { data } = await supabase.storage
        .from(BUCKET_AVATARS)
        .createSignedUrl(perfilRes.data.avatar_url, CADUCITAT_URL_SIGNADA_S)
      setAvatarUrl(data?.signedUrl ?? null)
    } else {
      setAvatarUrl(null)
    }

    setCarregant(false)
  }, [usuariId])

  useEffect(() => {
    carrega()
  }, [carrega])

  const carregaHistorial = useCallback(
    async (desDeIndex) => {
      const { data, error: historialError } = await supabase
        .from('completions')
        .select('id, punts_base_snapshot, estat, created_at, activitats(nom, emoji)')
        .eq('creada_per', usuariId)
        .order('created_at', { ascending: false })
        .range(desDeIndex, desDeIndex + MIDA_PAGINA_HISTORIAL - 1)

      if (historialError) {
        setErrorHistorial("No s'ha pogut carregar l'historial. Comprova la connexió.")
        return
      }

      setErrorHistorial('')
      setHistorial((actual) => (desDeIndex === 0 ? data : [...actual, ...data]))
      setHiHaMesHistorial(data.length === MIDA_PAGINA_HISTORIAL)
    },
    [usuariId],
  )

  useEffect(() => {
    setCarregantHistorial(true)
    carregaHistorial(0).finally(() => setCarregantHistorial(false))
  }, [carregaHistorial])

  async function handleVeureMes() {
    setCarregantMes(true)
    await carregaHistorial(historial.length)
    setCarregantMes(false)
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-paper/70" onClick={onTancar}>
      <div
        className="bisell max-h-[85vh] w-full overflow-y-auto rounded-t-2xl border border-vora bg-targeta p-6 pb-8"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-2 flex justify-end">
          <button
            type="button"
            onClick={onTancar}
            className="rounded-md px-2 py-1 text-sm text-tinta-sec hover:bg-vora"
          >
            Tanca
          </button>
        </div>

        {carregant ? (
          <p className="py-8 text-center text-sm text-tinta-sec">Carregant perfil…</p>
        ) : error ? (
          <p className="text-sm text-calent">{error}</p>
        ) : (
          <>
            <div className="flex flex-col items-center gap-3 text-center">
              <div className="bisell relative h-24 w-24 overflow-hidden rounded-full border border-vora bg-targeta">
                {avatarUrl ? (
                  <img src={avatarUrl} alt="" className="h-full w-full object-cover" />
                ) : (
                  <span className="flex h-full w-full items-center justify-center font-display text-2xl font-bold text-tinta">
                    {inicials(perfil.nom)}
                  </span>
                )}
              </div>

              <h1 className="font-display text-2xl font-bold text-tinta">{perfil.nom}</h1>

              <IndicadorsJugador
                diesSeguits={ratxa?.dies_seguits ?? 0}
                saldoMonedes={monedes?.saldo ?? 0}
              />
            </div>

            <div className="mt-6">
              <h2 className="mb-2 font-display text-xs font-medium uppercase tracking-wide text-tinta-sec">
                Historial
              </h2>

              {carregantHistorial ? (
                <p className="py-8 text-center text-sm text-tinta-sec">Carregant historial…</p>
              ) : errorHistorial ? (
                <p className="text-sm text-calent">{errorHistorial}</p>
              ) : historial.length === 0 ? (
                <p className="py-8 text-center text-sm text-tinta-sec">
                  Encara no ha fet cap tasca.
                </p>
              ) : (
                <>
                  <div className="space-y-2">
                    {historial.map((completion) => (
                      <TargetaHistorial key={completion.id} completion={completion} />
                    ))}
                  </div>

                  {hiHaMesHistorial && (
                    <button
                      type="button"
                      onClick={handleVeureMes}
                      disabled={carregantMes}
                      className="mt-3 w-full rounded-md border border-vora bg-targeta px-4 py-2 text-sm font-medium text-tinta disabled:opacity-50"
                    >
                      {carregantMes ? 'Carregant…' : "Veure'n més"}
                    </button>
                  )}
                </>
              )}
            </div>
          </>
        )}
      </div>
    </div>
  )
}
