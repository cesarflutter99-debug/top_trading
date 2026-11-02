-- =============================================================================
-- unificar_anuncios.sql
--
-- UN SOLO TIPO DE ANUNCIO para usuarios: 'standalone' (el que ya funciona),
-- con vínculo OPCIONAL a un producto, una tienda o un negocio propio.
--
--   * Los anuncios tipo 'admin' NO se tocan (bucket, carrusel y trigger
--     idénticos a los de hoy).
--   * Ranuras: permisos_usuario_anuncios + ranuras del plan de la tienda
--     (ej. SOCIO = 20). permisos_negocio / permisos_tienda_anuncios se
--     MIGRAN (copia) a permisos_usuario_anuncios; las tablas viejas NO se
--     borran (reversible).
--   * Todo se publica directo (sin 'pendiente' ni re-moderación).
--   * WhatsApp: se completa desde la tienda/negocio y se normaliza
--     (8 dígitos que empiezan con 5 -> antepone 53).
--   * Se retira el anuncio AUTOMÁTICO del negocio (triggers de sync).
--     Los que ya existen siguen hasta su vigencia.
--   * Feed: un solo RPC; el bucket 'standalone' ahora trae nombre/logo del
--     destino y filtra por provincia/municipio solo si hay tienda ligada.
--
-- Idempotente. Ejecutar completo en el SQL Editor de Supabase.
-- =============================================================================

begin;

-- ---------------------------------------------------------------------------
-- 0) Helpers
-- ---------------------------------------------------------------------------
create or replace function public.fn_normalizar_whatsapp(p text)
returns text
language sql
immutable
as $$
  select case
    when p is null then null
    when length(regexp_replace(p, '[^0-9]', '', 'g')) = 0 then null
    when length(regexp_replace(p, '[^0-9]', '', 'g')) = 8
         and regexp_replace(p, '[^0-9]', '', 'g') like '5%'
      then '53' || regexp_replace(p, '[^0-9]', '', 'g')
    else regexp_replace(p, '[^0-9]', '', 'g')
  end;
$$;

-- Ranuras totales del usuario = permisos vigentes + ranuras del plan de su tienda.
create or replace function public.fn_ranuras_pool(p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((select sum(pu.max_anuncios)
                from permisos_usuario_anuncios pu
               where pu.id_usuario = p_uid and pu.activo and pu.hasta > now()), 0)::int
  + coalesce((select max(pl.ranuras_anuncios)
                from tiendas t join planes pl on pl.codigo = t.plan
               where t.owner_id = p_uid and t.estado = 'active'), 0)::int;
$$;

create or replace function public.fn_plan_ranuras(p_uid uuid)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select max(pl.ranuras_anuncios)
                     from tiendas t join planes pl on pl.codigo = t.plan
                    where t.owner_id = p_uid and t.estado = 'active'), 0)::int;
$$;

-- Anuncios en uso del usuario (todos los tipos de usuario, no automáticos).
create or replace function public.fn_anuncios_usados(p_uid uuid, p_excluir uuid default null)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
    from anuncios a
   where a.creado_por = p_uid
     and a.tipo <> 'admin'
     and a.es_automatico = false
     and a.estado = 'aprobado'
     and (p_excluir is null or a.id_anuncio <> p_excluir);
$$;

-- ---------------------------------------------------------------------------
-- 1) Migración de permisos viejos -> permisos_usuario_anuncios (copia)
-- ---------------------------------------------------------------------------
alter table public.permisos_usuario_anuncios add column if not exists origen    text;
alter table public.permisos_usuario_anuncios add column if not exists origen_id uuid;

insert into public.permisos_usuario_anuncios
       (id_usuario, id_paquete, max_anuncios, desde, hasta, activo, origen, origen_id)
select n.id_dueno,
       coalesce(pn.id_paquete, (select id_paquete from paquetes_anuncio order by orden limit 1)),
       pn.max_anuncios, pn.desde, pn.hasta, true, 'negocio', pn.id_permiso
  from permisos_negocio pn
  join negocios n on n.id_negocio = pn.id_negocio
 where pn.activo and pn.hasta > now()
   and not exists (select 1 from permisos_usuario_anuncios x
                    where x.origen = 'negocio' and x.origen_id = pn.id_permiso);

insert into public.permisos_usuario_anuncios
       (id_usuario, id_paquete, max_anuncios, desde, hasta, activo, origen, origen_id)
select t.owner_id,
       (select id_paquete from paquetes_anuncio order by orden limit 1),
       pt.max_anuncios_extra, pt.desde, pt.hasta, true, 'tienda', pt.id_permiso
  from permisos_tienda_anuncios pt
  join tiendas t on t.id_tienda = pt.id_tienda
 where pt.activo and pt.hasta > now()
   and not exists (select 1 from permisos_usuario_anuncios x
                    where x.origen = 'tienda' and x.origen_id = pt.id_permiso);

-- ---------------------------------------------------------------------------
-- 2) Constraint de destino: permisivo (standalone puede llevar vínculos)
-- ---------------------------------------------------------------------------
alter table public.anuncios drop constraint if exists chk_destino_anuncio;
alter table public.anuncios
  add constraint chk_destino_anuncio check (tipo <> 'negocio' or id_negocio is not null);

-- ---------------------------------------------------------------------------
-- 3) Retirar el anuncio automático de negocio
-- ---------------------------------------------------------------------------
drop trigger if exists trg_negocios_sync_anuncio on public.negocios;
drop trigger if exists trg_permisos_negocio_sync on public.permisos_negocio;

-- ---------------------------------------------------------------------------
-- 4) INSERT: admin intacto + standalone unificado. Tipos viejos bloqueados.
-- ---------------------------------------------------------------------------
create or replace function public.anuncios_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_activos int;
  v_permiso public.permisos_usuario_anuncios%rowtype;
begin
  if new.creado_por is null then
    new.creado_por := auth.uid();
  end if;

  -- inserts del sistema (anuncios automáticos ya existentes)
  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true' then
    return new;
  end if;

  -- ---------------- ADMIN (sin cambios)
  if new.tipo = 'admin' then
    if not es_admin() then
      raise exception 'SOLO_ADMIN';
    end if;
    new.estado := 'aprobado';
    if new.vigencia_hasta is null then
      new.vigencia_hasta := now() + interval '30 days';
    end if;

  -- ---------------- STANDALONE unificado
  elsif new.tipo = 'standalone' then
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;

    -- vínculos opcionales: solo a cosas PROPIAS
    if new.id_producto is not null then
      select p.id_tienda into new.id_tienda
        from productos p where p.id_producto = new.id_producto;
      if new.id_tienda is null then
        raise exception 'PRODUCTO_INEXISTENTE';
      end if;
    end if;
    if new.id_tienda is not null then
      if not exists (select 1 from tiendas t
                      where t.id_tienda = new.id_tienda and t.owner_id = new.creado_por) then
        raise exception 'TIENDA_AJENA';
      end if;
    end if;
    if new.id_negocio is not null then
      if not exists (select 1 from negocios n
                      where n.id_negocio = new.id_negocio
                        and n.id_dueno = new.creado_por and n.estado = 'activo') then
        raise exception 'NEGOCIO_NO_HABILITADO';
      end if;
    end if;

    -- WhatsApp: normaliza y completa desde tienda/negocio
    new.whatsapp := fn_normalizar_whatsapp(new.whatsapp);
    if new.whatsapp is null and new.id_tienda is not null then
      select fn_normalizar_whatsapp(t.telefono_whatsapp) into new.whatsapp
        from tiendas t where t.id_tienda = new.id_tienda;
    end if;
    if new.whatsapp is null and new.id_negocio is not null then
      select fn_normalizar_whatsapp(n.whatsapp) into new.whatsapp
        from negocios n where n.id_negocio = new.id_negocio;
    end if;
    if new.whatsapp is null then
      raise exception 'WHATSAPP_REQUERIDO: agrega un número de WhatsApp para tu anuncio.';
    end if;

    -- cupo
    if new.id_permiso_usuario is not null then
      select * into v_permiso
        from permisos_usuario_anuncios where id_permiso = new.id_permiso_usuario;

      if v_permiso.id_permiso is null
         or v_permiso.id_usuario <> new.creado_por
         or not v_permiso.activo
         or v_permiso.hasta <= now() then
        raise exception 'PERMISO_INVALIDO: la ranura elegida no existe o ya no está vigente.';
      end if;

      select count(*) into v_activos
        from anuncios
       where tipo = 'standalone'
         and id_permiso_usuario = new.id_permiso_usuario
         and estado = 'aprobado';

      if v_activos >= v_permiso.max_anuncios then
        raise exception 'CUPO_ANUNCIOS: esa ranura ya no tiene espacio libre.';
      end if;
      new.vigencia_hasta := v_permiso.hasta;
    else
      -- pool: ranuras del plan de la tienda + permisos vigentes
      if fn_anuncios_usados(new.creado_por) >= fn_ranuras_pool(new.creado_por) then
        raise exception 'CUPO_ANUNCIOS: no tienes ranuras libres. Compra un paquete o pausa otro anuncio.';
      end if;
      if fn_plan_ranuras(new.creado_por) > 0 then
        new.vigencia_hasta := null;            -- vive mientras el plan dé ranuras
      else
        select max(pu.hasta) into new.vigencia_hasta
          from permisos_usuario_anuncios pu
         where pu.id_usuario = new.creado_por and pu.activo and pu.hasta > now();
      end if;
    end if;

    new.estado := 'aprobado';

  else
    -- 'producto' y 'negocio' ya no se crean: un cliente viejo no puede
    -- saltarse las reglas.
    raise exception 'TIPO_OBSOLETO: actualiza la app para publicar anuncios.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5) UPDATE: igual al vivo, solo cambia el cupo del standalone sin permiso
--    (ahora cuenta plan + permisos y todos los anuncios del usuario).
-- ---------------------------------------------------------------------------
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

  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true' then
    return new;
  end if;

  -- solo métricas
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

  if old.es_automatico = true then
    raise exception 'CAMPO_PROTEGIDO: este anuncio se gestiona automáticamente con tu paquete.';
  end if;

  -- pausar / reactivar del dueño
  if new.estado is distinct from old.estado then
    if old.tipo in ('producto', 'negocio', 'standalone')
       and ((old.estado = 'aprobado' and new.estado = 'pausado')
          or (old.estado = 'pausado' and new.estado = 'aprobado')) then

      if old.estado = 'pausado' then
        if old.tipo = 'producto' then
          select count(*) into v_activos
            from anuncios
           where tipo = 'producto' and id_tienda = old.id_tienda
             and estado = 'aprobado' and id_anuncio <> old.id_anuncio;
          select coalesce(max(pl.ranuras_anuncios), 0) into v_max
            from tiendas t left join planes pl on pl.codigo = t.plan
           where t.id_tienda = old.id_tienda;

        elsif old.tipo = 'negocio' then
          select count(*) into v_activos
            from anuncios
           where tipo = 'negocio' and id_negocio = old.id_negocio
             and estado in ('pendiente', 'aprobado') and id_anuncio <> old.id_anuncio;
          select least(coalesce(sum(pn.max_anuncios), 0), 5) into v_max
            from permisos_negocio pn
           where pn.id_negocio = old.id_negocio and pn.activo and pn.hasta > now();

        else -- standalone
          if old.id_permiso_usuario is not null then
            select count(*) into v_activos
              from anuncios
             where tipo = 'standalone'
               and id_permiso_usuario = old.id_permiso_usuario
               and estado = 'aprobado' and id_anuncio <> old.id_anuncio;
            select coalesce(max_anuncios, 0) into v_max
              from permisos_usuario_anuncios
             where id_permiso = old.id_permiso_usuario and activo and hasta > now();
          else
            v_activos := fn_anuncios_usados(old.creado_por, old.id_anuncio);
            v_max     := fn_ranuras_pool(old.creado_por);
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

  if new.motivo_rechazo is distinct from old.motivo_rechazo
     or new.vigencia_hasta is distinct from old.vigencia_hasta
     or new.tipo is distinct from old.tipo
     or new.id_negocio is distinct from old.id_negocio
     or new.id_producto is distinct from old.id_producto
     or new.es_automatico is distinct from old.es_automatico then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;

  -- re-moderación: solo anuncios 'negocio' VIEJOS
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

-- ---------------------------------------------------------------------------
-- 6) WhatsApp: respaldo (completa desde tienda/negocio antes de rechazar)
-- ---------------------------------------------------------------------------
create or replace function public.anuncios_exigir_whatsapp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.tipo = 'admin' then
    return new;
  end if;
  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true'
     or new.es_automatico = true then
    return new;
  end if;

  new.whatsapp := fn_normalizar_whatsapp(new.whatsapp);
  if new.whatsapp is null and new.id_tienda is not null then
    select fn_normalizar_whatsapp(t.telefono_whatsapp) into new.whatsapp
      from tiendas t where t.id_tienda = new.id_tienda;
  end if;
  if new.whatsapp is null and new.id_negocio is not null then
    select fn_normalizar_whatsapp(n.whatsapp) into new.whatsapp
      from negocios n where n.id_negocio = new.id_negocio;
  end if;
  if new.whatsapp is null then
    raise exception 'WHATSAPP_REQUERIDO: agrega un numero de WhatsApp para tu anuncio.';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7) Compras aprobadas -> SIEMPRE crean permiso de usuario
--    (compras viejas de negocio/tienda que aún estén pendientes también).
--    Las compras standalone las sigue manejando fn_aprobar_compra_standalone.
-- ---------------------------------------------------------------------------
create or replace function public.compras_anuncio_aprobar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paquete public.paquetes_anuncio%rowtype;
  v_dueno   uuid;
begin
  if new.estado = 'aprobada' and old.estado is distinct from 'aprobada' then
    select * into v_paquete from paquetes_anuncio where id_paquete = new.id_paquete;

    if new.id_negocio is not null then
      select n.id_dueno into v_dueno from negocios n where n.id_negocio = new.id_negocio;
    elsif new.id_tienda is not null then
      select t.owner_id into v_dueno from tiendas t where t.id_tienda = new.id_tienda;
    end if;

    if v_dueno is not null then
      insert into permisos_usuario_anuncios
             (id_usuario, id_paquete, max_anuncios, desde, hasta, origen, origen_id)
      values (v_dueno, new.id_paquete, v_paquete.max_anuncios, now(),
              now() + make_interval(days => v_paquete.duracion_dias),
              'compra', new.id_compra);

      insert into public.notificaciones
             (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
      values (v_dueno, '¡Ranuras activadas! 🎉',
              'Verificamos tu pago y ya puedes publicar tus anuncios desde Mi perfil > Anuncios.',
              'anuncio',
              jsonb_build_object('id_compra', new.id_compra,
                                 'codigo_ref', coalesce(new.codigo_ref, '')),
              false, now());
    end if;
  end if;

  if new.estado = 'rechazada' and old.estado is distinct from 'rechazada' then
    v_dueno := coalesce(
      (select t.owner_id from tiendas t where t.id_tienda = new.id_tienda),
      (select n.id_dueno from negocios n where n.id_negocio = new.id_negocio));

    if v_dueno is not null then
      insert into public.notificaciones
             (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
      values (v_dueno, 'Compra no verificada',
              'No pudimos validar el comprobante'
                || case when new.codigo_ref is not null then ' de ' || new.codigo_ref else '' end
                || '. Escríbenos por WhatsApp para revisarlo.',
              'anuncio',
              jsonb_build_object('id_compra', new.id_compra,
                                 'codigo_ref', coalesce(new.codigo_ref, '')),
              false, now());
    end if;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8) FEED único. Se elimina la sobrecarga vieja de 1 argumento.
--    admin / negocio(viejos) / producto(viejos) idénticos a hoy; el bucket
--    standalone ahora trae destino y filtra ubicación solo si hay tienda.
-- ---------------------------------------------------------------------------
drop function if exists public.obtener_anuncios_feed(integer);

create or replace function public.obtener_anuncios_feed(
  p_cantidad integer default 6,
  provincia text default null,
  municipio text default null
)
returns table (anuncio jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config     jsonb;
  v_sin        timestamptz;
  v_admins     jsonb := '[]'::jsonb;
  v_negs       jsonb := '[]'::jsonb;
  v_prods      jsonb := '[]'::jsonb;
  v_standalone jsonb := '[]'::jsonb;
  v_result     jsonb := '[]'::jsonb;
  v_tomado     boolean;
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

  -- ADMIN (sin cambios)
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

  -- NEGOCIO (anuncios viejos que sigan vigentes)
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

  -- PRODUCTO (anuncios viejos que sigan vigentes)
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

  -- STANDALONE UNIFICADO
  select coalesce(jsonb_agg(x.j), '[]') into v_standalone
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'precio_usd', a.precio_usd, 'whatsapp', a.whatsapp,
      'destino_nombre', coalesce(p.nombre, n.nombre, t.nombre),
      'destino_imagen', coalesce(p.imagen_url, n.logo_url, t.logo_url)
    ) as j
    from anuncios a
    left join productos p on p.id_producto = a.id_producto
    left join tiendas   t on t.id_tienda   = a.id_tienda
    left join negocios  n on n.id_negocio  = a.id_negocio
    where a.tipo = 'standalone' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
      and (a.id_tienda is null or (
            t.estado = 'active' and coalesce(t.eliminada, false) = false
            and (provincia is null or t.provincia = provincia)
            and (municipio is null or t.municipio = municipio)))
      and (a.id_negocio is null or n.estado = 'activo')
      and (a.id_producto is null or p.es_visible = true)
    order by a.veces_mostrado asc, random()
    limit p_cantidad
  ) x(j);

  loop
    exit when jsonb_array_length(v_result) >= p_cantidad;
    v_tomado := false;

    if jsonb_array_length(v_admins) > 0 then
      v_result := v_result || (v_admins -> 0); v_admins := v_admins - 0; v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_negs) > 0 then
      v_result := v_result || (v_negs -> 0); v_negs := v_negs - 0; v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_prods) > 0 then
      v_result := v_result || (v_prods -> 0); v_prods := v_prods - 0; v_tomado := true;
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
grant execute on function public.obtener_anuncios_feed(integer, text, text)
  to anon, authenticated, service_role;

commit;

-- =============================================================================
-- VERIFICACIÓN (ejecutar aparte):
--
-- select origen, count(*), sum(max_anuncios) from permisos_usuario_anuncios group by 1;
-- select tipo, estado, count(*) from anuncios group by 1,2 order by 1,2;
-- select count(*) from obtener_anuncios_feed(6, null, null);
-- select destino, standalone, nombre, precio_usd, activo from paquetes_anuncio order by orden;
-- =============================================================================
