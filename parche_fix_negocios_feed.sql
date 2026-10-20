-- parche_fix_negocios_feed.sql
--
-- QUÉ ARREGLA (dos bugs que hacen que los NEGOCIOS no salgan en el feed
-- ni en la sección "Anuncios", aunque sí en el mapa):
--
--   (1) ROTACIÓN DEL FEED: obtener_anuncios_feed() termina con
--       `update anuncios set veces_mostrado = veces_mostrado + 1`. El
--       RPC es security invoker (corre con el rol del usuario), así que
--       ese UPDATE dispara anuncios_before_update(), que lanza
--       CAMPO_PROTEGIDO al ver `veces_mostrado` cambiado. Resultado: el
--       RPC tira error -> la app cae al fallback _feedDirecto() que NO
--       rota. Por eso "no se alternan en el feed".
--
--   (2) RE-MODERACIÓN FANTASMA: anuncios_before_update() tiene
--       `if old.tipo='negocio' and old.estado in ('rechazado','aprobado')
--       then new.estado := 'pendiente'`. Eso corre en CUALQUIER update no
--       admin -- incluidos los internos (rotación del feed, conteo de
--       likes/comentarios, clics). Así, cada vez que un anuncio de
--       negocio se mostraba en el feed, la rotación lo dejaba en
--       'pendiente' y DESAPARECÍA del feed y de "Anuncios" (que filtran
--       estado='aprobado'). Por eso "no salen los negocios".
--
-- FIX: se reescribe anuncios_before_update() para que:
--   * deje pasar las actualizaciones del sistema (sync de anuncios
--     automáticos, GUC app.anuncio_automatico = true);
--   * deje pasar los updates que SOLO cambian métricas (veces_mostrado,
--     veces_clickeado, total_likes, total_comentarios, interacciones)
--     -- rotación del feed, clics y contadores de likes/comentarios;
--   * re-moderar un negocio SOLO si cambió contenido REAL (título, texto,
--     imagen, etiqueta), no en mantenimiento interno;
--   * mantenga protegidos los campos reservados para ediciones del dueño.
--
-- Además: re-sincroniza YA el anuncio automático de todos los negocios
-- con permiso vigente (por si el trigger no corrió antes) y, al final,
-- imprime un DIAGNÓSTICO para ver cuántos anuncios hay por tipo/estado y
-- el estado de cada negocio.
--
-- CÓMO: pega TODO en el SQL Editor de Supabase y ejecútalo. Idempotente.

-- ---------------------------------------------------------------------
-- 1) TRIGGER CORREGIDO
-- ---------------------------------------------------------------------
create or replace function public.anuncios_before_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max     int;
  v_activos int;
begin
  if es_admin() then
    return new;
  end if;

  -- (a) Mantenimiento del SISTEMA (crear/renovar/expirar el anuncio
  --     automático del negocio). El sync marca este GUC a propósito.
  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true' then
    return new;
  end if;

  -- (b) Updates que SOLO tocan MÉTRICAS (rotación del feed, clics y
  --     contadores de likes/comentarios). No son ediciones de contenido
  --     del dueño y NO deben bloquearse ni re-moderar nada.
  --     Criterio: NINGÚN campo de contenido/reservado cambió (las
  --     métricas --veces_mostrado, veces_clickeado, total_likes,
  --     total_comentarios, interacciones-- sí pueden haber cambiado).
  if new.estado         is not distinct from old.estado
     and new.vigencia_hasta is not distinct from old.vigencia_hasta
     and new.motivo_rechazo is not distinct from old.motivo_rechazo
     and new.titulo       is not distinct from old.titulo
     and new.texto        is not distinct from old.texto
     and new.imagen_url   is not distinct from old.imagen_url
     and new.etiqueta     is not distinct from old.etiqueta
     and new.tipo         is not distinct from old.tipo
     and new.id_negocio   is not distinct from old.id_negocio
     and new.id_producto  is not distinct from old.id_producto
     and new.es_automatico is not distinct from old.es_automatico then
    return new;
  end if;

  -- (c) Guard de anuncios AUTOMÁTICOS: el contenido lo gestiona el
  --     sistema con el paquete; el dueño no lo edita a mano.
  if old.es_automatico = true then
    raise exception 'CAMPO_PROTEGIDO: este anuncio se gestiona automáticamente con tu paquete.';
  end if;

  -- (d) Pausar/reactivar del DUEÑO (aprobado <-> pausado) con
  --     re-validación de cupo al reactivar (producto/negocio/standalone).
  if new.estado is distinct from old.estado then
    if old.tipo in ('producto', 'negocio', 'standalone')
       and ((old.estado = 'aprobado' and new.estado = 'pausado')
          or (old.estado = 'pausado' and new.estado = 'aprobado')) then

      if old.estado = 'pausado' then
        if old.tipo = 'producto' then
          select count(*) into v_activos
          from anuncios
          where tipo = 'producto' and id_tienda = old.id_tienda
            and estado = 'aprobado'
            and id_anuncio <> old.id_anuncio;

          select coalesce(max(pl.ranuras_anuncios), 0) into v_max
          from tiendas t
          left join planes pl on pl.codigo = t.plan
          where t.id_tienda = old.id_tienda;

        elsif old.tipo = 'negocio' then
          select count(*) into v_activos
          from anuncios
          where tipo = 'negocio' and id_negocio = old.id_negocio
            and estado in ('pendiente', 'aprobado')
            and id_anuncio <> old.id_anuncio;

          select least(coalesce(sum(pn.max_anuncios), 0), 5) into v_max
          from permisos_negocio pn
          where pn.id_negocio = old.id_negocio
            and pn.activo and pn.hasta > now();

        else -- standalone
          if old.id_permiso_usuario is not null then
            select count(*) into v_activos
            from anuncios
            where tipo = 'standalone'
              and id_permiso_usuario = old.id_permiso_usuario
              and estado = 'aprobado'
              and id_anuncio <> old.id_anuncio;
            select coalesce(max_anuncios, 0) into v_max
            from permisos_usuario_anuncios
            where id_permiso = old.id_permiso_usuario
              and activo and hasta > now();
          else
            select count(*) into v_activos
            from anuncios
            where tipo = 'standalone' and creado_por = old.creado_por
              and estado = 'aprobado'
              and id_anuncio <> old.id_anuncio;
            select coalesce(sum(max_anuncios), 0) into v_max
            from permisos_usuario_anuncios
            where id_usuario = old.creado_por
              and activo and hasta > now();
          end if;
        end if;

        if v_activos >= coalesce(v_max, 0) then
          raise exception 'CUPO_ANUNCIOS: no hay ranuras libres para reactivar.';
        end if;
      end if;
    else
      raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
    end if;
  end if;

  -- (e) Campos reservados para el admin (ya no incluye métricas: esas
  --     las dejó pasar el bloque (b)).
  if new.motivo_rechazo is distinct from old.motivo_rechazo
     or new.vigencia_hasta is distinct from old.vigencia_hasta
     or new.tipo is distinct from old.tipo
     or new.id_negocio is distinct from old.id_negocio
     or new.id_producto is distinct from old.id_producto
     or new.es_automatico is distinct from old.es_automatico then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;

  -- (f) Re-moderar SOLO negocio y SOLO si cambió contenido real.
  if old.tipo = 'negocio'
     and old.estado in ('rechazado', 'aprobado', 'pausado')
     and (new.titulo is distinct from old.titulo
          or new.texto is distinct from old.texto
          or new.imagen_url is distinct from old.imagen_url
          or new.etiqueta is distinct from old.etiqueta) then
    new.estado := 'pendiente';
  end if;

  return new;
end;
$$;

-- (El trigger trg_anuncios_update ya existe y apunta a esta función.)


-- ---------------------------------------------------------------------
-- 1b) RE-DEPLOY del RPC del feed (3 args: p_cantidad, provincia,
--     municipio). La app lo llama SIEMPRE con esos 3 argumentos; si el
--     RPC sólo tiene la firma de 1 arg, PostgREST falla y la app cae al
--     fallback sin rotación. Incluido aquí para garantizar que exista.
-- ---------------------------------------------------------------------
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


-- ---------------------------------------------------------------------
-- 2) RE-SINCRONIZAR el anuncio automático de los negocios con permiso
--    vigente (por si el trigger no corrió al aprobar su paquete).
-- ---------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select distinct pn.id_negocio
    from public.permisos_negocio pn
    join public.negocios n on n.id_negocio = pn.id_negocio
    where pn.activo and pn.hasta > now()
      and n.estado = 'activo'
  loop
    perform public.fn_sincronizar_anuncio_automatico_negocio(r.id_negocio);
  end loop;
end $$;


-- ---------------------------------------------------------------------
-- 3) DIAGNÓSTICO -- corre esto y mira la salida en "Results":
--    (A) cuántos anuncios hay por tipo/estado,
--    (B) cada negocio activo con su anuncio y si su paquete está vigente.
-- ---------------------------------------------------------------------
select 'A_anuncios_por_tipo_estado' as reporte,
       a.tipo, a.estado,
       count(*) as cantidad
from public.anuncios a
group by a.tipo, a.estado
order by a.tipo, a.estado;

select 'B_negocios' as reporte,
       n.nombre as negocio,
       n.estado as negocio_estado,
       (select count(*) from public.permisos_negocio pn
         where pn.id_negocio = n.id_negocio and pn.activo and pn.hasta > now()) as permisos_vigentes,
       (select count(*) from public.anuncios a
         where a.id_negocio = n.id_negocio and a.tipo = 'negocio') as anuncios_total,
       (select count(*) from public.anuncios a
         where a.id_negocio = n.id_negocio and a.tipo = 'negocio'
           and a.estado = 'aprobado') as anuncios_aprobados,
       (select max(pn.hasta) from public.permisos_negocio pn
         where pn.id_negocio = n.id_negocio and pn.activo and pn.hasta > now()) as permiso_hasta
from public.negocios n
order by n.creado_en desc;
