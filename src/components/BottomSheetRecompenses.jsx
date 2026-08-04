import { useState } from 'react'
import BottomSheetConfirmar from './BottomSheetConfirmar'

export default function BottomSheetRecompenses({ recompenses, saldo, onTancar, onBescanviar }) {
  const [seleccionada, setSeleccionada] = useState(null)
  const [enviant, setEnviant] = useState(false)
  const [error, setError] = useState('')

  async function handleConfirmar() {
    setEnviant(true)
    setError('')
    const err = await onBescanviar(seleccionada.id)
    setEnviant(false)
    if (err) {
      setError(err.message)
      return
    }
    onTancar()
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end bg-paper/70" onClick={onTancar}>
      <div
        className="bisell w-full rounded-t-2xl border border-vora bg-targeta p-6 pb-8"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-4 text-center">
          <p className="font-body text-sm text-tinta-sec">El teu saldo</p>
          <p className="font-display text-3xl font-bold text-tinta">🪙 {saldo}</p>
        </div>

        {recompenses.length === 0 ? (
          <p className="py-6 text-center font-body text-sm text-tinta-sec">
            Encara no hi ha cap recompensa configurada.
          </p>
        ) : (
          <div className="max-h-[50vh] space-y-2 overflow-y-auto">
            {recompenses.map((recompensa) => {
              const potPermetres = saldo >= recompensa.cost
              return (
                <div
                  key={recompensa.id}
                  className="bisell flex items-center gap-3 rounded-2xl border border-vora bg-paper p-3"
                >
                  <span className="text-2xl leading-none">{recompensa.emoji}</span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate font-display font-medium text-tinta">
                      {recompensa.nom}
                    </p>
                    <p className="font-body text-xs text-tinta-sec">🪙 {recompensa.cost}</p>
                  </div>
                  <button
                    type="button"
                    onClick={() => setSeleccionada(recompensa)}
                    disabled={!potPermetres}
                    className={`shrink-0 rounded-md px-3 py-1.5 font-body text-sm font-medium ${
                      potPermetres
                        ? 'bg-panda text-paper'
                        : 'bg-vora text-tinta-sec'
                    }`}
                  >
                    Bescanviar
                  </button>
                </div>
              )
            })}
          </div>
        )}
      </div>

      {seleccionada && (
        <BottomSheetConfirmar
          titol={`Bescanviar "${seleccionada.nom}"?`}
          missatge={`Es restaran ${seleccionada.cost} monedes del teu saldo.`}
          textConfirmar="Bescanviar"
          textEnviant="Bescanviant…"
          variant="principal"
          enviant={enviant}
          error={error}
          onCancelar={() => {
            setSeleccionada(null)
            setError('')
          }}
          onConfirmar={handleConfirmar}
        />
      )}
    </div>
  )
}
