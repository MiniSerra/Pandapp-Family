import { inicials } from '../lib/text'

const MIDES = {
  sm: 'h-8 w-8 text-xs',
  md: 'h-10 w-10 text-sm',
  lg: 'h-24 w-24 text-2xl',
}

// Cercle d'avatar amb bisell: foto si n'hi ha, inicials sobre --targeta si
// no. Compartit entre Perfil, PerfilMembre i SeccioComentaris.
export default function AvatarUsuari({ url, nom, mida = 'md' }) {
  return (
    <div
      className={`bisell shrink-0 overflow-hidden rounded-full border border-vora bg-targeta ${MIDES[mida]}`}
    >
      {url ? (
        <img src={url} alt="" className="h-full w-full object-cover" />
      ) : (
        <span className="flex h-full w-full items-center justify-center font-display font-bold text-tinta">
          {inicials(nom)}
        </span>
      )}
    </div>
  )
}
