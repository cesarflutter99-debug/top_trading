-- parche_optimizacion_almacenamiento.sql
-- =============================================================================
-- OPTIMIZACIÓN DE ALMACENAMIENTO — Fase 3 del plan (limpieza automática).
-- Ejecutar UNA sola vez en el SQL Editor de Supabase.
-- =============================================================================
-- Qué hace, en orden:
--   1) Habilita pg_cron (pg_net ya quedó habilitado por
--      parche_push_notificaciones.sql -- se re-asegura aquí).
--   2) purgar_notificaciones_viejas(): borra en LOTES (500) las
--      notificaciones leídas de más de 75 días. Programada semanal.
--   3) imagekit_pendientes_limpiar: tabla de tracking (red de seguridad
--      para fotos huérfanas) + triggers AFTER DELETE en tiendas y
--      negocios que registran la carpeta a limpiar.
--   4) procesar_limpieza_imagekit(): lee ese tracking y llama a la Edge
--      Function imagekit-delete por cada carpeta pendiente (vía pg_net).
--      Programada semanal (justo después de la purga).
--   5) VACUUM: pg_cron NO puede ejecutar VACUUM (corre dentro de una
--      transacción). Se deja el comando manual exacto abajo.
--
-- Idempotente: puede correrse varias veces sin romper nada.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Extensiones -----------------------------------------------
-- ---------------------------------------------------------------------------
create extension if not exists pg_cron;
create extension if not exists pg_net;


-- ---------------------------------------------------------------------------
-- 2) Purga de notificaciones leídas viejas (batch-safe) --------
-- ---------------------------------------------------------------------------
-- Borra en lotes de 500 (loop con LIMIT) para no mantener una
-- transacción gigante abierta. Solo toca leidas de más de 75 días; las
-- NO leídas y los avisos sin marcar se respetan siempre.
create or replace function public.purgar_notificaciones_viejas()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total integer := 0;
  v_lote  integer := 0;
  v_iter  integer := 0;
begin
  loop
    delete from public.notificaciones
    where id_notificacion in (
      select id_notificacion
      from public.notificaciones
      where leida = true
        and creado_en < now() - interval '75 days'
      limit 500
    );

    get diagnostics v_lote = row_count;
    v_total := v_total + v_lote;
    v_iter := v_iter + 1;

    exit when v_lote < 500 or v_iter >= 200; -- tope: 100k por corrida
  end loop;

  return v_total;
end;
$$;

-- Horario (UTC): Domingo 08:00 = 04:00 en Cuba (horario de verano,
-- 03:00 en invierno). Ajusta el cron si prefieres otra hora.
select cron.schedule(
  'purga-notificaciones',
  '0 8 * * 0',
  'select public.purgar_notificaciones_viejas()'
);


-- ---------------------------------------------------------------------------
-- 3) Tracking de fotos huérfanas para ImageKit -----------------
-- ---------------------------------------------------------------------------
create table if not exists public.imagekit_pendientes_limpiar (
  carpeta     text primary key,
  creado_en   timestamptz not null default now(),
  intentos    integer not null default 0,
  ultimo_error text
);

-- Tienda eliminada -> su carpeta de tienda y la de sus productos (los
-- productos/queries ya no existen cuando corre la limpieza, por eso se
-- registran ambos paths desde la fila de la tienda). Seguridad: si el
-- borrado en la app (borrarArchivosDeTienda) falló o el equipo se apagó,
-- esta fila garantiza que se reintente.
create or replace function public.tracking_carpeta_tienda_eliminada()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.imagekit_pendientes_limpiar (carpeta) values
    ('tiendas/' || old.id_tienda),
    ('productos/' || old.id_tienda)
  on conflict (carpeta) do nothing;
  return old;
end;
$$;

drop trigger if exists trg_tracking_carpeta_tienda on public.tiendas;
create trigger trg_tracking_carpeta_tienda
  after delete on public.tiendas
  for each row execute function public.tracking_carpeta_tienda_eliminada();

-- Negocio eliminado -> su carpeta de logo/portada.
create or replace function public.tracking_carpeta_negocio_eliminado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.imagekit_pendientes_limpiar (carpeta) values
    ('negocios/' || old.id_negocio)
  on conflict (carpeta) do nothing;
  return old;
end;
$$;

drop trigger if exists trg_tracking_carpeta_negocio on public.negocios;
create trigger trg_tracking_carpeta_negocio
  after delete on public.negocios
  for each row execute function public.tracking_carpeta_negocio_eliminado();


-- ---------------------------------------------------------------------------
-- 4) Procesador: llama a imagekit-delete por cada carpeta pendiente -------
-- ---------------------------------------------------------------------------
-- pg_net dispara el HTTP de forma asíncrona (fire-and-forget). La Edge
-- Function imagekit-delete es idempotente (borrar una carpeta que ya no
-- existe no falla), así que no hace falta esperar su respuesta para
-- liberar el tracking: si el enqueue llega a hacerse, la limpieza corre.
-- Con intents < 3: si pg_net falla, se reintenta en la próxima corrida.
create or replace function public.procesar_limpieza_imagekit()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r      record;
  v_url  text := 'https://azcdjfqqxptouweqejvk.supabase.co/functions/v1/imagekit-delete';
  n      integer := 0;
begin
  if not exists (select 1 from pg_extension where extname = 'pg_net') then
    return 0;
  end if;

  for r in
    select carpeta, intentos
    from public.imagekit_pendientes_limpiar
    where intentos < 3
    order by creado_en asc
  loop
    begin
      perform net.http_post(
        url     := v_url,
        headers := jsonb_build_object('Content-Type', 'application/json'),
        body    := jsonb_build_object('folder', r.carpeta)
      );
      delete from public.imagekit_pendientes_limpiar
      where carpeta = r.carpeta;
      n := n + 1;
    exception when others then
      update public.imagekit_pendientes_limpiar
         set intentos = intentos + 1,
             ultimo_error = left(SQLERRM, 200)
       where carpeta = r.carpeta;
    end;
  end loop;

  return n;
end;
$$;

-- Domingo 08:30 UTC, justo después de la purga de notificaciones.
select cron.schedule(
  'limpieza-imagekit-safety',
  '30 8 * * 0',
  'select public.procesar_limpieza_imagekit()'
);


-- ---------------------------------------------------------------------------
-- 5) VACUUM ------------------------------------------------------
-- ---------------------------------------------------------------------------
-- NO se puede programar con pg_cron: Pg_cron ejecuta el comando dentro
-- de una transacción y "VACUUM cannot run inside a transaction block".
-- Corre este comando MANUALMENTE en el SQL Editor DESPUÉS de la primera
-- corrida de la purga (libera el espacio físico que Postgres no suelta
-- solo). Con SKIP_LOCKED para no bloquear a los usuarios en vivo:
--
--   VACUUM (ANALYZE, SKIP_LOCKED) public.notificaciones;
--   VACUUM (ANALYZE, SKIP_LOCKED) public.anuncios;
--   VACUUM (ANALYZE, SKIP_LOCKED) public.productos;
--
-- Si prefieres reintentarlo por cron de todas formas (puede fallar):
--   select cron.schedule('vacuum-analyze', '0 9 * * 0',
--     'VACUUM (ANALYZE, SKIP_LOCKED)');


-- ---------------------------------------------------------------------------
-- ANEXO — monitoreo mensual (FASE 4) -----------------------------
-- ---------------------------------------------------------------------------
-- Cuánto ocupa cada tabla (para revisar una vez al mes):
--
--   select n.nspname as esquema,
--          c.relname as tabla,
--          pg_size_pretty(pg_total_relation_size(c.oid)) as tamano_total,
--          pg_size_pretty(pg_total_relation_size(c.oid) - pg_relation_size(c.oid)) as solo_indices,
--          c.reltuples::bigint as filas_aprox
--   from pg_class c
--   join pg_namespace n on n.oid = c.relnamespace
--   where n.nspname = 'public'
--     and c.relkind in ('r','m')
--   order by pg_total_relation_size(c.oid) desc;
--
-- Revisa también ImageKit (Settings -> Usage) mensualmente y planifica
-- el upgrade antes de llegar al límite (Supabase ~400MB de 500MB).