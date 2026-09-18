// imagekit-auth/index.ts
//
// Genera la firma temporal (token + expire + signature) que ImageKit
// exige para cada subida. La PRIVATE KEY vive acá como secret de
// Supabase (Deno.env) -- nunca debe estar en el código de la app
// Flutter, porque le daría a cualquiera que decompile el APK control
// total de la cuenta de ImageKit.
//
// Deploy:
//   supabase functions deploy imagekit-auth
//   supabase secrets set IMAGEKIT_PRIVATE_KEY=tu_private_key_aqui
//
// La app llama a este endpoint ANTES de cada subida y usa la
// respuesta {token, expire, signature} como parte del multipart/
// form-data que manda directo a https://upload.imagekit.io.

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

async function hmacSha1Hex(key: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const firma = await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message));
  return Array.from(new Uint8Array(firma))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY");
    if (!privateKey) {
      throw new Error(
        "Falta el secret IMAGEKIT_PRIVATE_KEY -- corre: supabase secrets set IMAGEKIT_PRIVATE_KEY=...",
      );
    }

    // Token único por subida + 40 minutos de margen para que no
    // expire mientras el usuario tiene mala conexión.
    const token = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 2400;
    const signature = await hmacSha1Hex(privateKey, token + expire);

    return new Response(JSON.stringify({ token, expire, signature }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: `${e}` }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});