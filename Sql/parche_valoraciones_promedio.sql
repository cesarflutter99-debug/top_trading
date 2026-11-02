-- parche_valoraciones_promedio.sql
-- ============================================================
-- FIX: el dueño ve las estrellas (calculadas en vivo por
-- vendedor_dashboard_resumen), pero el comprador externo ve 0 porque
-- tiendas.promedio_estrellas / total_valoraciones nunca se actualizaban
-- al insertar una valoración.
--
-- Solución: trigger que mantiene sincronizados promedio_estrellas y
-- total_valoraciones de la tienda cada vez que se inserta/actualiza/
-- borra una valoración (respetando las ocultas por moderación), más un
-- backfill para las tiendas que ya tienen valoraciones.
-- Idempotente.
-- ============================================================

-- 1) Función que recalcula el promedio y total de una tienda.
create or replace function public.actualizar_promedio_valoraciones()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id_tienda uuid;
  v_promedio  numeric;
  v_total     bigint;
begin
  if (tg_op = 'DELETE') then
    v_id_tienda := old.id_tienda;
  else
    v_id_tienda := new.id_tienda;
  end if;

  -- Si la valoración cambió de tienda, recalcular también la anterior.
  if (tg_op = 'UPDATE' and old.id_tienda is distinct from new.id_tienda) then
    select coalesce(avg(estrellas), 0), count(*)::bigint
      into v_promedio, v_total
      from public.valoraciones
      where id_tienda = old.id_tienda
        and coalesce(oculta, false) = false;
    update public.tiendas
       set promedio_estrellas = case when v_total = 0 then null else round(v_promedio, 2) end,
           total_valoraciones  = v_total
     where id_tienda = old.id_tienda;
  end if;

  select coalesce(avg(estrellas), 0), count(*)::bigint
    into v_promedio, v_total
    from public.valoraciones
    where id_tienda = v_id_tienda
      and coalesce(oculta, false) = false;

  update public.tiendas
     set promedio_estrellas = case when v_total = 0 then null else round(v_promedio, 2) end,
         total_valoraciones  = v_total
   where id_tienda = v_id_tienda;

  if (tg_op = 'DELETE') then
    return old;
  end if;
  return new;
end;
$$;

-- 2) Trigger.
drop trigger if exists trg_valoraciones_sync on public.valoraciones;
create trigger trg_valoraciones_sync
  after insert or update or delete on public.valoraciones
  for each row
  execute function public.actualizar_promedio_valoraciones();

-- 3) Backfill: recalcular para todas las tiendas existentes.
update public.tiendas t
   set promedio_estrellas = sub.promedio,
       total_valoraciones  = sub.total
  from (
        select t2.id_tienda,
               case when count(v.id_valoracion) = 0 then null
                    else round(avg(v.estrellas)::numeric, 2) end as promedio,
               count(v.id_valoracion)::bigint as total
          from public.tiendas t2
          left join public.valoraciones v
            on v.id_tienda = t2.id_tienda
           and coalesce(v.oculta, false) = false
         group by t2.id_tienda
       ) sub
 where t.id_tienda = sub.id_tienda;

-- 4) Consistencia: el dashboard del vendedor también ignora las ocultas.
create or replace function public.vendedor_dashboard_resumen(p_id_tienda uuid)
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
set search_path = public
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
  left join valoraciones v on v.id_tienda = t.id_tienda and coalesce(v.oculta, false) = false
  where t.id_tienda = p_id_tienda
  group by t.nombre;
end;
$$;