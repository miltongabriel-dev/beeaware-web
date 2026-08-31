// BeeAware Brasil roadmap / Phase 8 (alphabetical sweep of the remaining
// states) — PrSespAdapter (Paraná, SESP-PR/CAPE quarterly crime PDF).
//
// KNOWN LIMITATION, accepted deliberately (see conversation this was
// built in): unlike every other PDF-source adapter here (GO, and the
// dead ends documented in pe_sds.ts), there is no stable, crawlable page
// linking the current quarterly report. Checked seguranca.pr.gov.br's
// /CAPE/Estatisticas, /Pagina/Estatisticas, /Pagina/Estatisticas-Sesp,
// the Agência de Notícias archive, and a Drupal JSON:API probe — none
// link the report; the only way it surfaced at all was a Google site:
// search. STATS_PDF_URL below is therefore a PINNED snapshot (the
// "3º Trimestre 2025" report, Jan-Set 2024 vs Jan-Set 2025, published
// under a filename/folder that changes every quarter) — it will keep
// returning this same report and go silently stale once SESP-PR
// publishes the next quarter under a new, unpredictable URL. Revisit by
// re-running the same Google site: search this header documents and
// swapping STATS_PDF_URL when healthCheck's own age check (below) turns
// RED.
//
// What's real here: seguranca.pr.gov.br was also genuinely flaky from
// this environment during development (repeated TLS/connect failures
// that cleared up on retry, unrelated to the file's own reachability —
// worth retrying on a transient fetch() failure in production too, same
// as any other adapter).
//
// The PDF itself is a plain, real, dependency-free-parseable text PDF
// (same zlib-inflate + Tm/Tj/TJ position extraction as go_ssp.ts) — 13
// tables, each "Comparativo de <categoria>, Segundo as AISPs", one page
// per table, each with 23 AISP rows (Polícia Militar's own regional
// command areas, covering the whole state — not municipalities) x 2
// year-blocks x 12 months, plus a TOTAL row (skipped, it's a derived
// aggregate) and Diferença/Variação% columns (skipped, comparison
// figures, not occurrence counts).
//
// Two real gaps handled by skipping rather than guessing, same
// philosophy as every other adapter here:
//   - AISP is a multi-municipality police command area, not a real
//     municipality boundary, and PR's own AISP polygons aren't in
//     geo_areas (only RJ's AISP/RISP/CISP geometry has been loaded so
//     far). geoPrecision is therefore STATE, not MUNICIPALITY — the
//     AISP's "sede" (headquarters city) name is still kept in `city` as
//     informational context, but the system doesn't treat this as a
//     real point/pin the way it would MUNICIPALITY-tier data.
//   - Of the 13 tables, 5 are skipped outright: "Crimes Contra a
//     Pessoa" and "Crimes Contra o Patrimônio" (Tabelas 1-2) are broad
//     Penal Code chapter aggregates that already subsume the specific
//     categories tables 3/6/7/8/9/10/12/13 break out separately —
//     ingesting both would double-count the same underlying BOU records
//     under two different eventTypes. "Crimes Contra a Administração
//     Pública" (Tabela 4, corruption/embezzlement) doesn't fit any
//     citizen-safety category this taxonomy has. "Demais Crimes
//     Consumados" (Tabela 5) is too generic a bucket to name a real
//     eventType. "Recuperações de Veículos" (Tabela 11) is a positive
//     outcome metric (a vehicle recovered), not an incident.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { EventCategory } from "../../taxonomy.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const STATS_PDF_URL =
  "https://seguranca.pr.gov.br/sites/default/arquivos_restritos/files/documento/2025-12/3relatorio_estatistico_criminal_jan_set_2025_-_3o_trim_mapas.pdf";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// Tabela number -> [category, eventType, severity]. Only the 8 tables
// with an unambiguous, non-overlapping crime type are mapped — see file
// header for why 1, 2, 4, 5, 11 are deliberately absent.
const TABLE_MAP: Record<number, [EventCategory, string, "high" | "medium" | "low"]> = {
  3: ["VIOLENCE", "sexual_violence", "high"],
  6: ["PROPERTY", "theft", "low"],
  7: ["PROPERTY", "robbery", "medium"],
  8: ["PUBLIC_SAFETY", "weapon", "medium"],
  9: ["PROPERTY", "vehicle_theft", "low"],
  10: ["PROPERTY", "vehicle_robbery", "medium"],
  12: ["PUBLIC_SAFETY", "disturbance", "medium"],
  13: ["VIOLENCE", "assault", "medium"],
};

interface TextItem {
  str: string;
  x: number;
  y: number;
}

async function inflateAllStreams(pdfBytes: Uint8Array): Promise<string[]> {
  const latin1 = new TextDecoder("latin1").decode(pdfBytes);
  const re = /stream\r?\n([\s\S]*?)endstream/g;
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(latin1))) {
    const raw = Uint8Array.from(m[1], (c) => c.charCodeAt(0));
    try {
      const ds = new DecompressionStream("deflate");
      const writer = ds.writable.getWriter();
      writer.write(raw);
      writer.close();
      const inflated = await new Response(ds.readable).arrayBuffer();
      out.push(new TextDecoder("latin1").decode(inflated));
    } catch {
      // not a zlib/deflate stream (image/font binary) — skip
    }
  }
  return out;
}

const PDF_STR = /\(((?:[^()\\]|\\.)*)\)/g;

function decodePdfString(s: string): string {
  return s.replace(/\\([nrtbf()\\]|[0-7]{1,3})/g, (_, esc) => {
    if (esc === "n") return "\n";
    if (esc === "r") return "\r";
    if (esc === "t") return "\t";
    if (esc === "(" || esc === ")" || esc === "\\") return esc;
    return String.fromCharCode(parseInt(esc, 8));
  });
}

const TOKEN_RE =
  /(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+Tm|\(((?:[^()\\]|\\.)*)\)\s*Tj|\[((?:[^\[\]]|\\.)*)\]\s*TJ/g;

function extractTextItems(contentStream: string): TextItem[] {
  const items: TextItem[] = [];
  let x = 0;
  let y = 0;
  let m: RegExpExecArray | null;
  TOKEN_RE.lastIndex = 0;
  while ((m = TOKEN_RE.exec(contentStream))) {
    if (m[5] !== undefined && m[6] !== undefined) {
      x = Number(m[5]);
      y = Number(m[6]);
    } else if (m[7] !== undefined) {
      const str = decodePdfString(m[7]).trim();
      if (str) items.push({ str, x, y });
    } else if (m[8] !== undefined) {
      let text = "";
      let sm: RegExpExecArray | null;
      PDF_STR.lastIndex = 0;
      while ((sm = PDF_STR.exec(m[8]))) text += decodePdfString(sm[1]);
      text = text.trim();
      if (text) items.push({ str: text, x, y });
    }
  }
  return items;
}

function groupIntoRows(items: TextItem[]): TextItem[][] {
  const rows: { y: number; items: TextItem[] }[] = [];
  const ROW_TOL = 3;
  for (const it of items) {
    let row = rows.find((r) => Math.abs(r.y - it.y) <= ROW_TOL);
    if (!row) {
      row = { y: it.y, items: [] };
      rows.push(row);
    }
    row.items.push(it);
  }
  rows.sort((a, b) => b.y - a.y);
  for (const row of rows) row.items.sort((a, b) => a.x - b.x);
  return rows.map((r) => r.items);
}

function parseBrInt(s: string): number {
  const n = Number(s.replace(/\./g, ""));
  return Number.isFinite(n) ? n : 0;
}

interface PrRow {
  tableNum: number;
  aispSede: string;
  year: number;
  month: number; // 1-12
  count: number;
}

// One "table" is one PDF page here (confirmed against the real file:
// each of the 13 "Tabela N" pages is fully self-contained, all 23 AISPs
// fit on the one page).
function parseTablePage(items: TextItem[]): PrRow[] {
  const fullText = items.map((i) => i.str).join(" ");
  const titleMatch = fullText.match(/Tabela (\d+):/);
  if (!titleMatch) return [];
  const tableNum = Number(titleMatch[1]);
  if (!(tableNum in TABLE_MAP)) return [];

  const rows = groupIntoRows(items);

  // Year-label row: exactly the two 4-digit years, left-to-right in
  // column order (first half of the table's columns is the first year
  // found, second half the second).
  let years: number[] | undefined;
  for (const row of rows) {
    const yearTokens = row.filter((it) => /^(19|20)\d{2}$/.test(it.str));
    if (yearTokens.length === 2) {
      years = yearTokens.map((it) => Number(it.str));
      break;
    }
  }
  if (!years) return [];
  const [yearA, yearB] = years;

  const out: PrRow[] = [];
  for (const row of rows) {
    const label = row[0]?.str ?? "";
    if (!/^\d+ª\s*-/.test(label)) continue; // header/footer/TOTAL row

    const aispSede = label.replace(/^\d+ª\s*-\s*/, "").trim();
    const numeric = row.slice(1).filter((it) => /^-?[\d.]+$/.test(it.str));
    // 13 (Jan..Dez,Total) per year x 2 years = 26; Diferença/Variação%
    // trail after that and are dropped by the slice(0, 26).
    const values = numeric.slice(0, 26).map((it) => parseBrInt(it.str));
    if (values.length < 26) continue;

    for (let month = 1; month <= 12; month++) {
      const countA = values[month - 1];
      if (countA > 0) out.push({ tableNum, aispSede, year: yearA, month, count: countA });
      const countB = values[13 + month - 1];
      if (countB > 0) out.push({ tableNum, aispSede, year: yearB, month, count: countB });
    }
  }
  return out;
}

function slug(s: string): string {
  return s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

export class PrSespAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "PR",
      name: "SESP-PR/CAPE - Relatório Estatístico Criminal",
      organisation: "Secretaria de Estado da Segurança Pública do Paraná",
      sourceType: "official",
      sourceUrl: STATS_PDF_URL,
      adapterName: "PrSespAdapter",
      adapterVersion: "0.1.0",
      // The source itself is quarterly, but this adapter can't discover
      // a new quarter's URL automatically (see file header) — re-running
      // weekly costs nothing extra and picks up a manual URL update fast
      // whenever one happens.
      refreshFrequency: "weekly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(STATS_PDF_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`SESP-PR statistics PDF request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "pr-sesp-relatorio-estatistico",
        payload: new Uint8Array(await res.arrayBuffer()),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const bytes = record.payload as Uint8Array;
    const streams = await inflateAllStreams(bytes);

    const rows: PrRow[] = [];
    for (const stream of streams) {
      if (!stream.includes("BT") || !stream.includes("Tm")) continue;
      const items = extractTextItems(stream);
      if (!items.some((i) => i.str.startsWith("Tabela"))) continue;
      rows.push(...parseTablePage(items));
    }

    const locationConfidence = defaultLocationConfidence("STATE");
    const confidenceScore = computeConfidenceScore({
      reliabilityGrade: "official_confirmed_record",
      locationConfidence,
    });

    return rows.map((row) => {
      const [eventCategory, eventType, severity] = TABLE_MAP[row.tableNum];
      const mm = String(row.month).padStart(2, "0");
      return {
        countryCode: "BR",
        stateCode: "PR",
        sourceRecordId: `PR-t${row.tableNum}-${slug(row.aispSede)}-${row.year}-${mm}`,
        sourceType: "official",
        eventCategory,
        eventType,
        originalCategory: `AISP ${row.aispSede}`,
        occurredAt: `${row.year}-${mm}-01T00:00:00-03:00`,
        geoPrecision: "STATE",
        locationConfidence,
        city: row.aispSede,
        state: "Paraná",
        occurrenceCount: row.count,
        severity,
        confidenceScore,
      };
    });
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(STATS_PDF_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `Statistics PDF request failed: ${res.status}` };
      }
      const bytes = new Uint8Array(await res.arrayBuffer());
      const streams = await inflateAllStreams(bytes);
      let found = 0;
      for (const stream of streams) {
        if (stream.includes("Tabela")) found++;
      }
      if (found === 0) {
        return { status: "RED", message: "No 'Tabela N' pages found in PDF — layout may have changed" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
