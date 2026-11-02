-- parche_negocio_pausar.sql
--
-- QUÉ HACE: permite que el dueño de un negocio PAUSE su anuncio vivo
-- (aprobado -> pausado) y LO REACTIVE (pausado -> aprobado, con
-- re-validación de cupo del permiso vigente). Antes solo las tiendas
-- podían, así que un negocio quedaba clavado con un anuncio que no
-- podía ni quitar del feed.
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

  -- campos reservados: nadie que no sea admin los toca... EXCEPCIÓN:
  -- el dueño puede PAUSAR su anuncio vivo (aprobado -> pausado) y
  -- REACTIVARLO (pausado -> aprobado), con re-validación de cupo al
  -- reactivar. Vale para tipo='producto' (cupo del plan) y para
  -- tipo='negocio' (cupo del permiso vigente).
  if new.estado is distinct from old.estado then
    if old.tipo in ('producto', 'negocio')
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
        else
          select count(*) into v_activos
          from anuncios
          where tipo = 'negocio' and id_negocio = old.id_negocio
            and estado in ('pendiente', 'aprobado')
            and id_anuncio <> old.id_anuncio;

          select coalesce(max(pn.max_anuncios), 0) into v_max
          from permisos_negocio pn
          where pn.id_negocio = old.id_negocio
            and pn.activo and pn.hasta > now();
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
     or new.id_producto is distinct from old.id_producto then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;

  -- re-moderar SOLO los de negocio (los de producto/tienda se publican
  -- directos): si el dueño edita contenido, vuelve a 'pendiente'.
  -- Nota: editar un PAUSADO lo deja pausado (no se despublica nada).
  if old.tipo = 'negocio' and old.estado in ('rechazado', 'aprobado') then
    new.estado := 'pendiente';
  end if;

  return new;
end;
$$;
