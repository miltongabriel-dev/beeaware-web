// Live address suggestions for every search box in the app (Mapa search,
// Route Awareness origin/destination, Início location picker) — all of
// them call this function and expect a Nominatim-shaped array back:
// [{ display_name, lat, lon }, ...].
//
// Backed by Photon (photon.komoot.io), not Nominatim. Found 2026-09-29:
// the previous version proxied Nominatim and returned 500 on every call,
// because Nominatim answers "Access denied" (plain text) to Supabase's
// egress IPs and the function then crashed on res.json(). Nominatim's
// usage policy also explicitly forbids search-as-you-type, and it only
// matches whole words ("Avenida Paulis" finds nothing). Photon is built
// for autocomplete over the same OSM data and matches partial words.
//
// The response keeps Nominatim's shape on purpose, so the fix reaches the
// already-shipped iOS/Android builds without a new app release.
//
// Optional `lat`/`lon` query params bias results toward the user.

const PHOTON_URL = "https://photon.komoot.io/api/";
const MAX_LIMIT = 10;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200, extra: HeadersInit = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      ...extra,
    },
  });
}

type PhotonProps = {
  name?: string;
  housenumber?: string;
  street?: string;
  district?: string;
  locality?: string;
  city?: string;
  county?: string;
  state?: string;
  postcode?: string;
  country?: string;
};

type PhotonFeature = {
  geometry?: { coordinates?: [number, number] };
  properties?: PhotonProps;
};

// Builds "Primary, rest, of, address" — the app splits on the first comma
// into title/subtitle, so the most specific part must come first.
function displayName(p: PhotonProps): string {
  const streetLine = p.street
    ? (p.housenumber ? `${p.street}, ${p.housenumber}` : p.street)
    : undefined;

  const parts = [
    p.name,
    streetLine,
    p.district ?? p.locality,
    p.city ?? p.county,
    p.state,
    p.postcode,
    p.country,
  ].filter((s): s is string => !!s && s.trim().length > 0);

  // Drop repeats (e.g. a city whose name equals its state or district).
  return parts.filter((s, i) => parts.indexOf(s) === i).join(", ");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const query = url.searchParams.get("q")?.trim();
  if (!query) return json({ error: "Missing query" }, 400);

  const limit = Math.min(
    Math.max(parseInt(url.searchParams.get("limit") ?? "5", 10) || 5, 1),
    MAX_LIMIT,
  );

  const photon = new URL(PHOTON_URL);
  photon.searchParams.set("q", query);
  photon.searchParams.set("limit", String(limit));
  const lat = parseFloat(url.searchParams.get("lat") ?? "");
  const lon = parseFloat(url.searchParams.get("lon") ?? "");
  if (Number.isFinite(lat) && Number.isFinite(lon)) {
    photon.searchParams.set("lat", String(lat));
    photon.searchParams.set("lon", String(lon));
  }

  try {
    const res = await fetch(photon, {
      headers: { "User-Agent": "io.beeaware.app (BeeAware geocode function)" },
      signal: AbortSignal.timeout(6000),
    });

    if (!res.ok) {
      console.error(`photon ${res.status}: ${(await res.text()).slice(0, 200)}`);
      return json([], 502);
    }

    const data = await res.json();
    const features: PhotonFeature[] = Array.isArray(data?.features) ? data.features : [];

    const seen = new Set<string>();
    const results = [];
    for (const f of features) {
      const coords = f.geometry?.coordinates;
      if (!coords || !f.properties) continue;
      const display_name = displayName(f.properties);
      if (!display_name || seen.has(display_name)) continue;
      seen.add(display_name);
      results.push({
        display_name,
        lat: String(coords[1]),
        lon: String(coords[0]),
      });
    }

    return json(results, 200, { "Cache-Control": "public, max-age=3600" });
  } catch (e) {
    console.error("geocode error:", e);
    return json([], 502);
  }
});
