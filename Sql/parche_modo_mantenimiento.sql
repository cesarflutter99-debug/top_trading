-- parche_modo_mantenimiento.sql
-- ============================================================
-- Activa el soporte de "modo mantenimiento" en la app de la tienda.
--
-- El widget lib/widgets/mantenimiento_gate.dart consulta esta fila cada
-- 45 s, al abrir la app y al volver del background. Si la clave no
-- existe o la consulta falla, la app NO se bloquea (fail-open).
--
-- Idempotente: se puede correr varias veces sin efectos secundarios.
-- ============================================================

-- 1) Fila inicial: mantenimiento DESACTIVADO.
insert into public.configuracion_app (clave, valor)
values ('modo_mantenimiento', 'false'::jsonb)
on conflict (clave) do nothing;

-- ============================================================
-- USO
-- ============================================================
-- Activar mantenimiento (bloquea a todos salvo admins):
--   update public.configuracion_app
--   set valor = 'true'::jsonb, actualizado_en = now()
--   where clave = 'modo_mantenimiento';
--
-- Desactivar mantenimiento:
--   update public.configuracion_app
--   set valor = 'false'::jsonb, actualizado_en = now()
--   where clave = 'modo_mantenimiento';
--
-- Ver estado actual:
--   select clave, valor, actualizado_en
--   from public.configuracion_app
--   where clave = 'modo_mantenimiento';
--
-- Nota: la RLS de configuracion_app ya permite lectura publica y
-- escritura solo a admins (cfg_read / cfg_write), por lo que el gate
-- funciona sin cambios adicionales de permisos.