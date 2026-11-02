-- parche_fix_likes_comentarios.sql
--
-- QUÉ ARREGLA: los anuncios de NEGOCIO (es_automatico = true) no podían
-- recibir "me gusta" ni comentarios. El like/comentario inserta en
-- anuncio_likes / anuncio_comentarios y un trigger SECURITY DEFINER
-- (fn_actualizar_total_likes / fn_actualizar_total_comentarios) hace el
-- UPDATE de contador sobre `anuncios`. Ese UPDATE dispara el trigger
-- anuncios_before_update(), que en su versión de parche_negocio_auto_
-- anuncio.sql lanza CAMPO_PROTEGIDO para CUALQUIER cambio no-admin sobre
-- un anuncio automático -- incluida esa actualización interna del
-- contador (por eso decía "solo el administrador").
--
-- FIX: en anuncios_before_update() se exime de la protección a las
-- actualizaciones que vienen de DENTRO de otro trigger (pg_trigger_depth()
-- >= 1): así el mantenimiento del contador pasa libre, pero las ediciones
-- directas del usuario/duenio (depth 0) siguen protegidas.
--
-- CÓMO VERIFICAR ANTES (opcional, 1 línea en el SQL Editor):
--   select pg_get_functiondef('public.anuncios_before_update()'::regprocedure)
--          ilike '%es_automatico%' as tiene_guard_auto;
--   Esperado: true (confirma que el guard de anuncios automáticos está
--   desplegado y es el que bloquea el like/comentario).
--
-- CÓMO: pega TODO este bloque en el SQL Editor de Supabase y ejecútalo.
-- Es idempotente (puedes correrlo las veces que quieras).

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

  -- EXENCIÓN para el mantenimiento interno de contadores: fn_actualizar_
  -- total_likes / fn_actualizar_total_comentarios hacen un UPDATE sobre
  -- `anuncios` desde DENTRO de su propio trigger (pg_trigger_depth()>=1),
  -- y ese UPDATE no debe caer en la protección de anuncios automáticos.
  if pg_trigger_depth() >= 1 then
    return new;
  end if;

  -- Guard de anuncios automáticos (parche_negocio_auto_anuncio.sql): un
  -- anuncio que se gestiona solo no se edita a mano (ni por el duenio).
  if old.es_automatico = true then
    if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'false' then
      raise exception 'CAMPO_PROTEGIDO: este anuncio se gestiona automáticamente con tu paquete.';
    end if;
  end if;

  -- PaUsar/reactivar del DUEÑO (aprobado <-> pausado) con re-validación
  -- de cupo al reactivar. Vale para producto (plan), negocio (permiso) y
  -- standalone (permiso.usuario).
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

        else -- standalone: el cupo viene de permisos_usuario_anuncios
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
     or new.es_automatico is distinct from old.es_automatico then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;

  -- re-moderar SOLO los de negocio: si el dueño edita contenido, vuelve
  -- a 'pendiente'. Los UPDATE internos de contador ya salieron arriba.
  if old.tipo = 'negocio' and old.estado in ('rechazado', 'aprobado') then
    new.estado := 'pendiente';
  end if;

  return new;
end;
$$;