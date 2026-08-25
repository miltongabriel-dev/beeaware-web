// BeeAware Brasil roadmap / Phase 11 — Route Awareness (roadmap 9.5,
// 11.12): "route geometry -> 250-500m buffer -> recent events +
// historical activity + road hazards -> explainable route context."
//
// This function is the routing half only — it returns route geometry,
// not safety signals (that's route_safety_signals, a Postgres RPC, so
// the buffer/ST_DWithin work stays server-side in PostGIS rather than
// being reimplemented here). Proxies OpenRouteService's Directions API
// so the API key never reaches the client (same reason
// ingest-security-sources' adapters run server-side, not in Flutter).
//
// Verified live 2026-08-25 against real Rio coordinates: ORS's
// alternative_routes parameter only returns more than one route for the
// driving-car profile — foot-walking and cycling-regular both silently
// return a single route no matter what target_count is requested. Since
// BeeAware's core use case is a pedestrian checking a walking route
// (not a driver), accepting "only one route, no comparison" wasn't
// acceptable — instead this requests a second route via an explicit
// waypoint offset perpendicular to the direct path's midpoint, which
// forces ORS to compute a genuinely different walking path through that
// point. Confirmed live: for a 939m direct route, a 200m-scale
// perpendicular waypoint produced a real 1177m alternative (25% longer,
// a different real street path) rather than ORS silently collapsing
// back to the same route.
//
// Naming rule (roadmap 13.3): never label either route "safest" — that's
// enforced client-side (RouteAwarenessScreen), not here; this function
// only returns geometry/distance/duration, no safety framing at all.

const ORS_BASE = "https://api.openrouteservice.org/v2/directions";
const DEFAULT_PROFILE = "foot-walking";

// Perpendicular waypoint offset, scaled to the route's own straight-line
// distance so a short route gets a small nudge and a long one gets a
// real detour — clamped so neither a trivial 50m walk nor a multi-km
// trek produces a nonsensical waypoint (e.g. one that lands in the
// ocean for a coastal route).
const OFFSET_FRACTION = 0.15;
const OFFSET_MIN_METERS = 80;
const OFFSET_MAX_METERS = 400;

interface LatLng {
  lat: number;
  lng: number;
}

interface RouteRequest {
  origin: LatLng;
  destination: LatLng;
  profile?: string;
}

function haversineMeters(a: LatLng, b: LatLng): number {
  const R = 6371000;
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const sinDLat = Math.sin(dLat / 2);
  const sinDLng = Math.sin(dLng / 2);
  const h =
    sinDLat * sinDLat +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * sinDLng * sinDLng;
  return 2 * R * Math.asin(Math.sqrt(h));
}

// Midpoint + perpendicular offset, in the same flat-approximation style
// already used elsewhere in this codebase for small distances (e.g.
// pa_segup.ts's municipality matching) — accurate enough over a few
// kilometres, which is the realistic range for a walking route.
function perpendicularWaypoint(a: LatLng, b: LatLng): LatLng {
  const distance = haversineMeters(a, b);
  const offsetMeters = Math.min(
    OFFSET_MAX_METERS,
    Math.max(OFFSET_MIN_METERS, distance * OFFSET_FRACTION),
  );

  const midLat = (a.lat + b.lat) / 2;
  const midLng = (a.lng + b.lng) / 2;

  const dx = b.lng - a.lng;
  const dy = b.lat - a.lat;
  const len = Math.hypot(dx, dy) || 1;
  const perpX = -dy / len;
  const perpY = dx / len;

  const latRad = (midLat * Math.PI) / 180;
  const degPerMeterLat = 1 / 111320;
  const degPerMeterLng = 1 / (111320 * Math.cos(latRad));

  return {
    lat: midLat + perpY * offsetMeters * degPerMeterLat,
    lng: midLng + perpX * offsetMeters * degPerMeterLng,
  };
}

interface OrsRoute {
  geometry: { type: string; coordinates: [number, number][] };
  distanceMeters: number;
  durationSeconds: number;
}

// ORS's free tier rate-limits per-minute, not just per-day — confirmed
// live 2026-08-25: a request that succeeded moments earlier came back
// 502 shortly after (this function's own fetch to ORS almost certainly
// hit a 429, not a real routing failure — treating any ORS failure as
// "no route exists" was misleading the client into showing "couldn't
// find a route" for what was actually a rate limit). One retry after a
// short delay is cheap insurance against exactly that class of blip;
// genuine no-route responses (ORS 2010/2099-style routing errors) still
// fall through to null on the second attempt.
async function fetchOrsRouteOnce(
  apiKey: string,
  profile: string,
  coordinates: [number, number][],
): Promise<{ route: OrsRoute | null; status?: number; retryable: boolean }> {
  const res = await fetch(`${ORS_BASE}/${profile}/geojson`, {
    method: "POST",
    headers: {
      "Authorization": apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ coordinates }),
  });

  if (!res.ok) {
    const bodyText = await res.text();
    console.error(`ORS request failed: ${res.status} ${bodyText}`);
    return {
      route: null,
      status: res.status,
      retryable: res.status === 429 || res.status >= 500,
    };
  }

  const data = await res.json();
  const feature = data?.features?.[0];
  if (!feature) return { route: null, retryable: false };

  const segments = feature.properties?.segments ?? [];
  const distanceMeters = segments.reduce(
    (sum: number, s: { distance: number }) => sum + (s.distance ?? 0),
    0,
  );
  const durationSeconds = segments.reduce(
    (sum: number, s: { duration: number }) => sum + (s.duration ?? 0),
    0,
  );

  return {
    route: { geometry: feature.geometry, distanceMeters, durationSeconds },
    retryable: false,
  };
}

async function fetchOrsRoute(
  apiKey: string,
  profile: string,
  coordinates: [number, number][],
): Promise<OrsRoute | null> {
  const first = await fetchOrsRouteOnce(apiKey, profile, coordinates);
  if (first.route || !first.retryable) return first.route;

  await new Promise((resolve) => setTimeout(resolve, 800));
  const second = await fetchOrsRouteOnce(apiKey, profile, coordinates);
  return second.route;
}

// Supabase's Edge Runtime does NOT add CORS headers on its own — this
// was the actual bug behind "route not found" errors that only ever
// showed up in a real browser, never via curl: a browser sends a CORS
// preflight OPTIONS request before the real POST for any cross-origin
// JSON body request, and this function was rejecting that preflight
// with a bare 405 and no Access-Control-* headers at all, so the
// browser blocked the real POST from ever being sent — confirmed live
// 2026-08-25 with a direct OPTIONS request showing exactly that (405,
// no CORS headers), while the identical POST worked perfectly via curl
// every single time (curl has no concept of CORS, so it never surfaced
// this). Every response below — success, error, and the OPTIONS
// preflight itself — needs these headers, not just the preflight,
// since a browser checks Access-Control-Allow-Origin on the actual
// response too.
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response("Method not allowed", {
      status: 405,
      headers: CORS_HEADERS,
    });
  }

  const apiKey = Deno.env.get("OPENROUTESERVICE_API_KEY");
  if (!apiKey) {
    return jsonResponse({ error: "Route Awareness is not configured" }, 500);
  }

  let body: RouteRequest;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid request body" }, 400);
  }

  const { origin, destination } = body;
  const profile = body.profile ?? DEFAULT_PROFILE;

  if (
    typeof origin?.lat !== "number" || typeof origin?.lng !== "number" ||
    typeof destination?.lat !== "number" || typeof destination?.lng !== "number"
  ) {
    return jsonResponse(
      { error: "origin/destination lat,lng are required" },
      400,
    );
  }

  const originCoord: [number, number] = [origin.lng, origin.lat];
  const destCoord: [number, number] = [destination.lng, destination.lat];
  const waypoint = perpendicularWaypoint(origin, destination);
  const waypointCoord: [number, number] = [waypoint.lng, waypoint.lat];

  const [routeA, routeB] = await Promise.all([
    fetchOrsRoute(apiKey, profile, [originCoord, destCoord]),
    fetchOrsRoute(apiKey, profile, [originCoord, waypointCoord, destCoord]),
  ]);

  if (!routeA) {
    return jsonResponse({ error: "No route found between these points" }, 404);
  }

  // routeB can legitimately fail (e.g. the waypoint lands somewhere
  // unreachable) or come back identical to routeA if ORS couldn't find
  // a real detour — either way, returning just routeA is honest; a
  // fabricated "second route" that's really the same path would defeat
  // the whole point of a route comparison.
  const routes = [{ id: "A", ...routeA }];
  if (
    routeB &&
    (Math.abs(routeB.distanceMeters - routeA.distanceMeters) > 5 ||
      JSON.stringify(routeB.geometry) !== JSON.stringify(routeA.geometry))
  ) {
    routes.push({ id: "B", ...routeB });
  }

  return jsonResponse({ routes });
});
