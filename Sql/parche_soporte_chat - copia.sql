-- parche_soporte_chat.sql
-- ============================================================
-- Chat de soporte: los usuarios escriben desde la app y los
-- mensajes llegan al panel de administración (allado_admin_v2).
-- Idempotente.
-- ============================================================

-- 1) Tabla de chats (uno por usuario, reutilizable mientras esté abierto).
create table if not exists public.soporte_chats (
  id              uuid primary key default gen_random_uuid(),
  id_usuario      uuid not null references auth.users(id) on delete cascade,
  estado          text not null default 'abierto'
                    check (estado in ('abierto','cerrado')),
  ultimo_mensaje  text,
  creado_en       timestamptz not null default now(),
  actualizado_en  timestamptz not null default now(),
  leido_admin     boolean not null default false
);

create index if not exists idx_soporte_chats_usuario
  on public.soporte_chats(id_usuario);
create index if not exists idx_soporte_chats_actualizado
  on public.soporte_chats(actualizado_en desc);

-- 2) Tabla de mensajes.
create table if not exists public.soporte_mensajes (
  id          uuid primary key default gen_random_uuid(),
  id_chat     uuid not null references public.soporte_chats(id) on delete cascade,
  id_usuario  uuid not null references auth.users(id) on delete cascade,
  es_admin    boolean not null default false,
  contenido   text not null,
  creado_en   timestamptz not null default now(),
  leido       boolean not null default false
);

create index if not exists idx_soporte_mensajes_chat
  on public.soporte_mensajes(id_chat, creado_en);

-- 3) RLS.
alter table public.soporte_chats enable row level security;
alter table public.soporte_mensajes enable row level security;

-- Chats: el usuario ve/crea los suyos; el admin ve todos.
drop policy if exists soporte_chats_select on public.soporte_chats;
create policy soporte_chats_select on public.soporte_chats
  for select using (id_usuario = auth.uid() or es_admin());

drop policy if exists soporte_chats_insert on public.soporte_chats;
create policy soporte_chats_insert on public.soporte_chats
  for insert with check (id_usuario = auth.uid());

drop policy if exists soporte_chats_update on public.soporte_chats;
create policy soporte_chats_update on public.soporte_chats
  for update using (id_usuario = auth.uid() or es_admin())
  with check (id_usuario = auth.uid() or es_admin());

-- Mensajes: se leen/escriben si el chat pertenece al usuario o es admin.
drop policy if exists soporte_mensajes_select on public.soporte_mensajes;
create policy soporte_mensajes_select on public.soporte_mensajes
  for select using (
    exists (select 1 from public.soporte_chats c
            where c.id = id_chat
              and (c.id_usuario = auth.uid() or es_admin()))
  );

drop policy if exists soporte_mensajes_insert on public.soporte_mensajes;
create policy soporte_mensajes_insert on public.soporte_mensajes
  for insert with check (
    id_usuario = auth.uid()
    and exists (select 1 from public.soporte_chats c
                where c.id = id_chat
                  and (c.id_usuario = auth.uid() or es_admin()))
  );

-- 4) Trigger: al insertar un mensaje, actualiza el chat.
create or replace function public.soporte_mensaje_insertado()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.soporte_chats
     set ultimo_mensaje = new.contenido,
         actualizado_en = now(),
         leido_admin = case when new.es_admin then leido_admin else false end
   where id = new.id_chat;
  return new;
end;
$$;

drop trigger if exists trg_soporte_mensaje_insertado on public.soporte_mensajes;
create trigger trg_soporte_mensaje_insertado
  after insert on public.soporte_mensajes
  for each row execute function public.soporte_mensaje_insertado();

-- 5) RPC para que el admin obtenga la lista de chats.
create or replace function public.admin_soporte_chats()
returns table (
  id_chat         uuid,
  id_usuario      uuid,
  email           text,
  estado          text,
  ultimo_mensaje  text,
  actualizado_en  timestamptz,
  leido_admin     boolean,
  total_mensajes  bigint
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
  select c.id, c.id_usuario, u.email, c.estado, c.ultimo_mensaje,
         c.actualizado_en, c.leido_admin,
         (select count(*) from public.soporte_mensajes m where m.id_chat = c.id)::bigint
  from public.soporte_chats c
  left join auth.users u on u.id = c.id_usuario
  order by c.actualizado_en desc;
end;
$$;

grant execute on function public.admin_soporte_chats() to authenticated;

-- 6) Habilitar Realtime (idempotente: ignora si ya está en la publicación).
do $$
begin
  alter publication supabase_realtime add table public.soporte_chats;
exception when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.soporte_mensajes;
exception when duplicate_object then null;
end $$;
PY