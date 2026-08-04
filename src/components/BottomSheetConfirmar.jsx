// Full de confirmació genèric, mateix estil de bottom sheet que
// BottomSheetReclamar. De moment només el fa servir l'eliminació d'una
// completion pròpia (Feed i historial del Perfil).
export default function BottomSheetConfirmar({
  titol,
  missatge,
  textConfirmar = 'Eliminar',
  enviant,
  error,
  onCancelar,
  onConfirmar,
}) {
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
            className="bisell flex-1 rounded-md border border-calent-vora bg-calent-fons px-4 py-3 text-base font-medium text-calent disabled:opacity-50"
          >
            {enviant ? 'Eliminant…' : textConfirmar}
          </button>
        </div>
      </div>
    </div>
  )
}
