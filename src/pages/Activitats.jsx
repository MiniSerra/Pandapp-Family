import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/useAuth'
import { iniciPeriodeLocal, faTemps } from '../lib/temps'
import FilaActivitat from '../components/FilaActivitat'
import BlocActivitat from '../components/BlocActivitat'
import BottomSheetReclamar from '../components/BottomSheetReclamar'
import IndicadorsJugador from '../components/IndicadorsJugador'

// Ordre i aparença preferits per a les categories conegudes — el mateix
// per als xips i per a l'agrupació de la llista, ja no dues llistes que es
// puguin desincronitzar. Si `activitats.categoria` porta mai un valor que
// no hi és (una categoria nova al catàleg que encara no s'ha afegit aquí),
// `categoriesDeLActivitats` de sota la hi afegeix igualment al final en
// lloc de fer-la desaparèixer silenciosament de tot filtre visual.
const CATEGORIES_CONEGUDES = [
  { id: 'panda', nom: 'Panda', emoji: '🐾' },
  { id: 'cuina', nom: 'Cuina', emoji: '🍳' },
  { id: 'bany', nom: 'Bany', emoji: '🚿' },
  { id: 'roba', nom: 'Roba', emoji: '👕' },
  { id: 'casa', nom: 'Casa', emoji: '🏠' },
  { id: 'compres', nom: 'Compres', emoji: '🛒' },
  { id: 'manteniment', nom: 'Manteniment', emoji: '🔧' },
  { id: 'personals', nom: 'Personals', emoji: '💪' },
  { id: 'familiars', nom: 'Familiars', emoji: '👨‍👩‍👧' },
  { id: 'jardi', nom: 'Jardí', emoji: '🌱' },
  { id: 'fe', nom: 'Fe', emoji: '🙏' },
]

function capitalitza(text) {
  return text.charAt(0).toUpperCase() + text.slice(1)
}

// Les categories que realment existeixen a les activitats carregades,
// conegudes primer (en l'ordre de CATEGORIES_CONEGUDES) i qualsevol altra
// (encara sense emoji/etiqueta pròpia) després, ordenada alfabèticament.
function categoriesDeLesActivitats(activitats) {
  const presents = new Set(activitats.map((act) => act.categoria))
  const conegudes = CATEGORIES_CONEGUDES.filter((cat) => presents.has(cat.id))
  const desconegudes = [...presents]
    .filter((id) => !CATEGORIES_CONEGUDES.some((cat) => cat.id === id))
    .sort()
    .map((id) => ({ id, nom: capitalitza(id), emoji: null }))
  return [...conegudes, ...desconegudes]
}

const CLAU_VISTA = 'pandapp:vista-activitats'
const BUCKET_AVATARS = 'avatars'
// Prou perquè es vegin mentre es té la pantalla oberta (veure CLAUDE.md "Fotos").
const CADUCITAT_URL_SIGNADA_S = 60 * 60

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

function XipsCategoria({ categories, actiu, onCanvia }) {
  const chips = [{ id: 'tot', nom: 'Tot', emoji: null }, ...categories]

  return (
    <div className="no-scrollbar flex gap-2 overflow-x-auto px-4 pb-3">
      {chips.map((chip) => {
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
  const [membresFamilia, setMembresFamilia] = useState([])
  const [avatarUrls, setAvatarUrls] = useState({})
  const [ratxa, setRatxa] = useState(null)
  const [monedes, setMonedes] = useState(null)
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

    const [activitatsRes, completionsRes, perfilsRes, ratxaRes, monedesRes] = await Promise.all([
      supabase
        .from('activitats')
        .select('*')
        .eq('estat', 'activa')
        .order('categoria')
        .order('nom'),
      supabase
        .from('completions')
        .select(
          'id, activitat_id, creada_per, created_at, estat, participacions(usuari_id, punts_assignats, confirmat)',
        )
        .eq('familia_id', profile.familia_id)
        .gte('created_at', desDe)
        .order('created_at', { ascending: false }),
      supabase.from('profiles').select('id, nom, avatar_url'),
      // ratxes/monedes encara poden no tenir fila (es creen soles la
      // primera vegada que es completa el llindar diari).
      supabase.from('ratxes').select('dies_seguits').eq('usuari_id', profile.id).maybeSingle(),
      supabase.from('monedes').select('saldo').eq('usuari_id', profile.id).maybeSingle(),
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
    setMembresFamilia(perfilsRes.data.filter((p) => p.id !== profile.id))
    setRatxa(ratxaRes.data ?? { dies_seguits: 0 })
    setMonedes(monedesRes.data ?? { saldo: 0 })
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
  }, [profile])

  useEffect(() => {
    carregar()
  }, [carregar])

  // cooldown_individual O es_personal (fase 3): per a activitats com "Fer
  // el llit" (exemplar propi) o qualsevol activitat personal (llegir,
  // meditar...), l'última completació "que compta" per bloquejar/escalar
  // només és la meva pròpia, no la de qualsevol membre de la família —
  // mateix criteri que reclamar_activitat al servidor.
  const ultimaPerActivitat = useMemo(() => {
    const individuals = new Set(
      activitats
        .filter((act) => act.cooldown_individual || act.es_personal)
        .map((act) => act.id),
    )
    const mapa = {}
    for (const c of completions) {
      if (individuals.has(c.activitat_id) && c.creada_per !== profile?.id) continue
      if (!(c.activitat_id in mapa)) mapa[c.activitat_id] = c
    }
    return mapa
  }, [completions, activitats, profile])

  const categories = useMemo(() => categoriesDeLesActivitats(activitats), [activitats])

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
    for (const cat of categories) grups[cat.id] = []
    for (const act of activitatsFiltrades) {
      grups[act.categoria]?.push(act)
    }

    return categories
      .filter((cat) => grups[cat.id].length > 0)
      .map((cat) => ({ categoria: cat.id, nomCategoria: cat.nom, activitats: grups[cat.id] }))
  }, [activitatsFiltrades, categoriaActiva, categories])

  // Fase 2: una completion 'pendent' (validació creuada) encara no compta
  // al progrés del dia, encara que ja s'hagi reclamat. Fase 3: en una
  // tasca compartida, tampoc compta si encara no he confirmat "hi era".
  const puntsAvui = useMemo(() => {
    if (!profile) return 0
    const iniciAvui = iniciPeriodeLocal('day')
    return completions
      .filter((c) => c.estat === 'validada' && new Date(c.created_at) >= iniciAvui)
      .flatMap((c) => c.participacions ?? [])
      .filter((p) => p.usuari_id === profile.id && p.confirmat)
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
      <div className="flex items-center justify-center gap-4 border-b border-vora bg-targeta px-4 py-6">
        <AnellProgres punts={puntsAvui} llindar={llindar} />
        <IndicadorsJugador
          diesSeguits={ratxa?.dies_seguits ?? 0}
          saldoMonedes={monedes?.saldo ?? 0}
        />
      </div>

      <BarraCercaIVista cerca={cerca} onCerca={setCerca} vista={vista} onVista={setVista} />
      <XipsCategoria categories={categories} actiu={categoriaActiva} onCanvia={setCategoriaActiva} />

      {seccions.length === 0 && (
        <p className="px-4 py-10 text-center text-sm text-tinta-sec">
          Cap activitat coincideix. Prova un altre terme o una altra categoria.
        </p>
      )}

      {seccions.map((seccio) => (
        <section key={seccio.categoria ?? 'filtrada'} className="px-4 py-3">
          {seccio.categoria && (
            <h2 className="mb-2 font-display text-xs font-medium uppercase tracking-wide text-tinta-sec">
              {seccio.nomCategoria}
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
          membresFamilia={membresFamilia}
          avatarUrls={avatarUrls}
          onTancar={() => setActivitatSeleccionada(null)}
          onExit={gestionaExit}
        />
      )}
    </div>
  )
}
