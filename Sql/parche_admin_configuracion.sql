-- parche_admin_configuracion.sql
-- ===========================================================================
-- Prepara el backend para lo que el panel de admin necesita gestionar y
-- que HOY está hardcodeado en el cliente Flutter o no se puede separar:
--
--   1) categorias_tienda / categorias_negocio -- listas editables (antes
--      kCategoriasTienda y _kSugerenciasCategoria vivían fijas en Dart).
--   2) paquetes_anuncio.destino -- distingue si un paquete es para
--      NEGOCIO, RANURAS EXTRA DE TIENDA o STANDALONE (hoy negocio y
--      ranuras-extra-de-tienda comparten el mismo catálogo sin filtro).
--   3) configuracion_app -> clave 'limites' -- límites de retiro de
--      afiliado, horas de autocancelación de pedido y topes de ranuras
--      acumulables, hoy hardcodeados en tiendas_service.dart y
--      anuncios_service.dart.
--   4) admin_pedidos_todos() -- RPC para que el admin vea TODOS los
--      pedidos (hoy solo existe admin_pedidos_pendientes, que filtra).
--   5) admin_moderar_valoracion() -- oculta/muestra una valoración sin
--      borrarla, para cuando el admin modera contenido reportado.
--   6) Admin con permiso de gestionar tiendas/negocios directo (update/
--      delete) sin depender de ninguna política previa -- se agregan
--      políticas NUEVAS y aparte, nunca se tocan las que ya existen.
--
-- Ejecutar UNA vez en el SQL Editor de Supabase. Idempotente.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1) CATEGORÍAS EDITABLES
-- ---------------------------------------------------------------------------
create table if not exists public.categorias_tienda (
  id_categoria uuid primary key default gen_random_uuid(),
  nombre       text not null unique,
  orden        int  not null default 0,
  activa       boolean not null default true,
  creado_en    timestamptz not null default now()
);

create table if not exists public.categorias_negocio (
  id_categoria uuid primary key default gen_random_uuid(),
  nombre       text not null unique,
  destacada    boolean not null default false,
  orden        int  not null default 0,
  activa       boolean not null default true,
  creado_en    timestamptz not null default now()
);

insert into public.categorias_tienda (nombre, orden)
select v.nombre, v.orden
from (values
  ('Ropa y Accesorios', 1), ('Calzado', 2), ('Móviles y Laptops', 3),
  ('Electrodomésticos', 4), ('Hogar y Muebles', 5),
  ('Alimentos y Bebidas', 6), ('Belleza y Cuidado Personal', 7),
  ('Salud y Farmacia', 8), ('Deportes y Fitness', 9),
  ('Ocio y Videojuegos', 10), ('Juguetes y Niños', 11), ('Mascotas', 12),
  ('Vehículos y Repuestos', 13),
  ('Transporte y Motor (vehículos completos)', 14),
  ('Ferretería y Construcción', 15),
  ('Energía, Electricidad y Solar', 16), ('Otros', 17), ('Variada', 18)
) as v(nombre, orden)
where not exists (select 1 from public.categorias_tienda);

insert into public.categorias_negocio (nombre, destacada, orden)
select v.nombre, v.destacada, v.orden
from (values
  ('Evento / Fiesta puntual', true, 1),
  ('Barbería', false, 2), ('Peluquería', false, 3),
  ('Taller mecánico', false, 4), ('Taller de celulares', false, 5),
  ('Joyería', false, 6), ('Consultorio médico', false, 7),
  ('Consultorio odontológico', false, 8), ('Veterinaria', false, 9),
  ('Restaurante', false, 10), ('Cafetería', false, 11),
  ('Pizzería', false, 12), ('Gimnasio', false, 13),
  ('Lavandería', false, 14), ('Repostería', false, 15),
  ('Fotografía', false, 16), ('Otros servicios', false, 17)
) as v(nombre, destacada, orden)
where not exists (select 1 from public.categorias_negocio);

alter table public.categorias_tienda  enable row level security;
alter table public.categorias_negocio enable row level security;

drop policy if exists cat_tienda_select on public.categorias_tienda;
create policy cat_tienda_select on public.categorias_tienda
  for select using (activa or es_admin());
drop policy if exists cat_tienda_write on public.categorias_tienda;
create policy cat_tienda_write on public.categorias_tienda for all
  using (es_admin()) with check (es_admin());

drop policy if exists cat_negocio_select on public.categorias_negocio;
create policy cat_negocio_select on public.categorias_negocio
  for select using (activa or es_admin());
drop policy if exists cat_negocio_write on public.categorias_negocio;
create policy cat_negocio_write on public.categorias_negocio for all
  using (es_admin()) with check (es_admin());

-- ---------------------------------------------------------------------------
-- 2) paquetes_anuncio.destino -- separa negocio / tienda-extra / standalone.
-- ---------------------------------------------------------------------------
alter table public.paquetes_anuncio
  add column if not exists destino text
    check (destino in ('negocio', 'tienda_extra', 'standalone'));

update public.paquetes_anuncio
set destino = case when standalone then 'standalone' else 'negocio' end
where destino is null;

alter table public.paquetes_anuncio
  alter column destino set not null;

alter table public.paquetes_anuncio
  alter column destino set default 'negocio';

-- ---------------------------------------------------------------------------
-- 3) configuracion_app -> clave 'limites'.
-- ---------------------------------------------------------------------------
insert into public.configuracion_app (clave, valor)
values ('limites', jsonb_build_object(
  'retiro_minimo_cup', 1000,
  'retiro_maximo_dia_cup', 10000,
  'pedido_autocancela_horas', 72,
  'max_ranuras_negocio', 5,
  'max_ranuras_extra_tienda', 5
))
on conflict (clave) do nothing;

-- ---------------------------------------------------------------------------
-- 4) admin_pedidos_todos().
-- ---------------------------------------------------------------------------
create or replace function public.admin_pedidos_todos(
  p_estado text default null,
  p_limite int default 200
)
returns table (
  id_pedido text,
  numero_pedido text,
  tienda_nombre text,
  comprador_email text,
  total_usd numeric,
  estado text,
  created_at timestamptz
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
  select
    p.id_pedido,
    p.numero_pedido,
    t.nombre as tienda_nombre,
    u.email as comprador_email,
    p.total_usd,
    p.estado,
    p.created_at
  from pedidos p
  join tiendas t on t.id_tienda = p.id_tienda
  join auth.users u on u.id = p.id_comprador
  where p_estado is null or p.estado = p_estado
  order by p.created_at desc
  limit p_limite;
end;
$$;

grant execute on function public.admin_pedidos_todos(text, int) to authenticated;

-- ---------------------------------------------------------------------------
-- 5) Moderación de valoraciones.
-- ---------------------------------------------------------------------------
alter table public.valoraciones
  add column if not exists oculta boolean not null default false;

create or replace function public.admin_moderar_valoracion(
  p_id_valoracion text,
  p_ocultar boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;

  update valoraciones
  set oculta = p_ocultar
  where id_valoracion = p_id_valoracion;
end;
$$;

grant execute on function public.admin_moderar_valoracion(text, boolean) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Admin: permiso directo sobre tiendas y negocios.
-- ---------------------------------------------------------------------------
drop policy if exists admin_tiendas_update on public.tiendas;
create policy admin_tiendas_update on public.tiendas
  for update using (es_admin()) with check (es_admin());

drop policy if exists admin_tiendas_delete on public.tiendas;
create policy admin_tiendas_delete on public.tiendas
  for delete using (es_admin());

drop policy if exists admin_negocios_delete on public.negocios;
create policy admin_negocios_delete on public.negocios
  for delete using (es_admin());