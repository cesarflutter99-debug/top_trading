# Top Trading — Starter

## Cómo montar esto sobre tu proyecto Flutter recién creado

1. Crea el proyecto (si no lo has hecho):
   ```bash
   flutter create top_trading
   cd top_trading
   code .
   ```

2. Copia estos archivos dentro de tu proyecto, respetando la ruta:
   - `pubspec.yaml` → reemplaza el que trae por defecto
   - `lib/main.dart` → reemplaza el que trae por defecto
   - `lib/core/supabase_client.dart`
   - `lib/services/tiendas_service.dart`
   - `lib/services/whatsapp_service.dart`
   - `lib/services/location_service.dart`
   - `lib/screens/home_screen.dart`

3. Instala las dependencias:
   ```bash
   flutter pub get
   ```

4. Edita `lib/core/supabase_client.dart` y pon tu **URL** y **anon key**
   (Supabase → Project Settings → API).

5. Permisos de ubicación (necesarios para `geolocator`):
   - **Android**: en `android/app/src/main/AndroidManifest.xml`, dentro de `<manifest>`:
     ```xml
     <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
     <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
     ```
   - **iOS**: en `ios/Runner/Info.plist`:
     ```xml
     <key>NSLocationWhenInUseUsageDescription</key>
     <string>Usamos tu ubicación para mostrarte tiendas cercanas</string>
     ```

6. Corre la app:
   ```bash
   flutter run
   ```

## Qué incluye este starter

- Conexión a Supabase ya inicializada.
- `TiendasService`: llama a las funciones RPC del esquema
  (`carrusel_premium`, `carrusel_top_trending`, `buscar_tiendas_cercanas`)
  y maneja pedidos/valoraciones.
- `WhatsappService`: arma el link `wa.me` con el desglose del pedido.
- `LocationService`: pide permiso GPS y devuelve la posición.
- `HomeScreen`: ya arma los dos carruseles pedidos:
  - Arriba: **Destacados** (premium, manual).
  - Abajo: **Lo más caliente de la semana** (top trending, automático).

## Pendiente de construir (siguiente paso lógico)

- Pantalla de login/registro (Google Auth vía Supabase).
- Onboarding de tienda (formulario + GPS + estado 'pending').
- Vista de tienda individual + carrito local (Provider, TTL 72h).
- Pantalla de búsqueda por texto usando `buscar_tiendas_cercanas`.
- Pantalla de valoración post-compra (estrellas + foto opcional).

Dile a Claude cuál de estos quieres construir primero.
