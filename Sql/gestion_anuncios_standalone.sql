-- =====================================================================
-- gestion_anuncios_standalone.sql
--
-- Backend de la pantalla "Gestionar anuncio" (GestionarAnuncioScreen).
-- Es 100% ADITIVO: crea 3 funciones nuevas + 1 política nueva. No
-- modifica ninguna tabla, trigger ni función existente, y se puede
-- ejecutar varias veces sin problema (create or replace / drop if exists).
--
-- Qué resuelve:
--  1) anuncio_gestion_detalle   -> una sola llamada trae el anuncio, los
--     comentarios y los "me gusta" CON nombre y foto de quien interactuó
--     (esos datos viven en auth.users, que el cliente no puede leer).
--     Solo responde al DUEÑO del anuncio.
--  2) anuncio_reenviar_revision -> un anuncio RECHAZADO vuelve a
--     'pendiente'. Hoy el trigger anuncios_before_update lo impide al
--     dueño (CAMPO_PROTEGIDO), por eso hace falta esta función.
--  3) anuncio_renovar_standalone -> reactiva un anuncio VENCIDO usando
--     una ranura (permiso) vigente y con espacio libre. Si no hay,
--     lanza SIN_RANURA_LIBRE y la app abre la compra de paquetes.
--  4) Política: el dueño del anuncio puede borrar comentarios hechos en
--     SU anuncio (moderación). Hoy solo puede borrar los suyos.
--
-- Las funciones 2 y 3 usan el mismo mecanismo que ya usa tu sistema para
-- cambios internos (GUC app.anuncio_automatico, ver anuncios_before_update
-- punto (a)); la validación de dueño/tipo/estado/cupo se hace aquí dentro.
-- =====================================================================


-- ---------------------------------------------------------------------
-- 1) DETALLE PARA EL DUEÑO
-- ---------------------------------------------------------------------
create or replace function public.anuncio_gestion_detalle(p_id_anuncio uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_anuncio    anuncios%rowtype;
  v_likes      jsonb;
  v_coms       jsonb;
  v_tot_likes  int;
  v_tot_coms   int;
begin
  if auth.uid() is null then
    raise exception 'SESION_REQUERIDA';
  end if;

  select * into v_anuncio
  from anuncios
  where id_anuncio = p_id_anuncio
    and creado_por = auth.uid();

  if not found then
    raise exception 'NO_AUTORIZADO';
  end if;

  -- Conteos en vivo (no dependen de que total_likes/total_comentarios
  -- estén al día).
  select count(*) into v_tot_likes from anuncio_likes       where id_anuncio = p_id_anuncio;
  select count(*) into v_tot_coms  from anuncio_comentarios where id_anuncio = p_id_anuncio;

  select coalesce(jsonb_agg(x.j order by x.ord desc), '[]'::jsonb)
  into v_likes
  from (
    select l.creado_en as ord,
           jsonb_build_object(
             'id_usuario', l.id_usuario,
             'nombre', coalesce(
                nullif(u.raw_user_meta_data ->> 'full_name', ''),
                nullif(u.raw_user_meta_data ->> 'name', ''),
                'Usuario'),
             'foto', coalesce(
                nullif(u.raw_user_meta_data ->> 'avatar_url_custom', ''),
                nullif(u.raw_user_meta_data ->> 'avatar_url', '')),
             'creado_en', l.creado_en
           ) as j
    from anuncio_likes l
    left join auth.users u on u.id = l.id_usuario
    where l.id_anuncio = p_id_anuncio
    order by l.creado_en desc
    limit 50
  ) x;

  select coalesce(jsonb_agg(x.j order by x.ord desc), '[]'::jsonb)
  into v_coms
  from (
    select c.creado_en as ord,
           jsonb_build_object(
             'id_comentario', c.id_comentario,
             'id_usuario', c.id_usuario,
             'nombre_usuario', c.nombre_usuario,
             'texto', c.texto,
             'creado_en', c.creado_en,
             'foto', coalesce(
                nullif(u.raw_user_meta_data ->> 'avatar_url_custom', ''),
                nullif(u.raw_user_meta_data ->> 'avatar_url', ''))
           ) as j
    from anuncio_comentarios c
    left join auth.users u on u.id = c.id_usuario
    where c.id_anuncio = p_id_anuncio
    order by c.creado_en desc
    limit 100
  ) x;

  return jsonb_build_object(
    'anuncio',           to_jsonb(v_anuncio),
    'likes',             v_likes,
    'comentarios',       v_coms,
    'total_likes',       v_tot_likes,
    'total_comentarios', v_tot_coms
  );
end;
$$;


-- ---------------------------------------------------------------------
-- 2) REENVIAR A REVISIÓN (rechazado -> pendiente)
-- ---------------------------------------------------------------------
create or replace function public.anuncio_reenviar_revision(p_id_anuncio uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v anuncios%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESION_REQUERIDA';
  end if;

  select * into v
  from anuncios
  where id_anuncio = p_id_anuncio
    and creado_por = auth.uid()
  for update;

  if not found then
    raise exception 'NO_AUTORIZADO';
  end if;
  if v.tipo <> 'standalone' or v.es_automatico then
    raise exception 'NO_APLICA: este tipo de anuncio no se reenvía desde aquí.';
  end if;
  if v.estado <> 'rechazado' then
    raise exception 'ESTADO_INVALIDO: solo un anuncio rechazado se puede reenviar a revisión.';
  end if;
  if v.vigencia_hasta is not null and v.vigencia_hasta <= now() then
    raise exception 'ANUNCIO_VENCIDO: este anuncio ya venció.';
  end if;

  perform set_config('app.anuncio_automatico', 'true', true);
  update anuncios set estado = 'pendiente' where id_anuncio = p_id_anuncio;
  perform set_config('app.anuncio_automatico', 'false', true);
end;
$$;


-- ---------------------------------------------------------------------
-- 3) RENOVAR UN ANUNCIO STANDALONE VENCIDO
-- ---------------------------------------------------------------------
create or replace function public.anuncio_renovar_standalone(p_id_anuncio uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v      anuncios%rowtype;
  v_perm permisos_usuario_anuncios%rowtype;
begin
  if auth.uid() is null then
    raise exception 'SESION_REQUERIDA';
  end if;

  select * into v
  from anuncios
  where id_anuncio = p_id_anuncio
    and creado_por = auth.uid()
  for update;

  if not found then
    raise exception 'NO_AUTORIZADO';
  end if;
  if v.tipo <> 'standalone' or v.es_automatico then
    raise exception 'NO_APLICA: este tipo de anuncio no se renueva desde aquí.';
  end if;

  -- Vencido de verdad: expirado, o pausado cuya vigencia ya pasó.
  if not (
       v.estado = 'expirado'
    or (v.estado = 'pausado'
        and v.vigencia_hasta is not null
        and v.vigencia_hasta <= now())
  ) then
    raise exception 'ESTADO_INVALIDO: este anuncio no está vencido.';
  end if;

  -- Ranura vigente con espacio libre (mismo criterio de cupo que
  -- anuncios_before_insert: solo cuentan los 'aprobado').
  select pu.* into v_perm
  from permisos_usuario_anuncios pu
  where pu.id_usuario = auth.uid()
    and pu.activo
    and pu.hasta > now()
    and (
      select count(*)
      from anuncios a
      where a.tipo = 'standalone'
        and a.id_permiso_usuario = pu.id_permiso
        and a.estado = 'aprobado'
    ) < pu.max_anuncios
  order by pu.hasta desc
  limit 1
  for update of pu;

  if not found then
    raise exception 'SIN_RANURA_LIBRE: no tienes una ranura vigente con espacio. Compra un paquete.';
  end if;

  perform set_config('app.anuncio_automatico', 'true', true);
  update anuncios
  set estado             = 'aprobado',
      vigencia_hasta     = v_perm.hasta,
      id_permiso_usuario = v_perm.id_permiso
  where id_anuncio = p_id_anuncio;
  perform set_config('app.anuncio_automatico', 'false', true);
end;
$$;


-- ---------------------------------------------------------------------
-- Permisos de ejecución: solo usuarios con sesión.
-- ---------------------------------------------------------------------
revoke all on function public.anuncio_gestion_detalle(uuid)      from public, anon;
revoke all on function public.anuncio_reenviar_revision(uuid)    from public, anon;
revoke all on function public.anuncio_renovar_standalone(uuid)   from public, anon;
grant execute on function public.anuncio_gestion_detalle(uuid)    to authenticated;
grant execute on function public.anuncio_reenviar_revision(uuid)  to authenticated;
grant execute on function public.anuncio_renovar_standalone(uuid) to authenticated;


-- ---------------------------------------------------------------------
-- 4) El dueño del anuncio puede moderar (borrar) comentarios en SU anuncio.
--    Se SUMA a la política existente anuncio_comentarios_delete_own
--    (las políticas permisivas se combinan con OR).
-- ---------------------------------------------------------------------
drop policy if exists anuncio_comentarios_delete_dueno_anuncio on public.anuncio_comentarios;
create policy anuncio_comentarios_delete_dueno_anuncio
  on public.anuncio_comentarios
  for delete
  using (
    exists (
      select 1
      from public.anuncios a
      where a.id_anuncio = anuncio_comentarios.id_anuncio
        and a.creado_por = auth.uid()
    )
  );
