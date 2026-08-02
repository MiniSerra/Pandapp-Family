import { disponibleEn } from '../lib/temps'

const ESTIL_PASTILLA = {
  neutre: 'border-vora bg-vora text-tinta',
  tebi: 'border-tebi-vora bg-tebi-fons text-tebi',
  calent: 'border-calent-vora bg-calent-fons text-calent',
}

export default function FilaActivitat({ activitat, estat, flaix, onSeleccionar }) {
  const { bloquejada, fetPer, faTempsText, calorPunts, remainingMs } = estat

  const classesFons = flaix
    ? 'bg-panda text-paper'
    : bloquejada
      ? 'opacity-50'
      : 'hover:bg-vora/40'

  const contingut = (
    <>
      <span className="text-[2.25rem] leading-none">{activitat.emoji}</span>
      <div className="min-w-0 flex-1 text-left">
        <p className="truncate font-display font-medium text-tinta">
          {activitat.nom}
        </p>
        <p className="truncate font-body text-xs text-tinta-sec">
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
          className={`bisell shrink-0 rounded-full border px-3 py-1 font-display text-sm font-bold ${ESTIL_PASTILLA[calorPunts]}`}
        >
          {activitat.punts_base}
        </span>
      )}
    </>
  )

  if (bloquejada) {
    return (
      <div className={`flex items-center gap-3 px-3 py-2 transition-colors ${classesFons}`}>
        {contingut}
      </div>
    )
  }

  return (
    <button
      type="button"
      onClick={onSeleccionar}
      className={`flex w-full items-center gap-3 px-3 py-2 text-left transition-colors ${classesFons}`}
    >
      {contingut}
    </button>
  )
}
