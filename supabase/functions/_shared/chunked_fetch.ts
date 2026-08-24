// BeeAware Brasil roadmap — chunked HTTP Range fetch.
//
// Built after diagnosing SinespAdapter/SpVehicleAdapter's real production
// failures (see each adapter's own header): a single fetch() for a
// ~20-30MB government file consistently hit WORKER_RESOURCE_LIMIT, even
// after pinning execution to the sa-east-1 (São Paulo) region cut total
// time roughly 3x. The gap between a small file (fine) and a ~20MB file
// from the same origin/region (not fine) pointed at a per-request time
// constraint, not pure network-distance latency — so the fix is smaller
// requests, not a closer region alone.
//
// Confirmed live that both real sources this was built for genuinely
// support HTTP Range (both return 206 Partial Content with a real
// Content-Range header): dados.ssp.sp.gov.br (SpVehicleAdapter) and
// www.gov.br's SINESP download path (SinespAdapter). Not every server
// does — callers should confirm Range support on any new source before
// relying on this rather than assuming it.
//
// Honest result: this did NOT fix either adapter it was built for (see
// each adapter's own header for its specific null result), and neither
// is using it — both still do a single fetch(). SinespAdapter's fetch()
// stayed in the same ~12-16s failure band regardless of chunk count or
// concurrency, meaning that source's floor is very likely the origin
// server's own fixed per-connection overhead, not request size —
// chunking doesn't help a problem it isn't the cause of. SpVehicleAdapter
// failed just as fast (~3-4s) chunked as unchunked, consistent with a
// connection-level rejection (e.g. IP-based blocking) rather than a
// transfer-duration problem either. Kept as real, tested, reusable
// infrastructure (it correctly performs partial-content downloads) for
// a future source whose problem actually is bandwidth/duration-bound —
// don't reach for it by default without evidence the target source's
// failure has that shape.
//
// Every chunk is fetched sequentially, including the first (used to
// learn the real total size from Content-Range — Content-Length alone
// on an unranged HEAD isn't reliable here, e.g. SP's WAF 403s HEAD
// entirely, see sp_vehicle.ts). A parallel version (fire every remaining
// chunk via Promise.all once the total size was known) was tried first
// and measurably made things worse against SinespAdapter's real
// source — several large-buffer responses in flight simultaneously is a
// plausible resource-ceiling contributor on its own, on top of whatever
// concurrency limits a Varnish-fronted government site applies per
// client. Sequential is slower wall-clock but keeps peak memory to one
// chunk at a time and never opens more than one connection to the
// origin at once.

export interface ChunkedFetchOptions {
  chunkSize?: number;
  headers?: HeadersInit;
}

const DEFAULT_CHUNK_SIZE = 4 * 1024 * 1024; // 4MB

export async function fetchInChunks(url: string, options: ChunkedFetchOptions = {}): Promise<Uint8Array> {
  const chunkSize = options.chunkSize ?? DEFAULT_CHUNK_SIZE;
  const headers = options.headers ?? {};

  const firstEnd = chunkSize - 1;
  const firstRes = await fetch(url, { headers: { ...headers, Range: `bytes=0-${firstEnd}` } });
  if (firstRes.status !== 206 && firstRes.status !== 200) {
    throw new Error(`chunked fetch: first request failed: HTTP ${firstRes.status}`);
  }
  const firstChunk = new Uint8Array(await firstRes.arrayBuffer());

  if (firstRes.status === 200) {
    // Server ignored the Range header and sent the whole file — that's
    // the complete response already, nothing more to fetch.
    return firstChunk;
  }

  const contentRange = firstRes.headers.get("content-range"); // "bytes 0-4194303/30076962"
  const totalSize = contentRange ? Number(/\/(\d+)$/.exec(contentRange)?.[1]) : undefined;
  if (!totalSize || !Number.isFinite(totalSize)) {
    throw new Error(`chunked fetch: no usable Content-Range on 206 response (${contentRange})`);
  }

  if (firstChunk.length >= totalSize) return firstChunk;

  // Sequential, not parallel — an earlier parallel version (fire every
  // remaining chunk request at once via Promise.all) still hit
  // WORKER_RESOURCE_LIMIT inconsistently against SinespAdapter's real
  // source, while a run that happened to fail differently (a clean JS
  // exception) suggested the requests themselves were racing something.
  // Several concurrent large-buffer responses in flight simultaneously
  // is itself a plausible contributor to a resource ceiling, on top of
  // whatever server-side concurrency limits a Varnish-fronted government
  // site might apply — sequential is slower but keeps peak memory to one
  // chunk at a time and avoids opening several simultaneous connections
  // to the same origin.
  const result = new Uint8Array(totalSize);
  result.set(firstChunk, 0);
  let pos = firstChunk.length;
  const log: string[] = [`first: len=${firstChunk.length} totalSize=${totalSize}`];

  for (let offset = firstChunk.length; offset < totalSize; offset += chunkSize) {
    const end = Math.min(offset + chunkSize - 1, totalSize - 1);
    const t0 = performance.now();
    const res = await fetch(url, { headers: { ...headers, Range: `bytes=${offset}-${end}` } });
    const t1 = performance.now();
    if (res.status !== 206 && res.status !== 200) {
      throw new Error(`chunked fetch: chunk at offset ${offset} failed: HTTP ${res.status} (log: ${log.join(" | ")})`);
    }
    const chunk = new Uint8Array(await res.arrayBuffer());
    const t2 = performance.now();
    log.push(`offset=${offset} end=${end} status=${res.status} len=${chunk.length} pos=${pos} headMs=${(t1 - t0).toFixed(0)} bodyMs=${(t2 - t1).toFixed(0)}`);
    if (pos + chunk.length > totalSize) {
      throw new Error(`chunked fetch: overflow at offset ${offset} — pos=${pos} chunk.length=${chunk.length} totalSize=${totalSize} (log: ${log.join(" | ")})`);
    }
    result.set(chunk, pos);
    pos += chunk.length;
  }

  return result;
}
