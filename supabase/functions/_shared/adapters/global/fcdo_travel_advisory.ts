// BeeAware Global blueprint (Phase 1 part 2) — FcdoAdapter.
//
// UK FCDO travel advisories, via GOV.UK's public Content API — no auth, no
// scraping. Verified live on 2026-08-23:
//   GET https://www.gov.uk/api/content/foreign-travel-advice
// returns an index of every country (226 entries) under links.children,
// each with a `details.country.slug`; each country's own record is at
//   GET https://www.gov.uk/api/content/foreign-travel-advice/{slug}
// with the live risk signal in details.alert_status (an array — a country
// can carry more than one status at once, e.g. Ukraine currently has both
// avoid_all_travel_to_parts and avoid_all_but_essential_travel_to_parts for
// different regions; empty array means no active advisory).
//
// alert_status's value space isn't documented in GOV.UK's own JSON schema
// (it's typed as a bare string array there) — confirmed instead against the
// publishing app's own source, alphagov/travel-advice-publisher's
// app/models/travel_advice_edition.rb:
//   ALERT_STATUSES = %w[
//     avoid_all_but_essential_travel_to_parts
//     avoid_all_but_essential_travel_to_whole_country
//     avoid_all_travel_to_parts
//     avoid_all_travel_to_whole_country
//   ]
// LEVEL_PRIORITY below is exactly that closed set (plus the synthetic
// "no_advisory" for an empty array).
//
// details.change_description is a genuinely per-country, per-update
// summary (verified live: Ukraine -> "Updated information about the
// Russian invasion of Ukraine...", France -> "Updated information on
// European Entry-Exit System (EES)...") — unlike the top-level
// `description` field, which is identical boilerplate for every country
// ("FCDO travel advice for X. Includes safety and security, insurance,
// entry requirements and legal differences."). Used as `summary` here for
// that reason.
//
// FCDO keys everything by an editorial slug/name, not ISO codes.
// SLUG_TO_ISO2 was generated against the real 226-entry index using the
// same `i18n-iso-countries` package UnodcAdapter's ISO3 table used, then
// verified by hand for every miss: 205 auto-resolved by name, 19 more
// resolved via a corrected canonical name (e.g. "Laos" ->
// "Lao People's Democratic Republic", "St Maarten" ->
// "Sint Maarten (Dutch part)"), and exactly 2 left unmapped and skipped in
// normalize() rather than guessed — both are genuine multi-territory pages
// with no single honest ISO2: "Cook Islands, Tokelau and Niue" (three real
// codes: CK/TK/NU) and "St Martin and St Barthélemy" (two: MF/BL). Same
// "skip rather than guess" discipline as UnodcAdapter's CHA/XKX.

import type {
  RawSecurityRecord,
  SecuritySource,
  SourceHealth,
  TravelAdvisory,
  TravelAdvisoryAdapter,
} from "../types.ts";

const INDEX_URL = "https://www.gov.uk/api/content/foreign-travel-advice";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";
const FETCH_CONCURRENCY = 15;

const SLUG_TO_ISO2: Record<string, string> = {
  "afghanistan": "AF", "albania": "AL", "algeria": "DZ", "andorra": "AD", "angola": "AO",
  "anguilla": "AI", "antarctica-british-antarctic-territory": "AQ",
  "antigua-and-barbuda": "AG", "argentina": "AR", "armenia": "AM", "aruba": "AW",
  "australia": "AU", "austria": "AT", "azerbaijan": "AZ", "bahamas": "BS", "bahrain": "BH",
  "bangladesh": "BD", "barbados": "BB", "belarus": "BY", "belgium": "BE", "belize": "BZ",
  "benin": "BJ", "bermuda": "BM", "bhutan": "BT", "bolivia": "BO",
  "bonaire-st-eustatius-saba": "BQ", "bosnia-and-herzegovina": "BA", "botswana": "BW",
  "brazil": "BR", "british-indian-ocean-territory": "IO", "british-virgin-islands": "VG",
  "brunei": "BN", "bulgaria": "BG", "burkina-faso": "BF", "burundi": "BI", "cambodia": "KH",
  "cameroon": "CM", "canada": "CA", "cape-verde": "CV", "cayman-islands": "KY",
  "central-african-republic": "CF", "chad": "TD", "chile": "CL", "china": "CN",
  "colombia": "CO", "comoros": "KM", "congo": "CG", "costa-rica": "CR", "cote-d-ivoire": "CI",
  "croatia": "HR", "cuba": "CU", "curacao": "CW", "cyprus": "CY", "czechia": "CZ",
  "democratic-republic-of-the-congo": "CD", "denmark": "DK", "djibouti": "DJ",
  "dominica": "DM", "dominican-republic": "DO", "ecuador": "EC", "egypt": "EG",
  "el-salvador": "SV", "equatorial-guinea": "GQ", "eritrea": "ER", "estonia": "EE",
  "eswatini": "SZ", "ethiopia": "ET", "falkland-islands": "FK",
  "federated-states-of-micronesia": "FM", "fiji": "FJ", "finland": "FI", "france": "FR",
  "french-guiana": "GF", "french-polynesia": "PF", "gabon": "GA", "georgia": "GE",
  "germany": "DE", "ghana": "GH", "gibraltar": "GI", "greece": "GR", "grenada": "GD",
  "guadeloupe": "GP", "guatemala": "GT", "guinea": "GN", "guinea-bissau": "GW", "guyana": "GY",
  "haiti": "HT", "honduras": "HN", "hong-kong": "HK", "hungary": "HU", "iceland": "IS",
  "india": "IN", "indonesia": "ID", "iran": "IR", "iraq": "IQ", "ireland": "IE",
  "israel": "IL", "italy": "IT", "jamaica": "JM", "japan": "JP", "jordan": "JO",
  "kazakhstan": "KZ", "kenya": "KE", "kiribati": "KI", "kosovo": "XK", "kuwait": "KW",
  "kyrgyzstan": "KG", "laos": "LA", "latvia": "LV", "lebanon": "LB", "lesotho": "LS",
  "liberia": "LR", "libya": "LY", "liechtenstein": "LI", "lithuania": "LT", "luxembourg": "LU",
  "macao": "MO", "madagascar": "MG", "malawi": "MW", "malaysia": "MY", "maldives": "MV",
  "mali": "ML", "malta": "MT", "marshall-islands": "MH", "martinique": "MQ",
  "mauritania": "MR", "mauritius": "MU", "mayotte": "YT", "mexico": "MX", "moldova": "MD",
  "monaco": "MC", "mongolia": "MN", "montenegro": "ME", "montserrat": "MS", "morocco": "MA",
  "mozambique": "MZ", "myanmar": "MM", "namibia": "NA", "nauru": "NR", "nepal": "NP",
  "netherlands": "NL", "new-caledonia": "NC", "new-zealand": "NZ", "nicaragua": "NI",
  "niger": "NE", "nigeria": "NG", "north-korea": "KP", "north-macedonia": "MK", "norway": "NO",
  "oman": "OM", "pakistan": "PK", "palau": "PW", "palestine": "PS", "panama": "PA",
  "papua-new-guinea": "PG", "paraguay": "PY", "peru": "PE", "philippines": "PH",
  "pitcairn-island": "PN", "poland": "PL", "portugal": "PT", "qatar": "QA", "reunion": "RE",
  "romania": "RO", "russia": "RU", "rwanda": "RW", "samoa": "WS", "san-marino": "SM",
  "sao-tome-and-principe": "ST", "saudi-arabia": "SA", "senegal": "SN", "serbia": "RS",
  "seychelles": "SC", "sierra-leone": "SL", "singapore": "SG", "slovakia": "SK",
  "slovenia": "SI", "solomon-islands": "SB", "somalia": "SO", "south-africa": "ZA",
  "south-georgia-and-south-sandwich-islands": "GS", "south-korea": "KR", "south-sudan": "SS",
  "spain": "ES", "sri-lanka": "LK", "st-helena-ascension-and-tristan-da-cunha": "SH",
  "st-kitts-and-nevis": "KN", "st-lucia": "LC", "st-maarten": "SX",
  "st-pierre-and-miquelon": "PM", "st-vincent-and-the-grenadines": "VC", "sudan": "SD",
  "suriname": "SR", "sweden": "SE", "switzerland": "CH", "syria": "SY", "taiwan": "TW",
  "tajikistan": "TJ", "tanzania": "TZ", "thailand": "TH", "the-gambia": "GM",
  "timor-leste": "TL", "togo": "TG", "tonga": "TO", "trinidad-and-tobago": "TT",
  "tunisia": "TN", "turkey": "TR", "turkmenistan": "TM", "turks-and-caicos-islands": "TC",
  "tuvalu": "TV", "uganda": "UG", "ukraine": "UA", "united-arab-emirates": "AE",
  "uruguay": "UY", "usa": "US", "uzbekistan": "UZ", "vanuatu": "VU", "venezuela": "VE",
  "vietnam": "VN", "wallis-and-futuna": "WF", "western-sahara": "EH", "yemen": "YE",
  "zambia": "ZM", "zimbabwe": "ZW",
};

// Worst status wins for a single-row-per-country snapshot. Full-stop
// "avoid all travel" advisories rank above "essential only" regardless of
// geographic extent (whole-country vs parts) — an adjustable heuristic
// (same framing as UnodcAdapter's rate-to-severity thresholds), not a
// cited standard.
const LEVEL_PRIORITY = [
  "avoid_all_travel_to_whole_country",
  "avoid_all_travel_to_parts",
  "avoid_all_but_essential_travel_to_whole_country",
  "avoid_all_but_essential_travel_to_parts",
] as const;

function deriveLevel(alertStatus: string[]): string {
  for (const level of LEVEL_PRIORITY) {
    if (alertStatus.includes(level)) return level;
  }
  return "no_advisory";
}

interface IndexEntry {
  slug: string;
  apiUrl: string;
}

function parseIndex(body: unknown): IndexEntry[] {
  const children = (body as { links?: { children?: unknown[] } })?.links?.children ?? [];
  const entries: IndexEntry[] = [];
  for (const child of children) {
    const c = child as { api_url?: string; details?: { country?: { slug?: string } } };
    const slug = c.details?.country?.slug;
    if (slug && c.api_url) entries.push({ slug, apiUrl: c.api_url });
  }
  return entries;
}

async function fetchJson(url: string): Promise<unknown> {
  const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) return null;
  return await res.json();
}

// 226 small JSON documents (a few KB each) — no memory-limit risk like the
// CSV/XLSX adapters, but 226 sequential round trips would be needlessly
// slow. Bounded concurrency is both faster and more polite to GOV.UK than
// either extreme.
async function fetchAllCountries(entries: IndexEntry[]): Promise<RawSecurityRecord[]> {
  const records: RawSecurityRecord[] = [];
  const fetchedAt = new Date().toISOString();
  for (let i = 0; i < entries.length; i += FETCH_CONCURRENCY) {
    const batch = entries.slice(i, i + FETCH_CONCURRENCY);
    const payloads = await Promise.all(batch.map((entry) => fetchJson(entry.apiUrl)));
    batch.forEach((entry, idx) => {
      if (payloads[idx] != null) {
        records.push({ sourceRecordId: entry.slug, payload: payloads[idx], fetchedAt });
      }
    });
  }
  return records;
}

export class FcdoAdapter implements TravelAdvisoryAdapter {
  source(): SecuritySource {
    return {
      countryCode: "XX", // global source, not scoped to one country
      name: "UK FCDO Foreign Travel Advice",
      organisation: "Foreign, Commonwealth & Development Office (UK)",
      sourceType: "official",
      sourceUrl: "https://www.gov.uk/foreign-travel-advice",
      adapterName: "FcdoAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "daily", // advisories change far more often than crime baselines
    };
  }

  async fetch(): Promise<RawSecurityRecord[]> {
    const index = await fetchJson(INDEX_URL);
    if (!index) throw new Error("FCDO travel advice index request failed");
    const entries = parseIndex(index);
    if (entries.length === 0) return [];
    return await fetchAllCountries(entries);
  }

  async normalize(record: RawSecurityRecord): Promise<TravelAdvisory[]> {
    const countryCode = SLUG_TO_ISO2[record.sourceRecordId];
    if (!countryCode) return []; // combined multi-territory page — skip rather than guess

    const body = record.payload as {
      public_updated_at?: string;
      base_path?: string;
      details?: { alert_status?: string[]; change_description?: string };
    };

    const alertStatus = body.details?.alert_status ?? [];

    return [
      {
        countryCode,
        countrySlug: record.sourceRecordId,
        issuer: "UK FCDO",
        level: deriveLevel(alertStatus),
        rawAlertStatus: alertStatus,
        summary: body.details?.change_description?.trim() || undefined,
        sourceUrl: body.base_path ? `https://www.gov.uk${body.base_path}` : undefined,
        effectiveAt: body.public_updated_at,
      },
    ];
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const index = await fetchJson(INDEX_URL);
      const entries = parseIndex(index);
      if (entries.length === 0) {
        return { status: "RED", message: "No countries found in FCDO travel advice index" };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
