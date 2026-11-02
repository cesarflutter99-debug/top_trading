-- =============================================================================
-- parche_bucket_valoraciones.sql
-- Crea el bucket público "valoraciones" (foto de evidencia que el
-- comprador adjunta al puntuar un pedido) y su política de escritura
-- para usuarios autenticados. Idempotente: se puede correr varias veces.
--
-- Requiere conexión a internet (los archivos quedan públicos, igual que
-- los demás buckets de imágenes de la app).
-- =============================================================================

insert into storage.buckets (id, name, public)
values ('valoraciones', 'valoraciones', true)
on conflict (id) do nothing;

-- Cualquier usuario autenticado puede subir a su carpeta {uid}/; la
-- valoración en sí apunta a la URL pública devuelta.
drop policy if exists "valoraciones_upload_autenticado" on storage.objects;
create policy "valoraciones_upload_autenticado" on storage.objects
for insert to authenticated
with check (bucket_id = 'valoraciones' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "valoraciones_gestion_autenticado" on storage.objects;
create policy "valoraciones_gestion_autenticado" on storage.objects
for update to authenticated
using (bucket_id = 'valoraciones' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "valoraciones_borrar_autenticado" on storage.objects;
create policy "valoraciones_borrar_autenticado" on storage.objects
for delete to authenticated
using (bucket_id = 'valoraciones' and (storage.foldername(name))[1] = auth.uid()::text);