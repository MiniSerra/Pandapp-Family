// Inicials (màxim 2 lletres) per a l'avatar de fallback quan algú no té foto
// de perfil. Compartit entre Perfil.jsx (el propi) i PerfilMembre.jsx (el
// d'un altre membre de la família).
export function inicials(nom) {
  if (!nom) return '?'
  return nom
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase())
    .join('')
}
