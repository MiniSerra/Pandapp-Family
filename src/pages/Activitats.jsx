import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { iniciPeriodeLocal, faTemps } from '../lib/temps'
import FilaActivitat from '../components/FilaActivitat'
import BlocActivitat from '../components/BlocActivitat'
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

// Xips de categoria: ordre i emoji propis, diferents de l'ordre de les
// seccions de la llista (aquí el Panda va primer).
const CATEGORIA_CHIPS = [
  { id: 'tot', nom: 'Tot', emoji: null },
  { id: 'panda', nom: 'Panda', emoji: '🐾' },
  { id: 'cuina', nom: 'Cuina', emoji: '🍳' },
  { id: 'bany', nom: 'Bany', emoji: '🚿' },
  { id: 'roba', nom: 'Roba', emoji: '👕' },
  { id: 'casa', nom: 'Casa', emoji: '🏠' },
  { id: 'compres', nom: 'Compres', emoji: '🛒' },
  { id: 'manteniment', nom: 'Manteniment', emoji: '🔧' },
  { id: 'personals', nom: 'Personals', emoji: '💪' },
  { id: 'familiars', nom: 'Familiars', emoji: '👨‍👩‍👧' },
]

const CLAU_VISTA = 'pandapp:vista-activitats'

// Historial que fem servir per pintar cooldowns i "fa temps". La veritat del
// cooldown la decideix sempre reclamar_activitat al servidor; això és només
// per no mostrar files disponibles que en realitat rebutjaria el servidor.
const DIES_HISTORIC = 30
// Llindar de "temps sense fer-se" quan l'activitat no té periode_normal_h.
const PERIODE_NORMAL_DEFECTE_H = 48

// Treu els accents comparant cada caràcter, ja descompost en NFD, contra el
// rang Unicode dels diacrítics combinables (0x0300-0x036f), sense fer servir
// una classe de regex amb caràcters combinables literals al codi font.
function esMarcaCombinable(caracter) {
  const codi = caracter.codePointAt(0)
  return codi >= 0x0300 && codi <= 0x036f
}

function normalitza(text) {
  return Array.from(text.normalize('NFD'))
    .filter((caracter) => !esMarcaCombinable(caracter))
    .join('')
    .toLowerCase()
}

function llegeixVistaGuardada() {
  try {
    return localStorage.getItem(CLAU_VISTA) === 'blocs' ? 'blocs' : 'llista'
  } catch {
    return 'llista'
  }
}

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

function IconaLlista() {
  return (
    <svg
      viewBox="0 0 20 20"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
    >
      <line x1="4" y1="5" x2="16" y2="5" />
      <line x1="4" y1="10" x2="16" y2="10" />
      <line x1="4" y1="15" x2="16" y2="15" />
    </svg>
  )
}

function IconaBlocs() {
  return (
    <svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="3" width="6" height="6" rx="1" />
      <rect x="11" y="3" width="6" height="6" rx="1" />
      <rect x="3" y="11" width="6" height="6" rx="1" />
      <rect x="11" y="11" width="6" height="6" rx="1" />
    </svg>
  )
}

function BarraCercaIVista({ cerca, onCerca, vista, onVista }) {
  return (
    <div className="flex items-center gap-2 px-4 py-3">
      <input
        type="text"
        value={cerca}
        onChange={(event) => onCerca(event.target.value)}
        placeholder="Cerca una activitat…"
        className="bisell min-w-0 flex-1 rounded-xl border border-vora bg-targeta px-3 py-2 text-sm text-tinta placeholder:text-tinta-sec focus:outline-none"
      />
      <div className="flex shrink-0 gap-1">
        <button
          type="button"
          onClick={() => onVista('llista')}
          aria-label="Vista de llista"
          aria-pressed={vista === 'llista'}
          className={`rounded-lg p-2 ${vista === 'llista' ? 'bg-vora text-tinta' : 'text-tinta-sec'}`}
        >
          <IconaLlista />
        </button>
        <button
          type="button"
          onClick={() => onVista('blocs')}
          aria-label="Vista de blocs"
          aria-pressed={vista === 'blocs'}
          className={`rounded-lg p-2 ${vista === 'blocs' ? 'bg-vora text-tinta' : 'text-tinta-sec'}`}
        >
          <IconaBlocs />
        </button>
      </div>
    </div>
  )
}

function XipsCategoria({ actiu, onCanvia }) {
  return (
    <div className="no-scrollbar flex gap-2 overflow-x-auto px-4 pb-3">
      {CATEGORIA_CHIPS.map((chip) => {
        const seleccionat = actiu === chip.id
        return (
          <button
            key={chip.id}
            type="button"
            onClick={() => onCanvia(chip.id)}
            className={`shrink-0 rounded-full border px-3 py-1.5 font-body text-sm whitespace-nowrap transition-colors ${
              seleccionat
                ? 'border-panda bg-panda text-paper'
                : 'border-vora bg-targeta text-tinta-sec'
            }`}
          >
            {chip.emoji ? `${chip.emoji} ${chip.nom}` : chip.nom}
          </button>
        )
      })}
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
  const [cerca, setCerca] = useState('')
  const [categoriaActiva, setCategoriaActiva] = useState('tot')
  const [vista, setVista] = useState(llegeixVistaGuardada)

  useEffect(() => {
    try {
      localStorage.setItem(CLAU_VISTA, vista)
    } catch {
      // localStorage no disponible (mode privat, etc.): la preferència
      // simplement no es recorda entre sessions.
    }
  }, [vista])

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
          'id, activitat_id, creada_per, created_at, estat, participacions(usuari_id, punts_assignats)',
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

  const activitatsFiltrades = useMemo(() => {
    let resultat = activitats

    if (categoriaActiva !== 'tot') {
      resultat = resultat.filter((act) => act.categoria === categoriaActiva)
    }

    const cercaNorm = normalitza(cerca.trim())
    if (cercaNorm) {
      resultat = resultat.filter((act) => normalitza(act.nom).includes(cercaNorm))
    }

    return resultat
  }, [activitats, categoriaActiva, cerca])

  // Amb "Tot" es reagrupa per categoria (com abans); amb una categoria
  // concreta seleccionada ja no cal repetir la capçalera de categoria.
  const seccions = useMemo(() => {
    if (categoriaActiva !== 'tot') {
      return activitatsFiltrades.length > 0
        ? [{ categoria: null, activitats: activitatsFiltrades }]
        : []
    }

    const grups = {}
    for (const cat of ORDRE_CATEGORIES) grups[cat] = []
    for (const act of activitatsFiltrades) {
      grups[act.categoria]?.push(act)
    }

    return ORDRE_CATEGORIES.filter((cat) => grups[cat].length > 0).map((cat) => ({
      categoria: cat,
      activitats: grups[cat],
    }))
  }, [activitatsFiltrades, categoriaActiva])

  // Fase 2: una completion 'pendent' (validació creuada) encara no compta
  // al progrés del dia, encara que ja s'hagi reclamat.
  const puntsAvui = useMemo(() => {
    if (!profile) return 0
    const iniciAvui = iniciPeriodeLocal('day')
    return completions
      .filter((c) => c.estat === 'validada' && new Date(c.created_at) >= iniciAvui)
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

      <BarraCercaIVista cerca={cerca} onCerca={setCerca} vista={vista} onVista={setVista} />
      <XipsCategoria actiu={categoriaActiva} onCanvia={setCategoriaActiva} />

      {seccions.length === 0 && (
        <p className="px-4 py-10 text-center text-sm text-tinta-sec">
          Cap activitat coincideix. Prova un altre terme o una altra categoria.
        </p>
      )}

      {seccions.map((seccio) => (
        <section key={seccio.categoria ?? 'filtrada'} className="px-4 py-3">
          {seccio.categoria && (
            <h2 className="mb-2 font-display text-xs font-medium uppercase tracking-wide text-tinta-sec">
              {NOM_CATEGORIES[seccio.categoria]}
            </h2>
          )}

          {vista === 'llista' ? (
            <div className="bisell divide-y divide-vora overflow-hidden rounded-2xl border border-vora bg-targeta">
              {seccio.activitats.map((act) => (
                <FilaActivitat
                  key={act.id}
                  activitat={act}
                  estat={calculaEstat(act, ultimaPerActivitat[act.id], perfils)}
                  flaix={flaixId === act.id}
                  onSeleccionar={() => setActivitatSeleccionada(act)}
                />
              ))}
            </div>
          ) : (
            <div className="grid grid-cols-3 gap-2">
              {seccio.activitats.map((act) => (
                <BlocActivitat
                  key={act.id}
                  activitat={act}
                  estat={calculaEstat(act, ultimaPerActivitat[act.id], perfils)}
                  flaix={flaixId === act.id}
                  onSeleccionar={() => setActivitatSeleccionada(act)}
                />
              ))}
            </div>
          )}
        </section>
      ))}

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
