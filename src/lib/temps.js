const ZONA = 'Europe/Madrid'

// Mateixa finestra que comprova anullar_completion al servidor.
export const FINESTRA_ANULLACIO_MS = 15 * 60 * 1000

// Si encara es pot anul·lar una completion pròpia creada a `dataIso`. Només
// per no pintar la icona quan el servidor la rebutjaria igualment.
export function esPotAnullar(dataIso) {
  return Date.now() - new Date(dataIso).getTime() < FINESTRA_ANULLACIO_MS
}

// Diferència (en ms) entre "hora de rellotge UTC" i "hora de rellotge a la
// zona indicada" per a un instant concret. Les dues cadenes es parsegen amb
// el mateix Date() del motor, així que la zona horària local del sistema en
// què s'executa el codi es cancel·la en la resta.
function desfasamentZonaMs(zona, moment) {
  const utc = new Date(moment.toLocaleString('en-US', { timeZone: 'UTC' }))
  const local = new Date(moment.toLocaleString('en-US', { timeZone: zona }))
  return utc.getTime() - local.getTime()
}

// Rèplica en JS de la funció SQL inici_periode_local(unitat, moment): inici
// (com a instant real) del dia/setmana/mes local d'Europe/Madrid que conté
// `moment`. Fes-la servir sempre en lloc de truncar hores directament sobre
// un Date, que treballaria en UTC i faria començar el dia a les 2 de la
// matinada hora d'Espanya.
export function iniciPeriodeLocal(unitat, moment = new Date()) {
  const desfasament = desfasamentZonaMs(ZONA, moment)
  // "moment" convertit a hora local d'Espanya, però numèricament com si fos UTC.
  const local = new Date(moment.getTime() - desfasament)

  if (unitat === 'day') {
    local.setUTCHours(0, 0, 0, 0)
  } else if (unitat === 'week') {
    const diaSetmana = local.getUTCDay() // 0 = diumenge
    const diesDesDeDilluns = (diaSetmana + 6) % 7
    local.setUTCDate(local.getUTCDate() - diesDesDeDilluns)
    local.setUTCHours(0, 0, 0, 0)
  } else if (unitat === 'month') {
    local.setUTCDate(1)
    local.setUTCHours(0, 0, 0, 0)
  }

  return new Date(local.getTime() + desfasament)
}

// Text relatiu ("fa 3 h", "fa 2 dies") per pintar quan es va fer una
// activitat per última vegada. Només visual: no és la font de veritat.
export function faTemps(dataIso) {
  if (!dataIso) return 'mai feta'
  const ms = Date.now() - new Date(dataIso).getTime()
  const hores = ms / 3_600_000
  if (hores < 1) return 'fa poc'
  if (hores < 24) return `fa ${Math.floor(hores)} h`
  const dies = Math.floor(hores / 24)
  return `fa ${dies} ${dies === 1 ? 'dia' : 'dies'}`
}

// Text relatiu ("d'aquí a 4 h", "d'aquí a 2 dies") per al temps que queda de
// cooldown. `ms` ha de ser positiu (temps restant).
export function disponibleEn(ms) {
  const hores = ms / 3_600_000
  if (hores < 1) return "d'aquí a poc"
  if (hores < 24) return `d'aquí a ${Math.ceil(hores)} h`
  const dies = Math.ceil(hores / 24)
  return `d'aquí a ${dies} ${dies === 1 ? 'dia' : 'dies'}`
}

// Text relatiu de gra fi ("fa 5 min", "fa 2 h", "ahir", "fa 3 dies") per al
// feed, on cada minut compta. Diferent de faTemps (que és pensada per a
// l'"últim cop" d'una activitat i no necessita tanta precisió).
export function faTempsPrecis(dataIso) {
  const data = new Date(dataIso)
  const araMs = Date.now()
  const minuts = (araMs - data.getTime()) / 60_000

  if (minuts < 1) return 'ara mateix'
  if (minuts < 60) return `fa ${Math.floor(minuts)} min`

  const hores = minuts / 60
  if (hores < 24) return `fa ${Math.floor(hores)} h`

  const iniciAvui = iniciPeriodeLocal('day', new Date(araMs))
  const iniciAhir = new Date(iniciAvui.getTime() - 24 * 3_600_000)
  if (data >= iniciAhir && data < iniciAvui) return 'ahir'

  // Diferència en dies de calendari (no en múltiples de 24h reals): l'inici
  // del dia local que conté `data` és l'ancoratge, no `data` mateixa.
  const iniciDelDia = iniciPeriodeLocal('day', data)
  const dies = Math.round((iniciAvui.getTime() - iniciDelDia.getTime()) / (24 * 3_600_000))
  return `fa ${dies} ${dies === 1 ? 'dia' : 'dies'}`
}
