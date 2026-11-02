-- parche_admin_afiliados_ranking.sql
--
-- RPCs que el panel ADMIN (C:\Proyectos\Admin\allado_admin) invoca y
-- que no estaban versionadas en ningún .sql de ninguno de los dos
-- repos. Trabajan sobre la tabla REAL `usos_afiliado` (la misma que
-- escribe la app de la tienda). NOTA: el admin leía `usos_codigo_afiliado`,
-- una tabla que NO existe -- por eso el listado de tiendas referidas
-- salía vacío. Ese fix ya está hecho en admin_service.dart; acá solo
-- se versionan las funciones SQL que faltan.
--
-- TODO es `create or replace` / SELECT y condicional: idempotente,
-- se puede correr en el SQL Editor de Supabase tantas veces como se quiera.

-- ---------------------------------------------------------------------------
-- 1. admin_ranking_afiliados() — Ranking por volumen REAL generado.
--    El admin espera: {id_afiliado, nombre, codigo, tiendas_referidas,
--    tiendas_activas_hoy, ingreso_generado_usd, comision_historica_cup,
--    saldo_actual_cup}
--    - tiendas_referidas: tiendas que usaron el código (distintas).
--    - tiendas_activas_hoy: de esas, las activas y no eliminadas hoy.
--    - ingreso_generado_usd: el monto que la plataforma cobra hoy por esas
--      tiendas activas (suma del precio del plan actual; la comisión del
--      afiliado es 10% del plan, así que lo que "mueve" es el plan completo).
--    - comision_historica_cup: total de comisiones acreditadas históricas.
-- ---------------------------------------------------------------------------
create or replace function public.admin_ranking_afiliados()
returns table (
  id_afiliado uuid,
  nombre text,
  codigo text,
  tiendas_referidas bigint,
  tiendas_activas_hoy bigint,
  ingreso_generado_usd numeric,
  comision_historica_cup numeric,
  saldo_actual_cup numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  select
    a.id_afiliado,
    a.nombre,
    a.codigo,
    (select count(distinct c.id_tienda)
       from usos_afiliado c
      where c.id_afiliado = a.id_afiliado)::bigint as tiendas_referidas,
    (select count(distinct c2.id_tienda)
       from usos_afiliado c2
       join tiendas t on t.id_tienda = c2.id_tienda
      where c2.id_afiliado = a.id_afiliado
        and t.estado = 'active'
        and coalesce(t.eliminada, false) = false)::bigint as tiendas_activas_hoy,
    coalesce((
      select sum(pl.precio_usd)
        from usos_afiliado c3
        join tiendas t3 on t3.id_tienda = c3.id_tienda
        left join planes pl on pl.codigo = t3.plan
       where c3.id_afiliado = a.id_afiliado
         and t3.estado = 'active'
         and coalesce(t3.eliminada, false) = false
    ), 0)::numeric as ingreso_generado_usd,
    coalesce(sum(c.comision_cup_acreditada), 0)::numeric as comision_historica_cup,
    a.saldo_cup
  from afiliados a
  left join usos_afiliado c on c.id_afiliado = a.id_afiliado
  group by a.id_afiliado, a.nombre, a.codigo, a.saldo_cup
  order by ingreso_generado_usd desc, comision_historica_cup desc;
end;
$$;

revoke all on function public.admin_ranking_afiliados() from public;
grant execute on function public.admin_ranking_afiliados() to authenticated;
grant execute on function public.admin_ranking_afiliados() to service_role;

-- ---------------------------------------------------------------------------
-- 2. admin_marcar_retiro_pagado — el admin confirma que ya transfirió el
--    CUP al afiliado: marca el retiro como pagado (pagado_el = now()) y
--    descuenta ese monto del saldo_cup del afiliado.
-- ---------------------------------------------------------------------------
create or replace function public.admin_marcar_retiro_pagado(
  p_id_retiro uuid,
  p_id_afiliado uuid,
  p_monto numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.retiros
     set estado = 'pagado',
         pagado_el = now()
   where id_retiro = p_id_retiro
     and estado = 'pendiente';

  update public.afiliados
     set saldo_cup = greatest(coalesce(saldo_cup, 0) - coalesce(p_monto, 0), 0)
   where id_afiliado = p_id_afiliado;
end;
$$;

revoke all on function public.admin_marcar_retiro_pagado(uuid, uuid, numeric) from public;
grant execute on function public.admin_marcar_retiro_pagado(uuid, uuid, numeric) to authenticated;
grant execute on function public.admin_marcar_retiro_pagado(uuid, uuid, numeric) to service_role;

-- ---------------------------------------------------------------------------
-- 3. admin_aprobar_tienda — RPC que el admin invoca al aprobar una tienda
--    nueva y que la app espera que acredite la comisión del afiliado (10%
--    del plan). Estaba creado a mano en la DB sin versionar. Lo dejamos
--    versionado para que exista consistencia entre repos.
-- ---------------------------------------------------------------------------
create or replace function public.admin_aprobar_tienda(
  p_id_tienda uuid,
  p_tasa_cup_usd numeric default 320
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_codigo text;
  v_afiliado uuid;
  v_precio_usd numeric;
  v_comision_cup numeric;
begin
  update public.tiendas
     set estado = 'active',
         activada_en = coalesce(activada_en, now())
   where id_tienda = p_id_tienda;

  -- Acreditar comisión del afiliado que refirió esta tienda (si tiene código).
  select t.codigo_afiliado,
         coalesce((select pl.precio_usd from planes pl where pl.codigo = t.plan), 0)
    into v_codigo, v_precio_usd
    from tiendas t
   where t.id_tienda = p_id_tienda;

  if v_codigo is not null and v_precio_usd > 0 then
    select a.id_afiliado
      into v_afiliado
      from afiliados a
     where a.codigo = v_codigo
       and a.activo = true;

    if v_afiliado is not null then
      v_comision_cup := (v_precio_usd * 0.10) * coalesce(nullif(p_tasa_cup_usd, 0), 320);

      -- Si ya existía un uso para esta tienda, NO duplicar: solo actualizar.
      insert into usos_afiliado (id_afiliado, id_tienda, codigo, comision_cup_acreditada, estado)
      values (v_afiliado, p_id_tienda, v_codigo, round(v_comision_cup, 2), 'aprobado')
      on conflict do nothing;

      update afiliados a2
         set saldo_cup = coalesce(a2.saldo_cup, 0) + round(v_comision_cup, 2)
       where a2.id_afiliado = v_afiliado;
    end if;
  end if;
end;
$$;

revoke all on function public.admin_aprobar_tienda(uuid, numeric) from public;
grant execute on function public.admin_aprobar_tienda(uuid, numeric) to authenticated;
grant execute on function public.admin_aprobar_tienda(uuid, numeric) to service_role;