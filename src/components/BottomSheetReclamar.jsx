import { useState } from 'react'
import { supabase } from '../lib/supabase'

// TODO (següent pas): compressió al navegador (canvas -> 1080px -> WebP 0.7)
// i pujada real al bucket privat de Storage. De moment el selector de foto
// no envia enlloc; per això es desactiva el botó quan l'activitat requereix
// foto, en lloc de cridar reclamar_activitat amb p_foto_url = null (que
// donaria l'error "requereix foto" del servidor de manera confusa).
const PUJADA_FOTOS_IMPLEMENTADA = false

export default function BottomSheetReclamar({ activitat, onTancar, onExit }) {
  const [enviant, setEnviant] = useState(false)
  const [error, setError] = useState('')

  const potReclamar = !activitat.requereix_foto || PUJADA_FOTOS_IMPLEMENTADA

  async function handleReclamar() {
    setError('')
    setEnviant(true)

    const { error: rpcError } = await supabase.rpc('reclamar_activitat', {
      p_activitat_id: activitat.id,
      p_foto_url: null,
      p_thumb_url: null,
    })

    if (rpcError) {
      setEnviant(false)
      setError(rpcError.message)
      return
    }

    onExit(activitat.id)
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-end bg-paper/70"
      onClick={onTancar}
    >
      <div
        className="bisell w-full rounded-t-2xl border border-vora bg-targeta p-6 pb-8"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="mb-4 flex items-center gap-3">
          <span className="text-4xl">{activitat.emoji}</span>
          <h2 className="font-display text-xl font-medium text-tinta">
            {activitat.nom}
          </h2>
        </div>

        {activitat.requereix_foto && (
          <div className="mb-4">
            <label
              htmlFor="foto"
              className="mb-1 block text-sm font-medium text-tinta-sec"
            >
              Foto
            </label>
            <input
              id="foto"
              type="file"
              accept="image/*"
              capture="environment"
              className="block w-full text-sm text-tinta"
            />
            {!PUJADA_FOTOS_IMPLEMENTADA && (
              <p className="mt-2 text-sm text-tebi">
                Puja de fotos: al següent pas.
              </p>
            )}
          </div>
        )}

        {error && <p className="mb-3 text-sm text-calent">{error}</p>}

        <button
          type="button"
          onClick={handleReclamar}
          disabled={enviant || !potReclamar}
          className="w-full rounded-md bg-panda px-4 py-3 text-base font-medium text-paper disabled:opacity-50"
        >
          {enviant ? 'Enviant…' : 'Ho he fet'}
        </button>
      </div>
    </div>
  )
}
