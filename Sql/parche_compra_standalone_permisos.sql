-- parche_compra_standalone_permisos.sql
-- ===========================================================================
-- COMPRAS DE ANUNCIO STANDALONE + PERMISOS POR USUARIO + RPC DEL ADMIN
-- ===========================================================================
-- Agrega el flujo COMPLETO para que un usuario (sin tienda ni negocio)
-- compre un paquete standalone y su aprobación cree el permiso en
-- permisos_usuario_anuncios (equivalente a permisos_negocio).
--
-- CONTENIDO:
--   1) compras_anuncio.id_comprador .......... columna para ligar la compra
--      al usuario (sin id_negocio ni id_tienda).
--   2) permisos_usuario_anuncios ............. tabla de permisos por
--      usuario (max_anuncios + hasta) -- la lee ranurasStandalone()/
--      misPermisosStandalone().
--   3) fn_aprobar_compra_standalone() ........ trigger AFTER UPDATE: al
--      pasar a 'aprobada' crea el permiso + notifica al comprador; al
--      pasar a 'rechazada' notifica. Usa 'aprobada' (unificado con el
--      resto del sistema, NO 'aprobado').
--   4) anuncios_before_insert() .............. reescrito: la rama
--      tipo='standalone' valida el cupo contra permisos_usuario_anuncios
--      y pone vigencia_hasta según el permiso más lejano.
--   5) RLS ................................... permisos_usuario (select
--      propio/admin), compra_insert_standalone y compra_select_usuario.
--   6) admin_compras_anuncio() ................ RPC SECURITY DEFINER para
--      el panel admin: devuelve cada compra con su ORIGEN resuelto
--      (nombre_negocio / nombre_tienda / comprador_email) + paquete +
--      monto, ya sin necesidad de embeds PostgREST.
--
-- Ejecutar UNA sola vez en el SQL editor de Supabase (después de
-- parche_notif_compras_tienda.sql). Es re-ejecutable con create or replace.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) Columna id_comprador en compras_anuncio (nullable: solo standalone).
-- ---------------------------------------------------------------------------
alter table public.compras_anuncio
  add column if not exists id_comprador uuid references auth.users(id)
    on delete cascade;

create index if not exists idx_compras_comprador on public.compras_anuncio (id_comprador);


-- ---------------------------------------------------------------------------
-- 2) Permisos de anuncio POR USUARIO (standalone). Misma forma que
--    permisos_negocio pero anclada al usuario que compró el paquete.
-- ---------------------------------------------------------------------------
create table if not exists public.permisos_usuario_anuncios (
  id_permiso   uuid primary key default gen_random_uuid(),
  id_usuario   uuid not null references auth.users(id) on delete cascade,
  id_paquete   uuid not null references public.paquetes_anuncio(id_paquete),
  max_anuncios int  not null default 1 check (max_anuncios > 0),
  activo       boolean not null default true,
  desde        timestamptz not null default now(),
  hasta        timestamptz not null
);

create index if not exists idx_permisos_usuario on public.permisos_usuario_anuncios (id_usuario, activo, hasta);


-- ---------------------------------------------------------------------------
-- 2b) BACKFILL: compras standalone que ya quedaron 'aprobada' ANTES de este
--     parche (con el trigger viejo que no creaba el permiso). El trigger
--     nuevo solo dispara en UPDATEs DESPUÉS de aplicarlo, así que las
--     compras ya aprobadas necesitan este insert directo. Ignora las que
--     ya tienen permiso para no duplicar.
-- ---------------------------------------------------------------------------
insert into public.permisos_usuario_anuncios
       (id_usuario, id_paquete, max_anuncios, desde, hasta)
select ca.id_comprador,
       ca.id_paquete,
       coalesce(pq.max_anuncios, 1),
       ca.creado_en,
       ca.creado_en + make_interval(days => coalesce(pq.duracion_dias, 30))
from public.compras_anuncio ca
left join public.paquetes_anuncio pq on pq.id_paquete = ca.id_paquete
where ca.id_comprador is not null
  and ca.estado = 'aprobada'
  and not exists (
    select 1
    from public.permisos_usuario_anuncios pu
    where pu.id_usuario = ca.id_comprador
      and pu.id_paquete = ca.id_paquete
      and pu.activo
  );

-- ---------------------------------------------------------------------------
-- 3) Trigger: aprobar/rechazar compra STANDALONE -> permiso + notificación.
--    Estado unificado a 'aprobada' (NO 'aprobado').
-- ---------------------------------------------------------------------------
create or replace function public.fn_aprobar_compra_standalone()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_paquete public.paquetes_anuncio%rowtype;
begin
  -- Solo compras ligadas a un usuario standalone (sin negocio ni tienda).
  if new.id_comprador is null then
    return new;
  end if;

  if new.estado = 'aprobada' and old.estado is distinct from 'aprobada' then
    select * into v_paquete
    from public.paquetes_anuncio
    where id_paquete = new.id_paquete;

    insert into public.permisos_usuario_anuncios
           (id_usuario, id_paquete, max_anuncios, desde, hasta)
    values (
      new.id_comprador,
      new.id_paquete,
      coalesce(v_paquete.max_anuncios, 1),
      now(),
      now() + make_interval(days => coalesce(v_paquete.duracion_dias, 30))
    );

    insert into public.notificaciones
           (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
    values (
      new.id_comprador,
      '¡Paquete standalone activado! 🎉',
      'Verificamos tu pago y ya puedes publicar tu anuncio independiente.',
      'anuncio',
      jsonb_build_object('id_compra', new.id_compra,
                         'codigo_ref', coalesce(new.codigo_ref, '')),
      false,
      now()
    );

  elsif new.estado = 'rechazada' and old.estado is distinct from 'rechazada' then
    insert into public.notificaciones
           (id_usuario, titulo, mensaje, tipo, data, leida, creado_en)
    values (
      new.id_comprador,
      'Compra no verificada',
      'No pudimos validar el comprobante'
        || case when new.codigo_ref is not null
                then ' de ' || new.codigo_ref else '' end
        || '. Escríbenos por WhatsApp para revisarlo.',
      'anuncio',
      jsonb_build_object('id_compra', new.id_compra,
                         'codigo_ref', coalesce(new.codigo_ref, '')),
      false,
      now()
    );
  end if;

  return new;
end;
$$;

-- Limpia CUALQUIER trigger previo que dispare esta función (p. ej. el de
-- Claude pudo tener otro nombre y dos triggers duplicarían el permiso).
do $$
declare
  r record;
begin
  for r in select tgname
           from pg_trigger
           where tgrelid = 'public.compras_anuncio'::regclass
             and not tgisinternal
             and tgfoid = 'public.fn_aprobar_compra_standalone()'::regprocedure
  loop
    execute format('drop trigger %I on public.compras_anuncio', r.tgname);
  end loop;
end;
$$;

create trigger trg_compra_standalone_aprobar
after update on public.compras_anuncio
for each row execute function public.fn_aprobar_compra_standalone();


-- ---------------------------------------------------------------------------
-- 4) anuncios_before_insert() REESCRITO: mantiene admin/producto/negocio y
--    el bypass de anuncio automático, pero la rama 'standalone' ahora
--    valida el cupo contra permisos_usuario_anuncios (sin permiso vigente
--    -> CUPO_ANUNCIOS) y toma la vigencia del permiso más lejano.
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
    -- Anuncio independiente: sin tienda ni negocio, sale aprobado directo
    -- SOLO si el usuario tiene permiso vigente (paquete standalone aprobado).
    if new.id_tienda is not null then
      raise exception 'STANDALONE_SIN_TIENDA: los anuncios standalone no deben tener id_tienda.';
    end if;
    if new.id_negocio is not null then
      raise exception 'STANDALONE_SIN_NEGOCIO: los anuncios standalone no deben tener id_negocio.';
    end if;
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;

    -- Cupo = suma de permiso(s) standalone vigentes del usuario.
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

    new.estado := 'aprobado';
    select max(pu.hasta) into new.vigencia_hasta
    from permisos_usuario_anuncios pu
    where pu.id_usuario = new.creado_por and pu.activo and pu.hasta > now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_anuncios_insert on public.anuncios;
create trigger trg_anuncios_insert
before insert on public.anuncios
for each row execute function public.anuncios_before_insert();


-- ---------------------------------------------------------------------------
-- 5) RLS.
-- ---------------------------------------------------------------------------
alter table public.permisos_usuario_anuncios enable row level security;

-- permisos_usuario_anuncios: solo lectura del dueño (el trigger los crea
-- como security definer) + admin.
drop policy if exists permisos_usuario_select on public.permisos_usuario_anuncios;
create policy permisos_usuario_select on public.permisos_usuario_anuncios
  for select using (id_usuario = auth.uid() or es_admin());

-- compras standalone: el usuario inserta SOLO sus compras pendientes
-- (sin negocio ni tienda) y puede leer las suyas.
drop policy if exists compra_insert_standalone on public.compras_anuncio;
create policy compra_insert_standalone on public.compras_anuncio
  for insert to authenticated
  with check (id_negocio is null and id_tienda is null
              and id_comprador = auth.uid() and estado = 'pendiente');

drop policy if exists compra_select_usuario on public.compras_anuncio;
create policy compra_select_usuario on public.compras_anuncio
  for select using (id_comprador = auth.uid() or es_admin());


-- ---------------------------------------------------------------------------
-- 6) RPC para el ADMIN: lista compras de anuncio con el origen resuelto.
--    Reemplaza el select con embeds del panel (negocios(nombre) era el
--    único embed y no servía ni para tiendas ni para standalone).
-- ---------------------------------------------------------------------------
create or replace function public.admin_compras_anuncio(
  p_estado text default null,
  p_limite int default 100
)
returns table (
  id_compra       uuid,
  id_negocio      uuid,
  id_tienda       uuid,
  id_comprador    uuid,
  id_paquete      uuid,
  estado          text,
  codigo_ref      text,
  creado_en       timestamptz,
  nombre_negocio  text,
  nombre_tienda   text,
  comprador_email text,
  nombre_paquete  text,
  monto_usd       numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;

  return query
    select ca.id_compra, ca.id_negocio, ca.id_tienda, ca.id_comprador,
           ca.id_paquete, ca.estado, ca.codigo_ref, ca.creado_en,
           n.nombre, t.nombre, u.email,
           p.nombre, p.precio_usd
    from public.compras_anuncio ca
    left join public.negocios n on n.id_negocio = ca.id_negocio
    left join public.tiendas t on t.id_tienda = ca.id_tienda
    left join public.paquetes_anuncio p on p.id_paquete = ca.id_paquete
    left join auth.users u on u.id = ca.id_comprador
    where (p_estado is null or ca.estado = p_estado)
    order by ca.creado_en desc
    limit p_limite;
end;
$$;