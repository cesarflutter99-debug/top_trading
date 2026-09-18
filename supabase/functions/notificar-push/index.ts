// =============================================================================
// notificar-push -- Edge Function de Supabase
// =============================================================================
// Envía un push FCM (Firebase Cloud Messaging) al entorno del cliente que
// escribió en la tupla. La llama el trigger `trg_push_notificacion` de la
// tabla `notificaciones` con un POST HTTP (fire-and-forget).
//
// Protección: valida el header `x-push-secret` contra el secret
// "PUSH_SECRET" (configurado en Supabase > Edge Functions > Secrets).
// Sin ese header devuelve 403; no se usa JWT (la llamada sale del
// trigger, no de un cliente).
//
// Secrets requeridos en Supabase:
//   - PUSH_SECRET                 -> cadena aleatoria compartida
//   - FIREBASE_SERVICE_ACCOUNT    -> JSON completo del service account
//                                    de Firebase (IAM > Service accounts)
//
// Deploy:
//   supabase functions deploy notificar-push --no-verify-jwt
// =============================================================================

import { createClient } from "npm:@supabase/supabase-js@^2.45.0";
import admin from "npm:firebase-admin@^12.0.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const pushSecret = Deno.env.get("PUSH_SECRET")!;
const firebaseServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!;

const supabase = createClient(supabaseUrl, supabaseServiceRole);

// El Admin SDK se inicializa una sola vez por cold start.
admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(firebaseServiceAccount)),
});

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== pushSecret) {
    return Response.json({ error: "No autorizado" }, { status: 403 });
  }

  let payload: {
    user_id?: string;
    titulo?: string;
    mensaje?: string;
    tipo?: string;
    data?: Record<string, unknown> | null;
  };
  try {
    payload = await req.json();
  } catch {
    return Response.json({ error: "Body inválido" }, { status: 400 });
  }

  const userId = payload.user_id;
  if (!userId) {
    return Response.json({ error: "user_id requerido" }, { status: 400 });
  }

  // Tokens FCM activos del usuario. Se envían todos; FCM descarta los
  // que están obsoletos (un registro viejo no rompe el envío).
  const { data: dispositivos, error } = await supabase
    .from("dispositivos")
    .select("token")
    .eq("user_id", userId);

  if (error) {
    return Response.json({ error: error.message }, { status: 500 });
  }
  if (!dispositivos || dispositivos.length === 0) {
    return Response.json({ ok: true, enviados: 0 });
  }

  const tokens = dispositivos.map((d) => d.token as string);
  const data = payload.data ?? {};

  const mensaje: admin.messaging.MulticastMessage = {
    tokens,
    notification: {
      title: payload.titulo ?? "",
      body: payload.mensaje ?? "",
    },
    data: {
      tipo: payload.tipo ?? "general",
      // FCM data solo acepta strings: serializamos el jsonb original.
      ...Object.fromEntries(
        Object.entries(data).map(([k, v]) => [k, typeof v === "string" ? v : JSON.stringify(v)]),
      ),
    },
    android: {
      priority: "high",
      notification: {
        channelId: "notificaciones",
      },
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  };

  try {
    const respuesta = await admin.messaging().sendEachForMulticast(mensaje);
    return Response.json({
      ok: true,
      exito: respuesta.successCount,
      fallos: respuesta.failureCount,
    });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});