-- parche_negocio_eliminar.sql
--
-- QUÉ HACE: permite que el DUEÑO elimine su propio negocio desde la
-- mini-página (antes solo el admin podía). El borrado es en cascada:
-- se van solos sus anuncios, permisos y compras de paquetes.
--
-- CÓMO: pega TODO en el SQL Editor de Supabase y ejecuta. Idempotente.

drop policy if exists neg_delete on public.negocios;

create policy neg_delete on public.negocios for delete
  using (es_admin() or id_dueno = auth.uid());
