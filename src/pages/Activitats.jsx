import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { iniciPeriodeLocal, faTemps } from '../lib/temps'
import FilaActivitat from '../components/FilaActivitat'
import BottomSheetReclamar from '../components/BottomSheetReclamar'

const ORDRE_CATEGORIES = [
  'casa',
  'cuina',
  'bany',
  'roba',
  'panda',
  'compres',
  'manteniment',
  'personals',
  'familiars',
]

const NOM_CATEGORIES = {
  casa: 'Casa',
  cuina: 'Cuina',
  bany: 'Bany',
  roba: 'Roba',
  panda: 'Panda',
  compres: 'Compres',
  manteniment: 'Manteniment',
  personals: 'Personals',
  familiars: 'Familiars',
}

// Historial que fem servir per pintar cooldowns i "fa temps". La veritat del
// cooldown la decideix sempre reclamar_activitat al servidor; això és només
// per no mostrar files disponibles que en realitat rebutjaria el servidor.
const DIES_HISTORIC = 30
// Llindar de "temps sense fer-se" quan l'activitat no té periode_normal_h.
const PERIODE_NORMAL_DEFECTE_H = 48

function calculaEstat(activitat, ultima, perfils) {
  if (!ultima) {
    return {
      bloquejada: false,
      fetPer: null,
      faTempsText: 'mai feta',
      calorPunts: 'calent',
      remainingMs: 0,
    }
  }

  const araMs = Date.now()
  const ultimaMs = new Date(ultima.created_at).getTime()
  const elapsedHores = (araMs - ultimaMs) / 3_600_000
  const cooldownH = Number(activitat.cooldown_h) || 0
  const periodeNormalH = Number(activitat.periode_normal_h) || PERIODE_NORMAL_DEFECTE_H

  const bloquejada = elapsedHores < cooldownH

  let calorPunts = 'neutre'
  if (elapsedHores >= periodeNormalH * 2) {
    calorPunts = 'calent'
  } else if (elapsedHores >= periodeNormalH) {
    calorPunts = 'tebi'
  }

  return {
    bloquejada,
    fetPer: perfils[ultima.creada_per] ?? 'algú',
    faTempsText: faTemps(ultima.created_at),
    calorPunts,
    remainingMs: bloquejada ? (cooldownH - elapsedHores) * 3_600_000 : 0,
  }
}

function AnellProgres({ punts, llindar }) {
  const mida = 112
  const gruix = 10
  const radi = (mida - gruix) / 2
  const circumferencia = 2 * Math.PI * radi
  const percent = llindar > 0 ? Math.min(1, punts / llindar) : 0
  const offset = circumferencia * (1 - percent)

  return (
    <div className="relative" style={{ width: mida, height: mida }}>
      <svg width={mida} height={mida} className="-rotate-90">
        <circle
          cx={mida / 2}
          cy={mida / 2}
          r={radi}
          fill="none"
          stroke="var(--color-vora)"
          strokeWidth={gruix}
        />
        <circle
          cx={mida / 2}
          cy={mida / 2}
          r={radi}
          fill="none"
          stroke="var(--color-panda)"
          strokeWidth={gruix}
          strokeLinecap="round"
          strokeDasharray={circumferencia}
          strokeDashoffset={offset}
          className="transition-[stroke-dashoffset] duration-500 ease-out"
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className="font-display text-3xl font-bold text-tinta">{punts}</span>
        <span className="font-body text-xs text-tinta-sec">/ {llindar}</span>
      </div>
    </div>
  )
}

export default function Activitats() {
  const { profile } = useAuth()
  const [activitats, setActivitats] = useState([])
  const [completions, setCompletions] = useState([])
  const [perfils, setPerfils] = useState({})
  const [carregant, setCarregant] = useState(true)
  const [error, setError] = useState('')
  const [activitatSeleccionada, setActivitatSeleccionada] = useState(null)
  const [flaixId, setFlaixId] = useState(null)

  const carregar = useCallback(async () => {
    if (!profile) return

    setCarregant(true)
    setError('')

    const desDe = new Date(
      Date.now() - DIES_HISTORIC * 24 * 60 * 60 * 1000,
    ).toISOString()

    const [activitatsRes, completionsRes, perfilsRes] = await Promise.all([
      supabase
        .from('activitats')
        .select('*')
        .eq('estat', 'activa')
        .order('categoria')
        .order('nom'),
      supabase
        .from('completions')
        .select(
          'id, activitat_id, creada_per, created_at, participacions(usuari_id, punts_assignats)',
        )
        .eq('familia_id', profile.familia_id)
        .gte('created_at', desDe)
        .order('created_at', { ascending: false }),
      supabase.from('profiles').select('id, nom'),
    ])

    if (activitatsRes.error || completionsRes.error || perfilsRes.error) {
      setError("No s'ha pogut carregar el catàleg. Comprova la connexió.")
      setCarregant(false)
      return
    }

    const mapaPerfils = {}
    for (const p of perfilsRes.data) mapaPerfils[p.id] = p.nom

    setActivitats(activitatsRes.data)
    setCompletions(completionsRes.data)
    setPerfils(mapaPerfils)
    setCarregant(false)
  }, [profile])

  useEffect(() => {
    carregar()
  }, [carregar])

  const ultimaPerActivitat = useMemo(() => {
    const mapa = {}
    for (const c of completions) {
      if (!(c.activitat_id in mapa)) mapa[c.activitat_id] = c
    }
    return mapa
  }, [completions])

  const activitatsPerCategoria = useMemo(() => {
    const grups = {}
    for (const cat of ORDRE_CATEGORIES) grups[cat] = []
    for (const act of activitats) {
      grups[act.categoria]?.push(act)
    }
    return grups
  }, [activitats])

  const puntsAvui = useMemo(() => {
    if (!profile) return 0
    const iniciAvui = iniciPeriodeLocal('day')
    return completions
      .filter((c) => new Date(c.created_at) >= iniciAvui)
      .flatMap((c) => c.participacions ?? [])
      .filter((p) => p.usuari_id === profile.id)
      .reduce((suma, p) => suma + p.punts_assignats, 0)
  }, [completions, profile])

  async function gestionaExit(activitatId) {
    setActivitatSeleccionada(null)
    setFlaixId(activitatId)
    await carregar()
    setTimeout(() => {
      setFlaixId((actual) => (actual === activitatId ? null : actual))
    }, 900)
  }

  if (carregant) {
    return (
      <div className="flex flex-1 items-center justify-center py-16">
        <p className="text-tinta-sec">Carregant activitats…</p>
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

  const llindar = profile?.llindar_diari ?? 100

  return (
    <div className="pb-8">
      <div className="flex items-center justify-center border-b border-vora bg-targeta px-4 py-6">
        <AnellProgres punts={puntsAvui} llindar={llindar} />
      </div>

      {ORDRE_CATEGORIES.map((cat) => {
        const llista = activitatsPerCategoria[cat]
        if (!llista || llista.length === 0) return null

        return (
          <section key={cat} className="px-4 py-3">
            <h2 className="mb-2 font-display text-xs font-medium uppercase tracking-wide text-tinta-sec">
              {NOM_CATEGORIES[cat]}
            </h2>
            <div className="bisell divide-y divide-vora overflow-hidden rounded-2xl border border-vora bg-targeta">
              {llista.map((act) => (
                <FilaActivitat
                  key={act.id}
                  activitat={act}
                  estat={calculaEstat(act, ultimaPerActivitat[act.id], perfils)}
                  flaix={flaixId === act.id}
                  onSeleccionar={() => setActivitatSeleccionada(act)}
                />
              ))}
            </div>
          </section>
        )
      })}

      {activitatSeleccionada && (
        <BottomSheetReclamar
          activitat={activitatSeleccionada}
          onTancar={() => setActivitatSeleccionada(null)}
          onExit={gestionaExit}
        />
      )}
    </div>
  )
}
