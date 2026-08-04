import { useState } from 'react'
import { faTempsPrecis, esPotAnullar } from '../lib/temps'
import IconaPapereta from './IconaPapereta'
import BottomSheetConfirmar from './BottomSheetConfirmar'

// Versió informativa (sense validar/like) de la targeta del feed, per a
// l'historial personal del perfil. Quan es passa `onEliminar` totes les
// entrades ja són "meves" (l'historial només carrega creada_per = jo) i
// només cal la finestra dels 15 minuts per decidir si es pot eliminar.
// PerfilMembre.jsx reutilitza aquesta targeta en mode només lectura sense
// passar `onEliminar`: no s'hi mostra mai la papereta.
export default function TargetaHistorial({ completion, onEliminar }) {
  const [confirmantEliminar, setConfirmantEliminar] = useState(false)
  const [eliminant, setEliminant] = useState(false)
  const [errorEliminar, setErrorEliminar] = useState('')

  const pendent = completion.estat === 'pendent'
  const activitat = completion.activitats
  // "Bonus de ratxa" és una completion de sistema, no una reclamació: no té
  // sentit poder-la eliminar (veure comentari a anullar_completion).
  const potEliminar =
    Boolean(onEliminar) && activitat?.nom !== 'Bonus de ratxa' && esPotAnullar(completion.created_at)

  async function handleEliminar() {
    setEliminant(true)
    setErrorEliminar('')
    const err = await onEliminar(completion.id)
    setEliminant(false)
    if (err) setErrorEliminar(err.message)
    else setConfirmantEliminar(false)
  }

  return (
    <div className="bisell relative flex items-center gap-3 rounded-2xl border border-vora bg-targeta p-3">
      <span className="text-2xl leading-none">{activitat?.emoji}</span>
      <div className="min-w-0 flex-1">
        <p className="truncate font-display font-medium text-tinta">{activitat?.nom}</p>
        <div className="flex items-center gap-2">
          <p className="truncate font-body text-xs text-tinta-sec">
            {faTempsPrecis(completion.created_at)}
          </p>
          {pendent && (
            <span className="shrink-0 rounded-full border border-vora bg-vora px-2 py-0.5 font-body text-[11px] text-tinta-sec">
              pendent
            </span>
          )}
        </div>
      </div>
      <span
        className={`shrink-0 font-display text-lg font-bold ${
          pendent ? 'text-tinta-sec' : 'text-panda'
        }`}
      >
        {completion.punts_base_snapshot}
      </span>

      {potEliminar && (
        <button
          type="button"
          onClick={() => setConfirmantEliminar(true)}
          aria-label="Eliminar aquesta activitat"
          className="ml-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-calent"
        >
          <IconaPapereta />
        </button>
      )}

      {confirmantEliminar && (
        <BottomSheetConfirmar
          titol="Vols eliminar aquesta activitat?"
          missatge="Es restaran els punts i podràs tornar-la a reclamar."
          enviant={eliminant}
          error={errorEliminar}
          onCancelar={() => setConfirmantEliminar(false)}
          onConfirmar={handleEliminar}
        />
      )}
    </div>
  )
}
