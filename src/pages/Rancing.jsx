import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { PERIODES_RANQUING, calculaClassificacions } from '../lib/ranquing'

// Marge de seguretat perquè el rànquing mensual sempre inclogui tot el mes
// en curs (fins a 31 dies), calculat després en client amb iniciPeriodeLocal.
const DIES_HISTORIC = 35

function ordinal(posicio) {
  if (posicio === 1) return '1r'
  if (posicio === 2) return '2n'
  if (posicio === 3) return '3r'
  return `${posicio}è`
}

function PestanyesPeriode({ actiu, onCanvia }) {
  return (
    <div className="flex gap-2 px-4 py-3">
      {PERIODES_RANQUING.map((periode) => {
        const seleccionada = actiu === periode.id
        return (
          <button
            key={periode.id}
            type="button"
            onClick={() => onCanvia(periode.id)}
            className={`flex-1 rounded-xl border px-3 py-2 text-center font-body text-sm font-medium transition-colors ${
              seleccionada
                ? 'bisell border-panda bg-panda text-paper'
                : 'border-vora bg-targeta text-tinta-sec'
            }`}
          >
            {periode.nom}
          </button>
        )
      })}
    </div>
  )
}

function FilaClassificacio({ posicio, nom, punts, soc }) {
  const esPrimer = posicio === 1

  return (
    <div
      className={`bisell flex items-center gap-3 rounded-2xl border border-vora bg-targeta px-4 ${
        esPrimer ? 'border-t-2 border-t-panda py-4' : 'py-3'
      }`}
    >
      <span className="w-10 shrink-0 font-display text-xl font-bold text-tinta-sec">
        {ordinal(posicio)}
      </span>
      <span className="min-w-0 flex-1 truncate font-body text-tinta">{nom}</span>
      <span
        className={`shrink-0 font-display text-lg font-bold ${soc ? 'text-panda' : 'text-tinta'}`}
      >
        {punts}
      </span>
    </div>
  )
}

export default function Rancing() {
  const { profile } = useAuth()
  const [completions, setCompletions] = useState([])
  const [membres, setMembres] = useState([])
  const [carregant, setCarregant] = useState(true)
  const [error, setError] = useState('')
  const [periode, setPeriode] = useState('diari')

  const carregar = useCallback(async () => {
    if (!profile) return

    setCarregant(true)
    setError('')

    const desDe = new Date(
      Date.now() - DIES_HISTORIC * 24 * 60 * 60 * 1000,
    ).toISOString()

    const [completionsRes, membresRes] = await Promise.all([
      supabase
        .from('completions')
        .select('id, created_at, participacions(usuari_id, punts_assignats)')
        .eq('familia_id', profile.familia_id)
        .gte('created_at', desDe),
      supabase.from('profiles').select('id, nom'),
    ])

    if (completionsRes.error || membresRes.error) {
      setError("No s'ha pogut carregar el rànquing. Comprova la connexió.")
      setCarregant(false)
      return
    }

    setCompletions(completionsRes.data)
    setMembres(membresRes.data)
    setCarregant(false)
  }, [profile])

  useEffect(() => {
    carregar()
  }, [carregar])

  const classificacions = useMemo(
    () => calculaClassificacions(completions, membres),
    [completions, membres],
  )

  if (carregant) {
    return (
      <div className="flex flex-1 items-center justify-center py-16">
        <p className="text-tinta-sec">Carregant rànquing…</p>
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

  const classificacio = classificacions[periode] ?? []

  return (
    <div className="pb-8">
      <PestanyesPeriode actiu={periode} onCanvia={setPeriode} />

      <div className="space-y-2 px-4 py-2">
        {classificacio.map((membre, index) => (
          <FilaClassificacio
            key={membre.id}
            posicio={index + 1}
            nom={membre.nom}
            punts={membre.punts}
            soc={membre.id === profile?.id}
          />
        ))}
      </div>
    </div>
  )
}
