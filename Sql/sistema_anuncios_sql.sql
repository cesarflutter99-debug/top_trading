-- =============================================================================
-- SISTEMA DE ANUNCIOS AL LADO — Supabase SQL
-- Copia cada bloque en Supabase > SQL Editor y ejecútalo EN ORDEN.
--
-- PIEZAS:
--   0. configuracion_app ........ interruptor global de anuncios
--   1. negocios ................. barberías, talleres, joyerías, etc.
--   2. paquetes_anuncio ......... lo que compra un negocio (como los planes)
--   3. compras_anuncio .......... solicitud de compra (flujo WhatsApp)
--   4. permisos_negocio ......... compra YA activada por el admin
--   5. planes.ranuras_anuncios .. beneficio del plan para tiendas
--   6. anuncios ................. tabla unificada (admin|negocio|producto)
--   7. preferencias_usuario ..... "sin anuncios" pago
--   8. RLS ...................... políticas de seguridad
--   9. RPCs ..................... rotación priorizada + carrusel + clics
--  10. Storage .................. buckets 'anuncios' y 'negocios'
--
-- NOTA DE TIPOS: las FK hacia tiendas.id_tienda y productos.id_producto
-- se declaran uuid (igual que vendedor_productos_con_ventas usa
-- p_id_tienda uuid). Si al ejecutar sale error de tipos, avísame.
-- =============================================================================


-- ---------------------------------------------------------------------------
-- 0. CONFIGURACIÓN GLOBAL — interruptor de emergencia + CTA de negocios
-- ---------------------------------------------------------------------------
create table if not exists public.configuracion_app (
  clave          text primary key,
  valor          jsonb not null,
  actualizado_en timestamptz not null default now()
);

insert into public.configuracion_app (clave, valor)
values ('anuncios', '{"activos": true, "cta_negocio_activo": true}'::jsonb)
on conflict (clave) do nothing;

-- El admin apaga TODOS los anuncios con:
-- update configuracion_app set valor = '{"activos": false, "cta_negocio_activo": true}'
-- where clave = 'anuncios';


-- ---------------------------------------------------------------------------
-- 1. NEGOCIOS — mini-página del barbero / taller / joyería...
--    Sin productos ni carrito: foto, descripción, horario, contacto, mapa.
-- ---------------------------------------------------------------------------
create table if not exists public.negocios (
  id_negocio     uuid primary key default gen_random_uuid(),
  id_dueno       uuid not null references auth.users(id) on delete cascade,
  nombre         text not null,
  descripcion    text,
  categoria      text,                -- texto libre con sugerencias en la UI
  logo_url       text,
  portada_url    text,
  whatsapp       text,
  horario        jsonb,               -- {"lun":{"abre":"9:00","cierra":"17:00"}, ...}
  lista_precios  jsonb,               -- [{"item":"Corte","precio":"$5"}, ...] opcional
  latitud        double precision,
  longitud       double precision,
  direccion      text,
  estado         text not null default 'pendiente'
                 check (estado in ('pendiente','activo','rechazado','suspendido')),
  motivo_rechazo text,
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

create index if not exists idx_negocios_estado on public.negocios (estado);
create index if not exists idx_negocios_dueno  on public.negocios (id_dueno);
create index if not exists idx_negocios_geo    on public.negocios (latitud, longitud);


-- ---------------------------------------------------------------------------
-- 2. PAQUETES DE ANUNCIO — el admin los crea/edita desde su panel
--    (calca el patrón de `planes` + `planes_cuentas_pago`)
-- ---------------------------------------------------------------------------
create table if not exists public.paquetes_anuncio (
  id_paquete     uuid primary key default gen_random_uuid(),
  nombre         text not null,        -- "Anuncio · 1 mes"
  duracion_dias  int  not null check (duracion_dias > 0),
  precio_usd     numeric(10,2) not null check (precio_usd >= 0),
  max_anuncios   int  not null default 1 check (max_anuncios > 0),
  descripcion    text,
  orden          int  not null default 0,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now()
);

create table if not exists public.paquetes_anuncio_cuentas_pago (
  id_cuenta      uuid primary key default gen_random_uuid(),
  id_paquete     uuid not null references public.paquetes_anuncio(id_paquete) on delete cascade,
  tipo           text not null,        -- 'MLC' | 'CUP' | 'Clasica'
  numero_tarjeta text not null,
  qr_url         text,
  activo         boolean not null default true,
  creado_en      timestamptz not null default now()
);

-- Paquetes iniciales (solo si la tabla está vacía; luego el admin los
-- ajusta a su gusto desde el panel)
insert into public.paquetes_anuncio (nombre, duracion_dias, precio_usd, max_anuncios, orden)
select v.nombre, v.duracion_dias, v.precio_usd, v.max_anuncios, v.orden
from (values
  ('Anuncio · 1 semana', 7,  3.00, 1, 1),
  ('Anuncio · 1 mes',    30, 8.00, 1, 2),
  ('Anuncio · 3 meses',  90, 20.00, 2, 3)
) as v(nombre, duracion_dias, precio_usd, max_anuncios, orden)
where not exists (select 1 from public.paquetes_anuncio);


-- ---------------------------------------------------------------------------
-- 3. COMPRAS DE ANUNCIO — solicitud del negocio (igual que solicitudes de
--    plan): el negocio toca "Comprar", queda pendiente, manda comprobante
--    por WhatsApp con un código corto, y al aprobarla el admin se crea
--    SOLO el permiso (trigger abajo).
-- ---------------------------------------------------------------------------
create table if not exists public.compras_anuncio (
  id_compra   uuid primary key default gen_random_uuid(),
  id_negocio  uuid not null references public.negocios(id_negocio) on delete cascade,
  id_paquete  uuid not null references public.paquetes_anuncio(id_paquete),
  estado      text not null default 'pendiente'
              check (estado in ('pendiente','aprobada','rechazada')),
  codigo_ref  text,                    -- código corto legible para WhatsApp
  creado_en   timestamptz not null default now()
);

create index if not exists idx_compras_negocio on public.compras_anuncio (id_negocio);
create index if not exists idx_compras_estado  on public.compras_anuncio (estado);

-- Al aprobar la compra, el permiso nace solito con la vigencia correcta
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
  end if;
  return new;
end;
$$;

drop trigger if exists trg_compras_anuncio_aprobar on public.compras_anuncio;
create trigger trg_compras_anuncio_aprobar
after update on public.compras_anuncio
for each row execute function public.compras_anuncio_aprobar();


-- ---------------------------------------------------------------------------
-- 4. PERMISOS DE NEGOCIO — el derecho VIGENTE a tener anuncios corriendo.
--    La RPC valida contra esto: sin permiso vigente, no hay anuncios.
-- ---------------------------------------------------------------------------
create table if not exists public.permisos_negocio (
  id_permiso   uuid primary key default gen_random_uuid(),
  id_negocio   uuid not null references public.negocios(id_negocio) on delete cascade,
  id_paquete   uuid references public.paquetes_anuncio(id_paquete) on delete set null,
  max_anuncios int not null default 1,
  desde        timestamptz not null default now(),
  hasta        timestamptz not null,
  activo       boolean not null default true,  -- el admin puede cortarlo antes
  creado_en    timestamptz not null default now()
);

create index if not exists idx_permisos_negocio on public.permisos_negocio (id_negocio);


-- ---------------------------------------------------------------------------
-- 5. RANURAS DE ANUNCIO POR PLAN — beneficio editable por el admin.
--    Hoy premium = 3; mañana puede crear "Básico + 1 anuncio" y listo.
-- ---------------------------------------------------------------------------
alter table public.planes add column if not exists ranuras_anuncios int not null default 0;

-- Valor inicial razonable (el admin lo ajusta después desde su panel)
update public.planes set ranuras_anuncios = 3
where codigo = 'premium' and ranuras_anuncios = 0;


-- ---------------------------------------------------------------------------
-- 6. ANUNCIOS — tabla UNIFICADA para los tres tipos
--
--    tipo='admin'    : lo crea el admin desde su panel. Publica directo.
--                      Etiqueta UI: "Promoción del Marketplace"
--    tipo='negocio'  : lo crea una barbería/taller habilitado. Va a
--                      MODERACIÓN (estado pendiente). Etiqueta UI:
--                      "Negocio Patrocinado"
--    tipo='producto' : tienda potencia un producto o crea promo en pleno.
--                      Publica directo si su plan tiene ranura libre.
--                      Etiqueta UI: "Promoción Pagada"
--
--    Los anuncios de tienda NO tienen fecha de fin: valen mientras su
--    plan dé ranuras. Si baja de plan, la RPC pausa los excedentes solo.
-- ---------------------------------------------------------------------------
create table if not exists public.anuncios (
  id_anuncio      uuid primary key default gen_random_uuid(),

  tipo            text not null check (tipo in ('admin','negocio','producto')),

  titulo          text,
  texto           text,
  imagen_url      text,
  etiqueta        text,               -- si es null la UI usa la fija del tipo

  -- destino (según tipo)
  id_tienda       uuid references public.tiendas(id_tienda) on delete cascade,
  id_producto     uuid references public.productos(id_producto) on delete cascade,
  id_negocio      uuid references public.negocios(id_negocio) on delete cascade,

  creado_por      uuid references auth.users(id) on delete set null,

  estado          text not null default 'pendiente'
                  check (estado in ('pendiente','aprobado','rechazado','expirado','pausado')),
  motivo_rechazo  text,

  vigencia_hasta  timestamptz,        -- null = mientras el plan lo permita

  veces_mostrado  bigint not null default 0,
  veces_clickeado bigint not null default 0,

  creado_en       timestamptz not null default now(),

  -- integridad del destino según tipo
  -- FIX (2026-08): tipo='producto' ya NO exige id_producto -- la promo
  -- de tienda en pleno ("crear anuncio") va sin producto. Solo se
  -- prohíbe mezclar destino de negocio en un anuncio de producto.
  constraint chk_destino_anuncio check (
       (tipo = 'admin')
    or (tipo = 'negocio'  and id_negocio  is not null)
    or (tipo = 'producto' and id_negocio  is null)
  )
);

create index if not exists idx_anuncios_rotacion on public.anuncios (tipo, estado, vigencia_hasta);
create index if not exists idx_anuncios_tienda   on public.anuncios (id_tienda);
create index if not exists idx_anuncios_negocio  on public.anuncios (id_negocio);
create index if not exists idx_anuncios_autor    on public.anuncios (creado_por);

-- Helper: ¿el usuario actual es admin? (usa la tabla `admins` que ya existe)
create or replace function public.es_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from admins where user_id = auth.uid());
$$;


-- ---------------------------------------------------------------------------
-- 6b. TRIGGER DE INSERCIÓN — decide estado inicial y valida cupos
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

  -- ---------------- ADMIN: publica directo, vigencia 30 días por defecto
  if new.tipo = 'admin' then
    if not es_admin() then
      raise exception 'SOLO_ADMIN';
    end if;
    new.estado := 'aprobado';
    if new.vigencia_hasta is null then
      new.vigencia_hasta := now() + interval '30 days';
    end if;

  -- ---------------- PRODUCTO: directo si hay ranura libre en el plan
  --    Dos sabores (2026-08):
  --      a) Potenciar producto -> id_producto obligatorio; la tienda se
  --         deduce del producto.
  --      b) Promo de tienda en pleno ("crear anuncio") -> id_producto
  --         null y id_tienda del PROPIO usuario. Sin producto no hay
  --         deducción posible, así que validamos dueño directamente.
  elsif new.tipo = 'producto' then
    if new.creado_por is null then
      raise exception 'SESION_REQUERIDA';
    end if;

    if new.id_producto is not null then
      -- la tienda se deduce del producto (evita anunciar el producto ajeno)
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

  -- ---------------- NEGOCIO: siempre pasa por moderación + permiso vigente
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

    -- cupo simultáneo = el mejor de sus permisos vigentes
    select coalesce(max(pn.max_anuncios), 0) into v_max
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
    -- el anuncio vive como mucho hasta que se acabe el permiso
    select max(pn.hasta) into new.vigencia_hasta
    from permisos_negocio pn
    where pn.id_negocio = new.id_negocio and pn.activo and pn.hasta > now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_anuncios_insert on public.anuncios;
create trigger trg_anuncios_insert
before insert on public.anuncios
for each row execute function public.anuncios_before_insert();


-- ---------------------------------------------------------------------------
-- 6c. TRIGGER DE ACTUALIZACIÓN — el dueño edita contenido de SU anuncio,
--     pero estado/vigencia/métricas son solo del admin y del sistema.
--     Si un anuncio rechazado se edita, vuelve a 'pendiente'.
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

  -- campos reservados: nadie que no sea admin los toca... EXCEPCIÓN
  -- (2026-08): el dueño puede PAUSAR su anuncio vivo (aprobado ->
  -- pausado) y REACTIVARLO (pausado -> aprobado), con re-validación
  -- de cupo al reactivar. Vale para tipo='producto' (cupo del plan)
  -- y para tipo='negocio' (cupo del permiso vigente). Sin esto el
  -- dueño quedaba clavado con un anuncio que no podía ni quitar.
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
  -- directos: si el vendedor corrige su foto, no debe despublicarse)
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
-- 7. PREFERENCIAS DE USUARIO — "Navega sin promociones" (pago manual).
--    No existe tabla perfiles: los usuarios viven en auth.users.
-- ---------------------------------------------------------------------------
create table if not exists public.preferencias_usuario (
  id_usuario         uuid primary key references auth.users(id) on delete cascade,
  sin_anuncios_hasta timestamptz,       -- null = ve anuncios normalmente
  actualizado_en     timestamptz not null default now()
);


-- ---------------------------------------------------------------------------
-- 8. RLS — políticas de seguridad
-- ---------------------------------------------------------------------------
alter table public.configuracion_app          enable row level security;
alter table public.negocios                   enable row level security;
alter table public.paquetes_anuncio           enable row level security;
alter table public.paquetes_anuncio_cuentas_pago enable row level security;
alter table public.compras_anuncio            enable row level security;
alter table public.permisos_negocio           enable row level security;
alter table public.anuncios                   enable row level security;
alter table public.preferencias_usuario       enable row level security;

-- configuracion_app: lectura pública, escritura admin
drop policy if exists cfg_read on public.configuracion_app;
create policy cfg_read on public.configuracion_app for select using (true);
drop policy if exists cfg_write on public.configuracion_app;
create policy cfg_write on public.configuracion_app for all
  using (es_admin()) with check (es_admin());

-- negocios: cualquiera ve los activos; el dueño gestiona el suyo
drop policy if exists neg_select on public.negocios;
create policy neg_select on public.negocios for select
  using (estado = 'activo' or id_dueno = auth.uid() or es_admin());
drop policy if exists neg_insert on public.negocios;
create policy neg_insert on public.negocios for insert to authenticated
  with check (id_dueno = auth.uid() and estado = 'pendiente');
drop policy if exists neg_update on public.negocios;
create policy neg_update on public.negocios for update
  using (id_dueno = auth.uid() or es_admin())
  with check (id_dueno = auth.uid() or es_admin());
drop policy if exists neg_delete on public.negocios;
-- (2026-08) el DUEÑO también puede eliminar su propio negocio desde la
-- app -- los anuncios, permisos y compras se van en cascada por FK.
create policy neg_delete on public.negocios for delete
  using (es_admin() or id_dueno = auth.uid());

-- paquetes: lectura pública de activos; escritura admin
drop policy if exists paq_select on public.paquetes_anuncio;
create policy paq_select on public.paquetes_anuncio for select using (activo or es_admin());
drop policy if exists paq_write on public.paquetes_anuncio;
create policy paq_write on public.paquetes_anuncio for all
  using (es_admin()) with check (es_admin());

drop policy if exists paqcuentas_select on public.paquetes_anuncio_cuentas_pago;
create policy paqcuentas_select on public.paquetes_anuncio_cuentas_pago for select
  to authenticated using (activo or es_admin());
drop policy if exists paqcuentas_write on public.paquetes_anuncio_cuentas_pago;
create policy paqcuentas_write on public.paquetes_anuncio_cuentas_pago for all
  using (es_admin()) with check (es_admin());

-- compras: el negocio crea/ve las suyas; admin las gestiona
drop policy if exists compra_select on public.compras_anuncio;
create policy compra_select on public.compras_anuncio for select
  using (es_admin() or exists (
    select 1 from negocios n where n.id_negocio = compras_anuncio.id_negocio and n.id_dueno = auth.uid()));
drop policy if exists compra_insert on public.compras_anuncio;
create policy compra_insert on public.compras_anuncio for insert to authenticated
  with check (exists (
    select 1 from negocios n where n.id_negocio = compras_anuncio.id_negocio and n.id_dueno = auth.uid())
    and estado = 'pendiente');
drop policy if exists compra_update on public.compras_anuncio;
create policy compra_update on public.compras_anuncio for update
  using (es_admin()) with check (es_admin());

-- permisos: solo lectura del dueño; escritura admin (nacen por trigger)
drop policy if exists permiso_select on public.permisos_negocio;
create policy permiso_select on public.permisos_negocio for select
  using (es_admin() or exists (
    select 1 from negocios n where n.id_negocio = permisos_negocio.id_negocio and n.id_dueno = auth.uid()));
drop policy if exists permiso_write on public.permisos_negocio;
create policy permiso_write on public.permisos_negocio for all
  using (es_admin()) with check (es_admin());

-- anuncios: el feed lee los aprobados y vigentes; el dueño ve los suyos
drop policy if exists anuncio_select on public.anuncios;
create policy anuncio_select on public.anuncios for select
  using (
    es_admin()
    or creado_por = auth.uid()
    or (estado = 'aprobado' and (vigencia_hasta is null or vigencia_hasta > now()))
  );
drop policy if exists anuncio_insert on public.anuncios;
create policy anuncio_insert on public.anuncios for insert to authenticated
  with check (creado_por = auth.uid() or es_admin());
drop policy if exists anuncio_update on public.anuncios;
create policy anuncio_update on public.anuncios for update
  using (es_admin() or creado_por = auth.uid())
  with check (es_admin() or creado_por = auth.uid());
drop policy if exists anuncio_delete on public.anuncios;
-- (2026-08) el dueño también puede ELIMINAR sus anuncios de producto
-- ya aprobados -- antes quedaban clavados sin forma de quitarlos.
create policy anuncio_delete on public.anuncios for delete
  using (es_admin() or (creado_por = auth.uid() and
    (estado in ('pendiente','rechazado','pausado') or tipo = 'producto')));

-- preferencias: cada uno lee/escribe la suya; admin también
drop policy if exists pref_select on public.preferencias_usuario;
create policy pref_select on public.preferencias_usuario for select
  using (id_usuario = auth.uid() or es_admin());
drop policy if exists pref_write on public.preferencias_usuario;
create policy pref_write on public.preferencias_usuario for all
  using (id_usuario = auth.uid() or es_admin())
  with check (id_usuario = auth.uid() or es_admin());

-- AGUJERO TAPADO: sin este trigger, cualquiera podía hacer
-- insert preferencias_usuario values (auth.uid(), '2099-01-01')
-- y regalarse "sin anuncios" de por vida. El campo solo lo cambia el admin.
create or replace function public.preferencias_proteger()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin() then
    new.sin_anuncios_hasta := case
      when tg_op = 'UPDATE' then old.sin_anuncios_hasta
      else null
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_preferencias_proteger on public.preferencias_usuario;
create trigger trg_preferencias_proteger
before insert or update on public.preferencias_usuario
for each row execute function public.preferencias_proteger();


-- ---------------------------------------------------------------------------
-- 9. RPCs — rotación, carrusel, clics y limpieza
-- ---------------------------------------------------------------------------

-- 9a. Limpieza perezosa (reemplaza al job diario; la llaman las RPCs):
--     - expira los vencidos
--     - pausa excedentes si la tienda bajó de plan (los más viejos fuera)
--     - reactiva pausados si subió de plan
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
end;
$$;

-- 9b. FEED INTERCALADO — prioridad admin → negocio → producto (tienda),
--     round-robin entre grupos, reparte hasta p_cantidad anuncios.
--     Respeta: interruptor global y "sin anuncios" del usuario.
--     Devuelve jsonb listo para la TarjetaAnuncio (con nombre/logo destino).
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
  v_result   jsonb := '[]'::jsonb;
  v_tomado   boolean;
begin
  -- interruptor global
  select valor into v_config from configuracion_app where clave = 'anuncios';
  if found and coalesce(v_config->>'activos', 'true') <> 'true' then
    return;
  end if;

  -- usuario pagó por no ver anuncios
  if auth.uid() is not null then
    select sin_anuncios_hasta into v_sin
    from preferencias_usuario where id_usuario = auth.uid();
    if v_sin is not null and v_sin > now() then
      return;
    end if;
  end if;

  perform anuncios_limpiar_estados();

  -- ---- candidatos ADMIN (más vistos menos primero, desempate random)
  select coalesce(jsonb_agg(x.j), '[]')
  into v_admins
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'destino_nombre', null::text, 'destino_imagen', null::text
    ) as j
    from anuncios a
    where a.tipo = 'admin' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
    order by a.veces_mostrado asc, random()
    limit p_cantidad
  ) x(j);

  -- ---- candidatos NEGOCIO (solo negocios activos)
  select coalesce(jsonb_agg(x.j), '[]') into v_negs
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
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

  -- ---- candidates PRODUCTO (tiendas activas, productos visibles)
  --    LEFT JOINs (2026-08): las promos de tienda EN PLENO ("crear
  --    anuncio") no tienen id_producto -- con join interno desaparecían
  --    del feed y por eso el usuario dejaba de ver sus anuncios.
  select coalesce(jsonb_agg(x.j), '[]') into v_prods
  from (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
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

  -- ---- intercalado round-robin: 1 admin, 1 negocio, 1 producto, repetir
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

    exit when not v_tomado;
  end loop;

  -- FIX (2026-08): barajamos el resultado final. Antes el orden de
  -- tipos era fijo (siempre admin -> negocio -> producto), así que si
  -- solo había UN anuncio de un tipo (p.ej. un solo negocio) salía
  -- SIEMPRE en la misma posición del feed. Con el shuffle se mantiene
  -- la mezcla de tipos pero ninguna posición queda fija.
  select jsonb_agg(e order by random())
  into v_result
  from jsonb_array_elements(v_result) e;

  -- contar impresiones (servidos)
  update anuncios a set veces_mostrado = a.veces_mostrado + 1
  where a.id_anuncio in (
    select (e->>'id_anuncio')::uuid from jsonb_array_elements(v_result) e
  );

  return query
  select e from jsonb_array_elements(v_result) e;
end;
$$;

-- 9c. CARRUSEL SUPERIOR — solo admin, máx 5, rotación aleatoria
create or replace function public.obtener_anuncios_carrusel(p_limite int default 5)
returns table (anuncio jsonb)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config jsonb;
  v_sin    timestamptz;
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

  return query
  with candidatos as (
    select jsonb_build_object(
      'id_anuncio', a.id_anuncio, 'tipo', a.tipo,
      'titulo', a.titulo, 'texto', a.texto,
      'imagen_url', a.imagen_url, 'etiqueta', a.etiqueta,
      'id_tienda', a.id_tienda, 'id_producto', a.id_producto, 'id_negocio', a.id_negocio,
      'destino_nombre', null::text, 'destino_imagen', null::text
    ) as j, a.id_anuncio as aid
    from anuncios a
    where a.tipo = 'admin' and a.estado = 'aprobado'
      and (a.vigencia_hasta is null or a.vigencia_hasta > now())
    order by random()
    limit least(p_limite, 5)
  ),
  servidos as (
    update anuncios a set veces_mostrado = a.veces_mostrado + 1
    where a.id_anuncio in (select aid from candidatos)
  )
  select j from candidatos;
end;
$$;

-- 9d. REGISTRAR CLIC — los usuarios no pueden UPDATE directo (RLS),
--     así que el tap del anuncio llama esta RPC
create or replace function public.anuncio_registrar_clic(p_id_anuncio uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update anuncios set veces_clickeado = veces_clickeado + 1
  where id_anuncio = p_id_anuncio;
$$;

grant execute on function public.obtener_anuncios_feed(int)     to anon, authenticated;
grant execute on function public.obtener_anuncios_carrusel(int) to anon, authenticated;
grant execute on function public.anuncio_registrar_clic(uuid)   to anon, authenticated;


-- ---------------------------------------------------------------------------
-- 10. STORAGE — buckets públicos para imágenes de anuncios y negocios
--     Convención de ruta: {uid_del_usuario}/archivo.jpg
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public)
values ('anuncios', 'anuncios', true), ('negocios', 'negocios', true)
on conflict (id) do nothing;

drop policy if exists "anuncios_upload_propio" on storage.objects;
create policy "anuncios_upload_propio" on storage.objects for insert to authenticated
with check (bucket_id = 'anuncios' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "negocios_upload_propio" on storage.objects;
create policy "negocios_upload_propio" on storage.objects for insert to authenticated
with check (bucket_id = 'negocios' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "anuncios_gestion_propio" on storage.objects;
create policy "anuncios_gestion_propio" on storage.objects for update to authenticated
using (bucket_id = 'anuncios' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "negocios_gestion_propio" on storage.objects;
create policy "negocios_gestion_propio" on storage.objects for update to authenticated
using (bucket_id = 'negocios' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "anuncios_borrar_propio" on storage.objects;
create policy "anuncios_borrar_propio" on storage.objects for delete to authenticated
using (bucket_id = 'anuncios' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "negocios_borrar_propio" on storage.objects;
create policy "negocios_borrar_propio" on storage.objects for delete to authenticated
using (bucket_id = 'negocios' and (storage.foldername(name))[1] = auth.uid()::text);


-- =============================================================================
-- PRUEBAS RÁPIDAS (opcional, en SQL Editor):
--
--   select * from obtener_anuncios_feed(3);      -- vacío al principio, OK
--   select * from obtener_anuncios_carrusel(5);  -- vacío al principio, OK
--   select * from paquetes_anuncio;              -- 3 paquetes semilla
--   select ranuras_anuncios, codigo from planes; -- premium debería tener 3
-- =============================================================================
