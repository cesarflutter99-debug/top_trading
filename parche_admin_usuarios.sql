-- parche_admin_usuarios.sql
-- ===========================================================================
-- RPC para el panel admin: listar usuarios del marketplace desde auth.users.
-- ===========================================================================
-- No existe tabla `perfiles` y auth.users NO se puede leer por REST (RLS),
-- así que este RPC (SECURITY DEFINER, corre como postgres) devuelve cada
-- usuario de auth.users con sus roles cruzados contra:
--   tiendas (owner_id), negocios (id_dueno), afiliados (user_id), admins.
--
-- Uso desde el panel: admin_listar_usuarios(p_texto, p_limite)
--   -> filas: {id, email, creado_en, ultimo_acceso, es_admin, es_tienda,
--              es_negocio, es_afiliado, tiendas (jsonb)}
--
-- Ejecutar UNA sola vez en el SQL Editor de Supabase. Idempotente.
-- ===========================================================================

create or replace function public.admin_listar_usuarios(
  p_texto text default null,
  p_limite int default 100
)
returns table (
  id             uuid,
  email          text,
  creado_en      timestamptz,
  ultimo_acceso  timestamptz,
  es_admin       boolean,
  es_tienda      boolean,
  es_negocio     boolean,
  es_afiliado    boolean,
  tiendas        jsonb
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
      u.id,
      u.email::text,
      u.created_at,
      u.last_sign_in_at,
      exists(select 1 from admins a where a.user_id = u.id) as es_admin,
      exists(select 1 from tiendas t where t.owner_id = u.id and coalesce(t.eliminada, false) = false) as es_tienda,
      exists(select 1 from negocios n where n.id_dueno = u.id) as es_negocio,
      exists(select 1 from afiliados af where af.user_id = u.id) as es_afiliado,
      coalesce((
        select jsonb_agg(jsonb_build_object('id_tienda', t.id_tienda, 'nombre', t.nombre))
        from tiendas t
        where t.owner_id = u.id and coalesce(t.eliminada, false) = false
      ), '[]'::jsonb) as tiendas
    from auth.users u
    where (p_texto is null or u.email::text ilike '%' || p_texto || '%')
    order by u.created_at desc
    limit p_limite;
end;
$$;

revoke all on function public.admin_listar_usuarios(text, int) from public;
grant execute on function public.admin_listar_usuarios(text, int) to authenticated;
grant execute on function public.admin_listar_usuarios(text, int) to service_role;