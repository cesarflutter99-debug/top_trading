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
// IMPLEMENTACIÓN: SIN dependencias npm (sin firebase-admin). El admin SDK
// de Firebase no cargaba en el runtime edge de Deno (500 vacío en todas las
// llamadas, incluso con init diferido). Acá se usa:
//   1) crypto.subtle (WebCrypto, nativo de Deno) para firmar un JWT RS256
//      con la private_key del service account.
//   2) fetch a https://oauth2.googleapis.com/token para canjearlo por un
//      access_token.
//   3) fetch a la REST de FCM v1 (messages:send) por cada token.
//   4) fetch a PostgREST (SUPABASE_URL/rest/v1) para leer `dispositivos`.
// Todo con fetch + crypto globales => cold start liviano y sin imports rotos.
//
// Deploy:
//   supabase functions deploy notificar-push --no-verify-jwt
// =============================================================================

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const pushSecret = Deno.env.get("PUSH_SECRET")!;
const firebaseServiceAccount = Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!;

// -----------------------------------------------------------------------------
// OAuth2 + FCM v1 REST (sin firebase-admin)
// -----------------------------------------------------------------------------

let cuentaFirebase: {
  project_id?: string;
  client_email?: string;
  private_key?: string;
  token_uri?: string;
} | null = null;

function leerCuenta() {
  if (cuentaFirebase) return cuentaFirebase;
  if (!firebaseServiceAccount) {
    throw new Error("Secret FIREBASE_SERVICE_ACCOUNT no está configurado");
  }
  cuentaFirebase = JSON.parse(firebaseServiceAccount);
  if (!cuentaFirebase.private_key || !cuentaFirebase.client_email) {
    throw new Error(
      "FIREBASE_SERVICE_ACCOUNT no tiene private_key/client_email",
    );
  }
  return cuentaFirebase;
}

// "-----BEGIN PRIVATE KEY-----\nMII...\n-----END PRIVATE KEY-----\n" -> ArrayBuffer (PKCS#8)
function privateKeyBytes(pem: string): Uint8Array {
  const base64 = pem
    .replace(/-----[^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bytes = atob(base64);
  const out = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) out[i] = bytes.charCodeAt(i);
  return out;
}

function b64Url(s: string): string {
  return s.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function firmarJwt(): Promise<string> {
  const cuenta = leerCuenta();
  const ahora = Math.floor(Date.now() / 1000);
  const header = b64Url(btoa(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const claims = b64Url(btoa(JSON.stringify({
    iss: cuenta.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: ahora,
    exp: ahora + 3600,
  })));
  const data = `${header}.${claims}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(cuenta.private_key!).buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(data)),
  );
  let sigB64 = "";
  for (const b of sig) sigB64 += String.fromCharCode(b);
  return `${data}.${b64Url(btoa(sigB64))}`;
}

let accessTokenCache: { token: string; expira: number } | null = null;

// Access token con caché hasta 5 min antes de expirar.
async function obtenerAccessToken(): Promise<string> {
  const ahora = Date.now();
  if (accessTokenCache && accessTokenCache.expira > ahora + 300000) {
    return accessTokenCache.token;
  }
  const cuenta = leerCuenta();
  const jwt = await firmarJwt();
  const params = new URLSearchParams();
  params.set("grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer");
  params.set("assertion", jwt);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: params.toString(),
  });
  const body = await res.json();
  if (!res.ok || !body.access_token) {
    throw new Error(
      "OAuth2 falló: " +
        JSON.stringify(body).substring(0, 300) +
        " (firebase project del service account debe ser: " +
        cuenta.project_id +
        ")",
    );
  }
  accessTokenCache = {
    token: body.access_token as string,
    expira: ahora + (body.expires_in as number | undefined) * 1000 as number || ahora + 3600000,
  };
  return accessTokenCache.token;
}

// Envía un mensaje FCM a un token y devuelve true/false.
async function enviarToken(
  token: string,
  mensaje: {
    title: string;
    body: string;
    data: Record<string, string>;
  },
): Promise<boolean> {
  const cuenta = leerCuenta();
  const accessToken = await obtenerAccessToken();
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${cuenta.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: mensaje.title, body: mensaje.body },
          data: mensaje.data,
          android: {
            priority: "high",
            notification: { channelId: "notificaciones", sound: "default" },
          },
          apns: {
            payload: { aps: { sound: "default", "content-available": 1 } },
          },
        },
      }),
    },
  );
  return res.ok;
}

// -----------------------------------------------------------------------------
// Handler
// -----------------------------------------------------------------------------

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

  // Tokens FCM activos del usuario vía PostgREST (sin supabase-js).
  let tokens: string[] = [];
  try {
    const url =
      `${supabaseUrl}/rest/v1/dispositivos?select=token&user_id=eq.${encodeURIComponent(userId)}`;
    const res = await fetch(url, {
      headers: {
        apikey: supabaseServiceRole,
        Authorization: `Bearer ${supabaseServiceRole}`,
      },
    });
    if (!res.ok) {
      return Response.json(
        { error: "Error leyendo dispositivos: " + res.status + " " + (await res.text()).substring(0, 200) },
        { status: 500 },
      );
    }
    const filas = await res.json();
    tokens = Array.isArray(filas) ? filas.map((f: { token: string }) => f.token) : [];
  } catch (e) {
    return Response.json(
      { error: "dispositivos no legible: " + String(e) },
      { status: 500 },
    );
  }

  if (tokens.length === 0) {
    return Response.json({ ok: true, enviados: 0 });
  }

  const data: Record<string, string> = {
    tipo: payload.tipo ?? "general",
    ...(Object.fromEntries(
      Object.entries(payload.data ?? {}).map(([k, v]) => [
        k,
        typeof v === "string" ? v : JSON.stringify(v),
      ]),
    ) as Record<string, string>),
  };

  try {
    const mensaje = {
      title: payload.titulo ?? "",
      body: payload.mensaje ?? "",
      data,
    };
    const resultados = await Promise.all(
      tokens.map(async (t) => ({ t, ok: await enviarToken(t, mensaje) })),
    );
    return Response.json({
      ok: true,
      exito: resultados.filter((r) => r.ok).length,
      fallos: resultados.filter((r) => !r.ok).length,
    });
  } catch (e) {
    return Response.json(
      { error: "FCM falló: " + String(e) },
      { status: 500 },
    );
  }
});