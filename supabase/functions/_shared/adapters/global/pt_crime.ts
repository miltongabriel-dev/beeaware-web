// BeeAware Global blueprint — PtCrimeAdapter (Portugal concelho-level
// crime summary for the choropleth already used in Brazil and the UK).
//
// Investigated live (2026-09-01), not assumed:
// - `criminalidade.pt` is a third-party static site (not the government
//   portal itself) that republishes official DGPJ (Direção-Geral da
//   Política de Justiça)/INE/PORDATA crime statistics as public JSON, no
//   key needed, CORS wide open (`Access-Control-Allow-Origin: *`):
//     - https://criminalidade.pt/data/meta.json — `years` (1993-2025,
//       annual only) and the 19 `categories` DGPJ tracks.
//     - https://criminalidade.pt/data/series.json — keyed by `dico`
//       (Portugal's official district+concelho code, e.g. "1106" =
//       Lisboa), each holding `s`: one array per category id, aligned to
//       `meta.json`'s `years` array. Confirmed live: 308 concelhos, 19
//       category arrays each.
//     - https://criminalidade.pt/data/boundaries.json — real concelho
//       geometry, same `dico` key (used by the separate geometry
//       migration, not read here).
//   CONCELHO_NAME below maps each `dico` to the exact concelho name used
//   as `geo_areas.name` (20260902100000_pt_concelho_geometry.sql) — built
//   by cross-referencing criminalidade.pt's own `/municipios/` index page
//   (slug -> display name) against each `/municipio/<slug>/` page's own
//   `dico="XXXX"` attribute (confirmed on Lisboa: dico="1106"). All 308
//   matched with zero orphans either direction.
//
// - Only 8 of the 19 categories are safe to sum without double-counting
//   (see CATEGORY_MAP below for the full reasoning): id 0 "Total" is the
//   official grand total (would double the count if summed alongside
//   anything else); ids 1-9 are DGPJ's "crimes específicos" (concrete,
//   non-overlapping offence types) except id 7, which is the same vehicle
//   theft as id 2 but from INE's methodology instead of DGPJ's — excluded
//   to avoid counting the same theft twice; ids 10-17 are Penal Code
//   chapters that are NOT mutually exclusive (e.g. id 11 "Contra a
//   integridade física" is a subset of id 10 "Contra as pessoas") — not
//   used at all, to avoid an unverified double-count; id 18 is a rate
//   (per 1,000 residents), not a count. What's left — ids 1,2,3,4,5,6,8,9
//   — is a curated highlight list, not exhaustive crime coverage (no
//   homicide, sexual offences or drug trafficking in it): the choropleth
//   reflects these known indicators, not total registered crime, the same
//   kind of documented partial-coverage caveat already on UkPoliceAdapter.
//
// - No `poly`-style query-size ceiling to work around here (unlike
//   UkPoliceAdapter): the whole country's series and geometry are each a
//   single static JSON fetch, not 308 separate area queries. fetch() does
//   exactly two HTTP requests total, not 308.
//
// - DGPJ publishes annually, with a real lag — 2025 was already the
//   newest complete year in `years` as of September 2026. Only the single
//   latest available year is ever ingested (never a historical backfill
//   of 1993-2025): this repo's `security_events` retention cron
//   (20260901120000_security_events_retention_cron.sql) deletes anything
//   with `occurred_at` older than 12 months every month, so a full
//   historical backfill would just get erased the following month by a
//   policy this same session put in place. concelho_crime_summary
//   (20260902120000) defaults to a 24-month window specifically so the
//   single ingested year survives the gap between DGPJ's publish lag and
//   this cron's own cutoff.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const META_URL = "https://criminalidade.pt/data/meta.json";
const SERIES_URL = "https://criminalidade.pt/data/series.json";
// Not confirmed load-bearing (criminalidade.pt never showed any sign of
// blocking a plain fetch), kept for the same reason as uk_police.ts's own
// USER_AGENT: no reason to look unlike a normal client.
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// dico (district+concelho code) -> the exact geo_areas.name value the
// geometry migration used — see file header for how this was built.
// Exported for pt_news.ts, which matches article text against these same
// 308 names (via geo_text_match_generic.ts) rather than keeping a second
// copy of the list.
export const CONCELHO_NAME: Record<string, string> = {
  "0101": "Águeda",
  "0102": "Albergaria-a-Velha",
  "0103": "Anadia",
  "0104": "Arouca",
  "0105": "Aveiro",
  "0106": "Castelo de Paiva",
  "0107": "Espinho",
  "0108": "Estarreja",
  "0109": "Santa Maria da Feira",
  "0110": "Ílhavo",
  "0111": "Mealhada",
  "0112": "Murtosa",
  "0113": "Oliveira de Azeméis",
  "0114": "Oliveira do Bairro",
  "0115": "Ovar",
  "0116": "São João da Madeira",
  "0117": "Sever do Vouga",
  "0118": "Vagos",
  "0119": "Vale de Cambra",
  "0201": "Aljustrel",
  "0202": "Almodôvar",
  "0203": "Alvito",
  "0204": "Barrancos",
  "0205": "Beja",
  "0206": "Castro Verde",
  "0207": "Cuba",
  "0208": "Ferreira do Alentejo",
  "0209": "Mértola",
  "0210": "Moura",
  "0211": "Odemira",
  "0212": "Ourique",
  "0213": "Serpa",
  "0214": "Vidigueira",
  "0301": "Amares",
  "0302": "Barcelos",
  "0303": "Braga",
  "0304": "Cabeceiras de Basto",
  "0305": "Celorico de Basto",
  "0306": "Esposende",
  "0307": "Fafe",
  "0308": "Guimarães",
  "0309": "Póvoa de Lanhoso",
  "0310": "Terras de Bouro",
  "0311": "Vieira do Minho",
  "0312": "Vila Nova de Famalicão",
  "0313": "Vila Verde",
  "0314": "Vizela",
  "0401": "Alfândega da Fé",
  "0402": "Bragança",
  "0403": "Carrazeda de Ansiães",
  "0404": "Freixo de Espada à Cinta",
  "0405": "Macedo de Cavaleiros",
  "0406": "Miranda do Douro",
  "0407": "Mirandela",
  "0408": "Mogadouro",
  "0409": "Torre de Moncorvo",
  "0410": "Vila Flor",
  "0411": "Vimioso",
  "0412": "Vinhais",
  "0501": "Belmonte",
  "0502": "Castelo Branco",
  "0503": "Covilhã",
  "0504": "Fundão",
  "0505": "Idanha-a-Nova",
  "0506": "Oleiros",
  "0507": "Penamacor",
  "0508": "Proença-a-Nova",
  "0509": "Sertã",
  "0510": "Vila de Rei",
  "0511": "Vila Velha de Ródão",
  "0601": "Arganil",
  "0602": "Cantanhede",
  "0603": "Coimbra",
  "0604": "Condeixa-a-Nova",
  "0605": "Figueira da Foz",
  "0606": "Góis",
  "0607": "Lousã",
  "0608": "Mira",
  "0609": "Miranda do Corvo",
  "0610": "Montemor-o-Velho",
  "0611": "Oliveira do Hospital",
  "0612": "Pampilhosa da Serra",
  "0613": "Penacova",
  "0614": "Penela",
  "0615": "Soure",
  "0616": "Tábua",
  "0617": "Vila Nova de Poiares",
  "0701": "Alandroal",
  "0702": "Arraiolos",
  "0703": "Borba",
  "0704": "Estremoz",
  "0705": "Évora",
  "0706": "Montemor-o-Novo",
  "0707": "Mora",
  "0708": "Mourão",
  "0709": "Portel",
  "0710": "Redondo",
  "0711": "Reguengos de Monsaraz",
  "0712": "Vendas Novas",
  "0713": "Viana do Alentejo",
  "0714": "Vila Viçosa",
  "0801": "Albufeira",
  "0802": "Alcoutim",
  "0803": "Aljezur",
  "0804": "Castro Marim",
  "0805": "Faro",
  "0806": "Lagoa",
  "0807": "Lagos",
  "0808": "Loulé",
  "0809": "Monchique",
  "0810": "Olhão",
  "0811": "Portimão",
  "0812": "São Brás de Alportel",
  "0813": "Silves",
  "0814": "Tavira",
  "0815": "Vila do Bispo",
  "0816": "Vila Real de Santo António",
  "0901": "Aguiar da Beira",
  "0902": "Almeida",
  "0903": "Celorico da Beira",
  "0904": "Figueira de Castelo Rodrigo",
  "0905": "Fornos de Algodres",
  "0906": "Gouveia",
  "0907": "Guarda",
  "0908": "Manteigas",
  "0909": "Mêda",
  "0910": "Pinhel",
  "0911": "Sabugal",
  "0912": "Seia",
  "0913": "Trancoso",
  "0914": "Vila Nova de Foz Côa",
  "1001": "Alcobaça",
  "1002": "Alvaiázere",
  "1003": "Ansião",
  "1004": "Batalha",
  "1005": "Bombarral",
  "1006": "Caldas da Rainha",
  "1007": "Castanheira de Pêra",
  "1008": "Figueiró dos Vinhos",
  "1009": "Leiria",
  "1010": "Marinha Grande",
  "1011": "Nazaré",
  "1012": "Óbidos",
  "1013": "Pedrógão Grande",
  "1014": "Peniche",
  "1015": "Pombal",
  "1016": "Porto de Mós",
  "1101": "Alenquer",
  "1102": "Arruda dos Vinhos",
  "1103": "Azambuja",
  "1104": "Cadaval",
  "1105": "Cascais",
  "1106": "Lisboa",
  "1107": "Loures",
  "1108": "Lourinhã",
  "1109": "Mafra",
  "1110": "Oeiras",
  "1111": "Sintra",
  "1112": "Sobral de Monte Agraço",
  "1113": "Torres Vedras",
  "1114": "Vila Franca de Xira",
  "1115": "Amadora",
  "1116": "Odivelas",
  "1201": "Alter do Chão",
  "1202": "Arronches",
  "1203": "Avis",
  "1204": "Campo Maior",
  "1205": "Castelo de Vide",
  "1206": "Crato",
  "1207": "Elvas",
  "1208": "Fronteira",
  "1209": "Gavião",
  "1210": "Marvão",
  "1211": "Monforte",
  "1212": "Nisa",
  "1213": "Ponte de Sor",
  "1214": "Portalegre",
  "1215": "Sousel",
  "1301": "Amarante",
  "1302": "Baião",
  "1303": "Felgueiras",
  "1304": "Gondomar",
  "1305": "Lousada",
  "1306": "Maia",
  "1307": "Marco de Canaveses",
  "1308": "Matosinhos",
  "1309": "Paços de Ferreira",
  "1310": "Paredes",
  "1311": "Penafiel",
  "1312": "Porto",
  "1313": "Póvoa de Varzim",
  "1314": "Santo Tirso",
  "1315": "Valongo",
  "1316": "Vila do Conde",
  "1317": "Vila Nova de Gaia",
  "1318": "Trofa",
  "1401": "Abrantes",
  "1402": "Alcanena",
  "1403": "Almeirim",
  "1404": "Alpiarça",
  "1405": "Benavente",
  "1406": "Cartaxo",
  "1407": "Chamusca",
  "1408": "Constância",
  "1409": "Coruche",
  "1410": "Entroncamento",
  "1411": "Ferreira do Zêzere",
  "1412": "Golegã",
  "1413": "Mação",
  "1414": "Rio Maior",
  "1415": "Salvaterra de Magos",
  "1416": "Santarém",
  "1417": "Sardoal",
  "1418": "Tomar",
  "1419": "Torres Novas",
  "1420": "Vila Nova da Barquinha",
  "1421": "Ourém",
  "1501": "Alcácer do Sal",
  "1502": "Alcochete",
  "1503": "Almada",
  "1504": "Barreiro",
  "1505": "Grândola",
  "1506": "Moita",
  "1507": "Montijo",
  "1508": "Palmela",
  "1509": "Santiago do Cacém",
  "1510": "Seixal",
  "1511": "Sesimbra",
  "1512": "Setúbal",
  "1513": "Sines",
  "1601": "Arcos de Valdevez",
  "1602": "Caminha",
  "1603": "Melgaço",
  "1604": "Monção",
  "1605": "Paredes de Coura",
  "1606": "Ponte da Barca",
  "1607": "Ponte de Lima",
  "1608": "Valença",
  "1609": "Viana do Castelo",
  "1610": "Vila Nova de Cerveira",
  "1701": "Alijó",
  "1702": "Boticas",
  "1703": "Chaves",
  "1704": "Mesão Frio",
  "1705": "Mondim de Basto",
  "1706": "Montalegre",
  "1707": "Murça",
  "1708": "Peso da Régua",
  "1709": "Ribeira de Pena",
  "1710": "Sabrosa",
  "1711": "Santa Marta de Penaguião",
  "1712": "Valpaços",
  "1713": "Vila Pouca de Aguiar",
  "1714": "Vila Real",
  "1801": "Armamar",
  "1802": "Carregal do Sal",
  "1803": "Castro Daire",
  "1804": "Cinfães",
  "1805": "Lamego",
  "1806": "Mangualde",
  "1807": "Moimenta da Beira",
  "1808": "Mortágua",
  "1809": "Nelas",
  "1810": "Oliveira de Frades",
  "1811": "Penalva do Castelo",
  "1812": "Penedono",
  "1813": "Resende",
  "1814": "Santa Comba Dão",
  "1815": "São João da Pesqueira",
  "1816": "São Pedro do Sul",
  "1817": "Sátão",
  "1818": "Sernancelhe",
  "1819": "Tabuaço",
  "1820": "Tarouca",
  "1821": "Tondela",
  "1822": "Vila Nova de Paiva",
  "1823": "Viseu",
  "1824": "Vouzela",
  "3101": "Calheta (Madeira)",
  "3102": "Câmara de Lobos",
  "3103": "Funchal",
  "3104": "Machico",
  "3105": "Ponta do Sol",
  "3106": "Porto Moniz",
  "3107": "Ribeira Brava",
  "3108": "Santa Cruz",
  "3109": "Santana",
  "3110": "São Vicente",
  "3201": "Porto Santo",
  "4101": "Vila do Porto",
  "4201": "Lagoa (Açores)",
  "4202": "Nordeste",
  "4203": "Ponta Delgada",
  "4204": "Povoação",
  "4205": "Ribeira Grande",
  "4206": "Vila Franca do Campo",
  "4301": "Angra do Heroísmo",
  "4302": "Vila da Praia da Vitória",
  "4401": "Santa Cruz da Graciosa",
  "4501": "Calheta (Açores)",
  "4502": "Velas",
  "4601": "Lajes do Pico",
  "4602": "Madalena",
  "4603": "São Roque do Pico",
  "4701": "Horta",
  "4801": "Lajes das Flores",
  "4802": "Santa Cruz das Flores",
  "4901": "Corvo",
};

// meta.json category id -> [EventCategory, eventType, severity]. Only the
// 8 safe-to-sum "crimes específicos" ids — see file header for why 0, 7,
// 10-17 and 18 are excluded. Severity tiers follow the same violent/
// property/road-safety intuition as UkPoliceAdapter's own CATEGORY_MAP:
// domestic violence and assault are "high"/"medium" VIOLENCE, the four
// theft/burglary/robbery types are PROPERTY, and the two driving offences
// are ROAD_SAFETY (folded into public_safety_count by
// concelho_crime_summary so the UI keeps its usual 3-colour shape).
const CATEGORY_MAP: Record<number, [string, string, string]> = {
  1: ["VIOLENCE", "domestic_violence", "high"],
  2: ["PROPERTY", "vehicle_theft", "medium"],
  3: ["PROPERTY", "burglary", "medium"],
  4: ["PROPERTY", "burglary", "medium"],
  5: ["VIOLENCE", "assault", "medium"],
  6: ["PROPERTY", "robbery", "high"],
  8: ["ROAD_SAFETY", "road_hazard", "medium"],
  9: ["ROAD_SAFETY", "road_hazard", "low"],
};

interface SeriesEntry {
  s: Array<Array<number | null>>;
}

// One row per concelho, already reduced to the single latest year's 8
// category values — never the full 1993-2025 series, so nothing here
// scales with 29 years x 308 concelhos in memory.
interface ConcelhoPayload {
  dico: string;
  year: number;
  counts: Record<number, number>;
}

export class PtCrimeAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "PT",
      name: "criminalidade.pt — DGPJ/INE/PORDATA municipal crime series",
      organisation: "Direção-Geral da Política de Justiça (via criminalidade.pt)",
      sourceType: "official",
      sourceUrl: SERIES_URL,
      adapterName: "PtCrimeAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const metaRes = await fetch(META_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!metaRes.ok) throw new Error(`meta.json failed: ${metaRes.status}`);
    const meta = (await metaRes.json()) as { years: number[] };
    if (!meta.years?.length) throw new Error("meta.json returned no years");
    const year = meta.years[meta.years.length - 1];
    const yearIndex = meta.years.length - 1;

    const seriesRes = await fetch(SERIES_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!seriesRes.ok) throw new Error(`series.json failed: ${seriesRes.status}`);
    const series = (await seriesRes.json()) as Record<string, SeriesEntry>;

    const records: RawSecurityRecord[] = [];
    for (const [dico, entry] of Object.entries(series)) {
      if (!CONCELHO_NAME[dico]) continue;

      const counts: Record<number, number> = {};
      for (const categoryId of Object.keys(CATEGORY_MAP).map(Number)) {
        const value = entry.s[categoryId]?.[yearIndex];
        if (typeof value === "number" && value > 0) {
          counts[categoryId] = Math.round(value);
        }
      }
      if (Object.keys(counts).length === 0) continue;

      const payload: ConcelhoPayload = { dico, year, counts };
      records.push({
        sourceRecordId: `pt-crime-${dico}-${year}`,
        payload,
        fetchedAt: new Date().toISOString(),
      });
    }

    return records;
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const { dico, year, counts } = record.payload as ConcelhoPayload;
    const areaName = CONCELHO_NAME[dico];
    if (!areaName) return Promise.resolve([]);

    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    const events: SecurityEvent[] = [];
    for (const [categoryIdStr, occurrenceCount] of Object.entries(counts)) {
      const categoryId = Number(categoryIdStr);
      const [eventCategory, eventType, severity] = CATEGORY_MAP[categoryId];
      events.push({
        countryCode: "PT",
        sourceRecordId: `pt-crime-${dico}-${year}-${categoryId}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: String(categoryId),
        occurredAt: `${year}-01-01T00:00:00Z`,
        geoPrecision: "MUNICIPALITY",
        locationConfidence: municipalityLocationConfidence,
        district: areaName,
        occurrenceCount,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: municipalityLocationConfidence,
        }),
      });
    }

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(META_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on meta.json` };
      }
      const meta = (await res.json()) as { years: number[]; build_date?: string };
      const latestYear = meta.years?.length ? meta.years[meta.years.length - 1] : undefined;
      return {
        status: "GREEN",
        lastDataDate: latestYear ? `${latestYear}-01-01` : undefined,
      };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
