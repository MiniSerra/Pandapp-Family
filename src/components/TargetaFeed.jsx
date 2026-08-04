import { useState } from 'react'
import { faTempsPrecis, esPotAnullar } from '../lib/temps'
import IconaCor from './IconaCor'
import IconaPapereta from './IconaPapereta'
import BottomSheetConfirmar from './BottomSheetConfirmar'
import AvatarUsuari from './AvatarUsuari'
import SeccioComentaris from './SeccioComentaris'

// "Fet per X", "Fet per X i Y", "Fet per X, Y i Z".
function fetPerText(noms) {
  if (noms.length === 1) return `Fet per ${noms[0]}`
  if (noms.length === 2) return `Fet per ${noms[0]} i ${noms[1]}`
  return `Fet per ${noms.slice(0, -1).join(', ')} i ${noms[noms.length - 1]}`
}

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
  onEliminar,
  onConfirmarParticipacio,
}) {
  const [validant, setValidant] = useState(false)
  const [errorValidar, setErrorValidar] = useState('')
  const [confirmantEliminar, setConfirmantEliminar] = useState(false)
  const [eliminant, setEliminant] = useState(false)
  const [errorEliminar, setErrorEliminar] = useState('')
  const [confirmantParticipacio, setConfirmantParticipacio] = useState(false)
  const [errorParticipacio, setErrorParticipacio] = useState('')

  const activitat = completion.activitats
  const pendent = completion.estat === 'pendent'
  const socJoQuiLHaFet = completion.creada_per === jo
  const participacions = completion.participacions ?? []
  const participacioMeva = participacions.find((p) => p.usuari_id === jo)
  const socParticipant = Boolean(participacioMeva)
  // Tasques compartides: cap participant (etiquetat o no encara confirmat)
  // pot validar la completion, no només qui l'ha creat.
  const potValidar = pendent && !socParticipant
  const necessitoConfirmarParticipacio = participacioMeva && !participacioMeva.confirmat
  // "Bonus de ratxa" és una completion de sistema, no una reclamació: no té
  // sentit poder-la eliminar (veure comentari a anullar_completion).
  const potEliminar =
    socJoQuiLHaFet && activitat?.nom !== 'Bonus de ratxa' && esPotAnullar(completion.created_at)
  const likes = completion.likes ?? []
  const jaLiked = likes.some((like) => like.usuari_id === jo)

  const participantsConfirmats = participacions.filter((p) => p.confirmat)
  const participantsPendents = participacions.filter((p) => !p.confirmat)

  async function handleConfirmar() {
    setValidant(true)
    setErrorValidar('')
    const err = await onValidar(completion.id)
    setValidant(false)
    if (err) setErrorValidar(err.message)
  }

  async function handleEliminar() {
    setEliminant(true)
    setErrorEliminar('')
    const err = await onEliminar(completion.id)
    setEliminant(false)
    if (err) setErrorEliminar(err.message)
    else setConfirmantEliminar(false)
  }

  async function handleConfirmarParticipacio() {
    setConfirmantParticipacio(true)
    setErrorParticipacio('')
    const err = await onConfirmarParticipacio(completion.id)
    setConfirmantParticipacio(false)
    if (err) setErrorParticipacio(err.message)
  }

  return (
    <article className="bisell relative overflow-hidden rounded-2xl border border-vora bg-targeta">
      {potEliminar && (
        <button
          type="button"
          onClick={() => setConfirmantEliminar(true)}
          aria-label="Eliminar aquesta activitat"
          className="absolute top-3 right-3 z-10 flex h-7 w-7 items-center justify-center rounded-full bg-paper/70 text-calent"
        >
          <IconaPapereta />
        </button>
      )}

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
          {completion.pot_total}
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
        {participantsConfirmats.length > 0 && (
          <div className="mb-3 flex items-center gap-2">
            <div className="flex -space-x-2">
              {participantsConfirmats.map((p) => (
                <div key={p.usuari_id} className="rounded-full ring-2 ring-targeta">
                  <AvatarUsuari
                    url={avatarUrls[p.usuari_id]}
                    nom={perfils[p.usuari_id] ?? '?'}
                    mida="sm"
                  />
                </div>
              ))}
            </div>
            <p className="font-body text-xs text-tinta-sec">
              {fetPerText(participantsConfirmats.map((p) => perfils[p.usuari_id] ?? 'algú'))}
            </p>
          </div>
        )}

        {participantsPendents.length > 0 && (
          <p className="mb-3 font-body text-xs text-tebi">
            {participantsPendents.map((p) => perfils[p.usuari_id] ?? 'algú').join(', ')}{' '}
            {participantsPendents.length === 1 ? 'encara ha' : 'encara han'} de confirmar
          </p>
        )}

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
            {necessitoConfirmarParticipacio && (
              <button
                type="button"
                onClick={handleConfirmarParticipacio}
                disabled={confirmantParticipacio}
                className="rounded-md bg-panda px-3 py-1.5 font-body text-sm font-medium text-paper disabled:opacity-50"
              >
                {confirmantParticipacio ? 'Confirmant…' : 'Sí, hi era'}
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
        {errorParticipacio && <p className="mt-2 text-xs text-calent">{errorParticipacio}</p>}
      </div>

      <SeccioComentaris
        comentaris={completion.comentaris ?? []}
        perfils={perfils}
        avatarUrls={avatarUrls}
        jo={jo}
        onAfegeix={(text, respostaA) => onAfegeixComentari(completion.id, text, respostaA)}
        onAlternarLike={(comentariId) => onAlternarLikeComentari(completion.id, comentariId)}
      />

      {confirmantEliminar && (
        <BottomSheetConfirmar
          titol="Vols eliminar aquesta activitat?"
          missatge="Es restaran els punts i podràs tornar-la a reclamar."
          enviant={eliminant}
          error={errorEliminar}
          onCancelar={() => setConfirmantEliminar(false)}
          onConfirmar={handleEliminar}
        />
      )}
    </article>
  )
}
