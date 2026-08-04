import { faTempsPrecis } from '../lib/temps'

// Esdeveniment de sistema al feed (fase 3, veure CLAUDE.md "Objectiu
// col·lectiu" i "Recompenses"): sense foto, avatars, like ni comentaris —
// visualment diferent de les targetes de completion normals.
export default function TargetaEsdeveniment({ esdeveniment, perfils }) {
  const contingut = contingutEsdeveniment(esdeveniment, perfils)
  if (!contingut) return null
  const { icona, titol, subtitol } = contingut

  return (
    <article className="bisell flex items-center gap-3 rounded-2xl border border-panda/40 bg-panda/10 p-4">
      <span className="text-3xl leading-none">{icona}</span>
      <div className="min-w-0 flex-1">
        <p className="font-display font-medium text-tinta">{titol}</p>
        {subtitol && <p className="truncate font-body text-sm text-tinta-sec">{subtitol}</p>}
        <p className="font-body text-xs text-tinta-sec">
          {faTempsPrecis(esdeveniment.created_at)}
        </p>
      </div>
    </article>
  )
}

function contingutEsdeveniment(esdeveniment, perfils) {
  const dades = esdeveniment.dades ?? {}

  if (esdeveniment.tipus === 'objectiu_setmanal') {
    return { icona: '🎉', titol: 'Objectiu setmanal assolit!', subtitol: dades.premi }
  }

  if (esdeveniment.tipus === 'bescanvi') {
    const nom = perfils?.[esdeveniment.usuari_id] ?? 'Algú'
    return {
      icona: '🎟️',
      titol: `${nom} s'ha bescanviat: ${dades.recompensa}`,
      subtitol: `${dades.emoji ?? ''} 🪙 ${dades.cost}`.trim(),
    }
  }

  return null
}
