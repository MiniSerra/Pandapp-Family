import { faTempsPrecis } from '../lib/temps'

// Versió informativa (sense validar/like) de la targeta del feed, per a
// l'historial personal del perfil.
export default function TargetaHistorial({ completion }) {
  const pendent = completion.estat === 'pendent'
  const activitat = completion.activitats

  return (
    <div className="bisell flex items-center gap-3 rounded-2xl border border-vora bg-targeta p-3">
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
    </div>
  )
}
