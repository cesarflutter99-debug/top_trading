# Top Trading ("Al Lado")

Marketplace geolocalizado (Flutter + Supabase) con comprador, vendedor, sistema de anuncios y programa de afiliados.

## Stack

- **Frontend**: Flutter (Material 3), `go_router`, `provider`
- **Backend**: Supabase (Postgres + RLS + RPC + Realtime + Storage + Edge Functions)
- **Geolocalización**: `geolocator` + mapa `flutter_map`/OpenStreetMap
- **Auth**: Google nativo (`google_sign_in`) con fallback OAuth por navegador
- **Offline**: cache read-through + cola de acciones pendientes + banner de conectividad
- **Divisas**: precios en USD, toggle USD/CUP con tasa desde `tasas_cambio`

## Estructura

- `lib/core/`: cliente Supabase, auth guard, colores, provincias, config Google OAuth
- `lib/services/`: 18 servicios (tienda, negocio, afiliado, anuncios, carrito, notificaciones, ofline, etc.)
- `lib/screens/`: 27+ pantallas (welcome, home, mapa, favoritos, tienda, carrito, panel vendedor, onboarding, dashboards, anuncios...)
- `lib/widgets/`: componentes reutilizables (tarjetas anuncio, modales producto, sheets planes/paquetes, etc.)
- `*.sql` en la raíz: esquema y parches del backend

## Módulos principales

- **Comprador**: feed con anuncios, búsqueda, tiendas cercanas, mapa, carrito (TTL 72h), valoración post-compra, favoritos
- **Vendedor**: onboarding de tienda (plan gratis/basic/premium), panel con productos/planes/anuncios/analíticas, dashboard
- **Negocio/Evento**: CTA "promociona tu negocio", onboarding por steps, mini-página, paquetes de anuncios
- **Anuncios independientes**: vender algo puntual (moto, mueble) sin tienda ni negocio — standalone
- **Afiliado**: registro con código, comisiones, retiros, tiendas referidas
- **Admin**: aprobación de tiendas/negocios/planes/anuncios, notificaciones en tiempo real (panel aparte)

## Ranuras de anuncio

El cupo de anuncios de una tienda = ranuras del plan + ranuras extra compradas aparte
(`permisos_tienda_anuncios`). La UI muestra el desglose ("X de Y · Z del plan + W extra")
en el panel vendedor y en la tarjeta "Mi Tienda" de Mi Perfil.

## Configuración

1. `flutter pub get`
2. Edita `lib/core/supabase_client.dart` con tu URL y anon key.
3. Configura `lib/core/google_auth_config.dart` (webClientId / iosClientId reales).
4. Permisos de ubicación en Android/iOS (ver `pubspec.yaml` y manifiestos).
5. Aplica el esquema SQL (`*.sql` en la raíz) y los parches en Supabase.
6. Crea los buckets de storage públicos (`productos`, `tiendas`, `negocios`, `perfiles`) en Supabase.

## Pendiente / en revisión

- Verificación real de pago de paquetes (standalone y anuncios) — hoy los paquetes activos son de libre uso hasta definir la pasarela.
- Municipios completos de todas las provincias (hoy solo La Habana).
- Tests unitarios/de widget (solo hay `widget_test.dart` por defecto).
- Búsqueda por texto general a nivel de app.
