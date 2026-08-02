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

### Ratxes

- **Dia complert** = has arribat al llindar diari de punts (per defecte 100,
  configurable per persona).
- Bonus diari: **+5 punts × dies de ratxa**, amb topall a **+50**.
- Fites: **dia 7 → +100**, **dia 14 → +200**, **dia 30 → +500**.
- **Mai multiplicadors sobre els punts del dia** — dispararien el rànquing i el
  farien injugable.
- **Escut de ratxa:** un dia de gràcia al mes (o comprable amb monedes) que evita
  perdre la ratxa. Sense això, qui perd una ratxa llarga abandona l'app.

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

En reclamar una tasca es poden **etiquetar altres persones** que hi han participat.

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
- El **validador de la foto no pot ser cap participant**.
- Camp `compartible` per activitat. Fer el llit, posar menjar al gat o llegir **no**
  són compartibles. Regla: si la tasca no es fa realment més ràpida entre dos, no ho és.
- Arrodoniment cap amunt; el residu se'l queda qui puja la foto.
- L'objectiu col·lectiu suma el **pot sencer**, no la part de cadascú.

---

## Torns rotatius

Algunes tasques són obligacions, no oportunitats (plats, escombraries, sorral,
rentadora, WC, compra setmanal). Tenen torn assignat.

Si algú **cobreix el torn d'un altre**, s'emporta els punts **+50%**. Aquest bonus
no s'acumula amb la prima de grup: s'aplica el més alt dels dos.

---

## Validació de tasques

- Foto obligatòria per a les tasques de casa, cuina, bany, roba i Panda.
- Les **personals no porten foto** i tenen un **límit de 60 punts al dia**.
- **Fase 2:** els punts queden **pendents** fins que un altre familiar confirma
  l'entrada al feed. **Fase 1:** no hi ha validació creuada encara; `estat` es
  posa directament a `'validada'` en crear la `completion`. Les columnes `estat`
  i `validada_per` ja existeixen a l'esquema des de la fase 1 perquè la fase 2
  només canviï la lògica, no calgui migrar la taula.
- El timestamp el posa el servidor, mai el mòbil.
- **Cooldown per tasca (fase 1):** en reclamar, es mira l'última completació
  d'aquella activitat i es bloqueja si no han passat `cooldown_h`. És per
  activitat, no per usuari (si algú neteja el sorral, queda bloquejat per a
  tothom). Sense això el rànquing queda inservible des del primer dia.
- **Anul·lació:** es pot desfer una reclamació pròpia amb `anullar_completion`
  dins dels primers 15 minuts. Retorna `foto_url`/`thumb_url` perquè el client
  esborri els fitxers del bucket.

---

## Feed social

- Entrada per completació, amb foto, activitat, punts i participants.
- Les tasques compartides són **una sola entrada** amb totes les cares.
- **Els likes no donen punts** (si en donessin, us els regalaríeu). Alimenten un
  comptador d'"aplaudiments rebuts" al perfil.
- Els esdeveniments del sistema també hi surten: activitats noves aprovades,
  objectiu setmanal assolit, fites de ratxa.

---

## Fotos

- **Compressió al navegador abans de pujar:** canvas → redimensionar a 1080px →
  WebP qualitat 0.7 (~150 KB). Miniatura de 300px per al feed.
- **Esborrat automàtic als 14 dies** amb cron: posar `foto_url = NULL`
  **i esborrar el fitxer del bucket**. Si només es neteja la base de dades, queden
  fitxers orfes acumulant-se fins a omplir la quota.
- **L'històric de tasques no s'esborra mai.** Punts, dates, qui i validació es
  conserven per sempre. Només desapareix la imatge.
- Al feed, les entrades sense foto mostren la icona (o l'emoji) de l'activitat.
- **Ordre pujada foto / reclamació:** la foto es puja al bucket abans de cridar
  `reclamar_activitat` (cal la URL per passar-la a la funció). Si la crida falla
  (p. ex. cooldown actiu), el frontend **ha d'esborrar** el fitxer que acaba de
  pujar, si no queden fitxers orfes al bucket. Alternativa a valorar més endavant:
  pujar la foto només després que `reclamar_activitat` hagi tingut èxit (crear
  primer la completion sense foto i actualitzar-la després), si els fitxers orfes
  arriben a ser un problema real.

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
                    punts_base, cooldown_h, periode_normal_h, k_dia, sostre,
                    compartible, requereix_foto, es_personal, es_torn,
                    estat (proposta|activa|retirada), versio, proposada_per,
                    activa_des_de
completions         id, activitat_id, familia_id, creada_per, versio_punts,
                    punts_base_snapshot, pot_total, foto_url, thumb_url,
                    validada_per, estat (pendent|validada), created_at
participacions      completion_id, usuari_id, punts_assignats, confirmat,
                    es_qui_puja
likes               completion_id, usuari_id
propostes           id, tipus, activitat_id, payload, proposada_per, estat, caduca
vots                proposta_id, usuari_id, vot, punts_suggerits, created_at
torns               activitat_id, usuari_id, setmana
monedes             usuari_id, saldo
recompenses         id, familia_id, nom, cost
bescanvis           recompensa_id, usuari_id, created_at
resums              id, familia_id, usuari_id (null = familiar), periode, text
```

**Important:** els punts van a `participacions`, no a `completions`. Si es fa al
revés, cada consulta del rànquing ha de dividir i apareixen errors d'arrodoniment.

**Important:** `punts_base_snapshot` (i `versio_punts`) a `completions` congelen
els punts que valia l'activitat quan es va fer. Si es canvien els punts a mitja
temporada, l'històric no s'ha de recalcular sol.

**Important:** `familia_id` i `creada_per` estan denormalitzats a `completions`
perquè les polítiques de RLS i les consultes de feed/rànquing no calgui que facin
`JOIN` a `activitats` per saber de qui o de quina família és cada fila.

---

## Categories del catàleg

`casa` · `cuina` · `bany` · `roba` · `panda` · `compres` · `manteniment` ·
`personals` · `familiars`

El catàleg complet (66 activitats) ja està carregat via `supabase/seed.sql`. La
llista llarga es gestiona a la **interfície**, agrupant per categories i ordenant
per urgència — no es retalla el catàleg.

---

## Disseny

### Principis

- **És un marcador, no una revista.** La informació principal són números i un
  emoji. Xifres grosses i tabulars; tota la resta, discreta.
- **S'obre 20 segons, cinc cops al dia, dret a la cuina.** Llegible de reüll i
  amb una mà. Res de text gris clar ni tipografies fines.
- **La llista és l'app.** En obrir-la, la llista d'activitats ordenada per
  urgència amb el progrés del dia a dalt. Rànquings i perfil en pestanyes
  inferiors. Res de pantalla d'inici amb resum ni de graella de targetes.

### El color codifica urgència

Aquesta és la regla més important de la interfície. L'escalada per oblit és
invisible si tot es veu igual, així que **la pastilla de punts s'escalfa**:

| Estat de la tasca | Color de la pastilla |
|---|---|
| Al dia (dins del període normal) | neutre |
| Escalada iniciada | `--tebi` |
| Escalada prop del sostre | `--calent` |

Ambre i vermell **només** per a això. Si es fan servir per a res més, la senyal
es dilueix i es perd l'efecte.

### Tokens

```
--tinta      #15211B   text; gairebé negre amb un pèl de verd
--paper      #F1F3EF   fons
--targeta    #FFFFFF
--panda      #2E7D5B   verd Panda: fet, progrés, botó principal
--tebi       #C97A16   escalada mitjana
--calent     #B23A2F   escalada alta
--vora       #DDE1DA
```

El verd surt dels ulls del Panda i es reserva per a coses acabades i per a
l'acció principal.

### Tipografia

- **Bricolage Grotesque** — números grossos i títols.
- **Karla** — text corrent.
- **DM Mono** — punts i comptadors. Xifres tabulars perquè les columnes del
  rànquing quedin alineades.

Totes de Google Fonts. Definides com a variables CSS a `index.css`.

### Llista d'activitats

- Emoji a ~40px a l'esquerra, fa d'ancoratge visual.
- Nom de l'activitat, i a sota en petit el temps des de l'última vegada
  ("fa 3 dies", "al dia").
- Pastilla de punts a la dreta, amb el color d'urgència.
- **Les tasques fetes no desapareixen**: es queden en gris amb qui l'ha fet i
  quan es podrà tornar a reclamar. Així se sap que està feta i no es busca.

### Escriptura

- Sempre en català, tractament informal.
- Botons amb verb: "Ho he fet", no "Enviar".
- Els errors diuen què ha passat i què fer, sense demanar perdó.
- Les pantalles buides conviden a actuar, no s'excusen.

---

## Fases

1. **Fase 1 (actual):** auth, catàleg d'activitats, reclamar tasca amb foto, punts,
   els tres rànquings, **cooldown per activitat**. L'escalada per oblit i la
   validació creuada encara no.
2. **Fase 2:** feed, likes, validació creuada, escalada per oblit.
3. **Fase 3:** ratxes, monedes i recompenses, tasques compartides, estat del Panda.
4. **Fase 4:** propostes i votacions, resums amb Gemini, notificacions push.

**No implementis res de fases posteriors sense que s'hagi demanat explícitament.**
