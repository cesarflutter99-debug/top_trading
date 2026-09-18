-- sql/anuncio_likes.sql
--
-- Soporte para "me gusta" en anuncios (feed social de anuncios).
-- Sigue el mismo patrón de triggers que ya usa el proyecto
-- (ver notificar_nuevo_pedido, reservar_stock_pedido, etc.):
-- en vez de contar likes con COUNT(*) en cada carga del feed
-- (N+1 queries, lento con muchos anuncios), se mantiene una
-- columna `total_likes` en `anuncios` que un trigger actualiza
-- automáticamente al insertar/borrar un like.
--
-- AJUSTAR: si tu tabla `anuncios` usa un nombre de columna PK
-- distinto a `id_anuncio`, reemplázalo en todo este archivo.

-- 1. Columna de conteo en la tabla de anuncios ---------------------
alter table public.anuncios
  add column if not exists total_likes integer not null default 0;

-- 2. Tabla de likes -------------------------------------------------
create table if not exists public.anuncio_likes (
  id uuid primary key default gen_random_uuid(),
  id_anuncio uuid not null references public.anuncios(id_anuncio) on delete cascade,
  id_usuario uuid not null references auth.users(id) on delete cascade,
  creado_en timestamptz not null default now(),
  unique (id_anuncio, id_usuario)
);

create index if not exists idx_anuncio_likes_anuncio
  on public.anuncio_likes (id_anuncio);
create index if not exists idx_anuncio_likes_usuario
  on public.anuncio_likes (id_usuario);

-- 3. RLS --------------------------------------------------------------
alter table public.anuncio_likes enable row level security;

-- Cualquiera (incluso sin sesión) puede ver quién dio like -- se usa
-- para pintar el conteo y saber si "me gusta" mostrando el corazón
-- lleno al usuario actual.
drop policy if exists anuncio_likes_select_all on public.anuncio_likes;
create policy anuncio_likes_select_all
  on public.anuncio_likes
  for select
  using (true);

-- Solo el propio usuario autenticado puede dar like en su nombre.
drop policy if exists anuncio_likes_insert_own on public.anuncio_likes;
create policy anuncio_likes_insert_own
  on public.anuncio_likes
  for insert
  with check (auth.uid() = id_usuario);

-- Solo el propio usuario puede quitar SU like.
drop policy if exists anuncio_likes_delete_own on public.anuncio_likes;
create policy anuncio_likes_delete_own
  on public.anuncio_likes
  for delete
  using (auth.uid() = id_usuario);

-- 4. Trigger: mantiene anuncios.total_likes sincronizado -------------
create or replace function public.fn_actualizar_total_likes()
returns trigger
language plpgsql
security definer
as $$
begin
  if (tg_op = 'INSERT') then
    update public.anuncios
       set total_likes = total_likes + 1
     where id_anuncio = new.id_anuncio;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.anuncios
       set total_likes = greatest(total_likes - 1, 0)
     where id_anuncio = old.id_anuncio;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_anuncio_likes_insert on public.anuncio_likes;
create trigger trg_anuncio_likes_insert
after insert on public.anuncio_likes
for each row execute function public.fn_actualizar_total_likes();

drop trigger if exists trg_anuncio_likes_delete on public.anuncio_likes;
create trigger trg_anuncio_likes_delete
after delete on public.anuncio_likes
for each row execute function public.fn_actualizar_total_likes();
