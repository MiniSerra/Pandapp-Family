import PastillaPunts from './PastillaPunts'

export default function BlocActivitat({ activitat, estat, flaix, onSeleccionar }) {
  const { bloquejada, calorPunts } = estat

  const classesFons = flaix
    ? 'bg-panda text-paper'
    : bloquejada
      ? 'opacity-50'
      : 'hover:bg-vora/40'

  const contingut = (
    <>
      <span className="text-3xl leading-none">{activitat.emoji}</span>
      <p className="mt-2 line-clamp-2 text-center font-body text-xs text-tinta">
        {activitat.nom}
      </p>
      <div className="mt-2">
        {bloquejada ? (
          <span aria-hidden="true" className="text-lg text-panda">
            ✓
          </span>
        ) : (
          <PastillaPunts punts={activitat.punts_base} calor={calorPunts} mida="sm" />
        )}
      </div>
    </>
  )

  const classesComunes =
    'bisell flex flex-col items-center rounded-2xl border border-vora bg-targeta p-3 transition-colors'

  if (bloquejada) {
    return <div className={`${classesComunes} ${classesFons}`}>{contingut}</div>
  }

  return (
    <button
      type="button"
      onClick={onSeleccionar}
      className={`${classesComunes} ${classesFons}`}
    >
      {contingut}
    </button>
  )
}
