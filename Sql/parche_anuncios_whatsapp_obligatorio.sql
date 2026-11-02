-- parche_anuncios_whatsapp_obligatorio.sql
-- ===========================================================================
-- Makes the phone number (WhatsApp) a REQUIRED field for every ad a user
-- publishes.
--
-- Until now only tipo='standalone' required it (see
-- parche_standalone_ranuras_whatsapp.sql). Ads of type 'producto' (store
-- promos) and 'negocio' (business promos) could be published with no
-- number, so the "Me interesa" button in the feed had nothing to open.
--
-- What it does:
--   1) New trigger public.trg_anuncios_whatsapp_obligatorio: BEFORE
--      INSERT, it rejects the row if the ad is a user ad and has no
--      WhatsApp.
--   2) It does NOT touch ads created by the platform:
--        - tipo='admin'   -> the platform's own announcements.
--        - es_automatico -> promos auto-generated from a plan/package
--                           (the GUC app.anuncio_automatico is also
--                           checked, which is what the internal
--                           functions set).
--   3) It is a SEPARATE trigger on purpose: the existing
--      public.anuncios_before_insert() is NOT rewritten, so nothing that
--      already works (cupos, permisos, vigencias, moderacion) can break.
--   4) It only fires on INSERT: rows already published without a number
--      keep working (they just show no "Me interesa" button). The app
--      now asks for the number when editing them.
--   5) Backfill: ads already published without a number inherit the
--      contact number of their store / business, so the button starts
--      working on the old ones too.
--
-- Run ONCE in the Supabase SQL Editor. Idempotent.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 0) Garantiza que la columna es_automatico exista (la usa el trigger
--    para distinguir los anuncios que genera el sistema).
-- ---------------------------------------------------------------------------
alter table public.anuncios
  add column if not exists es_automatico boolean not null default false;

-- ---------------------------------------------------------------------------
-- 1) Funcion de validacion.
-- ---------------------------------------------------------------------------
create or replace function public.anuncios_exigir_whatsapp()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 1) Los anuncios de la plataforma (tipo='admin') no llevan numero:
  --    su contacto es el del admin, no el del usuario.
  if new.tipo = 'admin' then
    return new;
  end if;

  -- 2) Los anuncios automaticos (generados por el sistema al comprar un
  --    plan o paquete) no llevan numero.
  if coalesce(current_setting('app.anuncio_automatico', true), 'false') = 'true'
     or new.es_automatico = true then
    return new;
  end if;

  -- 3) Todo lo demas es un anuncio de un usuario -> numero obligatorio.
  if new.whatsapp is null or btrim(new.whatsapp) = '' then
    raise exception 'WHATSAPP_REQUERIDO: agrega un numero de WhatsApp para tu anuncio.';
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2) Trigger. BEFORE INSERT para poder rechazar la fila.
-- ---------------------------------------------------------------------------
drop trigger if exists trg_anuncios_whatsapp_obligatorio on public.anuncios;
create trigger trg_anuncios_whatsapp_obligatorio
  before insert on public.anuncios
  for each row execute function public.anuncios_exigir_whatsapp();


-- ---------------------------------------------------------------------------
-- 3) Backfill: los anuncios ya publicados sin numero heredan el numero de
--    contacto de su tienda (telefono_whatsapp) o de su negocio (whatsapp).
--    Solo afecta filas donde el destino existe y tiene numero configurado.
-- ---------------------------------------------------------------------------
update public.anuncios a
   set whatsapp = t.telefono_whatsapp
  from public.tiendas t
 where a.tipo = 'producto'
   and a.id_tienda = t.id_tienda
   and (a.whatsapp is null or btrim(a.whatsapp) = '')
   and t.telefono_whatsapp is not null
   and btrim(t.telefono_whatsapp) <> '';

update public.anuncios a
   set whatsapp = n.whatsapp
  from public.negocios n
 where a.tipo = 'negocio'
   and a.id_negocio = n.id_negocio
   and (a.whatsapp is null or btrim(a.whatsapp) = '')
   and n.whatsapp is not null
   and btrim(n.whatsapp) <> '';
