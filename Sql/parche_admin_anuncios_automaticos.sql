-- =============================================================================
-- ADMIN: GESTIÓN DE ANUNCIOS AUTOMÁTICOS DE NEGOCIO (es_automatico)
-- =============================================================================
-- Los anuncios automáticos los genera el sistema por triggers
-- (fn_sincronizar_anuncio_automatico_negocio): un negocio activo con
-- paquete vigente se autopromociona en el feed sin pasar por
-- moderación. El dueño NO puede tocarlos (campos protegidos en
-- anuncios_before_update y RLS), pero el admin sí.
--
-- Esta RPC permite al panel admin forzar una re-sincronización
-- (p.ej. cuando el negocio cambió de categoría/logo y el trigger aún
-- no corrió), con guard de es_admin(). Es idempotente.
-- =============================================================================

create or replace function public.admin_sincronizar_anuncio_negocio(p_id_negocio uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not es_admin() then
    raise exception 'SOLO_ADMIN';
  end if;
  perform fn_sincronizar_anuncio_automatico_negocio(p_id_negocio);
end;
$$;

grant execute on function public.admin_sincronizar_anuncio_negocio(uuid) to authenticated;