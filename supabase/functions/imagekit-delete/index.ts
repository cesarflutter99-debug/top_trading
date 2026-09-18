// imagekit-delete/index.ts
//
// Borrado de archivos en ImageKit. A diferencia de Supabase Storage
// (que borra por path), la API de ImageKit exige el fileId de cada
// archivo -- por eso esta función vive acá (requiere Private Key).
//
// Dos modos:
//   { "folder": "productos/uuid-de-la-tienda" }  -> lista y borra TODA
//      la carpeta (borrado en bloque, usado al eliminar tienda/negocio).
//   { "file": "/productos/uuid/1234.jpg" }       -> borra UN archivo
//      exacto por su ruta completa (usado al eliminar/editar un
//      producto o un anuncio, cuyas fotos comparten carpeta).
//
// Deploy:
//   supabase functions deploy imagekit-delete
// (usa el mismo secret IMAGEKIT_PRIVATE_KEY ya seteado para imagekit-auth)

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY") ?? "";

function authHeaders() {
  return { Authorization: "Basic " + btoa(`${privateKey}:`) };
}

// Codifica CADA segmento de la ruta (los "/" separadores quedan
// intactos) -- así funciona delete-by-path de ImageKit con nombres
// de archivo seguros.
function encodePath(path: string): string {
  return path
    .split("/")
    .map((s) => encodeURIComponent(s))
    .join("/");
}

async function borrarArchivoExacto(path: string): Promise<boolean> {
  const limpio = path.startsWith("/") ? path.slice(1) : path;
  const res = await fetch(
    `https://api.imagekit.io/v1/files/${encodePath(limpio)}`,
    { method: "DELETE", headers: authHeaders() },
  );
  return res.ok;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (!privateKey) {
      throw new Error("Falta el secret IMAGEKIT_PRIVATE_KEY");
    }

    const body = await req.json();

    // Modo 1: borrado por archivo exacto.
    if (typeof body.file === "string" && body.file.trim() !== "") {
      const ok = await borrarArchivoExacto(body.file.trim());
      return new Response(
        JSON.stringify({ borrado: ok, file: body.file.trim() }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Modo 2: borrado por carpeta (comportamiento anterior).
    const { folder } = body;
    if (!folder || typeof folder !== "string") {
      return new Response(
        JSON.stringify({
          error: "Falta 'folder' o 'file' en el body",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      );
    }

    // 1. Listar archivos de la carpeta (hasta 1000 -- de sobra para
    // una carpeta de tienda/producto/negocio individual).
    const listUrl =
      `https://api.imagekit.io/v1/files?path=${encodeURIComponent(folder)}&limit=1000`;
    const listRes = await fetch(listUrl, {
      headers: authHeaders(),
    });
    if (!listRes.ok) {
      const texto = await listRes.text();
      throw new Error(`Error listando archivos: ${listRes.status} ${texto}`);
    }
    const archivos = await listRes.json();

    // 2. Borrar cada uno por fileId. No abortamos si uno falla --
    // mismo criterio que storage_service.dart (mejor limpieza
    // parcial que bloquear el borrado de la tienda/producto).
    const resultados = [];
    for (const archivo of archivos) {
      try {
        const delRes = await fetch(
          `https://api.imagekit.io/v1/files/${archivo.fileId}`,
          { method: "DELETE", headers: authHeaders() },
        );
        resultados.push({ fileId: archivo.fileId, ok: delRes.ok });
      } catch (e) {
        resultados.push({ fileId: archivo.fileId, ok: false, error: `${e}` });
      }
    }

    return new Response(
      JSON.stringify({ borrados: resultados.length, resultados }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: `${e}` }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
