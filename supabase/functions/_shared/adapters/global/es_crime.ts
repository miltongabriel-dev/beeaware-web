// BeeAware Global blueprint — EsCrimeAdapter (Spain municipio-level crime
// summary for the choropleth already used in Brazil, the UK and Portugal).
//
// Investigated live (2026-09-01/02), not assumed:
// - `georiesgo.com` is a third-party static site (like criminalidade.pt
//   for Portugal, not the government portal itself) republishing official
//   Ministerio del Interior crime statistics as public JSON, no key
//   needed, CORS wide open (`Access-Control-Allow-Origin: *`):
//     - https://georiesgo.com/data/municipios-detalle.json — one file with
//       geometry AND crime counts already combined, one `feature` per
//       municipio. Confirmed live: 427 municipios, all with
//       `properties.poblacion` >= 19,995 — this matches the Ministerio's
//       own real coverage limit (Portal Estadístico de Criminalidad only
//       publishes below province level for municipios over ~20,000
//       inhabitants), not a limitation georiesgo.com introduced. There is
//       no equivalent province-level file on this site (checked, 404) —
//       full national coverage (like UkPoliceAdapter's 43 forces) would
//       need a different, harder source (the Ministerio's own province
//       figures are PC-Axis/Excel only, no ready JSON+geometry combo
//       found). This was presented to the user as an explicit trade-off
//       and municipio-level was the chosen option.
//   MUNICIPIO_NAME below maps each `properties.ine_code` (Spain's
//   official INE municipality code) to the exact name used as
//   `geo_areas.name` (20260903100000_es_municipio_geometry.sql) — all 427
//   names confirmed unique, no cross-checking needed the way Portugal's
//   slug/dico scrape did.
//
// - `properties.delitos` has 16 fields; only 11 are safe to sum without
//   double-counting, verified by script across all 427 municipios with
//   zero exceptions: `homicidios` + `homicidios_tentativa` + `lesiones` +
//   `secuestro` + `delitos_sexuales` (the parent field — its own two
//   children, `agresion_sexual_penetracion`/`delitos_sexuales_resto`, are
//   excluded, they're just its breakdown) + `robos_violencia` +
//   `robos_fuerza_total` (the parent — `robos_fuerza` alone is an
//   unlabelled subset of it, excluded) + `hurtos` + `sustraccion_vehiculo`
//   + `trafico_drogas` + `resto_convencional` sums to EXACTLY
//   `properties.subtotales.convencional`, which is itself exactly
//   `properties.total_hechos`, in all 427 municipios with zero mismatch.
//   `ciber_estafas` + `ciber_resto` separately sum to exactly
//   `subtotales.cibercriminalidad`. Cybercrime is deliberately excluded
//   here: there's no matching bucket in this app's taxonomy
//   (VIOLENCE/PROPERTY/PUBLIC_SAFETY/ROAD_SAFETY/COMMUNITY) and online
//   fraud isn't the physical-safety risk this app exists to surface.
//   `resto_convencional` (an undifferentiated catch-all, often over half
//   of a municipio's total conventional crime — e.g. 1690 of 3097 in one
//   sample) has no further breakdown in this source — a real, documented
//   limitation of the same kind already accepted for UkPoliceAdapter's
//   "violent-crime" bucket.
//
// - `properties.periodo` (e.g. "ene-sep 2025") is a year-to-date
//   CUMULATIVE balance — the Ministerio publishes these a few times a
//   year (quarterly-ish balances), not one clean closed calendar year the
//   way Portugal's DGPJ does. Summing a later, more complete period (say
//   "ene-dic 2025") on top of an earlier one for the same year ("ene-sep
//   2025") would double-count the overlapping months. To avoid this,
//   sourceRecordId is keyed by YEAR ONLY (extracted from `periodo`), not
//   by the exact period string — so a later run for the same year
//   upserts (replaces) the prior figure instead of adding a second row.
//   Only one GET is made per run (~850KB), no per-area query problem the
//   way UkPoliceAdapter has.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const DETALLE_URL = "https://georiesgo.com/data/municipios-detalle.json";
// Not confirmed load-bearing (georiesgo.com never showed any sign of
// blocking a plain fetch) — kept for the same reason as pt_crime.ts's own
// USER_AGENT: no reason to look unlike a normal client.
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// ine_code -> the exact geo_areas.name value the geometry migration used.
// Exported for es_news.ts, which matches article text against these same
// 427 names (via geo_text_match_generic.ts) rather than keeping a second
// copy of the list.
export const MUNICIPIO_NAME: Record<string, string> = {
  "01059": "Vitoria-Gasteiz",
  "02003": "Albacete",
  "02009": "Almansa",
  "02037": "Hellín",
  "02081": "Villarrobledo",
  "03009": "Alcoy/Alcoi",
  "03011": "L'Alfàs del Pi",
  "03014": "Alicante/Alacant",
  "03015": "Almoradí",
  "03018": "Altea",
  "03019": "Aspe",
  "03031": "Benidorm",
  "03047": "Calp",
  "03050": "Campello (el)",
  "03059": "Crevillent",
  "03063": "Dénia",
  "03065": "Elche/Elx",
  "03066": "Elda",
  "03079": "Ibi",
  "03082": "Jávea/Xàbia",
  "03090": "Mutxamel",
  "03093": "Novelda",
  "03099": "Orihuela",
  "03104": "Petrer",
  "03119": "Sant Joan d'Alacant",
  "03121": "Santa Pola",
  "03122": "San Vicente del Raspeig/Sant Vicent del Raspeig",
  "03133": "Torrevieja",
  "03139": "Villajoyosa/Vila Joiosa (la)",
  "03140": "Villena",
  "03902": "Pilar de la Horadada",
  "04003": "Adra",
  "04013": "Almería",
  "04053": "Huércal-Overa",
  "04066": "Níjar",
  "04079": "Roquetas de Mar",
  "04102": "Vícar",
  "04902": "Ejido (El)",
  "05019": "Ávila",
  "06011": "Almendralejo",
  "06015": "Badajoz",
  "06044": "Don Benito",
  "06083": "Mérida",
  "06153": "Villanueva de la Serena",
  "07003": "Alcudia",
  "07011": "Calvià",
  "07015": "Ciutadella de Menorca",
  "07026": "Eivissa",
  "07027": "Inca",
  "07031": "Llucmajor",
  "07032": "Maó-Mahón",
  "07033": "Manacor",
  "07036": "Marratxí",
  "07040": "Palma",
  "07046": "Sant Antoni de Portmany",
  "07048": "Sant Josep de sa Talaia",
  "07054": "Santa Eulària des Riu",
  "08015": "Badalona",
  "08019": "Barcelona",
  "08035": "Calella",
  "08051": "Castellar del Vallès",
  "08056": "Castelldefels",
  "08073": "Cornellà de Llobregat",
  "08076": "Esparreguera",
  "08077": "Esplugues de Llobregat",
  "08086": "Les Franqueses del Vallès",
  "08089": "Gavà",
  "08096": "Granollers",
  "08101": "Hospitalet de Llobregat (L')",
  "08102": "Igualada",
  "08112": "Manlleu",
  "08113": "Manresa",
  "08114": "Martorell",
  "08118": "Masnou (El)",
  "08121": "Mataró",
  "08123": "Molins de Rei",
  "08124": "Mollet del Vallès",
  "08125": "Montcada i Reixac",
  "08147": "Olesa de Montserrat",
  "08163": "Pineda de Mar",
  "08169": "Prat de Llobregat (El)",
  "08172": "Premià de Mar",
  "08180": "Ripollet",
  "08184": "Rubí",
  "08187": "Sabadell",
  "08194": "Sant Adrià de Besòs",
  "08196": "Sant Andreu de la Barca",
  "08200": "Sant Boi de Llobregat",
  "08205": "Sant Cugat del Vallès",
  "08211": "Sant Feliu de Llobregat",
  "08217": "Sant Joan Despí",
  "08219": "Vilassar de Mar",
  "08221": "Sant Just Desvern",
  "08231": "Sant Pere de Ribes",
  "08238": "Sant Quirze del Vallès",
  "08245": "Santa Coloma de Gramenet",
  "08252": "Barberà del Vallès",
  "08260": "Santa Perpètua de Mogoda",
  "08263": "Sant Vicenç dels Horts",
  "08266": "Cerdanyola del Vallès",
  "08270": "Sitges",
  "08279": "Terrassa",
  "08298": "Vic",
  "08301": "Viladecans",
  "08305": "Vilafranca del Penedès",
  "08307": "Vilanova i la Geltrú",
  "09018": "Aranda de Duero",
  "09059": "Burgos",
  "09219": "Miranda de Ebro",
  "10037": "Cáceres",
  "10148": "Plasencia",
  "11004": "Algeciras",
  "11006": "Arcos de la Frontera",
  "11007": "Barbate",
  "11008": "Barrios (Los)",
  "11012": "Cádiz",
  "11014": "Conil de la Frontera",
  "11015": "Chiclana de la Frontera",
  "11020": "Jerez de la Frontera",
  "11022": "Línea de la Concepción (La)",
  "11027": "Puerto de Santa María (El)",
  "11028": "Puerto Real",
  "11030": "Rota",
  "11031": "San Fernando",
  "11032": "Sanlúcar de Barrameda",
  "11033": "San Roque",
  "12009": "Almazora/Almassora",
  "12027": "Benicarló",
  "12028": "Benicasim/Benicàssim",
  "12032": "Borriana/Burriana",
  "12040": "Castellón de la Plana/Castelló de la Plana",
  "12084": "Onda",
  "12126": "Vall d'Uixó (la)",
  "12135": "Vila-real",
  "12138": "Vinaròs",
  "13005": "Alcázar de San Juan",
  "13034": "Ciudad Real",
  "13071": "Puertollano",
  "13082": "Tomelloso",
  "13087": "Valdepeñas",
  "14013": "Cabra",
  "14021": "Córdoba",
  "14038": "Lucena",
  "14042": "Montilla",
  "14049": "Palma del Río",
  "14055": "Priego de Córdoba",
  "14056": "Puente Genil",
  "15002": "Ames",
  "15005": "Arteixo",
  "15017": "Cambre",
  "15019": "Carballo",
  "15030": "Coruña (A)",
  "15031": "Culleredo",
  "15036": "Ferrol",
  "15054": "Narón",
  "15058": "Oleiros",
  "15073": "Ribeira",
  "15078": "Santiago de Compostela",
  "16078": "Cuenca",
  "17015": "Banyoles",
  "17023": "Blanes",
  "17066": "Figueres",
  "17079": "Girona",
  "17095": "Lloret de Mar",
  "17114": "Olot",
  "17117": "Palafrugell",
  "17152": "Roses",
  "17155": "Salt",
  "17160": "Sant Feliu de Guíxols",
  "18017": "Almuñécar",
  "18021": "Armilla",
  "18022": "Atarfe",
  "18023": "Baza",
  "18087": "Granada",
  "18122": "Loja",
  "18127": "Maracena",
  "18140": "Motril",
  "18193": "Zubia, La",
  "18905": "Gabias (Las)",
  "19046": "Azuqueca de Henares",
  "19130": "Guadalajara",
  "20030": "Eibar",
  "20040": "Hernani",
  "20045": "Irun",
  "20055": "Arrasate/Mondragón",
  "20067": "Errenteria",
  "20069": "Donostia/San Sebastián",
  "20071": "Tolosa",
  "20079": "Zarautz",
  "21002": "Aljaraque",
  "21005": "Almonte",
  "21010": "Ayamonte",
  "21021": "Cartaya",
  "21041": "Huelva",
  "21042": "Isla Cristina",
  "21044": "Lepe",
  "21050": "Moguer",
  "22125": "Huesca",
  "23002": "Alcalá la Real",
  "23005": "Andújar",
  "23050": "Jaén",
  "23055": "Linares",
  "23060": "Martos",
  "23092": "Úbeda",
  "24089": "León",
  "24115": "Ponferrada",
  "24142": "San Andrés del Rabanedo",
  "25120": "Lleida",
  "26036": "Calahorra",
  "26089": "Logroño",
  "27028": "Lugo",
  "28005": "Alcalá de Henares",
  "28006": "Alcobendas",
  "28007": "Alcorcón",
  "28009": "Algete",
  "28013": "Aranjuez",
  "28014": "Arganda del Rey",
  "28015": "Arroyomolinos",
  "28022": "Boadilla del Monte",
  "28040": "Ciempozuelos",
  "28045": "Colmenar Viejo",
  "28047": "Collado Villalba",
  "28049": "Coslada",
  "28058": "Fuenlabrada",
  "28061": "Galapagar",
  "28065": "Getafe",
  "28073": "Humanes de Madrid",
  "28074": "Leganés",
  "28079": "Madrid",
  "28080": "Majadahonda",
  "28084": "Mejorada del Campo",
  "28092": "Móstoles",
  "28096": "Navalcarnero",
  "28104": "Paracuellos de Jarama",
  "28106": "Parla",
  "28113": "Pinto",
  "28115": "Pozuelo de Alarcón",
  "28123": "Rivas-Vaciamadrid",
  "28127": "Rozas de Madrid (Las)",
  "28130": "San Fernando de Henares",
  "28132": "San Martín de la Vega",
  "28134": "San Sebastián de los Reyes",
  "28148": "Torrejón de Ardoz",
  "28152": "Torrelodones",
  "28161": "Valdemoro",
  "28176": "Villanueva de la Cañada",
  "28181": "Villaviciosa de Odón",
  "28903": "Tres Cantos",
  "29007": "Alhaurín de la Torre",
  "29008": "Alhaurín el Grande",
  "29015": "Antequera",
  "29025": "Benalmádena",
  "29038": "Cártama",
  "29042": "Coín",
  "29051": "Estepona",
  "29054": "Fuengirola",
  "29067": "Málaga",
  "29069": "Marbella",
  "29070": "Mijas",
  "29075": "Nerja",
  "29082": "Rincón de la Victoria",
  "29084": "Ronda",
  "29091": "Torrox",
  "29094": "Vélez-Málaga",
  "29901": "Torremolinos",
  "30003": "Águilas",
  "30005": "Alcantarilla",
  "30008": "Alhama de Murcia",
  "30009": "Archena",
  "30015": "Caravaca de la Cruz",
  "30016": "Cartagena",
  "30019": "Cieza",
  "30022": "Jumilla",
  "30024": "Lorca",
  "30026": "Mazarrón",
  "30027": "Molina de Segura",
  "30030": "Murcia",
  "30035": "San Javier",
  "30036": "San Pedro del Pinatar",
  "30037": "Torre-Pacheco",
  "30038": "Torres de Cotillas (Las)",
  "30039": "Totana",
  "30041": "La Unión",
  "30043": "Yecla",
  "31060": "Burlada/Burlata",
  "31086": "Valle de Egüés/Eguesibar",
  "31201": "Pamplona/Iruña",
  "31232": "Tudela",
  "32054": "Ourense",
  "33004": "Avilés",
  "33016": "Castrillón",
  "33024": "Gijón",
  "33031": "Langreo",
  "33037": "Mieres",
  "33044": "Oviedo",
  "33066": "Siero",
  "34120": "Palencia",
  "35002": "Agüimes",
  "35004": "Arrecife",
  "35006": "Arucas",
  "35009": "Gáldar",
  "35011": "Ingenio",
  "35012": "Mogán",
  "35014": "Oliva (La)",
  "35015": "Pájara",
  "35016": "Palmas de Gran Canaria (Las)",
  "35017": "Puerto del Rosario",
  "35019": "San Bartolomé de Tirajana",
  "35022": "Santa Lucía de Tirajana",
  "35024": "Teguise",
  "35026": "Telde",
  "35028": "Tías",
  "36008": "Cangas",
  "36017": "Estrada (A)",
  "36024": "Lalín",
  "36026": "Marín",
  "36038": "Pontevedra",
  "36039": "Porriño, O",
  "36042": "Ponteareas",
  "36045": "Redondela",
  "36057": "Vigo",
  "36060": "Vilagarcía de Arousa",
  "37274": "Salamanca",
  "38001": "Adeje",
  "38006": "Arona",
  "38011": "Candelaria",
  "38017": "Granadilla de Abona",
  "38019": "Guía de Isora",
  "38020": "Güímar",
  "38022": "Icod de los Vinos",
  "38023": "San Cristóbal de La Laguna",
  "38024": "Llanos de Aridane (Los)",
  "38026": "Orotava (La)",
  "38028": "Puerto de la Cruz",
  "38031": "Realejos (Los)",
  "38035": "San Miguel de Abona",
  "38038": "Santa Cruz de Tenerife",
  "38043": "Tacoronte",
  "39016": "Camargo",
  "39020": "Castro-Urdiales",
  "39052": "Piélagos",
  "39075": "Santander",
  "39087": "Torrelavega",
  "40194": "Segovia",
  "41004": "Alcalá de Guadaíra",
  "41017": "Bormujos",
  "41021": "Camas",
  "41024": "Carmona",
  "41034": "Coria del Río",
  "41038": "Dos Hermanas",
  "41039": "Écija",
  "41053": "Lebrija",
  "41058": "Mairena del Alcor",
  "41059": "Mairena del Aljarafe",
  "41065": "Morón de la Frontera",
  "41069": "Palacios y Villafranca (Los)",
  "41081": "Rinconada (La)",
  "41086": "San Juan de Aznalfarache",
  "41091": "Sevilla",
  "41093": "Tomares",
  "41095": "Utrera",
  "42173": "Soria",
  "43014": "Amposta",
  "43037": "Calafell",
  "43038": "Cambrils",
  "43123": "Reus",
  "43148": "Tarragona",
  "43155": "Tortosa",
  "43161": "Valls",
  "43163": "Vendrell (El)",
  "43171": "Vila-seca",
  "43905": "Salou",
  "44216": "Teruel",
  "45081": "Illescas",
  "45161": "Seseña",
  "45165": "Talavera de la Reina",
  "45168": "Toledo",
  "46005": "Alaquàs",
  "46013": "Alboraia/Alboraya",
  "46017": "Alzira",
  "46021": "Aldaia",
  "46022": "Alfafar",
  "46029": "Algemesí",
  "46070": "Bétera",
  "46078": "Burjassot",
  "46083": "Carcaixent",
  "46094": "Catarroja",
  "46102": "Quart de Poblet",
  "46105": "Cullera",
  "46110": "Xirivella",
  "46131": "Gandia",
  "46145": "Xàtiva",
  "46147": "Llíria",
  "46159": "Manises",
  "46169": "Mislata",
  "46171": "Moncada",
  "46181": "Oliva",
  "46184": "Ontinyent",
  "46186": "Paiporta",
  "46190": "Paterna",
  "46194": "Picassent",
  "46202": "Pobla de Vallbona (la)",
  "46205": "Puçol",
  "46213": "Requena",
  "46214": "Riba-roja de Túria",
  "46220": "Sagunto/Sagunt",
  "46230": "Silla",
  "46235": "Sueca",
  "46244": "Torrent",
  "46250": "Valencia",
  "47010": "Arroyo de la Encomienda",
  "47076": "Laguna de Duero",
  "47085": "Medina del Campo",
  "47186": "Valladolid",
  "48013": "Barakaldo",
  "48015": "Basauri",
  "48020": "Bilbao",
  "48027": "Durango",
  "48036": "Galdakao",
  "48044": "Getxo",
  "48054": "Leioa",
  "48078": "Portugalete",
  "48082": "Santurtzi",
  "48084": "Sestao",
  "48902": "Erandio",
  "49275": "Zamora",
  "50297": "Zaragoza",
};

// delitos field name -> [EventCategory, eventType, severity]. Only the 11
// leaf (mutually exclusive) fields — see file header for the verified
// partition and why the other 5 fields are excluded.
const CATEGORY_MAP: Record<string, [string, string, string]> = {
  homicidios: ["VIOLENCE", "homicide", "high"],
  homicidios_tentativa: ["VIOLENCE", "attempted_homicide", "high"],
  lesiones: ["VIOLENCE", "assault", "medium"],
  secuestro: ["VIOLENCE", "kidnapping", "high"],
  delitos_sexuales: ["VIOLENCE", "sexual_violence", "high"],
  robos_violencia: ["PROPERTY", "robbery", "high"],
  robos_fuerza_total: ["PROPERTY", "burglary", "medium"],
  hurtos: ["PROPERTY", "theft", "low"],
  sustraccion_vehiculo: ["PROPERTY", "vehicle_theft", "medium"],
  trafico_drogas: ["PUBLIC_SAFETY", "drugs", "medium"],
  resto_convencional: ["COMMUNITY", "other", "low"],
};

const SPANISH_MONTHS: Record<string, number> = {
  ene: 1, feb: 2, mar: 3, abr: 4, may: 5, jun: 6,
  jul: 7, ago: 8, sep: 9, oct: 10, nov: 11, dic: 12,
};

// "ene-sep 2025" -> 2025. Only the year matters for occurredAt/
// sourceRecordId — see file header on why the period is cumulative and
// keying by year alone lets a later, more complete balance for the same
// year replace an earlier one instead of double-counting on top of it.
function parsePeriodoYear(periodo: string): number | null {
  const m = /^[a-z]{3}-[a-z]{3}\s+(\d{4})$/i.exec(periodo.trim());
  if (!m) return null;
  return Number(m[1]);
}

interface MunicipioFeature {
  properties: {
    ine_code: string;
    periodo: string;
    delitos: Record<string, number>;
  };
}

interface MunicipioPayload {
  ineCode: string;
  year: number;
  counts: Record<string, number>;
}

export class EsCrimeAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "ES",
      name: "georiesgo.com — Portal Estadístico de Criminalidad (Ministerio del Interior)",
      organisation: "Ministerio del Interior (via georiesgo.com)",
      sourceType: "official",
      sourceUrl: DETALLE_URL,
      adapterName: "EsCrimeAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "monthly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(DETALLE_URL, { headers: { "User-Agent": USER_AGENT } });
    if (!res.ok) throw new Error(`municipios-detalle.json failed: ${res.status}`);
    const geojson = (await res.json()) as { features: MunicipioFeature[] };

    const records: RawSecurityRecord[] = [];
    for (const feature of geojson.features) {
      const { ine_code: ineCode, periodo, delitos } = feature.properties;
      if (!MUNICIPIO_NAME[ineCode]) continue;

      const year = parsePeriodoYear(periodo);
      if (year === null) {
        console.error(`EsCrimeAdapter: unparseable periodo "${periodo}" for ${ineCode}`);
        continue;
      }

      const counts: Record<string, number> = {};
      for (const category of Object.keys(CATEGORY_MAP)) {
        const value = delitos[category];
        if (typeof value === "number" && value > 0) {
          counts[category] = Math.round(value);
        }
      }
      if (Object.keys(counts).length === 0) continue;

      const payload: MunicipioPayload = { ineCode, year, counts };
      records.push({
        sourceRecordId: `es-crime-${ineCode}-${year}`,
        payload,
        fetchedAt: new Date().toISOString(),
      });
    }

    return records;
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const { ineCode, year, counts } = record.payload as MunicipioPayload;
    const areaName = MUNICIPIO_NAME[ineCode];
    if (!areaName) return Promise.resolve([]);

    const municipalityLocationConfidence = defaultLocationConfidence("MUNICIPALITY");

    const events: SecurityEvent[] = [];
    for (const [category, occurrenceCount] of Object.entries(counts)) {
      const [eventCategory, eventType, severity] = CATEGORY_MAP[category];
      events.push({
        countryCode: "ES",
        sourceRecordId: `es-crime-${ineCode}-${year}-${category}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: category,
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
      const res = await fetch(DETALLE_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on municipios-detalle.json` };
      }
      const lastModified = res.headers.get("last-modified") ?? undefined;
      return { status: "GREEN", lastDataDate: lastModified };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
