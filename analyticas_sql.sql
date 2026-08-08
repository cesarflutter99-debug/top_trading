-- =============================================================================
-- ANALÍTICAS POR ROL — Supabase SQL
-- Copia cada bloque en Supabase > SQL Editor y ejecútalo.
-- Las funciones usan SECURITY DEFINER para que el cliente pueda llamarlas
-- sin tener permiso directo de lectura sobre las tablas ajenas.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. ADMIN — Dashboard general
-- ---------------------------------------------------------------------------

-- Resumen general del dashboard (tiendas, pedidos, ingresos, afiliados)
create or replace function admin_dashboard_resumen()
returns table (
  total_tiendas bigint,
  tiendas_activas bigint,
  tiendas_pendientes bigint,
  total_pedidos bigint,
  pedidos_hoy bigint,
  ingresos_mes numeric,
  total_afiliados bigint,
  retiros_pendientes bigint,
  comisiones_pendientes numeric,
  planes_activos bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    (select count(*) from tiendas)::bigint as total_tiendas,
    (select count(*) from tiendas where estado = 'active')::bigint as tiendas_activas,
    (select count(*) from tiendas where estado = 'pending')::bigint as tiendas_pendientes,
    (select count(*) from pedidos)::bigint as total_pedidos,
    (select count(*) from pedidos where created_at >= date_trunc('day', now()))::bigint as pedidos_hoy,
    (select coalesce(sum(total_usd), 0) from pedidos where created_at >= date_trunc('month', now()))::numeric as ingresos_mes,
    (select count(*) from afiliados)::bigint as total_afiliados,
    (select count(*) from retiros where estado = 'pendiente')::bigint as retiros_pendientes,
    (select coalesce(sum(monto_cup), 0) from retiros where estado = 'pendiente')::numeric as comisiones_pendientes,
    (select count(*) from planes where activo = true)::bigint as planes_activos;
end;
$$;

-- Tiendas con más pedidos (top tiendas por volumen)
create or replace function admin_top_tiendas_por_pedidos(limite int default 10)
returns table (
  id_tienda text,
  nombre text,
  total_pedidos bigint,
  ingresos_total numeric,
  calificacion_promedio numeric
)
language plpgsql
security definer
as $$
begin
  return query
  select
    t.id_tienda,
    t.nombre,
    count(p.id_pedido)::bigint as total_pedidos,
    coalesce(sum(p.total_usd), 0)::numeric as ingresos_total,
    coalesce(avg(v.estrellas), 0)::numeric as calificacion_promedio
  from tiendas t
  left join pedidos p on p.id_tienda = t.id_tienda
  left join valoraciones v on v.id_tienda = t.id_tienda
  group by t.id_tienda, t.nombre
  order by total_pedidos desc
  limit limite;
end;
$$;

-- Pedidos pendientes de aprobación (para admin)
create or replace function admin_pedidos_pendientes()
returns table (
  id_pedido text,
  numero_pedido text,
  tienda_nombre text,
  comprador_email text,
  total_usd numeric,
  estado text,
  created_at timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    p.id_pedido,
    p.numero_pedido,
    t.nombre as tienda_nombre,
    u.email as comprador_email,
    p.total_usd,
    p.estado,
    p.created_at
  from pedidos p
  join tiendas t on t.id_tienda = p.id_tienda
  join auth.users u on u.id = p.id_comprador
  where p.estado in ('pending', 'confirmed')
  order by p.created_at desc;
end;
$$;

-- Solicitudes de cambio de plan pendientes
create or replace function admin_solicitudes_plan_pendientes()
returns table (
  id_solicitud text,
  tienda_nombre text,
  plan_anterior text,
  plan_nuevo text,
  uso_afiliado boolean,
  created_at timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    sc.id_solicitud,
    t.nombre as tienda_nombre,
    sc.plan_anterior,
    sc.plan_nuevo,
    sc.uso_afiliado,
    sc.created_at
  from solicitudes_cambio_plan sc
  join tiendas t on t.id_tienda = sc.id_tienda
  where sc.estado = 'pending'
  order by sc.created_at desc;
end;
$$;

-- Ingresos por mes (últimos 12 meses) para gráfico
create or replace function admin_ingresos_por_mes()
returns table (
  mes text,
  ingresos numeric,
  pedidos_count bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    to_char(created_at, 'YYYY-MM') as mes,
    coalesce(sum(total_usd), 0)::numeric as ingresos,
    count(*)::bigint as pedidos_count
  from pedidos
  where created_at >= date_trunc('month', now()) - interval '12 months'
  group by to_char(created_at, 'YYYY-MM')
  order by mes;
end;
$$;

-- Productos más vendidos (top productos)
create or replace function admin_top_productos(limite int default 10)
returns table (
  id_producto text,
  nombre text,
  tienda_nombre text,
  veces_vendido bigint,
  ingreso_total numeric
)
language plpgsql
security definer
as $$
begin
  return query
  select
    p.id_producto,
    p.nombre,
    t.nombre as tienda_nombre,
    count(pd.id_pedido)::bigint as veces_vendido,
    coalesce(sum(p.precio_usd), 0)::numeric as ingreso_total
  from productos p
  join tiendas t on t.id_tienda = p.id_tienda
  left join pedidos pd on pd.id_producto = p.id_producto
  group by p.id_producto, p.nombre, t.nombre
  order by veces_vendido desc
  limit limite;
end;
$$;

-- Afiliados con más comisiones
create or replace function admin_top_afiliados(limite int default 10)
returns table (
  id_afiliado text,
  nombre text,
  codigo text,
  saldo_cup numeric,
  comisiones_acumuladas numeric,
  retiros_realizados bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    a.id_afiliado,
    a.nombre,
    a.codigo,
    a.saldo_cup,
    coalesce(sum(c.comision_cup_acreditada), 0)::numeric as comisiones_acumuladas,
    (select count(*) from retiros r where r.id_afiliado = a.id_afiliado and r.estado = 'pagado')::bigint as retiros_realizados
  from afiliados a
  left join usos_afiliado c on c.id_afiliado = a.id_afiliado
  group by a.id_afiliado, a.nombre, a.codigo, a.saldo_cup
  order by comisiones_acumuladas desc
  limit limite;
end;
$$;


-- ---------------------------------------------------------------------------
-- 2. VENDEDOR — Dashboard de su tienda
-- ---------------------------------------------------------------------------

-- Resumen de la tienda del vendedor logueado
create or replace function vendedor_dashboard_resumen(p_id_tienda uuid)
returns table (
  nombre_tienda text,
  total_pedidos bigint,
  pedidos_hoy bigint,
  pedidos_mes bigint,
  ingresos_mes numeric,
  ingresos_total numeric,
  productos_activos bigint,
  calificacion_promedio numeric,
  total_valoraciones bigint,
  pedidos_pendientes bigint,
  pedidos_completados bigint,
  pedidos_cancelados bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    t.nombre as nombre_tienda,
    count(p.id_pedido)::bigint as total_pedidos,
    (select count(*) from pedidos where id_tienda = p_id_tienda and created_at >= date_trunc('day', now()))::bigint as pedidos_hoy,
    (select count(*) from pedidos where id_tienda = p_id_tienda and created_at >= date_trunc('month', now()))::bigint as pedidos_mes,
    (select coalesce(sum(total_usd), 0) from pedidos where id_tienda = p_id_tienda and created_at >= date_trunc('month', now()))::numeric as ingresos_mes,
    (select coalesce(sum(total_usd), 0) from pedidos where id_tienda = p_id_tienda)::numeric as ingresos_total,
    (select count(*) from productos where id_tienda = p_id_tienda and es_visible = true)::bigint as productos_activos,
    coalesce(avg(v.estrellas), 0)::numeric as calificacion_promedio,
    count(v.id_valoracion)::bigint as total_valoraciones,
    (select count(*) from pedidos where id_tienda = p_id_tienda and estado = 'pending')::bigint as pedidos_pendientes,
    (select count(*) from pedidos where id_tienda = p_id_tienda and estado = 'completado')::bigint as pedidos_completados,
    (select count(*) from pedidos where id_tienda = p_id_tienda and estado = 'cancelado')::bigint as pedidos_cancelados
  from tiendas t
  left join pedidos p on p.id_tienda = t.id_tienda
  left join valoraciones v on v.id_tienda = t.id_tienda
  where t.id_tienda = p_id_tienda
  group by t.nombre;
end;
$$;

-- Pedidos de la tienda del vendedor con filtro de estado
create or replace function vendedor_pedidos(p_id_tienda uuid, p_estado text default null)
returns table (
  id_pedido text,
  numero_pedido text,
  comprador_email text,
  total_usd numeric,
  estado text,
  created_at timestamptz,
  productos_count bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    p.id_pedido,
    p.numero_pedido,
    u.email as comprador_email,
    p.total_usd,
    p.estado,
    p.created_at,
    (select count(*) from pedidos_detalle pd where pd.id_pedido = p.id_pedido)::bigint as productos_count
  from pedidos p
  join auth.users u on u.id = p.id_comprador
  where p.id_tienda = p_id_tienda
    and (p_estado is null or p.estado = p_estado)
  order by p.created_at desc;
end;
$$;

-- Productos de la tienda con estadísticas de ventas
create or replace function vendedor_productos_con_ventas(p_id_tienda uuid)
returns table (
  id_producto text,
  nombre text,
  precio_usd numeric,
  es_visible boolean,
  veces_vendido bigint,
  ingreso_total numeric,
  stock_actual int
)
language plpgsql
security definer
as $$
begin
  return query
  select
    p.id_producto,
    p.nombre,
    p.precio_usd,
    p.es_visible,
    (select count(*) from pedidos pd where pd.id_producto = p.id_producto)::bigint as veces_vendido,
    (select coalesce(sum(p.precio_usd), 0) from pedidos pd where pd.id_producto = p.id_producto)::numeric as ingreso_total,
    p.cantidad_disponible as stock_actual
  from productos p
  where p.id_tienda = p_id_tienda
  order by veces_vendido desc;
end;
$$;

-- Valoraciones de la tienda
create or replace function vendedor_valoraciones(p_id_tienda uuid)
returns table (
  id_valoracion text,
  comprador_email text,
  estrellas int,
  comentario text,
  foto_url text,
  created_at timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    v.id_valoracion,
    u.email as comprador_email,
    v.estrellas,
    v.comentario,
    v.foto_url,
    v.created_at
  from valoraciones v
  join auth.users u on u.id = v.id_comprador
  where v.id_tienda = p_id_tienda
  order by v.created_at desc;
end;
$$;

-- Ingresos diarios de la tienda (últimos 30 días) para gráfico
create or replace function vendedor_ingresos_diarios(p_id_tienda uuid)
returns table (
  fecha text,
  ingresos numeric,
  pedidos_count bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    to_char(created_at, 'YYYY-MM-DD') as fecha,
    coalesce(sum(total_usd), 0)::numeric as ingresos,
    count(*)::bigint as pedidos_count
  from pedidos
  where id_tienda = p_id_tienda
    and created_at >= date_trunc('day', now()) - interval '30 days'
  group by to_char(created_at, 'YYYY-MM-DD')
  order by fecha;
end;
$$;


-- ---------------------------------------------------------------------------
-- 3. COMPRADOR — Mis pedidos y compras
-- ---------------------------------------------------------------------------

-- Resumen del comprador logueado
create or replace function comprador_dashboard_resumen(p_id_comprador uuid)
returns table (
  total_pedidos bigint,
  pedidos_activos bigint,
  pedidos_completados bigint,
  gasto_total numeric,
  gasto_mes numeric,
  primera_compra timestamptz,
  ultima_compra timestamptz,
  tiendas_favoritas bigint,
  valoracion_promedio numeric
)
language plpgsql
security definer
as $$
begin
  return query
  select
    count(*)::bigint as total_pedidos,
    (select count(*) from pedidos where id_comprador = p_id_comprador and estado in ('pending', 'confirmed'))::bigint as pedidos_activos,
    (select count(*) from pedidos where id_comprador = p_id_comprador and estado = 'completado')::bigint as pedidos_completados,
    coalesce(sum(total_usd), 0)::numeric as gasto_total,
    (select coalesce(sum(total_usd), 0) from pedidos where id_comprador = p_id_comprador and created_at >= date_trunc('month', now()))::numeric as gasto_mes,
    min(created_at) as primera_compra,
    max(created_at) as ultima_compra,
    (select count(distinct id_tienda) from pedidos where id_comprador = p_id_comprador)::bigint as tiendas_favoritas,
    null::numeric as valoracion_prominente
  from pedidos
  where id_comprador = p_id_comprador;
end;
$$;

-- Historial de pedidos del comprador
create or replace function comprador_pedidos(p_id_comprador uuid)
returns table (
  id_pedido text,
  numero_pedido text,
  tienda_nombre text,
  total_usd numeric,
  estado text,
  created_at timestamptz,
  productos_count bigint
)
language plpgsql
security definer
as $$
begin
  return query
  select
    p.id_pedido,
    p.numero_pedido,
    t.nombre as tienda_nombre,
    p.total_usd,
    p.estado,
    p.created_at,
    (select count(*) from pedidos_detalle pd where pd.id_pedido = p.id_pedido)::bigint as productos_count
  from pedidos p
  join tiendas t on t.id_tienda = p.id_tienda
  where p.id_comprador = p_id_comprador
  order by p.created_at desc;
end;
$$;


-- ---------------------------------------------------------------------------
-- 4. AFILIADO — Mis comisiones y referidos
-- ---------------------------------------------------------------------------

-- Resumen del afiliado logueado
create or replace function afiliado_dashboard_resumen(p_id_afiliado uuid)
returns table (
  nombre text,
  codigo text,
  saldo_cup numeric,
  comisiones_acumuladas numeric,
  comisiones_mes numeric,
  retiros_pendientes bigint,
  retiros_pagados bigint,
  total_referidos bigint,
  tiendas_usaron_codigo bigint,
  comisiones_pendientes numeric
)
language plpgsql
security definer
as $$
begin
  return query
  select
    a.nombre,
    a.codigo,
    a.saldo_cup,
    coalesce(sum(c.comision_cup_acreditada), 0)::numeric as comisiones_acumuladas,
    (select coalesce(sum(c2.comision_cup_acreditada), 0)
     from usos_afiliado c2
     where c2.id_afiliado = p_id_afiliado
       and c2.creado_en >= date_trunc('month', now()))::numeric as comisiones_mes,
    (select count(*) from retiros r where r.id_afiliado = p_id_afiliado and r.estado = 'pendiente')::bigint as retiros_pendientes,
    (select count(*) from retiros r where r.id_afiliado = p_id_afiliado and r.estado = 'pagado')::bigint as retiros_pagados,
    (select count(*) from usos_afiliado c where c.id_afiliado = p_id_afiliado)::bigint as total_referidos,
    (select count(distinct c.id_tienda) from usos_afiliado c where c.id_afiliado = p_id_afiliado)::bigint as tiendas_usaron_codigo,
    (select coalesce(sum(c3.comision_cup_acreditada), 0)
     from usos_afiliado c3
     where c3.id_afiliado = p_id_afiliado
       and c3.estado = 'pendiente')::numeric as comisiones_pendientes
  from afiliados a
  left join usos_afiliado c on c.id_afiliado = a.id_afiliado
  where a.id_afiliado = p_id_afiliado
  group by a.nombre, a.codigo, a.saldo_cup;
end;
$$;

-- Historial de comisiones del afiliado
create or replace function afiliado_comisiones(p_id_afiliado uuid)
returns table (
  id_uso text,
  tienda_nombre text,
  codigo_usado text,
  comision_cup numeric,
  comision_usd numeric,
  estado text,
  creado_en timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    c.id_uso,
    t.nombre as tienda_nombre,
    c.codigo,
    c.comision_cup_acreditada as comision_cup,
    (c.comision_cup_acreditada / nullif((select tasa from currency_service limit 1), 0))::numeric as comision_usd,
    c.estado,
    c.creado_en
  from usos_afiliado c
  join tiendas t on t.id_tienda = c.id_tienda
  where c.id_afiliado = p_id_afiliado
  order by c.creado_en desc;
end;
$$;

-- Historial de retiros del afiliado
create or replace function afiliado_retiros(p_id_afiliado uuid)
returns table (
  id_retiro text,
  monto_cup numeric,
  monto_usd numeric,
  estado text,
  created_at timestamptz,
  pagado_el timestamptz
)
language plpgsql
security definer
as $$
begin
  return query
  select
    r.id_retiro,
    r.monto_cup,
    (r.monto_cup / nullif((select tasa from currency_service limit 1), 0))::numeric as monto_usd,
    r.estado,
    r.created_at,
    r.pagado_el
  from retiros r
  where r.id_afiliado = p_id_afiliado
  order by r.created_at desc;
end;
$$;


-- ---------------------------------------------------------------------------
-- GRANT EXECUTE permissions (ajusta los roles según tu configuración RLS)
-- ---------------------------------------------------------------------------
grant execute on function admin_dashboard_resumen() to authenticated;
grant execute on function admin_top_tiendas_por_pedidos(int) to authenticated;
grant execute on function admin_pedidos_pendientes() to authenticated;
grant execute on function admin_solicitudes_plan_pendientes() to authenticated;
grant execute on function admin_ingresos_por_mes() to authenticated;
grant execute on function admin_top_productos(int) to authenticated;
grant execute on function admin_top_afiliados(int) to authenticated;

grant execute on function vendedor_dashboard_resumen(uuid) to authenticated;
grant execute on function vendedor_pedidos(uuid, text) to authenticated;
grant execute on function vendedor_productos_con_ventas(uuid) to authenticated;
grant execute on function vendedor_valoraciones(uuid) to authenticated;
grant execute on function vendedor_ingresos_diarios(uuid) to authenticated;

grant execute on function comprador_dashboard_resumen(uuid) to authenticated;
grant execute on function comprador_pedidos(uuid) to authenticated;

grant execute on function afiliado_dashboard_resumen(uuid) to authenticated;
grant execute on function afiliado_comisiones(uuid) to authenticated;
grant execute on function afiliado_retiros(uuid) to authenticated;

-- =============================================================================
-- NOTA: Algunas funciones usan tablas que podrían no existir exactamente con
-- esos nombres (ej. 'usos_afiliado', 'currency_service', 'pedidos_detalle').
-- Ajusta los nombres de tabla/columna según tu schema real de Supabase.
-- Las funciones que no dependen de tabas inexistentes funcionarán directamente.
-- =============================================================================