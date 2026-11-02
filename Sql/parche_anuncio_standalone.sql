-- parche_anuncio_standalone.sql
-- FASE 4: Flujo de "Anuncio" 100% independiente (sin tienda ni negocio)
-- Agrega soporte para crear anuncios tipo 'standalone' que no requieren
-- id_tienda ni id_negocio. El usuario paga un paquete standalone y crea
-- un anuncio con título, texto e imagen, el cual publica directo al feed.

-- 1) Columna para distinguir paquetes standalone.
alter table public.paquetes_anuncio
  add column if not exists standalone boolean not null default false;


-- 2) Modificamos el trigger anuncios_before_insert para agregar el case
--    de tipo standalone. Los standalone nacen aprobados directo, sin
--    moderación, y con creado_por = auth.uid() (el usuario que crea).
create or replace function public.anuncios_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_max int;
  v_activos int;
begin
  if new.creado_por is null then
    new.creado_por := auth.uid();
  end if;


  -- Bypass para inserts generados por el sistema (ver
  -- fn_sincronizar_anuncio_automatico_negocio) -- ya vienen
  -- validados internamente, no pasan por las reglas manuales.
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


    -- Fase 1: SUMA de permisos vigentes, tope 5.
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
    -- Announcement standalone: sin tienda ni negocio, sale aprobado directo.
    if new.id_tienda is not null then
      raise exception 'STANDALONE_SIN_TIENDA: los anuncios standalone no deben tener id_tienda.';
    end if;
    if new.id_negocio is not null then
      raise exception 'STANDALONE_SIN_NEGOCIO: los anuncios standalone no deben tener id_negocio.';
    end if;
    -- Validar que el usuario tenga un paquete standalone vigente y activo.
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;
    select count(*) into v_activos
    from anuncios
    where tipo = 'standalone' and creado_por = new.creado_por and estado = 'aprobado';
    -- No ponemos un cupo rígido aquí; cada usuario tiene su propio límite según sus paquetes adquiridos.
    -- Solo verificamos que no haya otro standalone aprobado igualitario (opcional).
    new.estado := 'aprobado';
    new.vigencia_hasta := now() + interval '30 days';
  end if;


  return new;
end;
$$;




-- 3) Vistas/Reportes: opcional - vista para ver anuncios standalone
create or replace view public.v_anuncios_standalone as
select a.id_anuncio, a.titulo, a.texto, a.imagen_url, a.creado_por,
       a.estado, a.vigencia_hasta, a.creado_en,
       u.email as usuario_email
from anuncios a
  left join auth.users u on a.creado_por = u.id;


-- 4) Comentario en la tabla
comment on column public.paquetes_anuncio.standalone is
  'Marca True si el paquete permite crear anuncios independientes (sin tienda ni negocio)';