-- =============================================================================
-- MÉTRICAS DE ANUNCIOS PARA EL PANEL ADMIN — Supabase SQL
-- =============================================================================
-- Tres RPC security-definer que el panel admin llama desde Flutter:
--   1) admin_resumen_anuncios()           -> KPIs globales del módulo
--   2) admin_top_anuncios(p_limite)       -> ranking por clics/CTR
--   3) admin_ingresos_anuncios_por_paquete() -> ingresos por paquete vendido
-- Pegar el archivo completo en Supabase > SQL Editor y ejecutar.
-- Idempotente: usa create or replace.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) RESUMEN GLOBAL
-- ---------------------------------------------------------------------------
create or replace function public.admin_resumen_anuncios()
returns table (
  total_anuncios       bigint,
  aprobados_admin      bigint,
  aprobados_negocio    bigint,
  aprobados_producto   bigint,
  aprobados_standalone bigint,
  pendientes           bigint,
  pausados             bigint,
  impresiones_totales  bigint,
  clics_totales        bigint,
  ctr_general          numeric,
  ingresos_aprobados   numeric,
  compras_pendientes   bigint,
  permisos_negocio     bigint,
  permisos_usuario     bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    (select count(*) from anuncios)::bigint as total_anuncios,
    (select count(*) from anuncios where estado = 'aprobado' and tipo = 'admin')::bigint,
    (select count(*) from anuncios where estado = 'aprobado' and tipo = 'negocio')::bigint,
    (select count(*) from anuncios where estado = 'aprobado' and tipo = 'producto')::bigint,
    (select count(*) from anuncios where estado = 'aprobado' and tipo = 'standalone')::bigint,
    (select count(*) from anuncios where estado = 'pendiente')::bigint,
    (select count(*) from anuncios where estado = 'pausado')::bigint,
    (select coalesce(sum(veces_mostrado), 0) from anuncios)::bigint,
    (select coalesce(sum(veces_clickeado), 0) from anuncios)::bigint,
    (select case
              when coalesce(sum(veces_mostrado), 0) > 0
              then round(coalesce(sum(veces_clickeado), 0)::numeric
                   / coalesce(sum(veces_mostrado), 0)::numeric, 4)
              else 0 end
       from anuncios)::numeric,
    (select coalesce(sum(p.precio_usd), 0)
       from compras_anuncio ca
       join paquetes_anuncio p on p.id_paquete = ca.id_paquete
       where ca.estado = 'aprobada')::numeric,
    (select count(*) from compras_anuncio where estado = 'pendiente')::bigint,
    (select count(*)
       from permisos_negocio
       where activo and hasta > now())::bigint,
    (select count(*)
       from permisos_usuario_anuncios
       where activo and (hasta is null or hasta > now()))::bigint;
end;
$$;

grant execute on function public.admin_resumen_anuncios() to authenticated;


-- ---------------------------------------------------------------------------
-- 2) TOP ANUNCIOS POR CLICS (nombre del origen resuelto según tipo)
-- ---------------------------------------------------------------------------
create or replace function public.admin_top_anuncios(p_limite int default 10)
returns table (
  id_anuncio      uuid,
  titulo          text,
  tipo            text,
  estado          text,
  nombre_origen   text,
  veces_mostrado  bigint,
  veces_clickeado bigint,
  ctr             numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id_anuncio,
    a.titulo,
    a.tipo,
    a.estado,
    coalesce(t.nombre, n.nombre, u.email, '—') as nombre_origen,
    a.veces_mostrado,
    a.veces_clickeado,
    case when a.veces_mostrado > 0
         then round(a.veces_clickeado::numeric / a.veces_mostrado::numeric, 4)
         else 0 end as ctr
  from anuncios a
  left join tiendas t     on t.id_tienda = a.id_tienda
  left join negocios n    on n.id_negocio = a.id_negocio
  left join auth.users u  on u.id = a.creado_por
  order by a.veces_clickeado desc, a.veces_mostrado desc
  limit greatest(coalesce(p_limite, 10), 0);
end;
$$;

grant execute on function public.admin_top_anuncios(int) to authenticated;


-- ---------------------------------------------------------------------------
-- 3) INGRESOS POR PAQUETE (compras aprobadas)
-- ---------------------------------------------------------------------------
create or replace function public.admin_ingresos_anuncios_por_paquete()
returns table (
  id_paquete  uuid,
  nombre      text,
  compras     bigint,
  monto_usd   numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    p.id_paquete,
    p.nombre,
    count(ca.id_compra)::bigint,
    coalesce(sum(p.precio_usd), 0)::numeric
  from paquetes_anuncio p
  left join compras_anuncio ca
         on ca.id_paquete = p.id_paquete
        and ca.estado = 'aprobada'
  group by p.id_paquete, p.nombre, p.orden
  order by p.orden;
end;
$$;

grant execute on function public.admin_ingresos_anuncios_por_paquete() to authenticated;