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
//
// Reverse mode: `lat`/`lon` with no `q` returns { label, state } — a
// short "Bairro, Cidade" for the Início location card (e.g. "Bela Vista,
// São Paulo") plus the state on its own, which the app uses to place news
// (the label used to be "City, State" and the state was read off its
// end). Both are null when Photon has nothing there. Replaces the app
// calling Nominatim directly, which rate-limits (429) shared IPs and
// left the card on "Localização indisponível" with a perfectly good fix.

const PHOTON_URL = "https://photon.komoot.io/api/";
const PHOTON_REVERSE_URL = "https://photon.komoot.io/reverse";
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

// Neighbourhood first (Photon's `district` is the bairro in Brazil and
// e.g. Covent Garden in London), then the city; state only when there's
// no neighbourhood to pair the city with.
function shortLabel(p: PhotonProps): string | null {
  const area = p.district ?? p.locality;
  const city = p.city ?? p.county;
  const parts = area ? [area, city] : [city, p.state];
  const clean = parts.filter((s): s is string => !!s && s.trim().length > 0);
  const unique = clean.filter((s, i) => clean.indexOf(s) === i);
  return unique.length ? unique.join(", ") : null;
}

async function reverse(lat: number, lon: number): Promise<Response> {
  const photon = new URL(PHOTON_REVERSE_URL);
  photon.searchParams.set("lat", String(lat));
  photon.searchParams.set("lon", String(lon));
  photon.searchParams.set("limit", "1");

  try {
    const res = await fetch(photon, {
      headers: { "User-Agent": "io.beeaware.app (BeeAware geocode function)" },
      signal: AbortSignal.timeout(6000),
    });

    if (!res.ok) {
      console.error(`photon reverse ${res.status}: ${(await res.text()).slice(0, 200)}`);
      return json({ label: null, state: null }, 502);
    }

    const data = await res.json();
    const props: PhotonProps | undefined = data?.features?.[0]?.properties;
    return json(
      { label: props ? shortLabel(props) : null, state: props?.state ?? null },
      200,
      { "Cache-Control": "public, max-age=86400" },
    );
  } catch (e) {
    console.error("reverse geocode error:", e);
    return json({ label: null, state: null }, 502);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const url = new URL(req.url);
  const query = url.searchParams.get("q")?.trim();
  if (!query) {
    const lat = parseFloat(url.searchParams.get("lat") ?? "");
    const lon = parseFloat(url.searchParams.get("lon") ?? "");
    if (Number.isFinite(lat) && Number.isFinite(lon)) return reverse(lat, lon);
    return json({ error: "Missing query" }, 400);
  }

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
