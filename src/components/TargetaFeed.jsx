import { useState } from 'react'
import { faTempsPrecis } from '../lib/temps'
import IconaCor from './IconaCor'
import SeccioComentaris from './SeccioComentaris'

export default function TargetaFeed({
  completion,
  nomAutor,
  fotoUrl,
  jo,
  perfils,
  avatarUrls,
  onValidar,
  onAlternarLike,
  onAfegeixComentari,
  onAlternarLikeComentari,
}) {
  const [validant, setValidant] = useState(false)
  const [errorValidar, setErrorValidar] = useState('')

  const activitat = completion.activitats
  const pendent = completion.estat === 'pendent'
  const socJoQuiLHaFet = completion.creada_per === jo
  const potValidar = pendent && !socJoQuiLHaFet
  const likes = completion.likes ?? []
  const jaLiked = likes.some((like) => like.usuari_id === jo)

  async function handleConfirmar() {
    setValidant(true)
    setErrorValidar('')
    const err = await onValidar(completion.id)
    setValidant(false)
    if (err) setErrorValidar(err.message)
  }

  return (
    <article className="bisell overflow-hidden rounded-2xl border border-vora bg-targeta">
      <div className="flex items-center gap-3 p-4 pb-3">
        <span className="text-3xl leading-none">{activitat?.emoji}</span>
        <div className="min-w-0 flex-1">
          <p className="truncate font-display font-medium text-tinta">{activitat?.nom}</p>
          <p className="truncate font-body text-xs text-tinta-sec">
            {nomAutor} · {faTempsPrecis(completion.created_at)}
          </p>
        </div>
        <span
          className={`shrink-0 font-display text-2xl font-bold ${
            pendent ? 'text-tinta-sec' : 'text-panda'
          }`}
        >
          {completion.punts_base_snapshot}
        </span>
      </div>

      {fotoUrl ? (
        <img src={fotoUrl} alt="" className="aspect-square w-full object-cover" />
      ) : (
        <div className="flex aspect-square w-full items-center justify-center bg-paper">
          <span className="text-7xl">{activitat?.emoji}</span>
        </div>
      )}

      <div className="p-4">
        <div className="flex items-center justify-between gap-3">
          <div className="flex flex-wrap items-center gap-2">
            {pendent && (
              <span className="rounded-full border border-vora bg-vora px-2 py-0.5 font-body text-xs text-tinta-sec">
                pendent de validar
              </span>
            )}
            {potValidar && (
              <button
                type="button"
                onClick={handleConfirmar}
                disabled={validant}
                className="rounded-md bg-panda px-3 py-1.5 font-body text-sm font-medium text-paper disabled:opacity-50"
              >
                {validant ? 'Confirmant…' : 'Confirmar'}
              </button>
            )}
            {pendent && socJoQuiLHaFet && (
              <span className="font-body text-xs text-tinta-sec">Esperant confirmació</span>
            )}
          </div>

          <button
            type="button"
            onClick={() => onAlternarLike(completion.id)}
            aria-label={jaLiked ? 'Treure el like' : 'Donar like'}
            className={`flex shrink-0 items-center gap-1 font-body text-sm ${
              jaLiked ? 'text-panda' : 'text-tinta-sec'
            }`}
          >
            <IconaCor ple={jaLiked} />
            {likes.length > 0 && <span>{likes.length}</span>}
          </button>
        </div>
        {errorValidar && <p className="mt-2 text-xs text-calent">{errorValidar}</p>}
      </div>

      <SeccioComentaris
        comentaris={completion.comentaris ?? []}
        perfils={perfils}
        avatarUrls={avatarUrls}
        jo={jo}
        onAfegeix={(text, respostaA) => onAfegeixComentari(completion.id, text, respostaA)}
        onAlternarLike={(comentariId) => onAlternarLikeComentari(completion.id, comentariId)}
      />
    </article>
  )
}
