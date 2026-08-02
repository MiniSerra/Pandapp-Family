const ZONA = 'Europe/Madrid'

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
