-- parche_comentarios_anuncios.sql
--
-- Comentarios en anuncios (Marketplace) + columna de interacciones.
--
-- Hace:
--   1. Columna `total_comentarios`  en public.anuncios.
--   2. Columna `interacciones`       en public.anuncios
--      (= total_likes + total_comentarios, mantenida por trigger).
--   3. Tabla public.anuncio_comentarios con RLS.
--   4. Trigger anti-insultos (bloquea comentarios con palabras ofensivas).
--   5. Trigger que sincroniza total_comentarios e interacciones.
--
-- Es idempotente: se puede ejecutar repetido sin error.

-- 1. Columnas de conteo ------------------------------------------------
alter table public.anuncios
  add column if not exists total_comentarios integer not null default 0;

alter table public.anuncios
  add column if not exists interacciones integer not null default 0;

-- Sincroniza interacciones = likes + comentarios cuando cambian esas
-- columnas (los triggers de likes/comentarios las actualizan).
create or replace function public.fn_sync_interacciones_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.interacciones := coalesce(new.total_likes, 0) + coalesce(new.total_comentarios, 0);
  return new;
end;
$$;

drop trigger if exists trg_anuncios_sync_interacciones on public.anuncios;
create trigger trg_anuncios_sync_interacciones
  before update of total_likes, total_comentarios on public.anuncios
  for each row execute function public.fn_sync_interacciones_anuncio();

-- 2. Tabla de comentarios ----------------------------------------------
create table if not exists public.anuncio_comentarios (
  id_comentario  uuid primary key default gen_random_uuid(),
  id_anuncio     uuid not null references public.anuncios(id_anuncio) on delete cascade,
  id_usuario     uuid not null references auth.users(id) on delete cascade,
  nombre_usuario text not null default 'Usuario',
  texto          text not null check (length(trim(texto)) between 1 and 500),
  creado_en      timestamptz not null default now()
);

create index if not exists idx_anuncio_comentarios_anuncio
  on public.anuncio_comentarios (id_anuncio, creado_en desc);
create index if not exists idx_anuncio_comentarios_usuario
  on public.anuncio_comentarios (id_usuario);

-- 3. RLS ----------------------------------------------------------------
alter table public.anuncio_comentarios enable row level security;

-- Cualquiera puede leer los comentarios (igual que el feed de anuncios).
drop policy if exists anuncio_comentarios_select_all on public.anuncio_comentarios;
create policy anuncio_comentarios_select_all
  on public.anuncio_comentarios
  for select
  using (true);

-- Solo el usuario autenticado puede comentar en su nombre.
drop policy if exists anuncio_comentarios_insert_own on public.anuncio_comentarios;
create policy anuncio_comentarios_insert_own
  on public.anuncio_comentarios
  for insert
  with check (auth.uid() = id_usuario);

-- Solo el propio usuario puede borrar su comentario.
drop policy if exists anuncio_comentarios_delete_own on public.anuncio_comentarios;
create policy anuncio_comentarios_delete_own
  on public.anuncio_comentarios
  for delete
  using (auth.uid() = id_usuario);

-- 4. Trigger anti-insultos ----------------------------------------------
create or replace function public.fn_validar_comentario_anuncio()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_texto      text;
  v_palabras   text[] := array[
    'pinga', 'pinqa', 'singao', 'singado', 'cingao', 'cingado',
    'conio', 'coño', 'coñazo', 'coñoso', 'verga', 'vergon',
    'puta', 'puto', 'pendejo', 'pendeja', 'maricon', 'maricona',
    'marica', 'cabron', 'cabrona', 'carajo', 'mierda', 'ojete',
    'mamabicho', 'mamahuevo', 'mamaguevo', 'hijueputa', 'hpta',
    'gafo', 'gafa', 'pajuo', 'pajua', 'culero', 'culera', 'malparido'
  ];
  v_token      text;
begin
  v_texto := lower(new.texto);

  foreach v_token in array v_palabras loop
    if v_texto ~ ('\m' || v_token || '\M') then
      raise exception 'Comentario no permitido: contiene lenguaje ofensivo.';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_validar_comentario_anuncio on public.anuncio_comentarios;
create trigger trg_validar_comentario_anuncio
  before insert or update on public.anuncio_comentarios
  for each row execute function public.fn_validar_comentario_anuncio();

-- 5. Trigger: mantiene anuncios.total_comentarios sincronizado ----------
create or replace function public.fn_actualizar_total_comentarios()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (tg_op = 'INSERT') then
    update public.anuncios
       set total_comentarios = total_comentarios + 1
     where id_anuncio = new.id_anuncio;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.anuncios
       set total_comentarios = greatest(total_comentarios - 1, 0)
     where id_anuncio = old.id_anuncio;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_anuncio_comentarios_insert on public.anuncio_comentarios;
create trigger trg_anuncio_comentarios_insert
  after insert on public.anuncio_comentarios
  for each row execute function public.fn_actualizar_total_comentarios();

drop trigger if exists trg_anuncio_comentarios_delete on public.anuncio_comentarios;
create trigger trg_anuncio_comentarios_delete
  after delete on public.anuncio_comentarios
  for each row execute function public.fn_actualizar_total_comentarios();