-- =====================================================================
-- Pandapp Family — polítiques del bucket privat de fotos (fase 1)
-- =====================================================================
-- El bucket `fotos-tasques` ja existeix (creat des del panell de Supabase,
-- privat). Aquest fitxer només afegeix les polítiques de RLS sobre
-- `storage.objects` perquè els usuaris puguin pujar i llegir les seves
-- pròpies fotos. Row Level Security ja ve activat per Supabase a
-- `storage.objects`; no cal (ni es pot, sense ser owner del sistema)
-- tornar-lo a activar aquí.
--
-- Esquema de rutes (veure CLAUDE.md "Fotos"):
--   {familia_id}/{identificador}/original.webp
--   {familia_id}/{identificador}/thumb.webp
-- `{identificador}` NO ha de ser necessàriament l'id real de la
-- `completion`: el client puja les fotos abans de saber quin id assignarà
-- `reclamar_activitat`, així que fa servir una carpeta temporal
-- `pendent-{uuid}` com a identificador únic. Un cop pujades, aquesta
-- carpeta ja no es mou ni es renombra encara que la reclamació tingui
-- èxit — només cal que el primer segment sigui la `familia_id` correcta,
-- que és l'únic que verifiquen les polítiques de sota.
--
-- Fase 1: INSERT i SELECT per a `authenticated`. No hi ha UPDATE de client.
-- L'esborrat automàtic als 14 dies el fa el cron amb la clau secreta
-- (service_role), que salta la RLS — però el client SÍ necessita poder
-- esborrar (fase 3): quan `reclamar_activitat` falla després de pujar la
-- foto (BottomSheetReclamar.jsx) i quan s'anul·la una completion pròpia
-- (anullar_completion, veure src/lib/completions.js). Sense política de
-- DELETE, `storage.remove()` no fa res (falla en silenci: no és cap error
-- HTTP, simplement no esborra) i queden fitxers orfes al bucket.
-- =====================================================================

create policy "fotos-tasques: pujar dins de la propia familia"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'fotos-tasques'
    and (storage.foldername(name))[1] = public.familia_id_actual()::text
  );

-- Necessària perquè el client pugui generar URLs signades (createSignedUrl
-- fa una comprovació de lectura sobre l'objecte abans de signar-lo).
create policy "fotos-tasques: veure dins de la propia familia"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'fotos-tasques'
    and (storage.foldername(name))[1] = public.familia_id_actual()::text
  );

create policy "fotos-tasques: esborrar dins de la propia familia"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'fotos-tasques'
    and (storage.foldername(name))[1] = public.familia_id_actual()::text
  );
