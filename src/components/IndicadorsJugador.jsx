// Ratxa (🔥 dies seguits) i monedes (🪙 saldo). Compartit entre la
// capçalera d'Activitats i la de Perfil. Amb `onTocaMonedes` (només
// Activitats.jsx, per obrir el full de recompenses) la pastilla de
// monedes es converteix en botó; sense, es queda com a simple indicador.
export default function IndicadorsJugador({ diesSeguits, saldoMonedes, onTocaMonedes }) {
  const ElementMonedes = onTocaMonedes ? 'button' : 'span'

  return (
    <div className="flex items-center gap-2">
      <span className="bisell flex items-center gap-1 rounded-full border border-vora bg-targeta px-3 py-1.5">
        <span aria-hidden="true" className="text-base leading-none">
          🔥
        </span>
        <span className="font-display text-sm font-bold text-tinta">{diesSeguits}</span>
      </span>
      <ElementMonedes
        type={onTocaMonedes ? 'button' : undefined}
        onClick={onTocaMonedes}
        aria-label={onTocaMonedes ? 'Obrir el menú de recompenses' : undefined}
        className="bisell flex items-center gap-1 rounded-full border border-vora bg-targeta px-3 py-1.5"
      >
        <span aria-hidden="true" className="text-base leading-none">
          🪙
        </span>
        <span className="font-display text-sm font-bold text-tinta">{saldoMonedes}</span>
      </ElementMonedes>
    </div>
  )
}
