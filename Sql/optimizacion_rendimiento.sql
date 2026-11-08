--------------------------------------------------------------------------------
-- SCRIPT DE OPTIMIZACIÓN DE RENDIMIENTO Y CONSULTAS (SUPABASE / POSTGRESQL)
-- Proyecto: Top Trading
-- Ubicación: Sql/optimizacion_rendimiento.sql
-- Descripción:
--   Este script recopila índices recomendados de alta eficiencia, funciones RPC
--   optimizadas para analíticas y resúmenes de alto rendimiento, y consultas de
--   mantenimiento seguro (VACUUM / ANALYZE y estadísticas).
--   Es completamente seguro, no destructivo y no altera ni borra tablas existentes.
--------------------------------------------------------------------------------

-- ============================================================================
-- 1. CREACIÓN DE ÍNDICES DE ALTA EFICIENCIA (COMPUESTOS Y PARCIALES)
-- ============================================================================

-- A. Optimización para la tabla de anuncios (filtrado por estado, caducidad y ordenamiento)
CREATE INDEX IF NOT EXISTS idx_anuncios_feed_opt 
ON public.anuncios (estado, fecha_fin DESC, creado_en DESC) 
WHERE estado = 'activo';

-- B. Optimización para la tabla de negocios (búsqueda por estado, categoría y ubicación/destacados)
CREATE INDEX IF NOT EXISTS idx_negocios_feed_opt 
ON public.negocios (estado, categoria, destacado DESC, creado_en DESC)
WHERE estado = 'activo';

-- C. Optimización para la tabla de productos (búsqueda por tienda, disponibilidad y precio)
CREATE INDEX IF NOT EXISTS idx_productos_tienda_precio 
ON public.productos (id_tienda, activo, precio);

-- D. Optimización para la tabla de pedidos (búsqueda rápida por tienda, estado y fecha)
CREATE INDEX IF NOT EXISTS idx_pedidos_tienda_estado_fecha 
ON public.pedidos (id_tienda, estado, creado_en DESC);

-- E. Optimización para la tabla de interacciones (likes y comentarios)
CREATE INDEX IF NOT EXISTS idx_anuncio_likes_compuesto 
ON public.anuncio_likes (id_anuncio, id_usuario);

CREATE INDEX IF NOT EXISTS idx_comentarios_anuncios_opt 
ON public.comentarios_anuncios (id_anuncio, creado_en DESC);

-- F. Optimización para notificaciones de usuarios
CREATE INDEX IF NOT EXISTS idx_notificaciones_usuario_leida 
ON public.notificaciones (id_usuario, leida, creado_en DESC);


-- ============================================================================
-- 2. FUNCIONES RPC OPTIMIZADAS PARA ANALÍTICAS Y RESÚMENES
-- ============================================================================

-- A. Resumen global de métricas del sistema para administradores (Optimizado con CTEs paralelas)
CREATE OR REPLACE FUNCTION public.fn_admin_dashboard_resumen_optimizado()
RETURNS TABLE (
    total_usuarios bigint,
    total_tiendas bigint,
    total_negocios bigint,
    total_anuncios bigint,
    total_pedidos bigint,
    ingresos_totales numeric
) 
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE sql
STABLE
AS $$
    WITH 
        u AS (SELECT count(*) AS cnt FROM auth.users),
        t AS (SELECT count(*) AS cnt FROM public.tiendas WHERE estado = 'activo'),
        n AS (SELECT count(*) AS cnt FROM public.negocios WHERE estado = 'activo'),
        a AS (SELECT count(*) AS cnt FROM public.anuncios WHERE estado = 'activo'),
        p AS (SELECT count(*) AS cnt, coalesce(sum(total), 0.0) AS suma FROM public.pedidos WHERE estado IN ('completado', 'entregado'))
    SELECT 
        u.cnt,
        t.cnt,
        n.cnt,
        a.cnt,
        p.cnt,
        p.suma
    FROM u, t, n, a, p;
$$;

REVOKE ALL ON FUNCTION public.fn_admin_dashboard_resumen_optimizado() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fn_admin_dashboard_resumen_optimizado() TO authenticated, service_role;


-- B. Resumen de rendimiento para vendedores (Optimizado por índices de tienda)
CREATE OR REPLACE FUNCTION public.fn_vendedor_dashboard_resumen_optimizado(p_id_tienda uuid)
RETURNS TABLE (
    total_productos bigint,
    total_pedidos bigint,
    pedidos_pendientes bigint,
    ventas_totales numeric,
    valoracion_promedio numeric
) 
SECURITY DEFINER
SET search_path = public, pg_temp
LANGUAGE sql
STABLE
AS $$
    WITH 
        prod AS (SELECT count(*) AS cnt FROM public.productos WHERE id_tienda = p_id_tienda AND activo = true),
        ped AS (
            SELECT 
                count(*) AS cnt,
                count(*) FILTER (WHERE estado IN ('pendiente', 'procesando')) AS pendientes,
                coalesce(sum(total) FILTER (WHERE estado IN ('completado', 'entregado')), 0.0) AS suma
            FROM public.pedidos 
            WHERE id_tienda = p_id_tienda
        ),
        val AS (
            SELECT coalesce(avg(puntuacion), 0.0) AS prom 
            FROM public.valoraciones 
            WHERE id_tienda = p_id_tienda
        )
    SELECT 
        prod.cnt,
        ped.cnt,
        ped.pendientes,
        ped.suma,
        val.prom
    FROM prod, ped, val;
$$;

REVOKE ALL ON FUNCTION public.fn_vendedor_dashboard_resumen_optimizado(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.fn_vendedor_dashboard_resumen_optimizado(uuid) TO authenticated, service_role;


-- ============================================================================
-- 3. CONSULTAS DE MANTENIMIENTO Y ESTADÍSTICAS
-- ============================================================================

-- Actualizar estadísticas de tablas críticas para el optimizador de consultas de PostgreSQL (Planner)
ANALYZE public.anuncios;
ANALYZE public.negocios;
ANALYZE public.productos;
ANALYZE public.pedidos;
ANALYZE public.anuncio_likes;
ANALYZE public.comentarios_anuncios;
ANALYZE public.notificaciones;

--------------------------------------------------------------------------------
-- FIN DEL SCRIPT DE OPTIMIZACIÓN
--------------------------------------------------------------------------------
