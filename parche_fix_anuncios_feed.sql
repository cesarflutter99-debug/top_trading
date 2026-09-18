-- parche_fix_anuncios_feed.sql
--
-- Corrige el RPC obtener_anuncios_feed(integer,text,text): la versión
-- anterior referenciaba columnas inexistentes (a.prioridad,
-- a.destino_nombre, a.destino_imagen) y eso rompía el feed (42703).
--
-- Se reescribe con la MISMA lógica de buckets del original sano
-- (admin -> negocio -> producto -> standalone, ordenando por
-- veces_mostrado y rotación aleatoria) y se le agrega el filtro por
-- provincia/municipio para anuncios de tienda. Idempotente.

create or replace function public.obtener_anuncios_feed(
  p_cantidad integer default 6,
  provincia text default null,
  municipio text default null
)
returns table (anuncio jsonb)
language plpgsql
stable
security invoker
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

  -- Los anuncios sin tienda (standalone/admin) no tienen ubicación:
  -- solo se muestran cuando NO hay filtro de provincia/municipio.
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

revoke all on function public.obtener_anuncios_feed(integer, text, text) from public;
grant execute on function public.obtener_anuncios_feed(integer, text, text) to anon, authenticated, service_role;