// BeeAware Brasil roadmap / Phase 8 (second-wave states) — GoSspAdapter
// (Goiás, SSP-GO Gerência do Observatório de Segurança Pública).
//
// GO was investigated as part of the state-expansion sweep and initially
// looked like a dead end, same category as BA/CE: dadosabertos.go.gov.br
// (a real CKAN instance) lists 0 datasets under "Segurança Pública", and
// the "digital platform for public consultation" a 2020-era news release
// describes (ssp.go.gov.br/estatisticas) no longer exists — that URL now
// 302s to the page below. What IS real: goias.gov.br/seguranca/
// estatisticas/ links one small PDF per year (2018-2025), each a single
// clean table — not the coarse annual-only shape every other PDF-only
// state in this codebase would suggest. Verified live 2026-08-30 by
// reading three of them (2018, 2024, 2025): one page, one table, 15
// crime "naturezas" x 12 months + a TOTAL column, and in all three years
// every row's 12 monthly values summed to exactly its own printed
// TOTAL — a free correctness check this adapter re-runs on every row,
// every fetch, not just at investigation time.
//
// Genuinely per-MONTH state totals, not the annual-only tier FBSP already
// covers for GO — a real step up in resolution for a state that otherwise
// had zero dedicated coverage. Still coarser than every point/municipality
// adapter here: no municipality/bairro breakdown exists in this source,
// so every row is geoPrecision 'STATE', same ceiling as FbspAnuarioAdapter
// and RENAEST's would-be output.
//
// PARSING: no PDF library — written by hand, same reasoning as
// xlsx_lite.ts's own header (a full library either didn't fit or didn't
// load here, so a minimal parser scoped to exactly what this source's
// files actually contain was written instead). Two real dead ends hit
// first, in order:
//   1. This session's own generic PDF-to-text tool silently GLUES the
//      last two columns of four short rows together (e.g. LATROCINIO's
//      real DEZ=2, TOTAL=19 came out as one token "219") — a naive
//      "extract text, split on whitespace" pass loses the column
//      boundary whenever a content stream leaves no space glyph between
//      two adjacent narrow numeric cells.
//   2. pdfjs-dist (position-aware, avoids the above entirely — every
//      number came back as its own separately-positioned text item,
//      confirmed against real files) parses correctly, but its bundle
//      failed at actual Supabase deploy time: `supabase functions
//      deploy` errored with "Module not found ... build/Release/
//      canvas.node?target=denonext" — a native Node canvas addon pulled
//      in as an optional rendering dependency, which esm.sh can't
//      resolve for Deno. This is exactly the class of risk flagged (but
//      not yet confirmed either way) when this adapter was first
//      written; it turned out real.
// What's used instead: PDF FlateDecode streams are plain zlib, decoded
// with the platform's own DecompressionStream("deflate") — same
// technique xlsx_lite.ts/rs_ssp.ts already use for ZIP's deflate-raw
// members, just the zlib-wrapped variant. Every decompressed content
// stream is scanned for `a b c d e f Tm` (sets the current absolute
// text position — confirmed by inspecting the real decompressed stream
// byte-for-byte: this source's export tool emits one `1 0 0 1 X Y Tm`
// immediately before every single cell's `Tj`/`TJ`, never relying on
// relative `Td` advances for grid layout) and `(...)  Tj` / `[...] TJ`
// (shows text at that position) — enough to reconstruct (string, x, y)
// triples equivalent to pdfjs's own getTextContent() output for this
// specific, simple, single-page report shape. Not a general PDF text
// extractor (no object/xref graph traversal, no font-metrics-based
// advance tracking for justified paragraphs) — scoped to exactly the
// Tm-per-cell grid layout this source's export tool produces, verified
// against all three years read (2018/2024/2025: 15/15 rows, 234/234
// text items, checksums all match).
//
// Row reconstruction from there is unchanged from the original plan:
// group text items by y (6pt tolerance covers the ~3pt label/number
// baseline offset seen in real files), sort each row left to right by
// x, and validate the 12 monthly values against the row's own printed
// TOTAL before trusting it.
//
// Every individual-year PDF is re-fetched on every run (not just the
// current year) — each is 20-40KB, negligible cost, and it means a
// correction to a past year on the SSP-GO site is picked up automatically
// rather than needing a one-off backfill migration like SINESP/SP-SSP
// needed. The one multi-year combined PDF (2019-2020-2021-2022-2023-
// e-2024) is deliberately excluded by the discovery regex below — same
// data, already covered year-by-year via the individual files, and its
// own internal layout (5 years in one table) hasn't been verified.
//
// Category/eventType mapping follows rj_isp.ts's COLUMN_MAP convention
// (map onto the existing taxonomy rather than inventing GO-specific
// types). FEMINICÍDIO and LATROCINIO and LESÃO SEGUIDA DE MORTE all fold
// into "homicide" — same choice rj_isp.ts and fbsp_anuario.ts already
// made for the same three labels (a violent death is a violent death);
// es_sesp.ts's choice to keep "femicide" distinct was for a source where
// that was the ONLY other value in the same column, a narrower case that
// doesn't apply here. "ROUBO EM RESIDÊNCIA" (violent/forced home robbery)
// keeps rj_isp.ts's "burglary" label; "FURTO EM RESIDÊNCIA" (non-violent
// home theft) is deliberately kept as generic "theft" instead, rather
// than also calling it "burglary" — collapsing both into the same
// eventType would erase the roubo/furto (violent/non-violent) distinction
// the source itself draws.
//
// Each row keeps its own sourceRecordId (state+year+month+original
// label) — same reasoning as fbsp_anuario.ts's header — so the four
// labels that all map to eventType "homicide" don't collide under
// runEventAdapter's dedupe-by-sourceRecordId step.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { EventCategory } from "../../taxonomy.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const STATS_PAGE_URL = "https://goias.gov.br/seguranca/estatisticas/";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// Matches "Estatisticas-de-2025.pdf" and "estatisticas_2024.pdf" (the two
// filename conventions actually used across 2018-2025) but NOT the
// combined "Estatisticas-de-2019-2020-2021-2022-2023-e-2024.pdf" — that
// one has no single 4-digit year immediately followed by ".pdf".
const YEAR_PDF_HREF = /href="([^"]*(?:Estatisticas-de-|estatisticas_)(\d{4})\.pdf)"/gi;

const MONTHS = ["JAN", "FEV", "MAR", "ABR", "MAI", "JUN", "JUL", "AGO", "SET", "OUT", "NOV", "DEZ"];

// natureza label (as printed, all-caps) -> [eventCategory, eventType].
// See the file header for the reasoning behind each choice.
const LABEL_MAP: Record<string, [EventCategory, string]> = {
  "HOMICÍDIO DOLOSO": ["VIOLENCE", "homicide"],
  "FEMINICÍDIO": ["VIOLENCE", "homicide"],
  "ESTUPRO": ["VIOLENCE", "sexual_violence"],
  "LATROCINIO": ["VIOLENCE", "homicide"],
  "LESAO SEGUIDA DE MORTE": ["VIOLENCE", "homicide"],
  "ROUBO A TRANSEUNTE": ["PROPERTY", "robbery"],
  "ROUBO DE VEÍCULOS": ["PROPERTY", "vehicle_robbery"],
  "ROUBO EM COMÉRCIO": ["PROPERTY", "robbery"],
  "ROUBO EM RESIDÊNCIA": ["PROPERTY", "burglary"],
  "ROUBO DE CARGA": ["PROPERTY", "cargo_robbery"],
  "ROUBO A INSTITUIÇÃO FINANCEIRA": ["PROPERTY", "robbery"],
  "FURTO DE VEÍCULOS": ["PROPERTY", "vehicle_theft"],
  "FURTO EM COMÉRCIO": ["PROPERTY", "theft"],
  "FURTO EM RESIDÊNCIA": ["PROPERTY", "theft"],
  "FURTO A TRANSEUNTE": ["PROPERTY", "theft"],
};

const HIGH_SEVERITY = new Set(["homicide", "sexual_violence"]);
const LOW_SEVERITY = new Set(["theft", "vehicle_theft"]);

function severityFor(eventType: string): string {
  if (HIGH_SEVERITY.has(eventType)) return "high";
  if (LOW_SEVERITY.has(eventType)) return "low";
  return "medium";
}

const COMBINING_DIACRITICS = new RegExp("[\\u0300-\\u036f]", "g");

function slug(s: string): string {
  return s
    .normalize("NFD")
    .replace(COMBINING_DIACRITICS, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

// Brazilian-formatted integer: "." is a thousands separator, never a
// decimal point in this table (every value here is a whole occurrence
// count).
function parseBrInt(s: string): number {
  return Number(s.replace(/\./g, ""));
}

interface DiscoveredPdf {
  year: number;
  url: string;
}

function discoverYearPdfs(html: string, baseUrl: string): DiscoveredPdf[] {
  const out: DiscoveredPdf[] = [];
  const seen = new Set<number>();
  for (const match of html.matchAll(YEAR_PDF_HREF)) {
    const year = Number(match[2]);
    if (seen.has(year)) continue; // page lists each year once anyway; defensive
    seen.add(year);
    const href = match[1];
    const url = href.startsWith("http") ? href : new URL(href, baseUrl).toString();
    out.push({ year, url });
  }
  return out;
}

// ===== Minimal PDF text-with-position extractor =====
// See file header for why this exists instead of a library. Scoped
// narrowly to what this source's own export tool produces: `stream`/
// `endstream` blocks that are plain zlib (FlateDecode), containing `Tm`-
// per-cell text positioning. Not a general PDF parser.

async function inflateZlib(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes]).stream().pipeThrough(new DecompressionStream("deflate"));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}

// PDF bytes decoded 1:1 via Latin-1 so every byte round-trips through a
// single JS char code — safe for locating the ASCII "stream"/"endstream"
// keywords and for re-encoding the exact original bytes for inflation
// (`Uint8Array.from(str, c => c.charCodeAt(0))`), same technique this
// project's other adapters use (e.g. rj_isp.ts's iso-8859-1 decode) when
// text needs byte-for-byte fidelity rather than a real character decode.
const STREAM_RE = /stream\r?\n([\s\S]*?)endstream/g;

async function extractContentStreams(pdfBytes: Uint8Array): Promise<string[]> {
  const latin1 = new TextDecoder("latin1").decode(pdfBytes);
  const streams: string[] = [];
  STREAM_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = STREAM_RE.exec(latin1))) {
    const rawBytes = Uint8Array.from(m[1], (c) => c.charCodeAt(0));
    try {
      const inflated = await inflateZlib(rawBytes);
      streams.push(new TextDecoder("latin1").decode(inflated));
    } catch {
      // Not a zlib stream (image/font binary data) — not page content, skip.
    }
  }
  return streams;
}

interface TextItem {
  str: string;
  x: number;
  y: number;
}

const PDF_STRING_RE = /\(((?:[^()\\]|\\.)*)\)/g;

function decodePdfString(s: string): string {
  return s.replace(/\\([nrtbf()\\]|[0-7]{1,3})/g, (_, esc) => {
    if (esc === "n") return "\n";
    if (esc === "r") return "\r";
    if (esc === "t") return "\t";
    if (esc === "b") return "\b";
    if (esc === "f") return "\f";
    if (esc === "(" || esc === ")" || esc === "\\") return esc;
    return String.fromCharCode(parseInt(esc, 8));
  });
}

// Matches either an absolute text-matrix set (`a b c d e f Tm` — e,f is
// the position; a,b,c,d are the scale/rotation this adapter doesn't
// need) or a text-show operator (`(str) Tj` / `[...] TJ`). Read as one
// ordered token stream so each show-text op picks up whatever position
// the most recent Tm established — exactly how the real content stream
// pairs them (confirmed byte-for-byte against a real file: one `Tm`
// immediately before every single cell's `Tj`/`TJ`).
const TOKEN_RE =
  /(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+Tm|\(((?:[^()\\]|\\.)*)\)\s*Tj|\[((?:[^\[\]]|\\.)*)\]\s*TJ/g;

function extractTextItems(contentStream: string): TextItem[] {
  const items: TextItem[] = [];
  let x = 0;
  let y = 0;
  TOKEN_RE.lastIndex = 0;
  let m: RegExpExecArray | null;
  while ((m = TOKEN_RE.exec(contentStream))) {
    if (m[5] !== undefined && m[6] !== undefined) {
      x = Number(m[5]);
      y = Number(m[6]);
    } else if (m[7] !== undefined) {
      const str = decodePdfString(m[7]).trim();
      if (str) items.push({ str, x, y });
    } else if (m[8] !== undefined) {
      // TJ array: alternating string literals and numeric kerning
      // adjustments — only the parenthesized parts are real text.
      let text = "";
      PDF_STRING_RE.lastIndex = 0;
      let sm: RegExpExecArray | null;
      while ((sm = PDF_STRING_RE.exec(m[8]))) text += decodePdfString(sm[1]);
      text = text.trim();
      if (text) items.push({ str: text, x, y });
    }
  }
  return items;
}

const NUMERIC_TOKEN = /^-?\d+([.,]\d+)*$/;
const ROW_Y_TOLERANCE = 6; // covers the ~3pt label/number baseline offset seen in real files

function groupIntoRows(items: TextItem[]): TextItem[][] {
  const rows: { y: number; items: TextItem[] }[] = [];
  for (const it of items) {
    let row = rows.find((r) => Math.abs(r.y - it.y) <= ROW_Y_TOLERANCE);
    if (!row) {
      row = { y: it.y, items: [] };
      rows.push(row);
    }
    row.items.push(it);
  }
  rows.sort((a, b) => b.y - a.y); // top of page first
  for (const row of rows) row.items.sort((a, b) => a.x - b.x); // left to right
  return rows.map((r) => r.items);
}

async function parsePdfIntoRows(bytes: Uint8Array): Promise<{ year: number; rows: Map<string, number[]> } | undefined> {
  const streams = await extractContentStreams(bytes);

  let items: TextItem[] = [];
  for (const stream of streams) {
    if (stream.includes("BT") && stream.includes("Tm")) {
      items = items.concat(extractTextItems(stream));
    }
  }
  if (items.length === 0) return undefined;

  const fullText = items.map((it) => it.str).join(" ");
  const anoMatch = fullText.match(/ANO\s*(\d{4})/i);
  if (!anoMatch) return undefined; // not a "DEMONSTRATIVO - ANO ####" table — skip

  const year = Number(anoMatch[1]);
  const rows = new Map<string, number[]>();

  for (const rowItems of groupIntoRows(items)) {
    const label = rowItems
      .filter((it) => !NUMERIC_TOKEN.test(it.str))
      .map((it) => it.str)
      .join(" ")
      .trim();
    if (!LABEL_MAP[label]) continue; // header row, footnotes, unrecognized label — skip

    const numberTokens = rowItems.filter((it) => NUMERIC_TOKEN.test(it.str)).map((it) => it.str);
    if (numberTokens.length !== 13) {
      console.warn(`GoSspAdapter: year ${year} row ${JSON.stringify(label)} has ${numberTokens.length} numeric tokens, expected 13 (12 months + total) — skipping`);
      continue;
    }

    const months = numberTokens.slice(0, 12).map(parseBrInt);
    const total = parseBrInt(numberTokens[12]);
    const sum = months.reduce((a, b) => a + b, 0);
    if (sum !== total) {
      console.warn(`GoSspAdapter: year ${year} row ${JSON.stringify(label)} monthly sum ${sum} != printed TOTAL ${total} — skipping (layout may have changed)`);
      continue;
    }

    rows.set(label, months);
  }

  return { year, rows };
}

export class GoSspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "GO",
      name: "SSP-GO - Estatísticas Criminais e de Produtividade (mensal)",
      organisation: "Secretaria de Estado da Segurança Pública de Goiás",
      sourceType: "official",
      sourceUrl: STATS_PAGE_URL,
      adapterName: "GoSspAdapter",
      adapterVersion: "0.2.0", // custom PDF parser, replacing the pdfjs-dist attempt that failed to deploy (canvas.node)
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const pageRes = await fetch(STATS_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!pageRes.ok) {
      throw new Error(`SSP-GO estatísticas page request failed: ${pageRes.status}`);
    }
    const html = await pageRes.text();
    const pdfs = discoverYearPdfs(html, STATS_PAGE_URL);
    if (pdfs.length === 0) {
      throw new Error("SSP-GO estatísticas page: no year PDF links found — page markup may have changed");
    }

    const records: RawSecurityRecord[] = [];
    for (const { year, url } of pdfs) {
      const fileRes = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
      if (!fileRes.ok) {
        console.warn(`GoSspAdapter: PDF for ${year} failed (${fileRes.status}) at ${url} — skipping that year`);
        continue;
      }
      records.push({
        sourceRecordId: `go-ssp-${year}`,
        payload: new Uint8Array(await fileRes.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      });
    }
    return records;
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const parsed = await parsePdfIntoRows(bytes);
    if (!parsed) return [];

    const events: SecurityEvent[] = [];
    const stateConfidence = defaultLocationConfidence("STATE");
    const { year, rows } = parsed;

    for (const [label, months] of rows) {
      const [eventCategory, eventType] = LABEL_MAP[label];
      const severity = severityFor(eventType);

      for (let m = 0; m < 12; m++) {
        const count = months[m];
        if (count <= 0) continue; // a real reported zero, but not an "event" worth a row

        events.push({
          countryCode: "BR",
          stateCode: "GO",
          sourceRecordId: `GO-${year}-${MONTHS[m]}-${slug(label)}`,
          sourceType: "official",
          eventCategory,
          eventType,
          originalCategory: label,
          occurredAt: `${year}-${String(m + 1).padStart(2, "0")}-01T00:00:00-03:00`,
          geoPrecision: "STATE",
          locationConfidence: stateConfidence,
          state: "Goiás",
          occurrenceCount: count,
          severity,
          confidenceScore: computeConfidenceScore({
            reliabilityGrade: "official_confirmed_record",
            locationConfidence: stateConfidence,
          }),
        });
      }
    }

    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(STATS_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on estatísticas page` };
      }
      const html = await res.text();
      const pdfs = discoverYearPdfs(html, STATS_PAGE_URL);
      if (pdfs.length === 0) {
        return { status: "RED", message: "No year PDF links found — page markup may have changed" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
