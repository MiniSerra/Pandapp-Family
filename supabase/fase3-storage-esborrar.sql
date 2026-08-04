-- =====================================================================
-- Pandapp Family — fase 3, peça: política de DELETE al bucket fotos-tasques
-- =====================================================================
-- Migració incremental per a la base de dades real. Segur de tornar a
-- executar (CREATE POLICY falla si ja existeix; en aquest cas es pot
-- ignorar l'error "policy already exists").
--
-- Fins ara el bucket `fotos-tasques` només tenia polítiques d'INSERT i
-- SELECT per a `authenticated`. Això feia que `storage.remove()` no
-- esborrés res (sense error HTTP, simplement cap fila complia la política
-- i no es tocava res) tant quan `reclamar_activitat` fallava després de
-- pujar la foto (BottomSheetReclamar.jsx) com quan s'anul·lava una
-- completion pròpia (anullar_completion). Veure supabase/storage.sql per
-- al fitxer complet.
-- =====================================================================

create policy "fotos-tasques: esborrar dins de la propia familia"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'fotos-tasques'
    and (storage.foldername(name))[1] = public.familia_id_actual()::text
  );
