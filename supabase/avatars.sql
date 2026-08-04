-- =====================================================================
-- Pandapp Family — polítiques del bucket privat d'avatars (fase 3)
-- =====================================================================
-- El bucket `avatars` ja existeix (creat manualment des del panell de
-- Supabase, privat, igual que `fotos-tasques`). Esquema de ruta: UN SOL
-- fitxer per usuari que es sobreescriu amb `upload(..., { upsert: true })`
-- — no s'acumulen versions com a fotos-tasques:
--   {familia_id}/{usuari_id}.webp
--
-- A diferència de fotos-tasques, aquí SÍ importa que la ruta identifiqui
-- exactament qui escriu (el segon segment és l'usuari_id, no un
-- identificador temporal), així que INSERT i UPDATE exigeixen que `name`
-- coincideixi exactament amb la ruta pròpia, no només que el primer
-- segment sigui la família correcta.
-- =====================================================================

create policy "avatars: pujar el propi" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and name = public.familia_id_actual()::text || '/' || auth.uid()::text || '.webp'
  );

-- Necessària perquè upload(..., { upsert: true }) pugui sobreescriure el
-- fitxer quan ja existeix (Storage fa un UPDATE, no un INSERT, en aquest cas).
create policy "avatars: actualitzar el propi" on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and name = public.familia_id_actual()::text || '/' || auth.uid()::text || '.webp'
  )
  with check (
    bucket_id = 'avatars'
    and name = public.familia_id_actual()::text || '/' || auth.uid()::text || '.webp'
  );

-- Es pot veure l'avatar de qualsevol membre de la família (calen les
-- URLs signades de tothom, no només la pròpia, per mostrar-los al
-- rànquing/feed més endavant).
create policy "avatars: veure la família" on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = public.familia_id_actual()::text
  );
