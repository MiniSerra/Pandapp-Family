const MIDA_ORIGINAL = 1080
const MIDA_THUMB = 300
const QUALITAT_WEBP = 0.7
const QUALITAT_JPEG_FALLBACK = 0.8

// Comprova si el navegador sap codificar WebP (canvas.toDataURL torna
// "data:image/png" si no ho suporta, en lloc de llançar un error).
function suportaWebp() {
  const canvas = document.createElement('canvas')
  canvas.width = 1
  canvas.height = 1
  return canvas.toDataURL('image/webp').startsWith('data:image/webp')
}

function carregaImatge(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file)
    const img = new Image()
    img.onload = () => {
      URL.revokeObjectURL(url)
      resolve(img)
    }
    img.onerror = () => {
      URL.revokeObjectURL(url)
      reject(new Error('No s\'ha pogut llegir la imatge.'))
    }
    img.src = url
  })
}

// Redimensiona perquè el costat més llarg faci com a màxim `midaMaxima`, sense
// ampliar imatges més petites.
function dibuixaRedimensionat(img, midaMaxima) {
  const escala = Math.min(1, midaMaxima / Math.max(img.width, img.height))
  const amplada = Math.round(img.width * escala)
  const alcada = Math.round(img.height * escala)

  const canvas = document.createElement('canvas')
  canvas.width = amplada
  canvas.height = alcada
  canvas.getContext('2d').drawImage(img, 0, 0, amplada, alcada)
  return canvas
}

function canvasABlob(canvas, tipus, qualitat) {
  return new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => {
        if (blob) resolve(blob)
        else reject(new Error('No s\'ha pogut generar la imatge comprimida.'))
      },
      tipus,
      qualitat,
    )
  })
}

// Comprimeix una foto de l'input de càmera al navegador, amb <canvas>, sense
// llibreries noves. Retorna els dos blobs (original 1080px i miniatura 300px)
// més el tipus MIME i l'extensió reals fets servir, ja que si el navegador no
// suporta WebP es fa fallback a JPEG.
export async function comprimirImatge(file) {
  const img = await carregaImatge(file)
  const ambWebp = suportaWebp()
  const tipus = ambWebp ? 'image/webp' : 'image/jpeg'
  const qualitat = ambWebp ? QUALITAT_WEBP : QUALITAT_JPEG_FALLBACK
  const extensio = ambWebp ? 'webp' : 'jpg'

  const [original, thumb] = await Promise.all([
    canvasABlob(dibuixaRedimensionat(img, MIDA_ORIGINAL), tipus, qualitat),
    canvasABlob(dibuixaRedimensionat(img, MIDA_THUMB), tipus, qualitat),
  ])

  return { original, thumb, tipus, extensio }
}

// `foto_url`/`thumb_url` guarden la URL signada que hi havia en el moment
// de reclamar (caduca als 60 min), no la ruta al bucket. Per poder-la
// tornar a signar cal recuperar la ruta original, que la URL ja conté
// abans del "?token=". Compartit entre Feed.jsx i Perfil.jsx.
export function extreuRutaDesDeUrlSignada(urlSignada, bucket) {
  try {
    const url = new URL(urlSignada)
    const prefix = `/storage/v1/object/sign/${bucket}/`
    const index = url.pathname.indexOf(prefix)
    if (index === -1) return null
    return decodeURIComponent(url.pathname.slice(index + prefix.length))
  } catch {
    return null
  }
}
