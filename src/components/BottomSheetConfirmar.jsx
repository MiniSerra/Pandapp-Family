// Full de confirmació genèric, mateix estil de bottom sheet que
// BottomSheetReclamar. `variant="perill"` (per defecte) és per a l'única
// acció destructiva de la interfície (eliminar una completion pròpia,
// veure CLAUDE.md "Disseny"): botó en --calent. `variant="principal"` és
// per a confirmacions normals no destructives (p. ex. bescanviar una
// recompensa): botó en --panda, com la resta de botons principals.
export default function BottomSheetConfirmar({
  titol,
  missatge,
  textConfirmar = 'Eliminar',
  textEnviant = 'Eliminant…',
  variant = 'perill',
  enviant,
  error,
  onCancelar,
  onConfirmar,
}) {
  const classesConfirmar =
    variant === 'principal'
      ? 'bg-panda text-paper'
      : 'bisell border border-calent-vora bg-calent-fons text-calent'
  return (
    <div className="fixed inset-0 z-50 flex items-end bg-paper/70" onClick={onCancelar}>
      <div
        className="bisell w-full rounded-t-2xl border border-vora bg-targeta p-6 pb-8"
        onClick={(event) => event.stopPropagation()}
      >
        <h2 className="mb-2 font-display text-xl font-medium text-tinta">{titol}</h2>
        <p className="mb-4 font-body text-sm text-tinta-sec">{missatge}</p>

        {error && <p className="mb-3 text-sm text-calent">{error}</p>}

        <div className="flex gap-3">
          <button
            type="button"
            onClick={onCancelar}
            disabled={enviant}
            className="flex-1 rounded-md border border-vora bg-targeta px-4 py-3 text-base font-medium text-tinta disabled:opacity-50"
          >
            Cancel·la
          </button>
          <button
            type="button"
            onClick={onConfirmar}
            disabled={enviant}
            className={`flex-1 rounded-md px-4 py-3 text-base font-medium disabled:opacity-50 ${classesConfirmar}`}
          >
            {enviant ? textEnviant : textConfirmar}
          </button>
        </div>
      </div>
    </div>
  )
}
