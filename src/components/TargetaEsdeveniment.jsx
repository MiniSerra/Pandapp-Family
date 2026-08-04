import { faTempsPrecis } from '../lib/temps'

// Esdeveniment de sistema al feed (fase 3, veure CLAUDE.md "Objectiu
// col·lectiu"): sense foto, avatars, like ni comentaris — visualment
// diferent de les targetes de completion normals.
export default function TargetaEsdeveniment({ esdeveniment }) {
  if (esdeveniment.tipus !== 'objectiu_setmanal') return null

  const { premi } = esdeveniment.dades ?? {}

  return (
    <article className="bisell flex items-center gap-3 rounded-2xl border border-panda/40 bg-panda/10 p-4">
      <span className="text-3xl leading-none">🎉</span>
      <div className="min-w-0 flex-1">
        <p className="font-display font-medium text-tinta">Objectiu setmanal assolit!</p>
        {premi && <p className="truncate font-body text-sm text-tinta-sec">{premi}</p>}
        <p className="font-body text-xs text-tinta-sec">
          {faTempsPrecis(esdeveniment.created_at)}
        </p>
      </div>
    </article>
  )
}
