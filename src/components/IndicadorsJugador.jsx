// Ratxa (🔥 dies seguits) i monedes (🪙 saldo). Compartit entre la
// capçalera d'Activitats i la de Perfil.
export default function IndicadorsJugador({ diesSeguits, saldoMonedes }) {
  return (
    <div className="flex items-center gap-2">
      <span className="bisell flex items-center gap-1 rounded-full border border-vora bg-targeta px-3 py-1.5">
        <span aria-hidden="true" className="text-base leading-none">
          🔥
        </span>
        <span className="font-display text-sm font-bold text-tinta">{diesSeguits}</span>
      </span>
      <span className="bisell flex items-center gap-1 rounded-full border border-vora bg-targeta px-3 py-1.5">
        <span aria-hidden="true" className="text-base leading-none">
          🪙
        </span>
        <span className="font-display text-sm font-bold text-tinta">{saldoMonedes}</span>
      </span>
    </div>
  )
}
