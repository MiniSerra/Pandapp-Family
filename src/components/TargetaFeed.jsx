import { useState } from 'react'
import { faTempsPrecis } from '../lib/temps'

function IconaCor({ ple }) {
  if (ple) {
    return (
      <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor">
        <path d="M11.645 20.91l-.007-.003-.022-.012a15.247 15.247 0 01-.383-.218 25.18 25.18 0 01-4.244-3.17C4.688 15.36 2.25 12.174 2.25 8.25 2.25 5.322 4.714 3 7.688 3A5.5 5.5 0 0112 5.052 5.5 5.5 0 0116.313 3c2.973 0 5.437 2.322 5.437 5.25 0 3.925-2.438 7.111-4.739 9.256a25.175 25.175 0 01-4.244 3.17 15.247 15.247 0 01-.383.219l-.022.012-.007.004-.003.001a.752.752 0 01-.704 0l-.003-.001z" />
      </svg>
    )
  }
  return (
    <svg
      viewBox="0 0 24 24"
      width="18"
      height="18"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinejoin="round"
    >
      <path d="M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z" />
    </svg>
  )
}

export default function TargetaFeed({
  completion,
  nomAutor,
  fotoUrl,
  jo,
  onValidar,
  onAlternarLike,
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
    </article>
  )
}
