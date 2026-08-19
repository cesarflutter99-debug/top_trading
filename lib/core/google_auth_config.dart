// google_auth_config.dart
//
// Configuración del LOGIN NATIVO de Google (google_sign_in).
//
// Con esto, "Iniciar sesión con Google" ya NO abre el navegador: el
// selector de cuentas sale como UI nativa del sistema Android/iOS y
// nunca se ve la URL de supabase.co (antes aparecía en la barra del
// navegador y asustaba a los usuarios).
//
// PASOS ÚNICOS (hay que hacerlos una sola vez):
//
// 1. Ve a https://console.cloud.google.com y elegí (o creá) el proyecto
//    donde ya configuraste el OAuth de Supabase.
// 2. Activa la "Pantalla de consentimiento de OAuth" (External) si no la
//    tenés activa.
// 3. En "Credenciales" creá un cliente OAuth de tipo "Aplicación web"
//    y copiá su "ID de cliente web" en webClientId de abajo.
// 4. En "Credenciales" creá un cliente OAuth de tipo "Android" con:
//      - Nombre de paquete: com.example.top_trading
//        (el applicationId de android/app/build.gradle.kts)
//      - SHA-1 de la firma con la que compilás (debug y release).
//        Para sacar el SHA-1 de debug en Windows:
//          keytool -list -v -alias androiddebugkey -keystore
//          %USERPROFILE%\.android\debug.keystore  (password: android)
//
// Si dejás el placeholder, el login cae automáticamente al modo
// navegador (el de antes), así que la app nunca se rompe.
class GoogleAuthConfig {
  static const String webClientId = 'YOUR_WEB_CLIENT_ID_HERE';

  // iOS: el clientId es el "ID de cliente" del tipo "iOS" en Google
  // Cloud. Dejalo vacío si solo probás en Android.
  static const String iosClientId = '';
}
