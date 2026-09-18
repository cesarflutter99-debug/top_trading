-- =============================================================================
-- parche_fix_ranura_notificacion.sql
-- =============================================================================
-- BUG: al aprobar una compra de paquete (ranura de negocio o ranura de
-- tienda) el dueño NO recibía la notificación "¡Ranuras activadas!".
--
-- CAUSA: los parches que reescriben `compras_anuncio_aprobar()` se pisan
-- entre sí (`create or replace`), y la ÚLTIMA versión ejecutada quedó sin
-- el bloque de notificación (p.ej. la del anuncio automático de negocio
-- solo inserta el permiso y sincroniza; la de notificaciones notifica
-- pero pierde la sincronización automática). Depende del orden de
-- ejecución, la función actual puede tener UNA pieza y no la otra.
--
-- ESTE ARCHIVO consolida la versión final con TODO:
--   1) permiso (negocio -> permisos_negocio, tienda -> permisos_tienda_anuncios)
--   2) notificación al dueño (aprobada y rechazada)
--   3) sincronización del anuncio automático del negocio (si la función
--      existe; si el negocio usa el flujo manual, no hace nada)
-- Las compras standalone (id_comprador) las gestiona SU propio trigger
-- (fn_aprobar_compra_standalone) y NO se tocan acá para no duplicar.
--
-- Idempotente. Pega TODO en Supabase > SQL Editor y ejecútalo.
-- =============================================================================

create or replace function public.compras_anuncio_aprobar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paquete  public.paquetes_anuncio%rowtype;
  v_dueno    uuid;
begin
  -- Standalone lo maneja su trigger dedicado: no intervenir para no
  -- duplicar permisos ni notificaciones.
  if new.id_comprador is not null then
    return new;
  end if;

  -- --- APROBADA ---------------------------------------------------
  if new.estado = 'aprobada' and old.estado is distinct from 'aprobada' then
    select * into v_paquete from paquetes_anuncio where id_paquete = new.id_paquete;

    if new.id_negocio is not null then
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

      -- Recupera la sincronización del anuncio automático si el parche
      -- que la introdujo (parche_negocio_auto_anuncio.sql) está presente.
      if to_regprocedure('public.fn_sincronizar_anuncio_automatico_negocio(uuid)') is not null then
        perform fn_sincronizar_anuncio_automatico_negocio(new.id_negocio);
      end if;

    elsif new.id_tienda is not null then
      insert into permisos_tienda_anuncios (id_tienda, max_anuncios_extra, desde, hasta)
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

  -- --- RECHAZADA --------------------------------------------------
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