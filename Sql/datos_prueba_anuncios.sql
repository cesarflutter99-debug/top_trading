-- ============================================================================
-- datos_prueba_anuncios.sql
--
-- DATOS DE PRUEBA para el flujo de anuncios de Al Lado:
--
--   · 30 USUARIOS falsos en auth.users (demo01@allado.test ... demo30@...)
--     -- necesarios porque tiendas.owner_id es UNIQUE y FK a auth.users.
--   · 30 TIENDAS "Tienda Demo 01..30" en La Habana, estado 'active'.
--     - Cada 3ra es PREMIUM (ranuras_anuncios = 3); el resto basic (0).
--   · 2-3 PRODUCTOS visibles por tienda (imágenes de picsum.photos --
--     requieren internet al cargarlas).
--   · ~7 ANUNCIOS tipo 'producto' ya APROBADOS (uno por las primeras
--     tiendas premium) -> salen intercalados en el feed al instante.
--   · 1 NEGOCIO demo activo ("Barbería Demo") + permiso vigente +
--     su anuncio tipo 'negocio' aprobado.
--   · 1 ANUNCIO ADMIN de cortesía si no existe ninguno.
--
-- ES IDEMPOTENTE: puedes correrlo varias veces sin duplicar.
-- El bloque de LIMPIEZA está al final, comentado.
--
-- NOTA: los usuarios demo NO pueden iniciar sesión real (contraseña
-- demo1234 pero no tienen identidad Google); son solo dueños de fila.
-- ============================================================================

do $$
declare
  v_uid      uuid;
  v_tid      uuid;
  v_i        int;
  v_j        int;
  v_nprods   int;
  v_cat_idx  int;
  v_plan     text;
  v_categorias text[] := array['Tecnología','Hogar','Moda','Comida','Deportes'];
  v_noms_tec   text[] := array['Audífonos Bluetooth','Cargador rápido','Mouse inalámbrico','Teclado mecánico','Power bank 20000'];
  v_noms_hog   text[] := array['Batidora eléctrica','Juego de ollas','Ventilador de pie','Cafetera express','Set de sábanas'];
  v_noms_mod   text[] := array['Jeans clásicos','Camiseta oversize','Zapatillas urbanas','Gorra bordada','Chaqueta ligera'];
  v_noms_com   text[] := array['Pizza familiar','Sándwich mixto','Jugo natural 1L','Helado artesanal','Café molido'];
  v_noms_dep   text[] := array['Mancuernas 5kg','Balón de fútbol','Tapete de yoga','Guantes de gym','Rodillo abdominal'];
  v_nombres    text[];
begin
  ------------------------------------------------------------------
  -- 1) TIENDAS + DUEÑOS + PRODUCTOS
  ------------------------------------------------------------------
  for v_i in 1..30 loop

    -- Usuario demo dueño de la tienda (FK + UNIQUE owner_id).
    -- FIX: auth.users no tiene UNIQUE sobre email en este proyecto,
    -- así que ON CONFLICT (email) falla (42P10); chequeamos antes.
    select id into v_uid from auth.users
    where email = 'demo'||v_i||'@allado.test';

    if v_uid is null then
      insert into auth.users (instance_id, id, aud, role, email,
                              encrypted_password, email_confirmed_at,
                              raw_app_meta_data, created_at, updated_at)
      values ('00000000-0000-0000-0000-000000000000',
              gen_random_uuid(),
              'authenticated', 'authenticated',
              'demo'||v_i||'@allado.test',
              crypt('demo1234', gen_salt('bf')),
              now(),
              '{"provider":"email","providers":["email"]}',
              now(), now())
      returning id into v_uid;
    end if;

    v_plan    := case when v_i % 3 = 0 then 'premium' else 'basic' end;
    v_cat_idx := 1 + (v_i % 5);

    insert into tiendas (owner_id, nombre, nombre_propietario,
                         telefono_whatsapp, provincia, municipio,
                         latitud, longitud, plan, categoria,
                         descripcion, logo_url, estado)
    values (v_uid,
            'Tienda Demo '||lpad(v_i::text, 2, '0'),
            'Propietario Demo '||v_i,
            '53'||lpad((81200000 + v_i * 137)::text, 8, '0'),
            'La Habana',
            (array['Plaza de la Revolución','Centro Habana','Playa',
                   'Cerro','Diez de Octubre'])[1 + (v_i % 5)],
            round(23.100 + ((v_i % 10) * 0.009), 6),
            round(-82.440 + ((v_i % 15) * 0.006), 6),
            v_plan,
            v_categorias[v_cat_idx],
            'Tienda de prueba para el sistema de anuncios de Al Lado.',
            'https://picsum.photos/seed/tienda'||v_i||'/300/300',
            'active')
    on conflict (owner_id) do nothing
    returning id_tienda into v_tid;

    if v_tid is null then
      select id_tienda into v_tid from tiendas
      where owner_id = v_uid;
    end if;

    -- Productos: 2 o 3 por tienda
    v_nprods  := 2 + (v_i % 2);
    v_nombres := case v_cat_idx
                   when 1 then v_noms_tec
                   when 2 then v_noms_hog
                   when 3 then v_noms_mod
                   when 4 then v_noms_com
                   else        v_noms_dep
                 end;

    for v_j in 1..v_nprods loop
      insert into productos (id_tienda, nombre, precio_usd, descripcion,
                             imagen_url, cantidad_disponible, categoria,
                             es_visible)
      select v_tid,
             v_nombres[1 + ((v_i * 3 + v_j) % 5)],
             ((v_i * 7 + v_j * 13) % 45 + 4)::numeric + 0.99,
             'Producto de prueba -- parte del lote demo de anuncios.',
             'https://picsum.photos/seed/p'||v_i||'x'||v_j||'/600/400',
             15,
             v_categorias[v_cat_idx],
             true
      where not exists (
        select 1 from productos
        where id_tienda = v_tid
          and nombre = v_nombres[1 + ((v_i * 3 + v_j) % 5)]
      );
    end loop;

  end loop;
end $$;


------------------------------------------------------------------
-- 2) ANUNCIOS tipo PRODUCTO ya aprobados
--    Uno por cada tienda DEMO premium (con productos visibles),
--    potenciando su primer producto. El trigger valida cupo y nace
--    'aprobado' -- no hace falta desactivarlo.
------------------------------------------------------------------
insert into anuncios (tipo, id_producto, id_tienda, titulo, texto,
                      imagen_url, creado_por, estado)
select 'producto',
       x.id_producto,
       x.id_tienda,
       '¡Oferta! ' || x.nombre,
       'Disponible en ' || x.tnombre || '. ¡Pídelo ya por WhatsApp!',
       x.imagen_url,
       x.uid,
       'aprobado'
from (
  select distinct on (t.id_tienda)
         p.id_producto, p.nombre, p.imagen_url,
         t.id_tienda, t.nombre as tnombre, t.owner_id as uid
  from productos p
  join tiendas t on t.id_tienda = p.id_tienda
  where t.nombre like 'Tienda Demo %'
    and t.plan = 'premium'
    and p.es_visible = true
  order by t.id_tienda, p.fecha_creacion asc
) x
where not exists (
  select 1 from anuncios a where a.id_producto = x.id_producto
);


------------------------------------------------------------------
-- 3) NEGOCIO DEMO completo: barbería activa + permiso vigente +
--    anuncio tipo negocio aprobado (aquí SÍ desactivo triggers:
--    el insert fuerza 'pendiente' y el update exige admin).
------------------------------------------------------------------
do $$
declare
  v_uid     uuid;
  v_nid     uuid;
begin
  -- mismo FIX que arriba: sin ON CONFLICT (email)
  select id into v_uid from auth.users
  where email = 'negocio.demo@allado.test';

  if v_uid is null then
    insert into auth.users (instance_id, id, aud, role, email,
                            encrypted_password, email_confirmed_at,
                            raw_app_meta_data, created_at, updated_at)
    values ('00000000-0000-0000-0000-000000000000',
            gen_random_uuid(), 'authenticated', 'authenticated',
            'negocio.demo@allado.test',
            crypt('demo1234', gen_salt('bf')),
            now(), '{"provider":"email","providers":["email"]}',
            now(), now())
    returning id into v_uid;
  end if;

  -- FIX: sin UNIQUE en id_dueno no hay ON CONFLICT posible; guard por nombre
  select id_negocio into v_nid from negocios
  where nombre = 'Barbería Demo El Corte'
  limit 1;

  if v_nid is null then
    insert into negocios (id_dueno, nombre, categoria, descripcion,
                          whatsapp, direccion, latitud, longitud,
                          horario, logo_url, portada_url, estado)
    values (v_uid,
            'Barbería Demo El Corte',
            'Barbería',
            'Cortes clásicos y modernos. Barba, corte de niño y '
            'diseños. Atención rápida sin demoras.',
            '5351234567',
            'Calle 23 #456 entre L y M, Vedado, La Habana',
            23.1391, -82.3866,
            '{"lun":{"abre":"09:00","cierra":"18:00"},
              "mar":{"abre":"09:00","cierra":"18:00"},
              "mie":{"descanso":true},
              "jue":{"abre":"09:00","cierra":"18:00"},
              "vie":{"abre":"09:00","cierra":"20:00"},
              "sab":{"abre":"09:00","cierra":"20:00"},
              "dom":{"descanso":true}}'::jsonb,
            'https://picsum.photos/seed/barberia/300/300',
            'https://picsum.photos/seed/barberiaportada/1200/500',
            'activo')
    returning id_negocio into v_nid;
  end if;

  -- Permiso vigente 90 días (como si hubiera comprado el paquete)
  insert into permisos_negocio (id_negocio, max_anuncios, desde, hasta, activo)
  select v_nid, 2, now(), now() + interval '90 days', true
  where not exists (
    select 1 from permisos_negocio
    where id_negocio = v_nid and activo and hasta > now()
  );

  -- Anuncio del negocio, directo APROBADO (saltando triggers)
  alter table anuncios disable trigger trg_anuncios_insert;
  insert into anuncios (tipo, id_negocio, titulo, texto, imagen_url,
                        creado_por, estado, vigencia_hasta)
  select 'negocio', v_nid,
         'Corte + barba a mitad de precio',
         'Solo este mes: combina tu corte con arreglo de barba y '
         'paga la mitad. Agenda por WhatsApp.',
         'https://picsum.photos/seed/barberiaad/800/450',
         (select id_dueno from negocios where id_negocio = v_nid),
         'aprobado',
         now() + interval '60 days'
  where not exists (
    select 1 from anuncios
    where id_negocio = v_nid and estado = 'aprobado'
  );
  alter table anuncios enable trigger trg_anuncios_insert;
end $$;


------------------------------------------------------------------
-- 4) UN ANUNCIO ADMIN de cortesía (si no existe ninguno aún).
--    Desactivamos el trigger porque desde el SQL Editor auth.uid()
--    es null y SOLO_ADMIN bloquearía.
------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from anuncios where tipo = 'admin') then
    alter table anuncios disable trigger trg_anuncios_insert;
    insert into anuncios (tipo, titulo, texto, imagen_url, estado,
                          vigencia_hasta)
    values ('admin',
            'Bienvenido a Al Lado',
            'Descubre las mejores tiendas cerca de ti. Compra fácil, '
            'rápido y sin complicaciones.',
            'https://picsum.photos/seed/adminwelcome/800/450',
            'aprobado',
            now() + interval '30 days');
    alter table anuncios enable trigger trg_anuncios_insert;
  end if;
end $$;


-- ============================================================================
-- LIMPIEZA (descomenta TODO el bloque para borrar los datos demo):
--
-- begin;
-- delete from anuncios where id_negocio in
--   (select id_negocio from negocios where nombre like 'Barbería Demo%');
-- delete from permisos_negocio where id_negocio in
--   (select id_negocio from negocios where nombre like 'Barbería Demo%');
-- delete from negocios where nombre like 'Barbería Demo%';
-- delete from anuncios where id_tienda in
--   (select id_tienda from tiendas where nombre like 'Tienda Demo %');
-- delete from productos where id_tienda in
--   (select id_tienda from tiendas where nombre like 'Tienda Demo %');
-- delete from tiendas where nombre like 'Tienda Demo %';
-- delete from auth.users where email like 'demo%@allado.test'
--    or email = 'negocio.demo@allado.test';
-- commit;
-- ============================================================================
