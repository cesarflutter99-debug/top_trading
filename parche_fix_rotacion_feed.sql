-- parche_fix_rotacion_feed.sql
-- ===========================================================================
-- FIX: los anuncios del feed NO se alternan (siempre salen los mismos).
--
-- CAUSA RAIZ: la funcion public.obtener_anuncios_feed(integer,text,text)
-- estaba declarada STABLE. En Postgres una funcion STABLE se ejecuta
-- dentro de una transaccion de SOLO LECTURA, asi que el
--
--     update anuncios a set veces_mostrado = veces_mostrado + 1
--
-- que hace al final (el contador que rota el feed) falla con:
--     ERROR 25006: cannot execute UPDATE in a read-only transaction
-- y la RPC entera revienta. La app captura el error y cae al fallback
-- _feedDirecto(), que ordena por creado_en desc -> SIEMPRE los mismos
-- anuncios, nunca rotan.
--
-- FIX:
--   1) La funcion pasa a VOLATILE (puede escribir) y a SECURITY DEFINER
--      (asi el UPDATE de veces_mostrado no choca con la RLS de
--      anuncios, que solo deja actualizar al dueno o al admin).
--   2) Se mantiene EXACTAMENTE la misma logica de buckets y de
--      rotacion (admin -> negocio -> producto -> standalone, ordenando
--      por veces_mostrado asc, y el UPDATE final que incrementa el
--      contador), mas los filtros por provincia/municipio y los campos
--   3) Se normaliza tambien la sobrecarga de 1 argumento
--      obtener_anuncios_feed(integer) para que quede VOLATILE + SECURITY
--      DEFINER y no vuelva a romper por el mismo motivo.
--
-- Ejecutar UNA vez en el SQL Editor de Supabase. Idempotente.
-- ===========================================================================

create or replace function public.obtener_anuncios_feed(
  p_cantidad integer default 6,
  provincia text default null,
  municipio text default null
)
returns table (anuncio jsonb)
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_config    jsonb;
  v_sin       timestamptz;
  v_admins    jsonb := '[]'::jsonb;
  v_negs      jsonb := '[]'::jsonb;
  v_prods     jsonb := '[]'::jsonb;
  v_standalone jsonb := '[]'::jsonb;
  v_result    jsonb := '[]'::jsonb;
  v_tomado    boolean;
begin
  select valor into v_config from configuracion_app where clave = 'anuncios';
  if found and coalesce(v_config->>'activos', 'true') <> 'true' then
    return;
  end if;

  if auth.uid() is not null then
    select sin_anuncios_hasta into v_sin
    from preferencias_usuario where id_usuario = auth.uid();
    if v_sin is not null and v_sin > now() then
      return;
    end if;
  end if;

  perform anuncios_limpiar_estados();

  select coalesce(jsonb_agg(x.j), '[]') into v_admins
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'precio_usd', a.precio_usd, 'whatsapp', a.whatsapp,
      'destino_nombre', null::text, 'destino_imagen', null::text
    ) as j
    from anuncios a
    where a.tipo = 'admin' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
    order by a.veces_mostrado asc, random()
    limit least(p_cantidad, 2)
  ) x(j);

  select coalesce(jsonb_agg(x.j), '[]') into v_negs
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'precio_usd', a.precio_usd, 'whatsapp', a.whatsapp,
      'destino_nombre', n.nombre, 'destino_imagen', n.logo_url
    ) as j
    from anuncios a
    join negocios n on n.id_negocio = a.id_negocio
    where a.tipo = 'negocio' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
      and n.estado = 'activo'
    order by a.veces_mostrado asc, random()
    limit least(p_cantidad, 2)
  ) x(j);

  select coalesce(jsonb_agg(x.j), '[]') into v_prods
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'precio_usd', a.precio_usd, 'whatsapp', a.whatsapp,
      'destino_nombre', coalesce(p.nombre, t.nombre),
      'destino_imagen', coalesce(p.imagen_url, t.logo_url)
    ) as j
    from anuncios a
    left join productos p on p.id_producto = a.id_producto
    left join tiendas t on t.id_tienda = a.id_tienda
    where a.tipo = 'producto' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
      and t.estado = 'active'
      and coalesce(t.eliminada, false) = false
      and (a.id_producto is null or p.es_visible = true)
      and (provincia is null or t.provincia = provincia)
      and (municipio is null or t.municipio = municipio)
    order by a.veces_mostrado asc, random()
    limit least(p_cantidad, 2)
  ) x(j);

  if provincia is null and municipio is null then
    select coalesce(jsonb_agg(x.j), '[]') into v_standalone
    from (
      select jsonb_build_object(
        'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
        'titulo', a.titulo, 'texto', a.texto,
        'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
        'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
        'precio_usd', a.precio_usd, 'whatsapp', a.whatsapp,
        'destino_nombre', null::text, 'destino_imagen', null::text
      ) as j
      from anuncios a
      where a.tipo = 'standalone' and a.estado = 'aprobado'
        and (a.vigencia_hasta is null or a.vigencia_hasta > now())
      order by a.veces_mostrado asc, random()
      limit least(p_cantidad, 2)
    ) x(j);
  end if;

  loop
    exit when jsonb_array_length(v_result) >= p_cantidad;
    v_tomado := false;

    if jsonb_array_length(v_admins) > 0 then
      v_result := v_result || (v_admins -> 0); v_admins := v_admins - 0; v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_negs) > 0 then
      v_result := v_result || (v_negs -> 0);   v_negs := v_negs - 0;   v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_prods) > 0 then
      v_result := v_result || (v_prods -> 0);  v_prods := v_prods - 0; v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_standalone) > 0 then
      v_result := v_result || (v_standalone -> 0); v_standalone := v_standalone - 0; v_tomado := true;
    end if;

    exit when not v_tomado;
  end loop;

  select jsonb_agg(e order by random())
  into v_result
  from jsonb_array_elements(v_result) e;

  update anuncios a set veces_mostrado = a.veces_mostrado + 1
  where a.id_anuncio in (
    select (e->>'id_anuncio')::uuid from jsonb_array_elements(v_result) e
  );

  return query
  select e from jsonb_array_elements(v_result) e;
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants (los mismos que antes).
-- ---------------------------------------------------------------------------
revoke all on function public.obtener_anuncios_feed(integer, text, text) from public;
grant  execute on function public.obtener_anuncios_feed(integer, text, text) to anon, authenticated, service_role;
