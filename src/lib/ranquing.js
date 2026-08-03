import { iniciPeriodeLocal } from './temps'

export const PERIODES_RANQUING = [
  { id: 'diari', nom: 'Diari', unitat: 'day' },
  { id: 'setmanal', nom: 'Setmanal', unitat: 'week' },
  { id: 'mensual', nom: 'Mensual', unitat: 'month' },
]

// Suma punts_assignats de les participacions d'una llista de completions
// (cada una amb les seves participacions niades) posteriors a `inici`,
// agrupats per usuari. Només compten les completions ja validades: les
// 'pendent' (fase 2, validació creuada) encara no sumen enlloc.
function sumaPuntsPerUsuari(completions, inici) {
  const sumes = {}
  for (const completion of completions) {
    if (completion.estat !== 'validada') continue
    if (new Date(completion.created_at) < inici) continue
    for (const participacio of completion.participacions ?? []) {
      sumes[participacio.usuari_id] =
        (sumes[participacio.usuari_id] ?? 0) + participacio.punts_assignats
    }
  }
  return sumes
}

// Calcula els tres rànquings (diari/setmanal/mensual) en client, reutilitzant
// la mateixa lògica de tall horari que el progrés diari d'Activitats.jsx
// (inici_periode_local reproduïda en JS a temps.js, sempre en hora local
// d'Europe/Madrid). Tots els membres de `membres` surten a cada llista,
// ordenats de més a menys punts, amb 0 si no n'han fet cap en el període.
export function calculaClassificacions(completions, membres) {
  const resultat = {}

  for (const periode of PERIODES_RANQUING) {
    const inici = iniciPeriodeLocal(periode.unitat)
    const sumes = sumaPuntsPerUsuari(completions, inici)

    resultat[periode.id] = membres
      .map((membre) => ({
        id: membre.id,
        nom: membre.nom,
        punts: sumes[membre.id] ?? 0,
      }))
      .sort((a, b) => b.punts - a.punts)
  }

  return resultat
}
