import { useEffect, useRef, useState } from 'react'

// Distància real d'estirada (px) necessària per disparar el refresc.
const LLINDAR_PX = 70
// "Efecte goma": cal estirar més px reals que els que es mouen visualment.
const RESISTENCIA = 2.2
const MAX_ESTIRADA_PX = 90

// Pull-to-refresh reutilitzable: només actua quan el gest comença amb la
// pàgina ja al capdamunt (window.scrollY === 0) i l'usuari estira cap
// avall. `onRefrescar` és la mateixa funció de càrrega que cada pàgina ja
// crida en muntar-se — es crida tal qual, sense inventar-ne una de
// silenciosa nova (veure CLAUDE.md, si mai es documenta aquí: la pàgina
// pot mostrar el seu propi estat de "carregant" mentre dura). Els
// listeners són nadius (no els sintètics de React) perquè calen
// `{ passive: false }` a touchmove per poder cridar preventDefault() i
// evitar el "bounce" natiu d'iOS mentre s'estira.
export default function PullToRefresh({ onRefrescar, children }) {
  const contenidorRef = useRef(null)
  const estatRef = useRef({ yInicial: 0, actiu: false, estirada: 0, refrescant: false })
  const [estirada, setEstirada] = useState(0)
  const [refrescant, setRefrescant] = useState(false)

  useEffect(() => {
    const node = contenidorRef.current
    if (!node) return

    function handleTouchStart(event) {
      const estat = estatRef.current
      if (estat.refrescant || window.scrollY > 0) {
        estat.actiu = false
        return
      }
      estat.yInicial = event.touches[0].clientY
      estat.actiu = true
    }

    function handleTouchMove(event) {
      const estat = estatRef.current
      if (!estat.actiu) return

      if (window.scrollY > 0) {
        estat.actiu = false
        estat.estirada = 0
        setEstirada(0)
        return
      }

      const diferencia = event.touches[0].clientY - estat.yInicial
      if (diferencia <= 0) {
        estat.estirada = 0
        setEstirada(0)
        return
      }

      // Evita el bounce natiu del navegador mentre dura el nostre gest.
      event.preventDefault()
      const nova = Math.min(diferencia / RESISTENCIA, MAX_ESTIRADA_PX)
      estat.estirada = nova
      setEstirada(nova)
    }

    async function handleTouchEnd() {
      const estat = estatRef.current
      if (!estat.actiu) return
      estat.actiu = false

      if (estat.estirada < LLINDAR_PX) {
        estat.estirada = 0
        setEstirada(0)
        return
      }

      estat.refrescant = true
      setRefrescant(true)
      try {
        await onRefrescar()
      } catch {
        // Silenciós expressament: si l'API falla en el refresc, es deixen
        // les dades tal com estaven, sense error intrusiu.
      } finally {
        estat.refrescant = false
        estat.estirada = 0
        setRefrescant(false)
        setEstirada(0)
      }
    }

    node.addEventListener('touchstart', handleTouchStart, { passive: true })
    node.addEventListener('touchmove', handleTouchMove, { passive: false })
    node.addEventListener('touchend', handleTouchEnd, { passive: true })
    node.addEventListener('touchcancel', handleTouchEnd, { passive: true })

    return () => {
      node.removeEventListener('touchstart', handleTouchStart)
      node.removeEventListener('touchmove', handleTouchMove)
      node.removeEventListener('touchend', handleTouchEnd)
      node.removeEventListener('touchcancel', handleTouchEnd)
    }
  }, [onRefrescar])

  const alcadaIndicador = refrescant ? LLINDAR_PX : estirada

  return (
    <div ref={contenidorRef}>
      <div
        className="flex items-center justify-center overflow-hidden transition-[height] duration-150 ease-out"
        style={{ height: alcadaIndicador }}
      >
        <span
          className={`bisell flex h-9 w-9 items-center justify-center rounded-full border border-vora bg-targeta text-lg ${
            refrescant ? 'animate-spin' : ''
          }`}
          style={
            refrescant
              ? undefined
              : {
                  transform: `rotate(${(estirada / LLINDAR_PX) * 360}deg)`,
                  opacity: Math.min(estirada / LLINDAR_PX, 1),
                }
          }
        >
          🐼
        </span>
      </div>
      {children}
    </div>
  )
}
