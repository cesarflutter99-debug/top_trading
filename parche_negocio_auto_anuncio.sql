-- parche_negocio_auto_anuncio.sql
-- FASE 3: el negocio se autopromociona en el feed mientras tenga un
-- paquete de anuncio vigente -- sin formulario de título/texto y SIN
-- pasar por moderación (el contenido se deriva del propio negocio). ya corri eso dime q falta
-- El flujo manual "Crear anuncio" (con moderación) se mantiene tal
-- cual para promos puntuales extra.
--
-- Pega TODO en el SQL Editor de Supabase y ejecuta. Idempotente.
-- Requiere haber corrido antes parche_ranuras_acumulables.sql (o
-- corre este archivo solo -- ya incluye ese fix combinado).


-- 1) Columna para distinguir el anuncio generado por el sistema.
alter table public.anuncios
  add column if not exists es_automatico boolean not null default false;


create index if not exists idx_anuncios_auto
  on public.anuncios (id_negocio, es_automatico);




-- 2) anuncios_before_insert -- agrega bypass para inserts del
--    sistema (GUC app.anuncio_automatico) + mantiene el fix de
--    ranuras acumulables de la fase 1.
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
  end if;


  return new;
end;
$$;




-- 3) anuncios_before_update -- bloquea CUALQUIER cambio manual sobre
--    un anuncio automático (ni el dueño ni nadie que no sea admin
--    puede editarlo/pausarlo/reactivarlo -- lo gestiona el sistema).
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


if old.es_automatico = true then
    if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'false' then
        raise exception 'CAMPO_PROTEGIDO: este anuncio se gestiona automáticamente con tu paquete.';
    end if;
end if;


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


          select least(coalesce(sum(pn.max_anuncios), 0), 5) into v_max
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
     or new.id_producto is distinct from old.id_producto
     or new.es_automatico is distinct from old.es_automatico then
    raise exception 'CAMPO_PROTEGIDO: ese campo solo lo cambia el administrador.';
  end if;


  if old.tipo = 'negocio' and old.estado in ('rechazado', 'aprobado') then
    new.estado := 'pendiente';
  end if;


  return new;
end;
$$;




-- 4) Función de sincronización: crea/actualiza/expira el anuncio
--    automático del negocio según su estado y sus permisos vigentes.
create or replace function public.fn_sincronizar_anuncio_automatico_negocio(
  p_id_negocio uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_negocio   negocios%rowtype;
  v_hasta     timestamptz;
  v_existente uuid;
  v_titulo    text;
  v_texto     text;
  v_imagen    text;
begin
  select * into v_negocio from negocios where id_negocio = p_id_negocio;
  if not found then
    return;
  end if;


  select max(pn.hasta) into v_hasta
  from permisos_negocio pn
  where pn.id_negocio = p_id_negocio and pn.activo and pn.hasta > now();


  select a.id_anuncio into v_existente
  from anuncios a
  where a.id_negocio = p_id_negocio
    and a.tipo = 'negocio'
    and a.es_automatico = true
    and a.estado <> 'expirado'
  order by a.creado_en desc
  limit 1;


  -- Sin negocio activo o sin permiso vigente -> se expira el que
  -- hubiera (si lo hay) y no se crea nada nuevo.
  if v_negocio.estado <> 'activo' or v_hasta is null then
    if v_existente is not null then
      perform set_config('app.anuncio_automatico', 'true', true);
      update anuncios set estado = 'expirado' where id_anuncio = v_existente;
      perform set_config('app.anuncio_automatico', 'false', true);
    end if;
    return;
  end if;


  v_titulo := v_negocio.nombre;
  v_texto := coalesce(nullif(trim(v_negocio.categoria), ''), 'Descúbrelo cerca de ti')
             || ' · Contáctanos por WhatsApp';
  v_imagen := coalesce(v_negocio.portada_url, v_negocio.logo_url);


  perform set_config('app.anuncio_automatico', 'true', true);


  if v_existente is not null then
    update anuncios
    set estado = 'aprobado',
        vigencia_hasta = v_hasta,
        titulo = v_titulo,
        texto = v_texto,
        imagen_url = coalesce(v_imagen, imagen_url)
    where id_anuncio = v_existente;
  else
    insert into anuncios (
      tipo, id_negocio, titulo, texto, imagen_url,
      creado_por, estado, vigencia_hasta, es_automatico
    ) values (
      'negocio', p_id_negocio, v_titulo, v_texto, v_imagen,
      v_negocio.id_dueno, 'aprobado', v_hasta, true
    );
  end if;


  perform set_config('app.anuncio_automatico', 'false', true);
end;
$$;





-- 5) Disparadores que llaman a la sincronización.


-- a) Al aprobar una compra de paquete (ya crea el permiso; ahora
--    también sincroniza el anuncio automático).
create or replace function public.compras_anuncio_aprobar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paquete public.paquetes_anuncio%rowtype;
begin
  if new.estado = 'aprobada' and old.estado is distinct from 'aprobada' then
    select * into v_paquete from paquetes_anuncio where id_paquete = new.id_paquete;
    insert into permisos_negocio (id_negocio, id_paquete, max_anuncios, desde, hasta)
    values (
      new.id_negocio,
      new.id_paquete,
      v_paquete.max_anuncios,
      now(),
      now() + make_interval(days => v_paquete.duracion_dias)
    );
    perform fn_sincronizar_anuncio_automatico_negocio(new.id_negocio);
  end if;
  return new;
end;
$$;


drop trigger if exists trg_compras_anuncio_aprobar on public.compras_anuncio;
create trigger trg_compras_anuncio_aprobar
after update on public.compras_anuncio
for each row execute function public.compras_anuncio_aprobar();


-- b) Al aprobar/cambiar el estado del negocio (lo hace el panel
--    admin, fuera de esta app -- por eso va como trigger de tabla).
create or replace function public.negocios_after_update_sync_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.estado is distinct from old.estado then
    perform fn_sincronizar_anuncio_automatico_negocio(new.id_negocio);
  end if;
  return new;
end;
$$;


drop trigger if exists trg_negocios_sync_anuncio on public.negocios;
create trigger trg_negocios_sync_anuncio
after update on public.negocios
for each row execute function public.negocios_after_update_sync_anuncio();


-- c) Si el admin activa/desactiva un permiso a mano (o cambia su
--    vigencia) desde su panel.
create or replace function public.permisos_negocio_after_change_sync()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform fn_sincronizar_anuncio_automatico_negocio(coalesce(new.id_negocio, old.id_negocio));
  return coalesce(new, old);
end;
$$;


drop trigger if exists trg_permisos_negocio_sync on public.permisos_negocio;
create trigger trg_permisos_negocio_sync
after insert or update on public.permisos_negocio
for each row execute function public.permisos_negocio_after_change_sync();




-- 6) RLS -- el dueño ya no puede eliminar el anuncio automático,
--    incluso si por algún motivo quedara en un estado borrable.
drop policy if exists anuncio_delete on public.anuncios;
create policy anuncio_delete on public.anuncios for delete
  using (
    es_admin() or (
      creado_por = auth.uid()
      and es_automatico = false
      and (estado in ('pendiente','rechazado','pausado') or tipo = 'producto')
    )
  );




-- 7) Backfill: sincroniza YA los negocios que ya tienen permiso
--    vigente pero nunca generaron su anuncio automático.
do $$
declare
  v_id uuid;
begin
  for v_id in
    select distinct id_negocio from permisos_negocio
    where activo and hasta > now()
  loop
    perform fn_sincronizar_anuncio_automatico_negocio(v_id);
  end loop;
end $$;