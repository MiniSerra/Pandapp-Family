const ESTIL_PASTILLA = {
  neutre: 'border-vora bg-vora text-tinta',
  tebi: 'border-tebi-vora bg-tebi-fons text-tebi',
  calent: 'border-calent-vora bg-calent-fons text-calent',
}

const MIDES = {
  sm: 'px-2 py-0.5 text-xs',
  md: 'px-3 py-1 text-sm',
}

export default function PastillaPunts({ punts, calor, mida = 'md' }) {
  return (
    <span
      className={`bisell shrink-0 rounded-full border font-display font-bold ${MIDES[mida]} ${ESTIL_PASTILLA[calor]}`}
    >
      {punts}
    </span>
  )
}
