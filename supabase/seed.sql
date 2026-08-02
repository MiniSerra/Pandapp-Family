-- =====================================================================
-- Pandapp Family — seed del catàleg d'activitats
-- =====================================================================
-- Carrega totes les activitats per a la família 'Serrano'.
--
-- Paràmetres de temps (veure CLAUDE.md):
--   cooldown_h        hores en què la tasca queda bloquejada per a tothom
--   periode_normal_h  hores dins de les quals es paguen els punts base
--   k_dia             pujada per dia passat el període (0.15 = +15%/dia)
--   sostre            multiplicador màxim sobre punts_base
--
-- Regla de disseny: com més urgent és la tasca, més de pressa puja i
-- abans arriba al sostre. Això evita que compensi esperar per cobrar més.
--
-- Les activitats personals no tenen escalada (k_dia = 0, sostre = 1),
-- no demanen foto, i sumen contra el límit de 60 punts personals al dia.
-- =====================================================================

insert into public.activitats (
  familia_id, categoria, nom, emoji, descripcio,
  punts_base, cooldown_h, periode_normal_h, k_dia, sostre,
  compartible, requereix_foto, es_personal, es_torn
)
select f.id, v.*
from public.families f
cross join (values

-- ---------------------------------------------------------------------
-- CASA
-- ---------------------------------------------------------------------
('casa'::text, 'Fer el llit'::text, '🛏️'::text,
 'Llit fet amb el cobrellit estirat i els coixins al seu lloc.'::text,
 10::integer, 20::numeric, 24::numeric, 0::numeric, 1::numeric,
 false::boolean, true::boolean, false::boolean, false::boolean),

('casa', 'Ordenar la teva habitació', '🧸',
 'Terra lliure, roba desada, taula despullada i res fora del seu lloc.',
 20, 24, 24, 0.10, 1.5, false, true, false, false),

('casa', 'Ordenar el menjador', '🛋️',
 'Sofà i taula buits, mantes plegades, res escampat per terra.',
 25, 24, 24, 0.15, 2, false, true, false, false),

('casa', 'Treure les escombraries', '🗑️',
 'Bossa treta al contenidor i bossa nova posada al cubell.',
 15, 20, 24, 0.40, 1.5, false, true, false, true),

('casa', 'Baixar vidre, paper o plàstic', '♻️',
 'Almenys una bossa sencera portada al contenidor de reciclatge.',
 20, 72, 72, 0.15, 2, false, true, false, false),

('casa', 'Escombrar o aspirar una estança', '🧹',
 'Una habitació sencera, cantonades i sota els mobles inclosos.',
 30, 48, 48, 0.12, 2, false, true, false, false),

('casa', 'Treure la pols', '🪶',
 'Prestatges, taules i superfícies visibles de la zona comuna.',
 35, 96, 96, 0.10, 2, false, true, false, false),

('casa', 'Netejar vidres i finestres', '🪟',
 'Vidres per dins sense marques, i marcs repassats.',
 50, 336, 336, 0.05, 2, true, true, false, false),

('casa', 'Fregar el terra', '🪣',
 'Una zona sencera fregada amb aigua i producte, no només escombrada.',
 60, 120, 120, 0.08, 2.5, true, true, false, false),

-- ---------------------------------------------------------------------
-- CUINA
-- ---------------------------------------------------------------------
('cuina', 'Netejar l''encimera i la taula', '🧽',
 'Superfícies buides i passades amb baieta, sense engrunes ni taques.',
 15, 8, 12, 0.30, 1.5, false, true, false, false),

('cuina', 'Buidar o omplir el rentaplats', '🍽️',
 'Rentaplats buidat i tot desat, o carregat i posat en marxa.',
 20, 10, 12, 0.40, 1.5, false, true, false, true),

('cuina', 'Netejar la vitro o els fogons', '🔥',
 'Sense restes cremades ni greix, incloent-hi els comandaments.',
 25, 48, 48, 0.20, 1.5, false, true, false, false),

('cuina', 'Rentar els plats a mà', '🧼',
 'Pica buida, tot rentat i escorregut. La pica ha de quedar neta també.',
 30, 8, 12, 0.40, 1.5, false, true, false, true),

('cuina', 'Ordenar la cuina', '🍳',
 'Encimeres buides, res fora de l''armari i pica sense res a dins.',
 30, 48, 72, 0.15, 2, false, true, false, false),

('cuina', 'Netejar el microones', '📻',
 'Per dins, incloent-hi el plat giratori i el sostre.',
 30, 240, 240, 0.06, 2, false, true, false, false),

('cuina', 'Netejar la nevera i llençar caducats', '🧊',
 'Prestatges repassats i tot el que estigui caducat o fet malbé, fora.',
 60, 336, 336, 0.05, 2, false, true, false, false),

('cuina', 'Netejar la campana i els filtres', '💨',
 'Filtres desmuntats i desengreixats, no només la part de fora.',
 70, 720, 720, 0.03, 2, false, true, false, false),

('cuina', 'Netejar el forn', '🔲',
 'Interior, safates i vidre de la porta sense restes cremades.',
 80, 720, 720, 0.03, 2, false, true, false, false),

-- ---------------------------------------------------------------------
-- BANY
-- ---------------------------------------------------------------------
('bany', 'Reposar paper i sabó', '🧻',
 'Rotllo nou posat i dosificadors de sabó plens.',
 10, 72, 72, 0.20, 1.5, false, true, false, false),

('bany', 'Netejar la pica i el mirall', '🪞',
 'Pica sense restes de pasta de dents i mirall sense esquitxos.',
 25, 72, 72, 0.12, 2, false, true, false, false),

('bany', 'Canviar les tovalloles', '🧺',
 'Tovalloles brutes al cistell i joc net penjat.',
 20, 168, 168, 0.08, 1.5, false, true, false, false),

('bany', 'Netejar el WC', '🚽',
 'Per dins amb escombreta i producte, i la tapa i la base per fora.',
 45, 72, 72, 0.12, 2, false, true, false, true),

('bany', 'Netejar la dutxa o la banyera', '🚿',
 'Plat, parets i mampara sense calç ni restes de sabó.',
 50, 120, 120, 0.10, 2, false, true, false, false),

-- ---------------------------------------------------------------------
-- ROBA
-- ---------------------------------------------------------------------
('roba', 'Guardar la teva roba a l''armari', '👕',
 'La teva roba neta plegada i desada. Cap cadira amb roba a sobre.',
 15, 24, 24, 0, 1, false, true, false, false),

('roba', 'Posar una rentadora', '🌀',
 'Rentadora carregada, amb detergent i engegada.',
 25, 12, 24, 0.20, 1.5, false, true, false, true),

('roba', 'Estendre la roba', '🪢',
 'Rentadora buidada i tota la roba estesa i separada.',
 25, 12, 12, 0.40, 1.5, false, true, false, false),

('roba', 'Canviar els llençols del teu llit', '🛌',
 'Joc complet canviat i els bruts al cistell.',
 30, 240, 240, 0.08, 2, false, true, false, false),

('roba', 'Recollir i plegar la roba', '🧦',
 'Roba retirada de l''estenedor i plegada. No compta deixar-la amuntegada.',
 35, 12, 24, 0.25, 1.5, true, true, false, false),

('roba', 'Planxar (tanda de 30 min)', '🔌',
 'Mínim mitja hora planxant, amb la roba penjada o plegada al final.',
 50, 24, 48, 0.10, 1.5, false, true, false, false),

-- ---------------------------------------------------------------------
-- PANDA
-- ---------------------------------------------------------------------
('panda', 'Canviar-li l''aigua', '💧',
 'Bol buidat, esbandit i omplert amb aigua neta.',
 12, 20, 24, 0.50, 1.5, false, true, false, false),

('panda', 'Posar-li el menjar', '🍚',
 'Ració posada al bol a la seva hora.',
 15, 10, 12, 0.50, 1.5, false, true, false, true),

('panda', 'Netejar-li els plats', '🥣',
 'Bols de menjar i aigua rentats amb sabó, no només esbandits.',
 15, 48, 48, 0.25, 1.5, false, true, false, false),

('panda', 'Jugar amb el Panda 15 min', '🎣',
 'Un quart d''hora de joc actiu amb ell, no només fer-li carícies.',
 20, 8, 24, 0.20, 1.5, false, true, false, false),

('panda', 'Netejar el terra del sorral', '🧴',
 'Sorra escampada al voltant recollida i terra passat.',
 20, 72, 72, 0.15, 1.5, false, true, false, false),

('panda', 'Netejar el sorral', '🐾',
 'Excrements i grumolls retirats amb la pala, i sorra anivellada.',
 25, 20, 24, 0.25, 1.5, false, true, false, true),

('panda', 'Raspallar el Panda', '🪮',
 'Sessió de raspallat sencera, amb el pèl retirat del raspall.',
 25, 72, 72, 0.15, 1.5, false, true, false, false),

('panda', 'Comprar-li pinso o sorra', '🛍️',
 'Compra feta i producte desat a casa.',
 30, 0, 24, 0, 1, false, true, false, false),

('panda', 'Tallar-li les ungles', '✂️',
 'Totes les ungles tallades. Sobreviure a l''intent ja té mèrit.',
 40, 504, 504, 0.05, 1.5, false, true, false, false),

('panda', 'Canvi complet de sorra', '🏖️',
 'Sorral buidat del tot, safata rentada i sorra nova posada.',
 45, 240, 240, 0.10, 2, false, true, false, false),

('panda', 'Portar-lo al veterinari', '🏥',
 'Visita feta, amb el desplaçament i la caixa de transport.',
 100, 0, 24, 0, 1, false, true, false, false),

-- ---------------------------------------------------------------------
-- COMPRES
-- ---------------------------------------------------------------------
('compres', 'Fer la llista de la compra', '📝',
 'Llista feta havent mirat la nevera i els armaris, no d''esma.',
 10, 72, 72, 0, 1, false, true, false, false),

('compres', 'Desar la compra', '📦',
 'Tot col·locat al seu lloc, incloent-hi nevera i congelador.',
 20, 8, 24, 0, 1, true, true, false, false),

('compres', 'Compra ràpida', '🥖',
 'Sortida a comprar quatre coses que faltaven.',
 25, 24, 24, 0, 1, false, true, false, false),

('compres', 'Posar gasolina o rentar el cotxe', '⛽',
 'Dipòsit ple o cotxe rentat per fora.',
 25, 168, 168, 0, 1, false, true, false, false),

('compres', 'Gestió fora de casa', '🏤',
 'Farmàcia, correus, banc o similar. Una gestió resolta.',
 30, 0, 24, 0, 1, false, true, false, false),

('compres', 'Fer la compra setmanal', '🛒',
 'Compra grossa feta i desada. Inclou carregar-ho tot.',
 80, 96, 168, 0.15, 1.5, true, true, false, true),

-- ---------------------------------------------------------------------
-- MANTENIMENT
-- ---------------------------------------------------------------------
('manteniment', 'Regar les plantes', '🪴',
 'Totes les plantes de casa regades, també les del balcó.',
 15, 72, 72, 0.20, 2, false, true, false, false),

('manteniment', 'Netejar el balcó o la terrassa', '🌇',
 'Terra escombrat, mobles repassats i fulles seques fora.',
 55, 336, 336, 0.05, 2, true, true, false, false),

('manteniment', 'Arreglar o muntar alguna cosa', '🔧',
 'Una reparació o un muntatge acabat i funcionant.',
 60, 0, 24, 0, 1, true, true, false, false),

('manteniment', 'Netejar l''interior del cotxe', '🚗',
 'Aspirat per dins, escombraries fora i tauler repassat.',
 60, 504, 504, 0.04, 2, true, true, false, false),

('manteniment', 'Anar a la deixalleria', '🚛',
 'Viatge fet amb trastos, electrònica o voluminosos.',
 60, 0, 24, 0, 1, false, true, false, false),

('manteniment', 'Ordenar un armari a fons', '🚪',
 'Armari buidat, repassat, ordenat i amb el que sobra apartat.',
 70, 720, 720, 0.03, 2, true, true, false, false),

-- ---------------------------------------------------------------------
-- PERSONALS  (sense foto, sense escalada, màxim 60 punts al dia)
-- ---------------------------------------------------------------------
('personals', 'Meditar o desconnectar 10 min', '🧘',
 'Deu minuts sense pantalles ni estímuls, només tu.',
 10, 24, 24, 0, 1, false, false, true, false),

('personals', 'Dormir abans de les 00:00', '🌙',
 'Al llit i amb el mòbil deixat abans de mitjanit.',
 15, 24, 24, 0, 1, false, false, true, false),

('personals', 'Llegir 30 min', '📖',
 'Mitja hora de lectura seguida. Llibre, no xarxes.',
 20, 12, 24, 0, 1, false, false, true, false),

('personals', 'Caminar 30 min o 5.000 passes', '🚶',
 'Passeig d''almenys mitja hora o 5.000 passes al comptador.',
 20, 12, 24, 0, 1, false, false, true, false),

('personals', 'Aprendre alguna cosa nova 30 min', '🧠',
 'Mitja hora dedicada a un idioma, un instrument o una habilitat.',
 25, 24, 24, 0, 1, false, false, true, false),

('personals', 'Estudiar 1 hora', '📚',
 'Una hora d''estudi real, sense mòbil a la vora.',
 30, 12, 24, 0, 1, false, false, true, false),

('personals', 'Entrenar 45 min', '💪',
 'Sessió d''entrenament de tres quarts d''hora, on sigui.',
 35, 24, 24, 0, 1, false, false, true, false),

-- ---------------------------------------------------------------------
-- FAMILIARS
-- ---------------------------------------------------------------------
('familiars', 'Parar o desparar la taula', '🍴',
 'Taula parada per a tothom, o recollida del tot després de menjar.',
 15, 6, 12, 0, 1, false, true, false, false),

('familiars', 'Trucar als avis o a la família', '📞',
 'Una trucada de veritat, no un missatge.',
 20, 72, 72, 0, 1, false, false, false, false),

('familiars', 'Sopar tots junts sense mòbils', '🕯️',
 'Sopar sencer amb tota la família i els mòbils lluny de la taula.',
 25, 20, 24, 0, 1, true, true, false, false),

('familiars', 'Ajudar algú amb els deures o la feina', '🤝',
 'Una estona ajudant de debò algú de casa amb el que li toca.',
 30, 12, 24, 0, 1, false, false, false, false),

('familiars', 'Fer una activitat tots junts fora', '🎡',
 'Sortida amb tota la família: excursió, cinema, el que sigui.',
 50, 72, 72, 0, 1, true, true, false, false),

('familiars', 'Cuinar per a tota la família', '👨‍🍳',
 'Àpat cuinat per a tothom. Escalfar no compta.',
 70, 8, 12, 0, 1, false, true, false, false),

('familiars', 'Neteja general en equip', '🧹',
 'Sessió de 45 min netejant entre diversos membres de la família.',
 100, 168, 168, 0.05, 1.5, true, true, false, false)

) as v(
  categoria, nom, emoji, descripcio,
  punts_base, cooldown_h, periode_normal_h, k_dia, sostre,
  compartible, requereix_foto, es_personal, es_torn
)
where f.nom = 'Serrano';