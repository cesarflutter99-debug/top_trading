-- activar_plan_gratis.sql
-- Activa el plan gratis en una tienda que YA existe (desde Gestionar Planes).
-- Replica lo que hace crear_tienda_plan_gratis (registro): una sola vez por
-- cuenta (fn_puede_usar_plan_gratis / fn_registrar_uso_plan_gratis, que son
-- permanentes aunque se borre la tienda), tienda activa al instante y
-- vencimiento a los días que diga el plan (14).

create or replace function public.activar_plan_gratis(
  p_id_tienda uuid,
  p_id_plan   uuid
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid := auth.uid();
  v_codigo  text;
  v_dias    int;
  v_gratis  boolean;
begin
  if v_user_id is null then
    raise exception 'Debes iniciar sesión';
  end if;

  -- La tienda debe ser del usuario que llama
  if not exists (
    select 1 from tiendas
    where id_tienda = p_id_tienda and owner_id = v_user_id
  ) then
    raise exception 'Esta tienda no te pertenece';
  end if;

  -- El plan debe existir, estar activo y ser el gratuito
  select codigo, duracion_dias, es_gratis
    into v_codigo, v_dias, v_gratis
  from planes
  where id_plan = p_id_plan and activo = true;

  if v_codigo is null or v_gratis is not true then
    raise exception 'El plan seleccionado no es un plan gratuito';
  end if;

  -- Una sola vez por cuenta
  if not fn_puede_usar_plan_gratis(v_user_id) then
    raise exception 'Ya usaste tu plan gratuito con esta cuenta. Elige un plan Basic o Premium.';
  end if;

  update tiendas
  set plan              = v_codigo,
      estado            = 'active',
      plan_expira_en    = now() + make_interval(days => coalesce(v_dias, 14)),
      plan_gratis_usado = true,
      ultima_activacion = now()
  where id_tienda = p_id_tienda;

  perform fn_registrar_uso_plan_gratis(v_user_id);
end;
$function$;

grant execute on function public.activar_plan_gratis(uuid, uuid) to authenticated;
