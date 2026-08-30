// BeeAware Brasil roadmap / Phase 8 (second-wave states) — MaSspAdapter
// (Maranhão, SSP-MA's Grande São Luís CVLI monthly matrix).
//
// Investigated before writing this: MA has NO usable statewide source.
// dados.ma.gov.br (the state's open-data portal, Drupal/CKAN-ish) carries
// zero public-security datasets — only finance/budget/HR topics
// (Despesas, Receitas, Orçamento, Patrimônio, Pessoal, Créditos e
// Financiamentos, Gestão Fiscal, Atividades Correicionais). SSP-MA's own
// site (ssp.ma.gov.br) has exactly one statistics page — confirmed via
// its own WP REST API (/wp-json/wp/v2/pages?search=estat) returning only
// "estatisticas" (an index with a single link) and
// "estatisticas-grande-sao-luis" (the real content). No PDF bulletins, no
// CSV/XLSX export, no per-region breakdown beyond that one page.
//
// So the real, verified scope here is narrower than every other state
// adapter so far: only Grande São Luís (São Luís, São José de Ribamar,
// Paço do Lumiar, Raposa — not the whole state) and only CVLI ("Crime
// Violento Letal Intencional") — Homicídio doloso, Feminicídio, Roubo
// seguido de morte (latrocínio), Lesão corporal seguida de morte. Same
// CVLI framing SSP-BA and SEDS-AL already use elsewhere in this codebase
// (see al_seds.ts), so every row here is already a fatality and severity
// is uniformly "high" — no severity-inference table needed.
//
// The page keeps a *rolling* ~12-month matrix (current year Jan..latest
// month, then the same trailing months of the prior year filled in blue)
// rather than a historical archive like GO's per-year PDFs — there is no
// deeper history to backfill from this source. Genuine upside: unlike
// every PDF/XLSX adapter in this directory, the data is a plain HTML
// <table> (WordPress/Elementor page), so no binary parsing is needed at
// all — and the header row spells out each column's exact "Mmm/YY" label,
// so month/year is read directly rather than inferred from page/PDF
// position.
//
// Also a real precision win over GO/RS/PA-style state-level adapters:
// each row is already scoped to one of 4 named municipalities, so
// geoPrecision is MUNICIPALITY (0.5 location_confidence), not STATE
// (0.3) — same tier AlAdapter gets from CIDADE DO FATO.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type { EventCategory } from "../../taxonomy.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const STATS_PAGE_URL = "https://www.ssp.ma.gov.br/estatisticas/estatisticas-grande-sao-luis/";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";
const IBGE_MUNICIPIOS_URL = "https://servicodados.ibge.gov.br/api/v1/localidades/estados/MA/municipios";

const MONTH_INDEX: Record<string, number> = {
  JAN: 1,
  FEV: 2,
  MAR: 3,
  ABR: 4,
  MAI: 5,
  JUN: 6,
  JUL: 7,
  AGO: 8,
  SET: 9,
  OUT: 10,
  NOV: 11,
  DEZ: 12,
};

// The 4 CVLI rows this page has ever published, normalized (accents
// stripped, uppercased) -> [category, eventType]. Exhaustive for this
// source — everything here is already a lethal intentional crime, same
// reasoning as AlAdapter's COMPLEMENTAR_MAP, mapped onto the same
// canonical eventType ("homicide") GoSspAdapter already uses for the
// equivalent Portuguese labels rather than inventing a "femicide" type
// outside taxonomy.ts's EVENT_TAXONOMY list.
const CATEGORY_MAP: Record<string, [EventCategory, string]> = {
  "HOMICIDIO DOLOSO": ["VIOLENCE", "homicide"],
  "FEMINICIDIO": ["VIOLENCE", "homicide"],
  "ROUBO SEGUIDO DE MORTE": ["VIOLENCE", "homicide"],
  "LESAO CORPORAL SEGUIDA DE MORTE": ["VIOLENCE", "homicide"],
};

function stripAccentsUpper(s: string): string {
  return s.normalize("NFD").replace(/[̀-ͯ]/g, "").toUpperCase().trim();
}

function decodeEntities(s: string): string {
  return s
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/g, "'")
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

// Tags are stripped to "" rather than " ": adjacent inline tags with no
// literal whitespace between them do occur in this source (e.g. one
// month header is split across two <strong> tags as "J" + "ul/26"), and
// they must rejoin into one token ("Jul/26"), not "J ul/26" — which
// silently broke the header's month/year regex and shifted every later
// column by one. There is no cell in this table where two genuinely
// separate tokens are tag-adjacent with no source whitespace, so this is
// safe for this parser.
function stripHtml(html: string): string {
  return decodeEntities(html.replace(/<[^>]*>/g, "")).replace(/\s+/g, " ").trim();
}

function extractCells(rowHtml: string): string[] {
  const cells: string[] = [];
  const re = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
  let m: RegExpExecArray | null;
  while ((m = re.exec(rowHtml))) {
    cells.push(stripHtml(m[1]));
  }
  return cells;
}

function parseBrInt(s: string): number {
  const n = Number(s.replace(/\./g, "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}

interface MaRow {
  city: string;
  month: number;
  year: number;
  eventCategory: EventCategory;
  eventType: string;
  originalLabel: string;
  count: number;
}

// Finds the one "GRANDE SÃO LUÍS" <table> on the page (the smaller
// "QUADRO COMPARATIVO" tables above it don't contain that heading) and
// walks its rows: the first cell of the header row also happens to name
// the first municipality (São Luís); later plain-label rows with blank
// data cells rename the "current" municipality for the rows under them;
// the trailing "CVLI – TOTAL" row is a derived aggregate, not a real
// per-city count, so parsing stops there.
function parseMaTable(html: string): MaRow[] {
  const tables = html.match(/<table[^>]*>[\s\S]*?<\/table>/gi) ?? [];
  const table = tables.find((t) => t.includes("GRANDE SÃO LUÍS"));
  if (!table) return [];

  const rows = table.match(/<tr[^>]*>[\s\S]*?<\/tr>/gi) ?? [];
  const rowCells = rows.map(extractCells);

  const headerRowIndex = rowCells.findIndex((cells) => cells.length > 2);
  if (headerRowIndex === -1) return [];

  const headerCells = rowCells[headerRowIndex];
  const monthColumns: { month: number; year: number }[] = [];
  for (let i = 1; i < headerCells.length; i++) {
    const m = headerCells[i].match(/^([A-ZÇ]{3})\/(\d{2})$/i);
    if (!m) continue;
    const month = MONTH_INDEX[m[1].toUpperCase()];
    if (!month) continue;
    monthColumns.push({ month, year: 2000 + Number(m[2]) });
  }
  if (monthColumns.length === 0) return [];

  const out: MaRow[] = [];
  let currentCity = headerCells[0];

  for (let r = headerRowIndex + 1; r < rowCells.length; r++) {
    const cells = rowCells[r];
    if (cells.length < 2) continue;

    const label = cells[0];
    const dataCells = cells.slice(1, 1 + monthColumns.length);
    const hasData = dataCells.some((c) => c.length > 0);

    if (stripAccentsUpper(label).includes("TOTAL")) break;

    const mapped = CATEGORY_MAP[stripAccentsUpper(label)];
    if (mapped) {
      const [eventCategory, eventType] = mapped;
      dataCells.forEach((cellText, i) => {
        const count = parseBrInt(cellText);
        if (count <= 0) return;
        out.push({
          city: currentCity,
          ...monthColumns[i],
          eventCategory,
          eventType,
          originalLabel: label,
          count,
        });
      });
      continue;
    }

    if (!hasData && label.length > 0) {
      currentCity = label;
    }
  }

  return out;
}

let municipioNameCache: Map<string, string> | undefined;

async function municipioNameMap(): Promise<Map<string, string>> {
  if (municipioNameCache) return municipioNameCache;

  const res = await fetch(IBGE_MUNICIPIOS_URL);
  if (!res.ok) {
    throw new Error(`IBGE MA municipios request failed: ${res.status}`);
  }
  const municipios = (await res.json()) as { id: number; nome: string }[];
  municipioNameCache = new Map(municipios.map((m) => [stripAccentsUpper(m.nome), String(m.id)]));
  return municipioNameCache;
}

function slug(s: string): string {
  return stripAccentsUpper(s).toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
}

export class MaSspAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "BR",
      stateCode: "MA",
      name: "SSP-MA - Grande São Luís CVLI",
      organisation: "Secretaria de Estado de Segurança Pública do Maranhão",
      sourceType: "official",
      sourceUrl: STATS_PAGE_URL,
      adapterName: "MaSspAdapter",
      adapterVersion: "0.1.0",
      // The page itself says "acumulado até a data de ontem" (updated
      // daily), but a small CVLI count changes slowly enough that
      // weekly matches PA-SEGUP/RS-SSP's own weekly cadence for
      // similarly rolling-window sources.
      refreshFrequency: "weekly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(STATS_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) {
      throw new Error(`SSP-MA statistics page request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "ma-ssp-grande-sao-luis",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const html = record.payload as string;
    const rows = parseMaTable(html);
    if (rows.length === 0) return [];

    const nameMap = await municipioNameMap();
    const locationConfidence = defaultLocationConfidence("MUNICIPALITY");
    const confidenceScore = computeConfidenceScore({
      reliabilityGrade: "official_confirmed_record",
      locationConfidence,
    });

    return rows.map((row) => {
      const mm = String(row.month).padStart(2, "0");
      return {
        countryCode: "BR",
        stateCode: "MA",
        cityIbgeCode: nameMap.get(stripAccentsUpper(row.city)),
        // slug(row.originalLabel), not eventType: all 4 CVLI categories
        // map onto the same canonical "homicide" eventType, which would
        // otherwise collide two genuinely different rows (e.g.
        // Feminicídio and Homicídio doloso, same city/month) onto one
        // sourceRecordId and drop one of them at the orchestrator's
        // dedupe-by-sourceRecordId step.
        sourceRecordId: `MA-${slug(row.city)}-${row.year}-${mm}-${slug(row.originalLabel)}`,
        sourceType: "official",
        eventCategory: row.eventCategory,
        eventType: row.eventType,
        originalCategory: row.originalLabel,
        occurredAt: `${row.year}-${mm}-01T00:00:00-03:00`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence,
        city: row.city,
        state: "Maranhão",
        occurrenceCount: row.count,
        severity: "high",
        confidenceScore,
      };
    });
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(STATS_PAGE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `Statistics page returned ${res.status}` };
      }
      const html = await res.text();
      const rows = parseMaTable(html);
      if (rows.length === 0) {
        return { status: "RED", message: "No CVLI rows parsed from Grande São Luís table" };
      }
      return { status: "GREEN" };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
