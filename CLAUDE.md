# Pandapp Family

App familiar de productivitat i benestar. La família guanya punts fent tasques de
casa, de cura del gat (**Panda**) i personals. Hi ha rànquing, feed social amb fotos
i objectius col·lectius.

**Nom oficial:** Pandapp Family · **Nom curt (icona):** Pandapp

---

## Instruccions per a Claude Code

- **Parla i escriu comentaris en català.** Tota la interfície va en català.
- **Una funcionalitat per sessió.** No implementis diverses coses alhora.
- **Commits petits i freqüents** després de cada peça que funcioni.
- **Mai posis claus secretes al client.** La clau publishable de Supabase
  (`sb_publishable_...`) sí que pot anar al frontend (és pública per disseny).
  La clau secreta (`sb_secret_...`) i la clau de Gemini només poden viure dins
  d'edge functions.
- **Les polítiques de RLS s'han de verificar sempre** amb una prova real: entrar amb
  un usuari i intentar llegir dades d'un altre ha de tornar buit.
- Si una decisió de disseny no és a aquest fitxer, **pregunta abans d'inventar-la**.
- JavaScript, no TypeScript. Res de dependències noves sense justificar-ho.

---

## Stack

| Capa | Tecnologia |
|---|---|
| Frontend | React + Vite (JavaScript), PWA instal·lable |
| Estils | Tailwind CSS |
| Backend | Supabase (Postgres + Auth + Storage + Edge Functions) |
| Cron | pg_cron dins de Supabase |
| Hosting | Vercel |
| IA | API de Gemini (model Flash), només des d'edge functions |

Tot ha de funcionar dins de les **capes gratuïtes**. Usuaris previstos: 4-6 persones.

---

## Autenticació i seguretat

- **No hi ha registre públic.** Els comptes es creen manualment des del panell de
  Supabase. Si algun dia cal registre, serà amb codi d'invitació validat en una edge
  function, mai al client.
- **RLS activat a totes les taules.** Regla base: només pots llegir i escriure files
  de la teva família.
- **El bucket de fotos és privat.** S'hi accedeix només amb URLs signades que
  caduquen. Mai públic.

---

## Sistema de punts

### Paràmetres de cada activitat

Cada activitat del catàleg té cinc números que en defineixen el comportament:

| Camp | Significat |
|---|---|
| `punts_base` | punts si es fa dins del període normal |
| `cooldown_h` | hores durant les quals **no es pot reclamar** |
| `periode_normal_h` | fins aquí, punts base |
| `k_dia` | quant pugen els punts per cada dia passat el període (%) |
| `sostre` | multiplicador màxim |

El cooldown i l'escalada són **de la tasca, no de la persona**: si algú neteja el
sorral, queda bloquejat per a tothom.

**Excepció — `cooldown_individual` (fase 3):** per a tasques on cadascú té el
seu propi "exemplar" (el llit, l'habitació pròpia), aquest principi es giraria
en contra: que algú faci la seva no hauria de bloquejar ni desescalar la dels
altres. Amb aquest flag a `true`, el cooldown i l'escalada passen a ser propis
de cada usuari. Activades de moment a **Fer el llit**, **Escombrar o aspirar
una estança** i **Ordenar la teva habitació** (`supabase/seed.sql`). Per
defecte `false` (comportament de sempre).

### Escalada per oblit

Passat `periode_normal_h`, els punts creixen de manera contínua per dia:

```
punts = punts_base × (1 + k_dia × dies_passats_del_periode)   [limitat per sostre]
```

**Regla de disseny:** com més urgent és la tasca, **més de pressa puja i abans es
queda quieta**. Això evita que la gent esperi per cobrar més (campament). El sorral
arriba al seu sostre en 2 dies; fregar el terra triga 19.

Les **activitats personals no tenen escalada**. Que ningú hagi llegit en una setmana
no fa que llegir valgui més.

**Implementat a fase 2:** el càlcul es fa dins de `reclamar_activitat`, mai al
client, amb arrodoniment normal (no cap amunt — això és per al repartiment de
tasques compartides, fase 3). El resultat es guarda a
`completions.punts_base_snapshot`, que a partir d'ara ja no és
`activitats.punts_base` pla.

### Ratxes

- **Dia complert** = has arribat al llindar diari de punts (per defecte 100,
  configurable per persona).
- Bonus diari: **+5 punts × dies de ratxa**, amb topall a **+50**.
- Fites: **dia 7 → +100**, **dia 14 → +200**, **dia 30 → +500**.
- **Mai multiplicadors sobre els punts del dia** — dispararien el rànquing i el
  farien injugable.
- **Escut de ratxa:** un dia de gràcia al mes (o comprable amb monedes) que evita
  perdre la ratxa. Sense això, qui perd una ratxa llarga abandona l'app.

**Implementat a fase 3:** tot dins de `processar_punts_validats` (mai al
client). De moment només el dia de gràcia automàtic al mes; comprar-ne un amb
monedes no està fet. `ultim_dia_complert`/`escut_usat_mes` són dates locals
d'Europe/Madrid, no instants — una ratxa és per dies de calendari.

### Dues monedes

- **Punts de rànquing:** no es gasten mai. Són la puntuació de la temporada.
- **Monedes:** es guanyen alhora que els punts i **es gasten** en recompenses reals
  pactades a casa (lliurar-se d'un torn, triar el sopar, triar la pel·lícula...).

Sense la segona moneda l'app és només una taula de rècords i s'esgota.

### Rànquings i temporades

- Rànquing **diari**, **setmanal** i **mensual**.
- El mes és una **temporada**: es tanca amb guanyador i títol, i es reseteja. Ningú
  queda despenjat per sempre.
- **Fus horari:** totes les agrupacions per dia, setmana i mes (rànquings, ratxes,
  límit personal diari) es calculen en **hora local d'Espanya (Europe/Madrid)**,
  mai en UTC. `date_trunc('day', now())` directament fa que el dia comenci a les
  2h de la matinada. La funció SQL `inici_periode_local(unitat, moment)` ho
  centralitza i s'ha de fer servir sempre en lloc de truncar a mà.
- **Implementació fase 1:** els tres rànquings es calculen **en client**
  (`src/lib/ranquing.js`), sense funció SQL ni vista pròpia. Es llegeixen les
  `participacions` (amb la seva `completion`) de la família dels últims ~35
  dies i se sumen `punts_assignats` per usuari en JavaScript, filtrant cada
  rànquing per `iniciPeriodeLocal('day' | 'week' | 'month')` — la mateixa
  rèplica en JS de `inici_periode_local` que ja fa servir el progrés diari
  d'`Activitats.jsx` (`src/lib/temps.js`). Surten tots els membres de la
  família encara que tinguin 0 punts en el període.

### Objectiu col·lectiu

- Barra de progrés familiar setmanal (~1.500-1.800 punts per a una família de 4).
- Si s'assoleix, **premi real per a tothom**. El guanyador individual no s'emporta
  el premi: és de tots o de ningú.
- L'estat del Panda pot **bloquejar el premi**: si el sorral porta més de 2 dies
  brut, no hi ha premi encara que s'hagin fet els punts.

---

## Estat del Panda i de la casa

Pantalla amb indicadors visuals que es degraden si no es fan les tasques:

- **Panda**: menjar, aigua, sorral, joc. Verd / groc / vermell segons hores.
- **Casa**: cuina, bany, menjador, roba.

No és decoració: és el que converteix una llista de tasques en una responsabilitat.

---

## Tasques compartides

**Implementat a fase 3.** En reclamar una tasca es poden **etiquetar altres
persones** que hi han participat.

El pot es multiplica **abans** de repartir-se a parts iguals:

| Persones | Multiplicador del pot | Per cap (tasca de 60) |
|---|---|---|
| 1 | x1 | 60 |
| 2 | x1.4 | 42 |
| 3 | x1.8 | 36 |
| 4 | x2.2 | 33 |

Sense aquesta prima, cooperar sortiria a compte de no fer-ho mai.

**Regles:**
- L'etiquetat ha de **confirmar** ("sí, hi era") perquè els punts s'abonin.
- El **validador no pot ser cap participant** (ni qui ha reclamat ni cap
  etiquetat, hagi confirmat o no).
- Camp `compartible` per activitat. Fer el llit, posar menjar al gat o llegir **no**
  són compartibles. Regla: si la tasca no es fa realment més ràpida entre dos, no ho és.
- **Arrodoniment avall** per persona; el residu (pot menys la suma repartida)
  se l'emporta qui ha reclamat (`es_qui_puja`).
- L'objectiu col·lectiu suma el **pot sencer**, no la part de cadascú.

**`estat` (de la completion) i `confirmat` (de cada participació) són dues
coses diferents:** `estat` diu si la completion en conjunt ja compta
("s'ha validat"); `confirmat` diu si un participant CONCRET hi era de
veritat. Els punts d'un participant només sumen a rànquings i progrés quan
totes dues coses són certes (`completions.estat = 'validada' AND
participacions.confirmat = true`) — filtrat al client a `ranquing.js` i
`Activitats.jsx`, igual que ja es feia només amb `estat`.

**Validació automàtica quan els participants cobreixen tota la família
(`confirmar_participacio`):** si en confirmar un etiquetat ja no queda
ningú pendent I el conjunt de participants (qui reclama + etiquetats) és
exactament tots els membres de la família, no pot quedar ningú extern per
validar-la — es valida sola en aquest mateix moment (`validada_per` és qui
acaba de fer l'última confirmació) i es processen ratxa/monedes de tots els
participants de cop. Si en queda algú de la família fora dels participants,
la completion es queda `'pendent'` fins que aquesta persona (que no hi era)
la validi amb `validar_completion` com sempre. Si un participant confirma
QUAN la completion ja estava validada externament (algú de fora ho ha fet
abans que ell confirmés), és en aquest moment que es processen la seva
ratxa i monedes — no abans, encara que `estat` ja fos `'validada'`.
`reclamar_activitat` accepta un 4t paràmetre `p_participants_ids` (filtra
sol els que no siguin de la família o coincideixin amb qui reclama).

**Interfície:** interruptor "Activitat compartida" a `BottomSheetReclamar.jsx`
(només si `activitat.compartible`), amb selector multi-selecció dels altres
membres. Al feed (`TargetaFeed.jsx`), cada targeta mostra els avatars dels
participants ja confirmats (cercles lleugerament solapats) amb "Fet per
{noms}", i si en queda algun de pendent, un avís ("X encara ha de
confirmar") — amb un botó "Sí, hi era" (`confirmar_participacio`) visible
només per a qui hi és etiquetat i encara no ha confirmat. És una acció
diferent del botó "Confirmar" (`validar_completion`), que ara només surt
per a qui NO és participant.

---

## Torns rotatius

Algunes tasques són obligacions, no oportunitats (plats, escombraries, sorral,
rentadora, WC, compra setmanal). Tenen torn assignat.

Si algú **cobreix el torn d'un altre**, s'emporta els punts **+50%**. Aquest bonus
no s'acumula amb la prima de grup: s'aplica el més alt dels dos.

---

## Validació de tasques

- **La foto sempre és opcional, per a totes les activitats** (fase 3): a
  `reclamar_activitat` no bloqueja mai que no n'hi hagi, i a la interfície
  el selector de foto ("Afegir foto (opcional)") surt sempre, també a les
  personals, que abans no en tenien l'opció. `activitats.requereix_foto` es
  manté a la taula sense fer res — no es fa servir enlloc, es guarda per si
  algun dia serveix per suggerir quan convé posar-ne.
- Les **personals** tenen un **límit de 60 punts al dia**.
- **Validació creuada (backend fet a fase 2):** una `completion` neix
  `'pendent'`, excepte les **personals**, que neixen `'validada'` a l'instant
  (ningú més les pot confirmar). Un altre membre de la família —**mai cap
  participant**, ni qui l'ha creat ni cap etiquetat d'una tasca compartida
  (fase 3)— la valida amb `validar_completion`, que posa `estat = 'validada'`
  i `validada_per`. Els punts d'una completion `'pendent'` **no compten** al
  progrés del dia ni als rànquings fins que es valida (filtrat al client, a
  `Activitats.jsx` i `ranquing.js`). **Encara falta la interfície** (el feed)
  per validar des de l'app; de moment només des de l'SQL Editor cridant
  `select public.validar_completion('<id>')`.
- El timestamp el posa el servidor, mai el mòbil.
- **Cooldown per tasca (fase 1):** en reclamar, es mira l'última completació
  d'aquella activitat i es bloqueja si no han passat `cooldown_h`. És per
  activitat, no per usuari (si algú neteja el sorral, queda bloquejat per a
  tothom) — **excepte si `cooldown_individual = true`** (fase 3), on cada
  usuari té la seva pròpia última completació. Sense el cas general, el
  rànquing queda inservible des del primer dia.
  **Les activitats `es_personal = true` també fan servir el cooldown
  individual, encara que `cooldown_individual` quedi a `false`** (fase 3):
  una activitat personal és individual per definició — que Joel llegeixi no
  pot bloquejar que Raquel llegeixi. `reclamar_activitat` combina els dos
  flags amb un OR; `Activitats.jsx` fa el mateix càlcul en client.
- **Anul·lació:** es pot desfer una reclamació pròpia amb `anullar_completion`
  dins dels primers 15 minuts. Retorna `foto_url`/`thumb_url` perquè el client
  esborri els fitxers del bucket. Si la completion ja estava `'validada'`,
  també reverteix les monedes i la ratxa que hagués donat
  `processar_punts_validats`: resta les monedes d'aquesta completion concreta
  si va ser ella qui va fer creuar el llindar diari, i decrementa
  `dies_seguits` (mai per sota de 0) només si sense ella el dia ja no arriba
  al llindar. Es recalcula amb l'estat actual assumint que no ha canviat res
  més des de la validació (raonable dins de 15 minuts); casos límit (dos
  creuaments el mateix dia, escut gastat en un dia anterior) queden resolts
  amb una aproximació, mai amb saldo o `dies_seguits` negatius — és
  intencionadament una aproximació de fase 3, no un recàlcul exacte. Les
  completions de "Bonus de ratxa" (veure "Ratxes") mai reverteixen res en
  esborrar-se — no són una reclamació real, mai poden ser "les que creuen
  el llindar" — i la papereta no s'hi mostra a la interfície.
  **Interfície feta:** icona de paperera (`--calent`) a les targetes pròpies
  de menys de 15 minuts, tant al feed (`TargetaFeed.jsx`) com a l'historial
  del propi perfil (`TargetaHistorial.jsx`/`Perfil.jsx`; no a `PerfilMembre.jsx`,
  que és de només lectura, ni a les completions de "Bonus de ratxa"), amb
  confirmació (`BottomSheetConfirmar.jsx`) abans d'esborrar.
  `src/lib/completions.js` centralitza la crida a `anullar_completion` i
  l'esborrat de les fotos del bucket.

---

## Feed social

- Entrada per completació, amb foto, activitat, punts i participants.
- Les tasques compartides són **una sola entrada** amb totes les cares.
- **Els likes no donen punts** (si en donessin, us els regalaríeu). Alimenten un
  comptador d'"aplaudiments rebuts" al perfil.
- Els esdeveniments del sistema també hi surten: activitats noves aprovades,
  objectiu setmanal assolit, fites de ratxa.
- **Comentaris (fase 3):** cada entrada del feed té el seu fil de comentaris,
  amb respostes (**un sol nivell**: respondre una resposta l'enganxa igualment
  al mateix fil) i like propi per comentari. Com els likes, no donen punts ni
  passen per cap funció `security definer` — el client escriu directament a
  `comentaris`/`comentari_likes` amb RLS normal. Implementat a
  `SeccioComentaris.jsx` (`src/pages/Feed.jsx` en carrega els comentaris niats
  dins de la mateixa consulta de `completions`, i les URLs signades dels
  avatars de tota la família en bloc).

---

## Fotos

- **Sempre opcional, per a totes les activitats (fase 3).** El selector de
  foto surt sempre a `BottomSheetReclamar.jsx` com "Afegir foto (opcional)",
  també a les personals (abans no en tenien l'opció). Veure "Validació de
  tasques".
- **Compressió al navegador abans de pujar:** canvas → redimensionar a 1080px →
  WebP qualitat 0.7 (~150 KB), amb fallback a JPEG qualitat 0.8 si el navegador
  no suporta WebP. Miniatura de 300px per al feed, mateix format/qualitat.
  Implementat a `src/lib/fotos.js` (`comprimirImatge`).
- **Selector de fitxer sense `capture`:** els inputs de foto (reclamar tasca,
  canviar avatar) són `<input type="file" accept="image/*">` sense l'atribut
  `capture`. Amb `capture="environment"`/`"user"` el mòbil obria la càmera
  directament i no deixava triar una foto ja feta de la galeria; sense
  `capture`, el selector natiu ofereix totes dues opcions.
- **Bucket privat `fotos-tasques`.** Esquema de ruta:
  `{familia_id}/{identificador}/original.<ext>` i
  `{familia_id}/{identificador}/thumb.<ext>` (`<ext>` és `webp` o, en fallback,
  `jpg`). `{identificador}` **no** ha de coincidir amb l'id real de la
  `completion`: com que el client no el coneix fins que `reclamar_activitat`
  s'executa, es fa servir una carpeta temporal `pendent-{uuid}` generada al
  client (`crypto.randomUUID()`). Un cop pujades les fotos no es mouen ni es
  renombren encara que la reclamació tingui èxit — l'únic que verifiquen les
  polítiques de RLS (`supabase/storage.sql`) és que el primer segment de la
  ruta sigui la `familia_id` de qui puja/llegeix/esborra. **Política de
  DELETE (fase 3):** calia afegir-la explícitament — sense ella
  `storage.remove()` no fa res (no torna cap error, simplement no esborra
  cap fila) i queden fitxers orfes. Necessària tant per al cleanup quan
  `reclamar_activitat` falla després de pujar la foto com per a
  `anullar_completion`.
- **Bucket privat `avatars` (fase 3).** Un sol fitxer per usuari, sempre a
  `{familia_id}/{usuari_id}.webp`, sobreescrit amb `upload(..., { upsert: true })`
  en lloc d'acumular-se com a `fotos-tasques`. Com que aquí la ruta sí
  identifica exactament de qui és l'avatar, `supabase/avatars.sql` exigeix
  que `INSERT`/`UPDATE` coincideixin amb tota la ruta pròpia, no només amb
  el primer segment (`familia_id`). `profiles.avatar_url` guarda la
  **ruta** (no una URL signada): es torna a signar cada vegada que es
  llegeix, a `Perfil.jsx`. Només cal comprimir el thumb de 300px, no
  l'original de 1080px. El bucket el crea l'admin manualment des del
  panell, igual que `fotos-tasques`.
- **URLs signades:** es generen amb `createSignedUrl`, caducitat de 60 minuts.
  N'hi ha prou perquè `reclamar_activitat` les guardi a `foto_url`/`thumb_url`
  just després de pujar; el feed i el perfil n'hauran de generar una de nova
  en cada visualització futura (una URL signada caducada no es pot "refrescar"
  sola).
- **Esborrat automàtic als 14 dies** amb cron: posar `foto_url = NULL`
  **i esborrar el fitxer del bucket**. Si només es neteja la base de dades, queden
  fitxers orfes acumulant-se fins a omplir la quota.
- **L'històric de tasques no s'esborra mai.** Punts, dates, qui i validació es
  conserven per sempre. Només desapareix la imatge.
- Al feed, les entrades sense foto mostren la icona (o l'emoji) de l'activitat.
- **Ordre pujada foto / reclamació:** la foto es puja al bucket abans de cridar
  `reclamar_activitat` (cal la URL per passar-la a la funció). Si la crida falla
  (p. ex. cooldown actiu), el frontend **ha d'esborrar** el fitxer que acaba de
  pujar, si no queden fitxers orfes al bucket. Implementat a
  `BottomSheetReclamar.jsx`: si `reclamar_activitat` retorna error, es criden
  `storage.remove()` sobre `original` i `thumb` abans de mostrar l'error a
  l'usuari. Si la pròpia pujada (o la generació de la URL signada) falla abans
  d'arribar a cridar `reclamar_activitat`, es mostra l'error de connexió i no
  es crida la funció.

---

## Propostes i votacions

Els membres poden proposar canvis al catàleg des de l'app.

**Tres tipus:** crear activitat · modificar punts d'una existent · retirar-ne una.

**Formulari:** nom, emoji, descripció, categoria i punts. Els punts **no es demanen
en blanc**: dos sliders (quant es triga / quant fàstic fa) generen una suggerència
coherent amb el catàleg. El cooldown i l'escalada s'omplen per defecte segons la
categoria i queden en "opcions avançades".

**Regles de votació:**
- **Majoria absoluta** de tota la família, no només dels que voten.
- El vot del proposant compta com a sí.
- **Caduca als 72h.** No votar és abstenir-se.
- **Màxim 2 propostes actives per persona.**
- Qui vota NO pot suggerir opcionalment **quants punts hi posaria**. El proposant veu
  les suggerències i pot rellançar la proposta amb un botó.

**Antiinflació:**
- Les activitats aprovades **s'activen la setmana següent**, no immediatament.
- A la pantalla de vot es mostren 2-3 activitats del catàleg amb punts semblants.
- Revisió mensual: l'app llista les 3 activitats més i menys reclamades i suggereix
  ajustar-les.

---

## Resums amb IA

- Es generen **una vegada per nit amb cron**, es guarden a taula, i l'app només
  llegeix text ja escrit. Mai cridar l'API des del client.
- S'envien **només estadístiques agregades en JSON**. Mai fotos ni dades personals.
- Model Flash de Gemini, clau dins de l'edge function.
- **Resum familiar (públic):** en positiu i en col·lectiu. No assenyala ningú.
- **Resum personal (privat):** només el veu el seu propietari. Aquí sí que hi va
  el "què has fet i què pots millorar".

Assenyalar públicament qui fa menys fa mal de veritat en una família. El rànquing
ja ho diu amb números freds, que és molt més fàcil de païr.

---

## Model de dades (esborrany)

```
families            id, nom, llindar_diari_defecte, objectiu_setmanal
profiles            id (=auth.uid), familia_id, nom, avatar_url, llindar_diari
activitats          id, familia_id, categoria, nom, emoji, descripcio,
                    punts_base, cooldown_h, cooldown_individual, periode_normal_h,
                    k_dia, sostre, compartible, requereix_foto, es_personal, es_torn,
                    estat (proposta|activa|retirada), versio, proposada_per,
                    activa_des_de
completions         id, activitat_id, familia_id, creada_per, versio_punts,
                    punts_base_snapshot, pot_total, foto_url, thumb_url,
                    validada_per, estat (pendent|validada), created_at
participacions      completion_id, usuari_id, punts_assignats, confirmat,
                    es_qui_puja
likes               completion_id, usuari_id, created_at
comentaris          id, completion_id, usuari_id, resposta_a (null = arrel),
                    text, created_at
comentari_likes     comentari_id, usuari_id, created_at
propostes           id, tipus, activitat_id, payload, proposada_per, estat, caduca
vots                proposta_id, usuari_id, vot, punts_suggerits, created_at
torns               activitat_id, usuari_id, setmana
monedes             usuari_id, saldo
ratxes              usuari_id, dies_seguits, ultim_dia_complert (date local),
                    escut_disponible, escut_usat_mes (date local)
recompenses         id, familia_id, nom, cost
bescanvis           recompensa_id, usuari_id, created_at
resums              id, familia_id, usuari_id (null = familiar), periode, text
```

**Important:** els punts van a `participacions`, no a `completions`. Si es fa al
revés, cada consulta del rànquing ha de dividir i apareixen errors d'arrodoniment.

**Important:** `punts_base_snapshot` (i `versio_punts`) a `completions` congelen
els punts que valia l'activitat quan es va fer. Si es canvien els punts a mitja
temporada, l'històric no s'ha de recalcular sol.

**Important:** `monedes` i `ratxes` (fase 3) només es modifiquen des de
`processar_punts_validats`, cridada des de `reclamar_activitat` (personals,
validades a l'instant) i des de `validar_completion` (la resta). El bonus de
ratxa i les fites es materialitzen com una `completion` més ("Bonus de ratxa",
activitat de sistema per família, `estat = 'retirada'` perquè no surti al
catàleg ni es pugui reclamar a mà).

**Important:** `familia_id` i `creada_per` estan denormalitzats a `completions`
perquè les polítiques de RLS i les consultes de feed/rànquing no calgui que facin
`JOIN` a `activitats` per saber de qui o de quina família és cada fila.

**Important:** `likes`, `comentaris` i `comentari_likes` són les úniques taules
(a banda de les de fases futures) on el client escriu directament amb
polítiques RLS normals, sense passar per cap funció `security definer`. Cap
de les tres dona punts ni afecta cap regla de negoci — només compten
"aplaudiments" o guarden text—, així que no calia protegir-les darrere d'una
funció com `reclamar_activitat`. Definides a `supabase/likes.sql` i
`supabase/comentaris.sql`.

---

## Categories del catàleg

`panda` · `cuina` · `bany` · `roba` · `casa` · `compres` · `manteniment` ·
`personals` · `familiars` · `jardi` (🌱 Jardí) · `fe` (🙏 Fe)

El catàleg complet ja està carregat via `supabase/seed.sql` (ampliat més
endavant amb `jardi` i `fe` — la restricció CHECK de `activitats.categoria`
s'ha d'ampliar manualment cada vegada que s'afegeix una categoria nova). La
llista llarga es gestiona a la **interfície**, agrupant per categories i ordenant
per urgència — no es retalla el catàleg.

**Important:** els xips de categoria i l'agrupació visual de la llista
(`Activitats.jsx`) es deriven de les categories que **realment existeixen**
a les activitats carregades, mai d'una llista fixa: `CATEGORIES_CONEGUDES`
només dona l'ordre i l'emoji preferits, però qualsevol categoria present a
la base de dades que no hi surti es mostra igualment (al final, amb un
nom capitalitzat i sense emoji) en lloc de desaparèixer en silenci de tot
filtre visual. Si afegeixes una categoria nova, l'única actualització
opcional és afegir-la a `CATEGORIES_CONEGUDES` per donar-li emoji i posició
— sense fer-ho, ja funciona igualment.

---

## Disseny

### Principis

- **És un marcador, no una revista.** La informació principal són números i un
  emoji. Xifres grosses; tota la resta, discreta.
- **S'obre 20 segons, cinc cops al dia, dret a la cuina.** Llegible de reüll i
  amb una mà. Res de text gris clar ni tipografies fines.
- **La llista és l'app.** En obrir-la, la llista d'activitats ordenada per
  urgència amb el progrés del dia a dalt. Res de pantalla d'inici amb resum
  ni de graella de targetes.
- **Navegació inferior (implementada):** quatre pestanyes fixes —
  **Activitats** (la llista, pestanya per defecte), **Feed**, **Rànquing** i
  **Perfil** — amb bisell metàl·lic a la pestanya activa (`src/App.jsx`,
  sense router).
- **Negre pur (OLED), mode fosc per defecte** segons preferència del sistema
  (`prefers-color-scheme`). No hi ha selector manual clar/fosc a la fase 1.
- **Minimalista amb un únic detall d'acabat**: el bisell metàl·lic de les
  targetes (veure sota). No s'afegeixen més ornaments — el risc de disseny
  es concentra aquí i enlloc més.

### El color codifica urgència

Aquesta és la regla més important de la interfície. L'escalada per oblit és
invisible si tot es veu igual, així que **la pastilla de punts s'escalfa**:

| Estat de la tasca | Color de la pastilla |
|---|---|
| Al dia (dins del període normal) | neutre |
| Escalada iniciada | `--tebi` |
| Escalada prop del sostre | `--calent` |

Ambre i vermell **només** per a això. Si es fan servir per a res més, la senyal
es dilueix i es perd l'efecte. Sobre negre pur, `--tebi` i `--calent` són el
color clar com a text sobre un fons fosc del mateix to (no el color saturat
ple, que sobre negre cansa la vista).

**Única excepció explícita:** la icona de paperera per eliminar una completion
pròpia (Feed i historial del Perfil) també fa servir `--calent`, com a color
de perill genèric, no d'urgència de tasca — són l'única acció destructiva de
tota la interfície.

### Tokens

```
--paper       #000000   negre pur, fons general
--targeta     #0A0A0A   fons de les targetes, gairebé negre
--vora        #1C1C1C   contorn de targeta
--tinta       #FAFAFA   text principal
--tinta-sec   #5C5C5C   text secundari
--panda       #4ADE94   verd Panda: progrés, fet, acció principal
--tebi        text #E3C282 · fons #231C0E · vora #362b13
--calent      text #E8A688 · fons #241410 · vora #362019
```

El verd surt dels ulls del Panda i es reserva per a coses acabades i per a
l'acció principal.

### El bisell metàl·lic (signatura visual de l'app)

Totes les targetes (grups d'activitats, pastilles de punts, fulls inferiors)
porten aquest acabat: una vora gairebé invisible més una línia de llum interior
de dalt, que simula que la targeta té cantell i li toca la llum:

```css
border: 1px solid var(--vora);
box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);
```

És l'únic detall decoratiu de tota la interfície — per això funciona. No
s'apliquen gradients de color, glow, ni cap altre efecte enlloc més. Aplica'l
també, amb la mateixa opacitat, a les pastilles de punts (vora del mateix to
que el seu fons, un punt més clara).

### Tipografia

**Dues famílies, no tres.** Un sistema de "display + body + mono" és el
default genèric que fa servir qualsevol IA sense pensar-hi — es va descartar
explícitament perquè "delatava fet per IA".

- **Bricolage Grotesque** (pesos 500 i 700) — títols, noms d'activitat, I
  **tots els números** (punts, progrés del dia, rànquings). Els números porten
  el pes 700 per donar-los personalitat pròpia; res de font monospace.
- **Karla** (pesos 400 i 500) — text de suport: temps transcorregut,
  subtítols, botons.

Cap monospace enlloc de la interfície. Totes dues de Google Fonts, definides
com a variables CSS a `index.css`.

### Llista d'activitats

- Emoji a ~28-40px a l'esquerra, fa d'ancoratge visual.
- Nom de l'activitat en Bricolage Grotesque 500, i a sota en Karla 12px i
  `--tinta-sec` el temps des de l'última vegada ("fa 3 dies", "al dia").
- Pastilla de punts a la dreta, en Bricolage Grotesque 700, amb el color
  d'urgència i el bisell metàl·lic.
- Les activitats s'agrupen en targetes per categoria (una targeta amb bisell
  per categoria, files a dins separades per una línia fina `--vora`), amb el
  nom de la categoria en Bricolage Grotesque 500, majúscules, `--tinta-sec`,
  a sobre de cada targeta.
- **Les tasques fetes no desapareixen**: es queden amb opacitat reduïda, amb
  qui l'ha fet i quan es podrà tornar a reclamar, i la pastilla substituïda
  per una icona de check en `--panda`. Així se sap que està feta i no es
  busca.
- El progrés del dia, a la capçalera, en un anell circular (no una barra
  plana) amb els punts al mig en Bricolage Grotesque 700 gros.

### Cerca, vista i filtres

Amb les 66 activitats carregades, la llista necessita tres eines de navegació,
totes en client (JavaScript pur sobre les activitats ja carregades, sense
tornar a Supabase):

- **Cercador** de text fix a dalt, sota la capçalera de progrés. Filtra per
  nom mentre s'escriu, sense esperar a prémer res.
- **Interruptor llista / blocs**, a la dreta del cercador (dues icones petites).
  - *Llista*: com ara, fila amb nom i "fa X dies" a sota.
  - *Blocs*: graella de 3 columnes, emoji gros a dalt i pastilla de punts a
    sota de cada bloc. Sense el text de temps (no hi ha espai); el color de
    la pastilla ja comunica la urgència.
  - La preferència es recorda a `localStorage` (és el navegador del client,
    no el `window.storage` d'artifacts — aquí sí és el lloc correcte).
- **Xips de categoria** horitzontals i lliscables per sobre de la llista:
  `Tot · 🐾 Panda · 🍳 Cuina · 🚿 Bany · 👕 Roba · 🏠 Casa · 🛒 Compres ·
  🔧 Manteniment · 💪 Personals · 👨‍👩‍👧 Familiars`. Un de sol actiu cada
  vegada; "Tot" és l'estat per defecte. Xips per tocar, no un desplegable
  clàssic — més ràpid en mòbil.

Cerca, vista i filtre de categoria es combinen entre si (p. ex. cercar dins
d'una categoria concreta).

### Escriptura

- Sempre en català, tractament informal.
- Botons amb verb: "Ho he fet", no "Enviar".
- Els errors diuen què ha passat i què fer, sense demanar perdó.
- Les pantalles buides conviden a actuar, no s'excusen.

---

## Fases

1. **Fase 1 (feta):** auth, catàleg d'activitats, reclamar tasca amb foto,
   punts, els tres rànquings, cooldown per activitat.
2. **Fase 2 (feta):** escalada per oblit i validació creuada al backend
   (`reclamar_activitat` calcula l'escalada; les completions no personals
   neixen `'pendent'` i `validar_completion` les valida, mai el propi
   creador). Feed (`src/pages/Feed.jsx`): targeta amb foto o emoji, punts en
   `--panda`/`--tinta-sec` segons validada/pendent, botó "Confirmar" per a
   qui no l'ha creada, likes (taula `likes`, sense donar punts).
3. **Fase 3 (en curs):** ratxes i monedes **fetes** (`processar_punts_validats`,
   cridada des de `reclamar_activitat`/`validar_completion`; indicadors 🔥/🪙 a
   la capçalera d'Activitats). Pestanya **Perfil feta**: avatar (bucket
   `avatars`), historial paginat de les pròpies completions, i des del
   rànquing es pot veure el perfil (de només lectura) de qualsevol membre
   (`PerfilMembre.jsx`). Cooldown personal (`cooldown_individual`) per a
   tasques amb exemplar propi (fer el llit, etc.). Comentaris al feed, amb
   respostes i like. **Pendent:** recompenses, tasques compartides, estat
   del Panda.
4. **Fase 4:** propostes i votacions, resums amb Gemini, notificacions push.

**No implementis res de fases posteriors sense que s'hagi demanat explícitament.**
