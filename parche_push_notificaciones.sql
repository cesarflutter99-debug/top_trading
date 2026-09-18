-- =============================================================================
-- parche_push_notificaciones.sql
-- =============================================================================
-- Push FCM "AL LADO" -- por encima de las notificaciones in-app.
--
-- Con la arquitectura anterior, las notificaciones viven en la tabla
-- `notificaciones` y se entregan en vivo por Supabase Realtime (la
-- campanita). Eso SOLO funciona con la app abierta. Este parche agrega
-- el push FCM (Firebase Cloud Messaging, plan Spark gratuito) para que
-- también lleguen con la app cerrada/en background, usando el mismo
-- logo de la app como ícono de la notificación.
--
-- Qué hace, en orden:
--   1) Crea la tabla `dispositivos` (token FCM por usuario).
--   2) Habilita la extensión pg_net (gratuita en Supabase).
--   3) Crea el trigger que, al insertarse una fila en `notificaciones`,
--      llama a la Edge Function `notificar-push` por HTTP (async).
--      La Edge Function hace el envío real a Firebase.
--   4) Guarda en `configuracion_app` (clave 'push') la URL de la Edge
--      Function y un secreto compartido que también debe setearse como
--      secret "PUSH_SECRET" en Supabase Edge Functions.
--
-- IDEMPOTENTE: se puede correr varias veces sin errores.
--
-- ⚠️  La Edge Function `notificar-push` vive en el repo (supabase/
--     functions/notificar-push). Desplegarla y setear sus secrets:
--       supabase functions deploy notificar-push --no-verify-jwt
--       supabase secrets set PUSH_SECRET=... FIREBASE_SERVICE_ACCOUNT='<JSON del service account de Firebase>'
--     El PUSH_SECRET debe coincidir con 'secreto' de configuracion_app de abajo.
-- =============================================================================
-----------------------------------------------
-- 1) Token FCM por usuario. Un usuario puede tener varios dispositivos.
-- ---------------------------------------------------------------------------
create table if not exists public.dispositivos (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  token          text not null unique,          -- token FCM del dispositivo
  plataforma     text not null default 'android',
  creado_en      timestamptz not null default now(),
  actualizado_en timestamptz not null default now()
);

-- La app (edge function) usa service_role: ignora RLS. Los clientes
-- autenticados solo manejan SUS propios tokens.
alter table public.dispositivos enable row level security;

drop policy if exists "dispositivos_propio_select" on public.dispositivos;
create policy "dispositivos_propio_select" on public.dispositivos
  for select to authenticated using (user_id = auth.uid());

drop policy if exists "dispositivos_propio_insert" on public.dispositivos;
create policy "dispositivos_propio_insert" on public.dispositivos
  for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "dispositivos_propio_update" on public.dispositivos;
create policy "dispositivos_propio_update" on public.dispositivos
  for update to authenticated using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "dispositivos_propio_delete" on public.dispositivos;
create policy "dispositivos_propio_delete" on public.dispositivos
  for delete to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 2) pg_net: permite al trigger hacer una llamada HTTP asíncrona a la
--    Edge Function. Gratuita y nativa en Supabase.
-- ---------------------------------------------------------------------------
create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 3) Trigger AFTER INSERT en notificaciones -> invoca notificar-push.
--    Nada se guarda acá: la llamada es fire-and-forget, así el INSERT
--    de la notificación nunca se ve afectado por un fallo del push.
-- ---------------------------------------------------------------------------
create or replace function public.fn_push_notificacion()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_config jsonb;
  v_url    text;
  v_secret text;
  v_body   jsonb;
begin
  select valor into v_config
    from public.configuracion_app
   where clave = 'push';

  if v_config is null then
    return new; -- sin config de push, no hay nada que enviar
  end if;

  v_url    := v_config ->> 'url';
  v_secret := v_config ->> 'secreto';
  if v_url is null or v_secret is null or NEW.id_usuario is null then
    return new;
  end if;

  v_body := jsonb_build_object(
    'user_id', NEW.id_usuario::text,
    'titulo',  COALESCE(NEW.titulo, ''),
    'mensaje', COALESCE(NEW.mensaje, ''),
    'tipo',    COALESCE(NEW.tipo, 'general'),
    'data',    COALESCE(NEW.data, '{}'::jsonb)
  );

  perform net.http_post(
    url     := v_url,
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-push-secret',  v_secret
    ),
    body    := v_body
  );

  return new;
end;
$$;

drop trigger if exists trg_push_notificacion on public.notificaciones;
create trigger trg_push_notificacion
  after insert on public.notificaciones
  for each row execute function public.fn_push_notificacion();

-- ---------------------------------------------------------------------------
-- 4) Config de la Edge Function (URL + secreto compartido).
--    ⚠️  MANTENER ESTOS DOS VALORES EN LÍNEA con lo que se setea en
--    Supabase Dashboard > Edge Functions > Secrets (PUSH_SECRET).
-- ===========================================================================
insert into public.configuracion_app (clave, valor)
values ('push', jsonb_build_object(
  'url', 'https://azcdjfqqxptouweqejvk.supabase.co/functions/v1/notificar-push',
  'secreto', 'hV03yBuvzxcOgJdje5EfXXcSURmhLaImawXrGoZKFNX0hD7pcq1XM0ZFnQmV6/S0'
))
on conflict (clave) do update
set valor = excluded.valor,
    actualizado_en = now();