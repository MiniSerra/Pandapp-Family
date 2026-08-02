import { disponibleEn } from '../lib/temps'

const COLOR_PASTILLA = {
  neutre: 'bg-vora text-tinta',
  tebi: 'bg-tebi text-white',
  calent: 'bg-calent text-white',
}

export default function FilaActivitat({ activitat, estat, flaix, onSeleccionar }) {
  const { bloquejada, fetPer, faTempsText, calorPunts, remainingMs } = estat

  const classesFons = flaix
    ? 'bg-panda text-white'
    : bloquejada
      ? 'bg-targeta opacity-50'
      : 'bg-targeta hover:bg-vora/40'

  const contingut = (
    <>
      <span className="text-[2.25rem] leading-none">{activitat.emoji}</span>
      <div className="min-w-0 flex-1 text-left">
        <p className="truncate font-body font-medium text-tinta">{activitat.nom}</p>
        <p className="truncate text-xs text-tinta/60">
          {bloquejada
            ? `l'ha fet ${fetPer} · disponible ${disponibleEn(remainingMs)}`
            : faTempsText}
        </p>
      </div>
      {bloquejada ? (
        <span aria-hidden="true" className="shrink-0 text-xl text-panda">
          ✓
        </span>
      ) : (
        <span
          className={`shrink-0 rounded-full px-3 py-1 font-mono text-sm ${COLOR_PASTILLA[calorPunts]}`}
        >
          {activitat.punts_base}
        </span>
      )}
    </>
  )

  if (bloquejada) {
    return (
      <div
        className={`flex items-center gap-3 rounded-xl px-3 py-2 transition-colors ${classesFons}`}
      >
        {contingut}
      </div>
    )
  }

  return (
    <button
      type="button"
      onClick={onSeleccionar}
      className={`flex w-full items-center gap-3 rounded-xl px-3 py-2 text-left transition-colors ${classesFons}`}
    >
      {contingut}
    </button>
  )
}
