-- parche_notificaciones_anuncios.sql
-- =============================================================================
-- NOTIFICACIONES AL DUEÑO del anuncio cuando alguien interactúa con él:
--   • LE DA LIKE  -> tipo 'anuncio_like'
--   • LO COMENTA  -> tipo 'anuncio_comentario'
--
-- Mismo patrón que parche_notif_compras_tienda.sql: un trigger AFTER INSERT
-- inserta una FILA REAL en `notificaciones` dirigida al DUEÑO del anuncio
-- (anuncios.creado_por). Con eso la notificación:
--   1) llega por Realtime a la campanita (app abierta), y
--   2) dispara el trigger trg_push_notificacion (parche_push_notificaciones.sql)
--      que envía el push FCM (app cerrada/en background).
--
-- Reglas anti-spam:
--   - NO se notifica cuando el propio dueño es quien da like/comenta.
--   - NO se notifica si el anuncio no tiene creado_por (ej. autogenerados).
--   - Solo se notifica en el INSERT (nuevo like/nuevo comentario).
--
-- El `data` incluye {id_anuncio, tipo_anuncio, id_tienda, id_negocio,
-- id_producto} para que la app navegue a "Mis anuncios" resaltando el anuncio.
--
-- Ejecutar UNA sola vez en el SQL editor de Supabase.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) LIKE nuevo -> avisar al dueño del anuncio.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_like_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dueno    uuid;
  v_titulo   text;
  v_snippet  text;
  v_tipo_anuncio text;
  v_id_tienda   uuid;
  v_id_negocio  uuid;
  v_id_producto uuid;
begin
  select a.creado_por, a.titulo, a.tipo, a.id_tienda, a.id_negocio, a.id_producto
    into v_dueno, v_titulo, v_tipo_anuncio, v_id_tienda, v_id_negocio, v_id_producto
    from anuncios a
   where a.id_anuncio = new.id_anuncio;

  -- sin dueño (ej. autogenerados) o el dueño se da like a sí mismo -> callar
  if v_dueno is null or v_dueno = new.id_usuario then
    return new;
  end if;

  select coalesce(
           u.raw_user_meta_data ->> 'full_name',
           u.raw_user_meta_data ->> 'nombre',
           split_part(u.email, '@', 1),
           'Alguien'
         )
    into v_snippet
    from auth.users u
   where u.id = new.id_usuario;

  v_snippet := coalesce(nullif(v_snippet, ''), 'Alguien');

  insert into public.notificaciones
         (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
  values (
    v_dueno,
    'Nuevo like en tu anuncio ❤️',
    v_snippet || ' le dio "me gusta" a "' || coalesce(v_titulo, 'tu anuncio') || '".',
    'anuncio_like',
    jsonb_build_object(
      'id_anuncio',    new.id_anuncio::text,
      'tipo_anuncio',  coalesce(v_tipo_anuncio, ''),
      'id_tienda',     v_id_tienda::text,
      'id_negocio',    v_id_negocio::text,
      'id_producto',   v_id_producto::text
    ),
    false,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_notif_like_anuncio on public.anuncio_likes;
create trigger trg_notif_like_anuncio
  after insert on public.anuncio_likes
  for each row execute function public.notificar_like_anuncio();

-- ---------------------------------------------------------------------------
-- 2) COMENTARIO nuevo -> avisar al dueño del anuncio.
-- ---------------------------------------------------------------------------
create or replace function public.notificar_comentario_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dueno    uuid;
  v_titulo   text;
  v_snippet  text;
  v_texto    text;
  v_tipo_anuncio text;
  v_id_tienda   uuid;
  v_id_negocio  uuid;
  v_id_producto uuid;
begin
  select a.creado_por, a.titulo, a.tipo, a.id_tienda, a.id_negocio, a.id_producto
    into v_dueno, v_titulo, v_tipo_anuncio, v_id_tienda, v_id_negocio, v_id_producto
    from anuncios a
   where a.id_anuncio = new.id_anuncio;

  -- sin dueño o el dueño comenta su propio anuncio -> callar
  if v_dueno is null or v_dueno = new.id_usuario then
    return new;
  end if;

  select coalesce(
           u.raw_user_meta_data ->> 'full_name',
           u.raw_user_meta_data ->> 'nombre',
           split_part(u.email, '@', 1),
           'Alguien'
         )
    into v_snippet
    from auth.users u
   where u.id = new.id_usuario;

  v_snippet := coalesce(nullif(v_snippet, ''), 'Alguien');
  v_texto   := replace(new.texto, E'\n', ' ');
  if length(v_texto) > 60 then
    v_texto := left(v_texto, 57) || '…';
  end if;

  insert into public.notificaciones
         (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
  values (
    v_dueno,
    'Nuevo comentario en tu anuncio 💬',
    v_snippet || ': «' || v_texto || '»',
    'anuncio_comentario',
    jsonb_build_object(
      'id_anuncio',    new.id_anuncio::text,
      'tipo_anuncio',  coalesce(v_tipo_anuncio, ''),
      'id_tienda',     v_id_tienda::text,
      'id_negocio',    v_id_negocio::text,
      'id_producto',   v_id_producto::text
    ),
    false,
    now()
  );
  return new;
end;
$$;

drop trigger if exists trg_notif_comentario_anuncio on public.anuncio_comentarios;
create trigger trg_notif_comentario_anuncio
  after insert on public.anuncio_comentarios
  for each row execute function public.notificar_comentario_anuncio();