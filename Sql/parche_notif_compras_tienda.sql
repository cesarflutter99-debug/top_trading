-- parche_notif_compras_tienda.sql
-- ===========================================================================
-- NOTIFICACIONES COMPLETAS AL LADO — parche consolidado.
-- ===========================================================================
-- Cubre las notificaciones de compras de ranuras/paquetes de anuncio Y
-- las notificaciones que faltaban por completo en el sistema.
--
-- SECCION 1 — Compras de RANURAS EXTRA DE TIENDA y paquetes de NEGOCIO:
--   - Las compras de ranuras extra de TIENDA se registran en
--     compras_anuncio con id_tienda (sin id_negocio).
--   - El trigger original (compras_anuncio_aprobar) solo acreditaba
--     permisos_negocio y exigia id_negocio NOT NULL.
--   - Acá se hace id_negocio nullable, se agrega id_tienda, se acredita
--     el permiso correcto y se NOTIFICA al dueño (aprobada y rechazada)
--     insertando una fila real en notificaciones.
--
-- SECCION 2 — Notificaciones que faltaban por completo:
--   2a. negocio_aprobado / negocio_rechazado / negocio_suspendido
--   2b. tienda_rechazada
--   2c. pedido_cancelado_comprador (al vendedor) y pedido_completado (al
--       comprador)
--   2d. anuncio_por_vencer (recordatorio antes de caerse del feed)
--
-- Ejecutar UNA sola vez en el SQL editor de Supabase.
--
-- OJO columnas asumidas (edita si tu BD difiere):
--   - notificaciones(id_usuario, titulo, mensaje, tipo, data jsonb,
--                    leida, creado_en)
--   - pedidos(numero_pedido, id_tienda, id_comprador, estado,
--             cancelado_por)   <- cancelado_por lo pone fn_cancelar_pedido
--   - tiendas(estado 'pending'/'active', owner_id, motivo_rechazo?)
--   - negocios(estado, id_dueno, motivo_rechazo)  [versionado]
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Columnas de compras_anuncio para soportar compras de tienda.
-- ---------------------------------------------------------------------------
alter table public.compras_anuncio
  alter column id_negocio drop not null;

alter table public.compras_anuncio
  add column if not exists id_tienda uuid references public.tiendas(id_tienda)
    on delete cascade;

create index if not exists idx_compras_tienda on public.compras_anuncio (id_tienda);


-- ---------------------------------------------------------------------------
-- 2) Trigger de aprobacion: acredita el permiso correspondiente Y notifica.
--    Nota: ajusta el nombre/columnas de permisos_tienda_anuncios si en tu
--    base difieren (aqui se asume el esquema documentado en la app:
--    id_permiso, id_tienda, max_anuncios_extra, desde, hasta, activo).
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
      -- Compra de paquete de NEGOCIO -> permisos_negocio
      insert into permisos_negocio (id_negocio, id_paquete, max_anuncios, desde, hasta)
      values (
        new.id_negocio,
        new.id_paquete,
        v_paquete.max_anuncios,
        now(),
        now() + make_interval(days => v_paquete.duracion_dias)
      );

      select n.id_dueno into v_dueno
      from negocios n
      where n.id_negocio = new.id_negocio;

    elsif new.id_tienda is not null then
      -- Compra de RANURAS EXTRA de TIENDA -> permisos_tienda_anuncios
      insert into permisos_tienda_anuncios
             (id_tienda, max_anuncios_extra, desde, hasta)
      values (
        new.id_tienda,
        v_paquete.max_anuncios,
        now(),
        now() + make_interval(days => v_paquete.duracion_dias)
      );

      select t.owner_id into v_dueno
      from tiendas t
      where t.id_tienda = new.id_tienda;
    end if;

    -- Notificacion al dueño (negocio o tienda) de que el pago se verifico.
    if v_dueno is not null then
      insert into public.notificaciones
             (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
      values (
        v_dueno,
        case
          when new.id_tienda is not null
            then '¡Ranuras activadas! ✨'
          else '¡Paquete activado! 🎉'
        end,
        case
          when new.id_tienda is not null
            then 'Verificamos tu pago y ya puedes publicar tus anuncios '
                 'con las ranuras extra de tu tienda.'
          else 'Verificamos tu pago y ya puedes publicar tus anuncios '
               'de negocio.'
        end,
        'anuncio',
        jsonb_build_object(
          'id_compra', new.id_compra,
          'codigo_ref', coalesce(new.codigo_ref, '')
        ),
        false,
        now()
      );
    end if;
  end if;

  -- Compra RECHAZADA por el admin -> avisar al dueño para que hable con
  -- soporte por WhatsApp. (Igual que la del negocio, pero también cubre
  -- la compra de ranuras de tienda.)
  if new.estado = 'rechazada' and old.estado is distinct from 'rechazada' then
    select coalesce(t.owner_id, n.id_dueno) into v_dueno
    from (select new.id_tienda::uuid as id_tienda, new.id_negocio::uuid as id_negocio) x
    left join tiendas t on t.id_tienda = x.id_tienda and x.id_tienda is not null
    left join negocios n on n.id_negocio = x.id_negocio and x.id_negocio is not null;

    if v_dueno is not null then
      insert into public.notificaciones
             (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
      values (
        v_dueno,
        'Compra no verificada',
        'No pudimos validar el comprobante'
          || case when new.codigo_ref is not null
                  then ' de ' || new.codigo_ref else '' end
          || '. Escríbenos por WhatsApp para revisarlo.',
        'anuncio',
        jsonb_build_object(
          'id_compra', new.id_compra,
          'codigo_ref', coalesce(new.codigo_ref, '')
        ),
        false,
        now()
      );
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_compras_anuncio_aprobar on public.compras_anuncio;
create trigger trg_compras_anuncio_aprobar
after update on public.compras_anuncio
for each row execute function public.compras_anuncio_aprobar();


-- ---------------------------------------------------------------------------
-- 3) RLS: permitir que el vendedor lea sus compras de ranuras de tienda.
--    (Las de negocio ya tienen su politica; esta cubre id_tienda).
-- ---------------------------------------------------------------------------
drop policy if exists compra_select_tienda on public.compras_anuncio;
create policy compra_select_tienda on public.compras_anuncio
  for select to authenticated
  using (
    id_tienda is not null and exists (
      select 1 from tiendas t
      where t.id_tienda = compras_anuncio.id_tienda
        and t.owner_id = auth.uid()
    )
  );


-- ===========================================================================
-- SECCION 2 — NOTIFICACIONES FALTANTES (negocios, tiendas, pedidos,
-- anuncios por vencer). Cada trigger inserta una FILA REAL en
-- notificaciones, así la notificación llega por el canal Realtime (y
-- sobrevive aunque la app esté cerrada), en vez de depender de un aviso
-- local del dispositivo.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 2a. NEGOCIOS — avisar al dueño cuando el admin aprueba, rechaza o
--     suspende su negocio. Tabla `negocios` versionada: estado en
--     ('pendiente','activo','rechazado','suspendido') + motivo_rechazo.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_estado_negocio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulo  text;
  v_mensaje text;
  v_tipo    text;
begin
  if old.estado is not distinct from new.estado then
    return new;
  end if;

  if new.estado = 'activo' then
    v_tipo    := 'negocio_aprobado';
    v_titulo  := '¡Tu negocio fue aprobado! ✅';
    v_mensaje := '"' || coalesce(new.nombre, 'Tu negocio') || '" ya está '
                 || 'visible en el marketplace.';
  elsif new.estado = 'rechazado' then
    v_tipo    := 'negocio_rechazado';
    v_titulo  := 'Tu negocio no fue aprobado';
    v_mensaje := '"' || coalesce(new.nombre, 'Tu negocio') || '" fue '
                 || 'rechazado. Edita los datos y vuelve a intentarlo'
                 || case when new.motivo_rechazo is not null
                         then ' Motivo: ' || new.motivo_rechazo
                         else '' end;
  elsif new.estado = 'suspendido' then
    v_tipo    := 'negocio_suspendido';
    v_titulo  := 'Tu negocio fue suspendido';
    v_mensaje := '"' || coalesce(new.nombre, 'Tu negocio') || '" fue '
                 || 'suspendido temporalmente por moderación.'
                 || case when new.motivo_rechazo is not null
                         then ' Motivo: ' || new.motivo_rechazo
                         else '' end;
  else
    return new;
  end if;

  insert into public.notificaciones
         (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
  values (
    new.id_dueno,
    v_titulo,
    v_mensaje,
    v_tipo,
    jsonb_build_object('id_negocio', new.id_negocio),
    false,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_notif_estado_negocio on public.negocios;
create trigger trg_notif_estado_negocio
after update on public.negocios
for each row execute function public.notificar_estado_negocio();


-- ---------------------------------------------------------------------------
-- 2b. TIENDAS — avisar al vendedor cuando el admin rechaza la tienda
--     nueva. La aprobación ya tiene su notificación (tienda_aprobada);
--     este cubre el caso de rechazo (estado != 'active' y distinto de
--     'pending'). Si tu BD usa otro valor para el rechazo ("rejected",
--     "rechazada", etc.) el mensaje aparece igual; solo avisamos cuando
--     el admin SALIÓ de pending sin activar.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_tienda_rechazada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.estado is distinct from 'pending' or new.estado = 'active'
     or new.estado = 'pending' then
    return new;
  end if;

  insert into public.notificaciones
         (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
  values (
    new.owner_id,
    'Tu tienda no fue aprobada',
    '"' || coalesce(new.nombre, 'Tu tienda') || '" fue rechazada por el admin. '
      || 'Ajusta los datos y vuelve a enviar tu solicitud.',
    'tienda_rechazada',
    jsonb_build_object('id_tienda', new.id_tienda),
    false,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_notif_tienda_rechazada on public.tiendas;
create trigger trg_notif_tienda_rechazada
after update on public.tiendas
for each row execute function public.notificar_tienda_rechazada();


-- ---------------------------------------------------------------------------
-- 2c. PEDIDOS — dos flujos:
--       • pedido_cancelado_comprador -> avisa al VENDEDOR cuando el
--         comprador cancela su propio pedido.
--       • pedido_completado          -> avisa al COMPRADOR cuando el
--         vendedor entrega y marca la venta como completada.
--     Necesita la columna `pedidos.cancelado_por` (puesto por
--     fn_cancelar_pedido con 'comprador'/'vendedor'); si tu BD no la
--     tiene, edita o quita esa condición.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_estado_pedido()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cancelado_por text;
  v_tiene_quien   boolean;
begin
  if old.estado is not distinct from new.estado then
    return new;
  end if;

  -- Cancelado por el COMPRADOR -> avisar al vendedor. Comprobamos antes
  -- si la columna cancelado_por existe (la pone fn_cancelar_pedido); si
  -- no existe, tratamos toda cancelación igual (seguro pero menos fino).
  if new.estado = 'cancelado' then
    v_tiene_quien := exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'pedidos'
        and column_name = 'cancelado_por'
    );
    if v_tiene_quien then
      execute 'select cancelado_por from public.pedidos where id_pedido = $1'
        into v_cancelado_por using new.id_pedido;
    end if;

    if not v_tiene_quien or coalesce(v_cancelado_por, '') = 'comprador' then
      insert into public.notificaciones
             (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
      select
        t.owner_id,
        'Un pedido fue cancelado',
        'El comprador canceló el pedido #' || coalesce(new.numero_pedido::text, '')
          || ' antes de completarse. El stock ya se liberó.',
        'pedido_cancelado_comprador',
        jsonb_build_object('id_pedido', new.id_pedido,
                           'id_tienda', new.id_tienda::text),
        false,
        now()
      from tiendas t
      where t.id_tienda = new.id_tienda;
    end if;

  -- Venta completada -> avisar al comprador
  elsif new.estado = 'completado' then
    insert into public.notificaciones
           (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
    values (
      new.id_comprador,
      '¡Tu pedido fue entregado! ✅',
      'El vendedor marcó como completado el pedido #'
        || coalesce(new.numero_pedido::text, '') || '. '
        || 'Cuéntanos cómo te fue con tu compra.',
      'pedido_completado',
      jsonb_build_object('id_pedido', new.id_pedido,
                         'id_tienda', new.id_tienda::text),
      false,
      now()
    );
  end if;

  return new;
end;
$$;

drop trigger if exists trg_notif_estado_pedido on public.pedidos;
create trigger trg_notif_estado_pedido
after update on public.pedidos
for each row execute function public.notificar_estado_pedido();


-- ---------------------------------------------------------------------------
-- 2d. ANUNCIO POR VENCER + PAQUETE POR VENCER — avisa al creador/dueño
--     antes de que el anuncio se caiga del feed.
--     Se integra con anuncios_limpiar_estados() (ya existente): cada
--     vez que se limpian estados, si un anuncio aprobado tiene menos de
--     X días de vida y aún no se avisó, se inserta el recordatorio.
--     Guardamos el aviso en notificaciones.data.ya_avisado_aviso para no
--     duplicar (si se vuelve a llamar, no repite).
-- ---------------------------------------------------------------------------
create or replace function public.anuncios_avisar_por_vencer()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
begin
  for r in
    select a.id_anuncio, a.titulo, a.vigencia_hasta, a.creado_por
    from anuncios a
    where a.estado = 'aprobado'
      and a.vigencia_hasta is not null
      and a.vigencia_hasta > now()
      and a.vigencia_hasta - now() <= interval '2 days'
    loop
      -- no repetir si ya avisamos de este anuncio
      if not exists (
        select 1 from notificaciones n
        where n.id_usuario = r.creado_por
          and n.tipo = 'anuncio_por_vencer'
          and n.data ->> 'id_anuncio' = r.id_anuncio::text
      ) then
        insert into public.notificaciones
               (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
        values (
          r.creado_por,
          'Tu anuncio está por vencer',
          '"' || coalesce(r.titulo, 'Tu anuncio') || '" se caerá del feed '
            || 'en menos de 2 días. Renueva tu paquete para mantenerlo.',
          'anuncio_por_vencer',
          jsonb_build_object('id_anuncio', r.id_anuncio::text),
          false,
          now()
        );
      end if;
    end loop;
end;
$$;

-- Llamar anuncios_avisar_por_vencer() dentro de la limpieza que ya corre
-- en cada obtención de feed, para que no dependa de un job programado.
create or replace function public.anuncios_limpiar_estados()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update anuncios set estado = 'expirado'
  where estado = 'aprobado'
    and vigencia_hasta is not null
    and vigencia_hasta <= now();

  with vivos as (
    select a.id_anuncio,
           row_number() over (partition by a.id_tienda order by a.creado_en desc) as rn,
           coalesce((
             select pl.ranuras_anuncios
             from tiendas t join planes pl on pl.codigo = t.plan
             where t.id_tienda = a.id_tienda limit 1
           ), 0) as cupo
    from anuncios a
    where a.tipo = 'producto' and a.estado = 'aprobado'
  )
  update anuncios an set estado = 'pausado'
  where an.id_anuncio in (select id_anuncio from vivos where rn > cupo);

  with pausados as (
    select a.id_anuncio,
           row_number() over (partition by a.id_tienda order by a.creado_en desc) as rn,
           coalesce((
             select pl.ranuras_anuncios
             from tiendas t join planes pl on pl.codigo = t.plan
             where t.id_tienda = a.id_tienda limit 1
           ), 0) as cupo
    from anuncios a
    where a.tipo = 'producto' and a.estado = 'pausado'
  )
  update anuncios an set estado = 'aprobado'
  where an.id_anuncio in (select id_anuncio from pausados where rn <= cupo);

  -- recién después de limpiar, marcar avisos de vencimiento próximos
  perform anuncios_avisar_por_vencer();
end;
$$;


-- ---------------------------------------------------------------------------
-- 2e. ANUNCIO aprobado / pausado / rechazado / enviado a revisión — avisa
--     al CREADOR cuando el estado del anuncio cambia desde fuera (el
--     admin modera, o se re-moderó al editar). Antes esto era un aviso
--     100% local (AnunciosStateService.agregarLocal); ahora se inserta
--     una fila real en notificaciones para que sobreviva al cierre de la
--     app y no dependa del dispositivo.
--
--     Regla anti-spam: NO notificamos cuando el propio creador es quien
--     cambió el estado (el dueño pausa/reactiva su anuncio desde "Mis
--     anuncios" -- eso no debe generar aviso). Solo moderación ajena.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_estado_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_titulo  text;
  v_mensaje text;
begin
  if old.estado is not distinct from new.estado then
    return new;
  end if;

  -- cambio hecho por el propio creador (pausar/reactivar propio) -> callar
  if new.creado_por is not null and new.creado_por = auth.uid() then
    return new;
  end if;

  if new.estado = 'aprobado' then
    v_titulo  := 'Anuncio aprobado ✅';
    v_mensaje := '"' || coalesce(new.titulo, 'Tu anuncio') || '" ya está '
                 || 'corriendo en el feed.';
  elsif new.estado = 'pausado' then
    v_titulo  := 'Anuncio pausado';
    v_mensaje := '"' || coalesce(new.titulo, 'Tu anuncio') || '" fue puesto '
                 || 'en pausa por moderación. Puedes reactivarlo desde Mis '
                 || 'anuncios.';
  elsif new.estado = 'rechazado' then
    v_titulo  := 'Anuncio rechazado';
    v_mensaje := '"' || coalesce(new.titulo, 'Tu anuncio') || '" no pasó la '
                 || 'revisión. Edita los datos y vuelve a intentarlo'
                 || case when new.motivo_rechazo is not null
                         then ' Motivo: ' || new.motivo_rechazo else '' end;
  elsif new.estado = 'pendiente' then
    v_titulo  := 'Anuncio enviado a revisión';
    v_mensaje := '"' || coalesce(new.titulo, 'Tu anuncio') || '" está '
                 || 'esperando aprobación.';
  else
    return new;
  end if;

  if new.creado_por is null then
    return new;
  end if;

  insert into public.notificaciones
         (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
  values (
    new.creado_por,
    v_titulo,
    v_mensaje,
    'anuncio',
    jsonb_build_object('id_anuncio', new.id_anuncio::text),
    false,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_notif_estado_anuncio on public.anuncios;
create trigger trg_notif_estado_anuncio
after update on public.anuncios
for each row execute function public.notificar_estado_anuncio();
