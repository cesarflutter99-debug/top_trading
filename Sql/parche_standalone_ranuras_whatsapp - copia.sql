-- parche_standalone_ranuras_whatsapp.sql
-- ===========================================================================
-- Ajustes al flujo de ANUNCIO INDEPENDIENTE (standalone):
--
--   1) anuncios.id_permiso_usuario -- ahora el usuario ELIGE de qué
--      ranura (permiso comprado: 1 semana / 1 mes / 3 meses...) se
--      descuenta su anuncio, en vez de un pool agregado sin distinción.
--      El cupo/vigencia del anuncio dependen de ESE permiso puntual.
--   2) anuncios.precio_usd y anuncios.whatsapp -- obligatorios para
--      tipo='standalone'. Se usan para armar el mensaje de WhatsApp
--      "Me interesa" cuando alguien toca el anuncio en el feed.
--   3) anuncios_before_insert(): valida el permiso elegido (dueño,
--      vigente, con cupo) y usa SU hasta como vigencia_hasta. Exige
--      whatsapp no vacío.
--   4) anuncios_before_update(): permite pausar/reactivar anuncios
--      standalone (antes solo producto/negocio podían), revalidando
--      cupo del permiso al reactivar.
--   5) anuncio_delete: el dueño puede eliminar sus anuncios standalone
--      en cualquier estado (igual que ya podía con 'producto').
--   6) obtener_anuncios_feed(): se agrega el grupo STANDALONE a la
--      rotación del feed (antes nunca aparecían), y se agregan los
--      campos precio_usd/whatsapp en TODOS los tipos para que la
--      tarjeta pueda armar el botón de WhatsApp cuando corresponda.
--
-- Ejecutar UNA vez en el SQL Editor de Supabase. Idempotente.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Columnas nuevas en anuncios.
-- ---------------------------------------------------------------------------
alter table public.anuncios
  add column if not exists precio_usd numeric(10,2);

alter table public.anuncios
  add column if not exists whatsapp text;

alter table public.anuncios
  add column if not exists id_permiso_usuario uuid
    references public.permisos_usuario_anuncios(id_permiso) on delete set null;

create index if not exists idx_anuncios_permiso_usuario
  on public.anuncios (id_permiso_usuario);


-- ---------------------------------------------------------------------------
-- 2) anuncios_before_insert() -- reescrito: agrega validación de
--    permiso elegido + whatsapp obligatorio en la rama 'standalone'.
--    El resto (admin/producto/negocio) queda igual que antes.
-- ---------------------------------------------------------------------------
create or replace function public.anuncios_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_activos int;
  v_permiso public.permisos_usuario_anuncios%rowtype;
begin
  if new.creado_por is null then
    new.creado_por := auth.uid();
  end if;

  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true' then
    return new;
  end if;

  if new.tipo = 'admin' then
    if not es_admin() then
      raise exception 'SOLO_ADMIN';
    end if;
    new.estado := 'aprobado';
    if new.vigencia_hasta is null then
      new.vigencia_hasta := now() + interval '30 days';
    end if;

  elsif new.tipo = 'producto' then
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;

    if new.id_producto is not null then
      select p.id_tienda into new.id_tienda
      from productos p
      where p.id_producto = new.id_producto;
      if new.id_tienda is null then
        raise exception 'PRODUCTO_INEXISTENTE';
      end if;
    else
      if not exists (
        select 1 from tiendas t
        where t.id_tienda = new.id_tienda and t.owner_id = auth.uid()
      ) then
        raise exception 'TIENDA_AJENA';
      end if;
    end if;
    new.vigencia_hasta := null;

    select count(*) into v_activos
    from anuncios
    where tipo = 'producto' and id_tienda = new.id_tienda and estado = 'aprobado';

    select coalesce(max(pl.ranuras_anuncios), 0) into v_max
    from tiendas t
    left join planes pl on pl.codigo = t.plan
    where t.id_tienda = new.id_tienda;

    if v_activos >= coalesce(v_max, 0) then
      raise exception 'CUPO_ANUNCIOS: tu plan actual no tiene ranuras libres. Sube de plan o pon en pausa otro anuncio.';
    end if;
    new.estado := 'aprobado';

  elsif new.tipo = 'negocio' then
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;
    if not exists (
      select 1 from negocios n
      where n.id_negocio = new.id_negocio
        and n.id_dueno = new.creado_por
        and n.estado = 'activo'
    ) then
      raise exception 'NEGOCIO_NO_HABILITADO';
    end if;

    if not exists (
      select 1 from permisos_negocio pn
      where pn.id_negocio = new.id_negocio
        and pn.activo and pn.hasta > now()
    ) then
      raise exception 'SIN_PERMISO_VIGENTE: compra o renueva un paquete de anuncio.';
    end if;

    select least(coalesce(sum(pn.max_anuncios), 0), 5) into v_max
    from permisos_negocio pn
    where pn.id_negocio = new.id_negocio and pn.activo and pn.hasta > now();

    select count(*) into v_activos
    from anuncios
    where tipo = 'negocio' and id_negocio = new.id_negocio
      and estado in ('pendiente', 'aprobado');

    if v_activos >= coalesce(v_max, 0) then
      raise exception 'CUPO_ANUNCIOS: alcanzaste el máximo simultáneo de tu paquete.';
    end if;

    new.estado := 'pendiente';
    select max(pn.hasta) into new.vigencia_hasta
    from permisos_negocio pn
    where pn.id_negocio = new.id_negocio and pn.activo and pn.hasta > now();

  elsif new.tipo = 'standalone' then
    if new.id_tienda is not null then
      raise exception 'STANDALONE_SIN_TIENDA: los anuncios standalone no deben tener id_tienda.';
    end if;
    if new.id_negocio is not null then
      raise exception 'STANDALONE_SIN_NEGOCIO: los anuncios standalone no deben tener id_negocio.';
    end if;
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;
    if new.whatsapp is null or trim(new.whatsapp) = '' then
      raise exception 'WHATSAPP_REQUERIDO: agrega un número de WhatsApp para tu anuncio.';
    end if;

    -- El usuario ELIGE de qué permiso (ranura comprada) se descuenta.
    if new.id_permiso_usuario is not null then
      select * into v_permiso
      from permisos_usuario_anuncios
      where id_permiso = new.id_permiso_usuario;

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
      -- Compatibilidad: si no se especifica permiso, se usa el pool
      -- agregado de todos los permisos vigentes (comportamiento previo).
      select coalesce(sum(pu.max_anuncios), 0) into v_max
      from permisos_usuario_anuncios pu
      where pu.id_usuario = new.creado_por
        and pu.activo
        and pu.hasta > now();

      select count(*) into v_activos
      from anuncios
      where tipo = 'standalone' and creado_por = new.creado_por and estado = 'aprobado';

      if v_activos >= coalesce(v_max, 0) then
        raise exception 'CUPO_ANUNCIOS: alcanzaste el máximo de anuncios independientes de tu paquete.';
      end if;

      select max(pu.hasta) into new.vigencia_hasta
      from permisos_usuario_anuncios pu
      where pu.id_usuario = new.creado_por and pu.activo and pu.hasta > now();
    end if;

    new.estado := 'aprobado';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_anuncios_insert on public.anuncios;
create trigger trg_anuncios_insert
before insert on public.anuncios
for each row execute function public.anuncios_before_insert();


-- ---------------------------------------------------------------------------
-- 3) anuncios_before_update() -- se agrega 'standalone' a la lista de
--    tipos que el dueño puede pausar/reactivar él mismo, revalidando
--    cupo del permiso puntual al reactivar.
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

  if new.motivo_rechazo is distinct from old.motivo_rechazo
     or new.vigencia_hasta is distinct from old.vigencia_hasta
     or new.veces_mostrado is distinct from old.veces_mostrado
     or new.veces_clickeado is distinct from old.veces_clickeado
     or new.tipo is distinct from old.tipo
     or new.id_negocio is distinct from old.id_negocio
     or new.id_producto is distinct from old.id_producto
     or new.id_permiso_usuario is distinct from old.id_permiso_usuario
     or (old.es_automatico = true
         and coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'false') then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;

  if old.tipo = 'negocio' and old.estado in ('rechazado', 'aprobado') then
    new.estado := 'pendiente';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_anuncios_update on public.anuncios;
create trigger trg_anuncios_update
before update on public.anuncios
for each row execute function public.anuncios_before_update();


-- ---------------------------------------------------------------------------
-- 4) anuncio_delete -- el dueño puede eliminar sus anuncios standalone
--    en cualquier estado (mismo trato que 'producto').
-- ---------------------------------------------------------------------------
drop policy if exists anuncio_delete on public.anuncios;
create policy anuncio_delete on public.anuncios for delete
  using (
    es_admin() or (
      creado_por = auth.uid()
      and es_automatico = false
      and (estado in ('pendiente','rechazado','pausado') or tipo in ('producto','standalone'))
    )
  );


-- ---------------------------------------------------------------------------
-- 5) obtener_anuncios_feed() -- se agrega el grupo STANDALONE a la
--    rotación (antes nunca se mostraban en el feed) y se incluyen
--    precio_usd/whatsapp en todos los tipos.
-- ---------------------------------------------------------------------------
create or replace function public.obtener_anuncios_feed(p_cantidad int default 3)
returns table (anuncio jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config   jsonb;
  v_sin      timestamptz;
  v_admins   jsonb := '[]'::jsonb;
  v_negs     jsonb := '[]'::jsonb;
  v_prods    jsonb := '[]'::jsonb;
  v_standalone jsonb := '[]'::jsonb;
  v_result   jsonb := '[]'::jsonb;
  v_tomado   boolean;
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

  select coalesce(jsonb_agg(x.j), '[]')
  into v_admins
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
    limit p_cantidad
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
    limit p_cantidad
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
      and (a.id_producto is null or p.es_visible = true)
    order by a.veces_mostrado asc, random()
    limit p_cantidad
  ) x(j);

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
    limit p_cantidad
  ) x(j);

  loop
    exit when jsonb_array_length(v_result) >= p_cantidad;
    v_tomado := false;

    if jsonb_array_length(v_admins) > 0 then
      v_result := v_result || (v_admins -> 0);  v_admins := v_admins - 0;  v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_negs) > 0 then
      v_result := v_result || (v_negs -> 0);    v_negs := v_negs - 0;    v_tomado := true;
    end if;
    exit when jsonb_array_length(v_result) >= p_cantidad;

    if jsonb_array_length(v_prods) > 0 then
      v_result := v_result || (v_prods -> 0);   v_prods := v_prods - 0;  v_tomado := true;
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

grant execute on function public.obtener_anuncios_feed(int) to anon, authenticated;