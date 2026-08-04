import { useState } from 'react'
import { faTempsPrecis } from '../lib/temps'
import AvatarUsuari from './AvatarUsuari'
import IconaCor from './IconaCor'

function FilaComentari({
  comentari,
  nomAutor,
  avatarUrl,
  jo,
  onAlternarLike,
  mostraResponEnllac,
  onRespon,
}) {
  const likes = comentari.comentari_likes ?? []
  const jaLiked = likes.some((like) => like.usuari_id === jo)

  return (
    <div className="flex gap-2">
      <AvatarUsuari url={avatarUrl} nom={nomAutor} mida="sm" />
      <div className="min-w-0 flex-1">
        <div className="bisell rounded-2xl border border-vora bg-paper px-3 py-2">
          <p className="font-display text-xs font-medium text-tinta">{nomAutor}</p>
          <p className="break-words font-body text-sm text-tinta">{comentari.text}</p>
        </div>
        <div className="mt-1 flex items-center gap-3 px-1">
          <span className="font-body text-[11px] text-tinta-sec">
            {faTempsPrecis(comentari.created_at)}
          </span>
          <button
            type="button"
            onClick={() => onAlternarLike(comentari.id)}
            aria-label={jaLiked ? 'Treure el like' : 'Donar like'}
            className={`flex items-center gap-1 font-body text-[11px] ${
              jaLiked ? 'text-panda' : 'text-tinta-sec'
            }`}
          >
            <IconaCor ple={jaLiked} />
            {likes.length > 0 && <span>{likes.length}</span>}
          </button>
          {mostraResponEnllac && (
            <button
              type="button"
              onClick={onRespon}
              className="font-body text-[11px] text-tinta-sec"
            >
              Respon
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// Comentaris i respostes (un sol nivell) d'una completion del feed, amb
// like propi. El client escriu directament a `comentaris`/`comentari_likes`
// (RLS normal, sense funció intermèdia): no donen punts.
export default function SeccioComentaris({
  comentaris,
  perfils,
  avatarUrls,
  jo,
  onAfegeix,
  onAlternarLike,
}) {
  const [textNou, setTextNou] = useState('')
  const [enviant, setEnviant] = useState(false)
  const [error, setError] = useState('')
  const [respostaObertaA, setRespostaObertaA] = useState(null)
  const [textResposta, setTextResposta] = useState('')
  const [enviantResposta, setEnviantResposta] = useState(false)

  const arrels = comentaris
    .filter((c) => !c.resposta_a)
    .sort((a, b) => new Date(a.created_at) - new Date(b.created_at))

  function respostesDe(comentariId) {
    return comentaris
      .filter((c) => c.resposta_a === comentariId)
      .sort((a, b) => new Date(a.created_at) - new Date(b.created_at))
  }

  async function handleEnviar() {
    if (!textNou.trim()) return
    setEnviant(true)
    setError('')
    const err = await onAfegeix(textNou.trim(), null)
    setEnviant(false)
    if (err) {
      setError('Error de connexió. Torna-ho a provar.')
      return
    }
    setTextNou('')
  }

  async function handleEnviarResposta(arrelId) {
    if (!textResposta.trim()) return
    setEnviantResposta(true)
    const err = await onAfegeix(textResposta.trim(), arrelId)
    setEnviantResposta(false)
    if (!err) {
      setTextResposta('')
      setRespostaObertaA(null)
    }
  }

  return (
    <div className="border-t border-vora px-4 py-3">
      {arrels.length > 0 && (
        <div className="space-y-3">
          {arrels.map((arrel) => (
            <div key={arrel.id} className="space-y-2">
              <FilaComentari
                comentari={arrel}
                nomAutor={perfils[arrel.usuari_id] ?? 'algú'}
                avatarUrl={avatarUrls[arrel.usuari_id]}
                jo={jo}
                onAlternarLike={onAlternarLike}
                mostraResponEnllac
                onRespon={() =>
                  setRespostaObertaA((actual) => (actual === arrel.id ? null : arrel.id))
                }
              />

              {respostesDe(arrel.id).map((resposta) => (
                <div key={resposta.id} className="ml-10">
                  <FilaComentari
                    comentari={resposta}
                    nomAutor={perfils[resposta.usuari_id] ?? 'algú'}
                    avatarUrl={avatarUrls[resposta.usuari_id]}
                    jo={jo}
                    onAlternarLike={onAlternarLike}
                    mostraResponEnllac={false}
                  />
                </div>
              ))}

              {respostaObertaA === arrel.id && (
                <div className="ml-10 flex items-center gap-2">
                  <input
                    type="text"
                    value={textResposta}
                    onChange={(event) => setTextResposta(event.target.value)}
                    placeholder="Respon…"
                    className="bisell min-w-0 flex-1 rounded-full border border-vora bg-paper px-3 py-1.5 text-sm text-tinta placeholder:text-tinta-sec focus:outline-none"
                  />
                  <button
                    type="button"
                    onClick={() => handleEnviarResposta(arrel.id)}
                    disabled={enviantResposta || !textResposta.trim()}
                    className="shrink-0 rounded-full bg-panda px-3 py-1.5 font-body text-sm font-medium text-paper disabled:opacity-50"
                  >
                    Envia
                  </button>
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      <div className={`flex items-center gap-2 ${arrels.length > 0 ? 'mt-3' : ''}`}>
        <input
          type="text"
          value={textNou}
          onChange={(event) => setTextNou(event.target.value)}
          placeholder="Escriu un comentari…"
          className="bisell min-w-0 flex-1 rounded-full border border-vora bg-paper px-3 py-1.5 text-sm text-tinta placeholder:text-tinta-sec focus:outline-none"
        />
        <button
          type="button"
          onClick={handleEnviar}
          disabled={enviant || !textNou.trim()}
          className="shrink-0 rounded-full bg-panda px-3 py-1.5 font-body text-sm font-medium text-paper disabled:opacity-50"
        >
          {enviant ? '…' : 'Envia'}
        </button>
      </div>
      {error && <p className="mt-1 text-xs text-calent">{error}</p>}
    </div>
  )
}
