// BeeAware Global blueprint — NiPoliceAdapter, the choropleth source for
// Northern Ireland. uk_police.ts is the direct model for this file's
// shape (same fetch/normalize/healthCheck structure, same bounded-
// concurrency worker pool) — see that file's header for the fuller
// "known, accepted failure modes" rationale this shares.
//
// Investigated live (2026-09-01): Northern Ireland's point-level map
// pins already work today with zero code changes — UkPoliceApi
// (lib/backend/uk_police_api.dart) is a plain lat/lng query against
// data.police.uk, called by IncidentStore for every viewport in the
// world regardless of country, and PSNI publishes through the exact
// same endpoint (confirmed live: 1223 real crimes near Belfast for a
// single month). The only real gap was the CHOROPLETH: England & Wales'
// own Police Force Area geometry (uk_police.ts, 20260831120000) is
// explicitly EW-only, so PSNI — in data.police.uk's own force list, but
// with no boundary in that ONS dataset — never had an area to colour.
//
// This adapter closes that gap using Northern Ireland's 11 councils
// ("Local Government Districts", 2015 reorganisation) rather than a
// single national PSNI polygon — confirmed live via the same ONS Open
// Geography Portal already used for the EW force geometry
// ('Local Authority Districts (December 2023) Boundaries UK BGC',
// filtered to LAD23CD starting 'N' — exactly 11 features, matching NI's
// real council count). Geometry migration: 20260905170000.
//
// A single whole-of-Northern-Ireland `poly` query to data.police.uk
// deterministically 503s (confirmed live) — the exact same result-size
// ceiling documented in uk_police.ts for England's 13 highest-volume
// forces, just triggered here by the country's total size rather than
// one dense force. Querying per council instead (each roughly a
// quarter of the country's area or smaller — confirmed live with test
// boxes of that scale, all 200) sidesteps it entirely: every one of the
// 11 councils was verified live to return real data with no 503, so
// unlike UkPoliceAdapter this adapter has no "skip these known-bad
// areas" list.
//
// LGD_QUERY_POLYGONS below is a separate, coarser simplification
// (shapely, tolerance 0.01) of the same council boundaries the geometry
// migration uses at full precision — same relationship as
// FORCE_QUERY_POLYGONS to its own display geometry in uk_police.ts, for
// the same reason (the real boundary is far too detailed for a URL
// query parameter). Keyed directly by the council's own name (which is
// also geo_areas.name for this area_type), unlike uk_police.ts's
// force-id-keyed map, since there's no separate short "force id" for a
// council the way data.police.uk has for forces.

import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import { CATEGORY_MAP } from "./uk_police.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const DATES_URL = "https://data.police.uk/api/crimes-street-dates";
const CRIMES_URL = "https://data.police.uk/api/crimes-street/all-crime";
const USER_AGENT = "Mozilla/5.0 (compatible; BeeAwareBot/1.0)";

// council name (== geo_areas.name for area_type='LGD') -> simplified
// query polygon, "lat,lng:lat,lng:...". See file header for how these
// were generated and verified.
const LGD_QUERY_POLYGONS: Record<string, string> = {
  "Antrim and Newtownabbey": "54.8106,-6.1623:54.8059,-6.1074:54.7926,-6.1027:54.8001,-6.0098:54.7740,-5.9868:54.7803,-5.9008:54.7724,-5.8874:54.7658,-5.9059:54.7453,-5.8923:54.7143,-5.9101:54.6889,-5.8682:54.6456,-5.9156:54.6650,-5.9507:54.6523,-5.9488:54.6453,-5.9709:54.6594,-5.9864:54.6287,-6.0235:54.6117,-6.0211:54.6059,-6.0455:54.6244,-6.0876:54.6208,-6.1481:54.5879,-6.2370:54.5967,-6.2945:54.5800,-6.2812:54.5729,-6.3046:54.5913,-6.3238:54.5682,-6.4260:54.6488,-6.4071:54.7137,-6.4959:54.7618,-6.4572:54.7809,-6.4771:54.7791,-6.3852:54.8013,-6.3377:54.7885,-6.2272",
  "Armagh City, Banbridge and Craigavon": "54.5340,-6.2755:54.4962,-6.2395:54.4795,-6.2580:54.4327,-6.2102:54.4442,-6.1565:54.4342,-6.1589:54.4027,-6.0539:54.3872,-6.0642:54.3775,-6.0207:54.3269,-6.0636:54.3185,-6.1044:54.2914,-6.0599:54.2656,-6.0766:54.2631,-6.0388:54.2462,-6.0453:54.2431,-6.1366:54.2189,-6.1603:54.2586,-6.2123:54.2729,-6.4028:54.2550,-6.4668:54.2257,-6.5041:54.2371,-6.5255:54.2189,-6.5999:54.1791,-6.6462:54.2002,-6.6919:54.1815,-6.7386:54.2230,-6.8162:54.2615,-6.8277:54.2790,-6.8780:54.2920,-6.8510:54.3279,-6.8655:54.3358,-6.8369:54.4146,-6.7943:54.4039,-6.7101:54.4422,-6.6971:54.4696,-6.6504:54.4867,-6.6507:54.5042,-6.6282:54.5036,-6.5914:54.5421,-6.5413:54.5913,-6.3238:54.5574,-6.2777",
  "Belfast": "54.6650,-5.9507:54.6094,-5.8077:54.5817,-5.8228:54.5667,-5.9121:54.5402,-5.9332:54.5308,-5.9728:54.5551,-6.0597:54.5641,-6.0410:54.6123,-6.0420:54.6117,-6.0211:54.6287,-6.0235:54.6594,-5.9864:54.6453,-5.9709:54.6523,-5.9488",
  "Causeway Coast and Glens": "55.2520,-6.4817:55.2323,-6.4093:55.2396,-6.3326:55.2027,-6.2359:55.2280,-6.1460:55.1989,-6.0622:55.1405,-6.0255:55.1310,-6.0412:55.1033,-6.0360:55.0601,-6.0622:55.0563,-5.9769:54.9840,-6.0980:54.9882,-6.1316:55.0344,-6.1808:55.0048,-6.2792:55.0102,-6.3238:54.9791,-6.3230:54.9880,-6.3456:54.9646,-6.4482:54.9405,-6.4078:54.9366,-6.4284:54.9168,-6.4222:54.9188,-6.4999:54.9520,-6.5376:54.9335,-6.5368:54.9235,-6.5850:54.9382,-6.6175:54.9163,-6.6906:54.9318,-6.7075:54.9288,-6.7381:54.9137,-6.7758:54.9031,-6.7576:54.8732,-6.7682:54.8466,-6.8026:54.8530,-6.8866:54.8318,-6.8870:54.8203,-6.9138:54.8337,-6.9462:54.8209,-7.0069:54.8455,-7.0388:54.8870,-7.0193:54.8884,-7.0346:54.9140,-7.0436:54.9275,-7.0876:54.9858,-7.0810:54.9853,-7.1266:55.0340,-7.1659:55.0517,-7.0434:55.0777,-7.0136:55.1003,-7.0202:55.1095,-6.9900:55.1479,-6.9688:55.1946,-6.9664:55.1681,-6.8747:55.1686,-6.7526:55.1734,-6.7245:55.1899,-6.7219:55.1995,-6.6584:55.2127,-6.6629:55.2162,-6.5453",
  "Derry City and Strabane": "55.0474,-7.2891:55.0635,-7.2455:55.0442,-7.2518:55.0609,-7.2257:55.0573,-7.1480:55.0340,-7.1659:54.9853,-7.1266:54.9858,-7.0810:54.9275,-7.0876:54.9140,-7.0436:54.8884,-7.0346:54.8870,-7.0193:54.8455,-7.0388:54.8209,-7.0069:54.8337,-6.9462:54.8204,-6.9121:54.8025,-6.9224:54.7832,-6.9034:54.7799,-7.0054:54.7494,-7.1173:54.7520,-7.2265:54.7310,-7.2610:54.7383,-7.3064:54.7133,-7.3193:54.6931,-7.3917:54.6410,-7.4478:54.6542,-7.4841:54.6474,-7.5617:54.6296,-7.5729:54.6267,-7.6576:54.6080,-7.6958:54.6349,-7.7084:54.6180,-7.7416:54.6439,-7.8133:54.6307,-7.8514:54.6505,-7.8566:54.6697,-7.9109:54.6880,-7.8980:54.7027,-7.9181:54.7027,-7.8795:54.7364,-7.8367:54.7043,-7.7500:54.7515,-7.6366:54.7470,-7.5343:54.7893,-7.5493:54.8240,-7.4838:54.8693,-7.4444:54.9352,-7.4472:54.9454,-7.3921:54.9637,-7.4075:55.0224,-7.3914:55.0505,-7.3462",
  "Fermanagh and Omagh": "54.7799,-6.9783:54.7662,-6.9360:54.7180,-7.0111:54.7058,-6.9942:54.6715,-7.0026:54.6637,-6.9694:54.6519,-6.9885:54.6080,-6.9480:54.5795,-6.9696:54.5815,-6.9886:54.5707,-6.9699:54.5564,-6.9858:54.5451,-6.9728:54.5258,-7.0291:54.5056,-7.0393:54.5003,-7.0994:54.4755,-7.1212:54.4779,-7.2029:54.4663,-7.1986:54.4545,-7.2358:54.4604,-7.2726:54.4436,-7.2948:54.4375,-7.3670:54.4050,-7.3316:54.3717,-7.3344:54.3716,-7.2805:54.3270,-7.2462:54.3418,-7.2010:54.3335,-7.1819:54.3097,-7.1791:54.2996,-7.2122:54.2861,-7.1729:54.2726,-7.1793:54.2532,-7.1414:54.2437,-7.1590:54.2398,-7.1460:54.2209,-7.1533:54.2045,-7.2480:54.1978,-7.2330:54.1922,-7.2591:54.1774,-7.2583:54.1697,-7.2403:54.1191,-7.2919:54.1321,-7.3089:54.1365,-7.2854:54.1441,-7.3013:54.1538,-7.2838:54.1719,-7.2913:54.1468,-7.3395:54.1234,-7.3053:54.1133,-7.3189:54.1314,-7.3635:54.1202,-7.3919:54.1395,-7.3728:54.1369,-7.4204:54.1562,-7.4096:54.1539,-7.4423:54.1223,-7.4793:54.1358,-7.5281:54.1221,-7.5474:54.1438,-7.6104:54.1857,-7.6561:54.1820,-7.6766:54.2078,-7.6854:54.2009,-7.8115:54.2176,-7.8602:54.2795,-7.8732:54.2935,-7.8619:54.3124,-7.9616:54.3582,-8.0004:54.3657,-8.0574:54.4420,-8.1619:54.4507,-8.1428:54.4648,-8.1775:54.4877,-8.0426:54.5459,-8.0060:54.5330,-7.8505:54.5816,-7.7940:54.6267,-7.6576:54.6296,-7.5729:54.6474,-7.5617:54.6386,-7.5505:54.6538,-7.5104:54.6410,-7.4478:54.6931,-7.3917:54.7133,-7.3193:54.7383,-7.3064:54.7310,-7.2610:54.7520,-7.2265:54.7494,-7.1173",
  "Lisburn and Castlereagh": "54.6229,-6.0810:54.5935,-6.0395:54.5641,-6.0410:54.5551,-6.0597:54.5307,-5.9763:54.5402,-5.9332:54.5667,-5.9121:54.5817,-5.8228:54.6165,-5.8075:54.6133,-5.7710:54.5814,-5.7575:54.5710,-5.7890:54.5457,-5.7930:54.5249,-5.8271:54.4923,-5.8257:54.4475,-5.9179:54.4333,-5.9148:54.4037,-5.9507:54.3839,-5.9384:54.3705,-6.0185:54.3872,-6.0642:54.4039,-6.0562:54.4342,-6.1589:54.4442,-6.1565:54.4327,-6.2102:54.4795,-6.2580:54.4946,-6.2391:54.5196,-6.2732:54.5574,-6.2777:54.5729,-6.3046:54.5800,-6.2812:54.5967,-6.2945:54.5879,-6.2370:54.6208,-6.1481",
  "Mid and East Antrim": "55.0533,-5.9696:54.9864,-5.9917:54.9618,-5.9190:54.9076,-5.8780:54.9008,-5.8443:54.8522,-5.7976:54.8462,-5.7222:54.8029,-5.6894:54.7670,-5.6880:54.7459,-5.7101:54.6889,-5.8682:54.7167,-5.9107:54.7453,-5.8923:54.7658,-5.9059:54.7724,-5.8874:54.7740,-5.9868:54.8001,-6.0098:54.7926,-6.1027:54.8059,-6.1074:54.8119,-6.1720:54.7885,-6.2272:54.8013,-6.3377:54.7791,-6.3852:54.7809,-6.4771:54.8246,-6.4573:54.9083,-6.5063:54.9248,-6.4678:54.9168,-6.4222:54.9366,-6.4284:54.9405,-6.4078:54.9646,-6.4482:54.9880,-6.3456:54.9791,-6.3230:55.0102,-6.3238:55.0048,-6.2792:55.0344,-6.1808:54.9882,-6.1316:54.9840,-6.0980:55.0370,-6.0247",
  "Mid Ulster": "54.9520,-6.5376:54.8246,-6.4573:54.7759,-6.4803:54.7618,-6.4572:54.7137,-6.4959:54.6488,-6.4071:54.5682,-6.4260:54.5421,-6.5413:54.5036,-6.5914:54.5038,-6.6295:54.4696,-6.6504:54.4422,-6.6971:54.4039,-6.7101:54.4151,-6.7935:54.3729,-6.8089:54.3294,-6.8540:54.3504,-6.9064:54.3745,-6.9110:54.3778,-6.9327:54.3829,-6.9238:54.4213,-7.0289:54.3683,-7.1097:54.3560,-7.1034:54.3351,-7.1539:54.3418,-7.2010:54.3270,-7.2462:54.3716,-7.2805:54.3717,-7.3344:54.4050,-7.3316:54.4375,-7.3670:54.4436,-7.2948:54.4604,-7.2726:54.4545,-7.2358:54.4663,-7.1986:54.4779,-7.2029:54.4755,-7.1212:54.5003,-7.0994:54.5056,-7.0393:54.5258,-7.0291:54.5451,-6.9728:54.5564,-6.9858:54.5707,-6.9699:54.5815,-6.9886:54.5795,-6.9696:54.6080,-6.9480:54.6519,-6.9885:54.6637,-6.9694:54.6715,-7.0026:54.7058,-6.9942:54.7180,-7.0111:54.7411,-6.9906:54.7522,-6.9408:54.7736,-6.9400:54.7832,-6.9034:54.8025,-6.9224:54.8318,-6.8870:54.8530,-6.8866:54.8466,-6.8026:54.8732,-6.7682:54.9031,-6.7576:54.9137,-6.7758:54.9288,-6.7381:54.9318,-6.7075:54.9163,-6.6906:54.9382,-6.6175:54.9235,-6.5850:54.9335,-6.5368",
  "Newry, Mourne and Down": "54.4903,-5.8165:54.4636,-5.7911:54.4639,-5.7360:54.4474,-5.7212:54.4650,-5.6282:54.4495,-5.5838:54.4069,-5.5955:54.3738,-5.5484:54.3243,-5.5160:54.2638,-5.5906:54.2654,-5.6080:54.2488,-5.6087:54.2524,-5.6344:54.2582,-5.6297:54.2591,-5.6367:54.2633,-5.6364:54.2630,-5.6398:54.2423,-5.6364:54.2256,-5.6602:54.2515,-5.6955:54.2433,-5.8227:54.2570,-5.8338:54.2591,-5.8159:54.2723,-5.8203:54.2842,-5.8167:54.2839,-5.8144:54.2847,-5.8138:54.2855,-5.8150:54.2867,-5.8139:54.2545,-5.8496:54.2419,-5.8297:54.2054,-5.8929:54.1676,-5.8718:54.1047,-5.8969:54.0228,-6.0628:54.0402,-6.1074:54.0459,-6.0731:54.0626,-6.0949:54.0650,-6.1594:54.0982,-6.1981:54.0964,-6.2541:54.1127,-6.2909:54.0910,-6.3180:54.1136,-6.3664:54.0726,-6.3635:54.0588,-6.3915:54.0565,-6.4435:54.0771,-6.4778:54.0663,-6.4713:54.0527,-6.5105:54.0575,-6.5866:54.0365,-6.6238:54.0730,-6.6690:54.0960,-6.6451:54.1226,-6.6612:54.1535,-6.6297:54.1827,-6.6443:54.2125,-6.6121:54.2371,-6.5255:54.2257,-6.5041:54.2673,-6.4395:54.2718,-6.2791:54.2586,-6.2123:54.2189,-6.1603:54.2431,-6.1366:54.2462,-6.0453:54.2631,-6.0388:54.2635,-6.0757:54.2914,-6.0599:54.3260,-6.0998:54.3269,-6.0636:54.3716,-6.0174:54.3839,-5.9384:54.4037,-5.9507:54.4615,-5.9034:54.4914,-5.8454",
  "Ards and North Down": "54.6787,-5.5974:54.6343,-5.5317:54.6231,-5.5341:54.5994,-5.5226:54.5641,-5.4772:54.5466,-5.4858:54.4979,-5.4632:54.4873,-5.4328:54.4571,-5.4356:54.4293,-5.4798:54.3864,-5.4602:54.3764,-5.4897:54.3567,-5.4813:54.3243,-5.5160:54.3738,-5.5484:54.4069,-5.5955:54.4495,-5.5838:54.4650,-5.6282:54.4477,-5.7229:54.4639,-5.7360:54.4636,-5.7911:54.5013,-5.8331:54.5360,-5.8177:54.5457,-5.7930:54.5639,-5.7964:54.5814,-5.7575:54.6133,-5.7710:54.6236,-5.8585:54.6570,-5.8105:54.6776,-5.7410:54.6630,-5.6729",
};

interface CrimeRow {
  category: string;
  month: string;
}

// Same reasoning as uk_police.ts's own ForcePayload: reduce to per-
// category counts right after each response is parsed, don't carry the
// full crime array around.
interface LgdPayload {
  councilName: string;
  month: string;
  categoryCounts: Record<string, number>;
}

async function findLatestMonth(): Promise<string> {
  const res = await fetch(DATES_URL, { headers: { "User-Agent": USER_AGENT } });
  if (!res.ok) throw new Error(`crimes-street-dates failed: ${res.status}`);
  const dates = (await res.json()) as Array<{ date: string }>;
  let maxYm = "0000-00";
  for (const d of dates) {
    if (d.date > maxYm) maxYm = d.date;
  }
  if (maxYm === "0000-00") throw new Error("crimes-street-dates returned no dates");
  return maxYm;
}

export class NiPoliceAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "GB",
      name: "data.police.uk - Street-level crime by Northern Ireland council",
      organisation: "Police Service of Northern Ireland (via data.police.uk)",
      sourceType: "official",
      sourceUrl: CRIMES_URL,
      adapterName: "NiPoliceAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "weekly",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const month = await findLatestMonth();
    const councilEntries = Object.entries(LGD_QUERY_POLYGONS);
    const records: RawSecurityRecord[] = [];

    // Same bounded-concurrency shape as UkPoliceAdapter, though with only
    // 11 areas (all verified live to succeed — see file header) this is
    // mostly headroom against a transient hiccup, not the load-bearing
    // fix it is for UK's 43 forces.
    const CONCURRENCY = 4;
    const MAX_ATTEMPTS = 3;
    let cursor = 0;

    async function worker() {
      while (cursor < councilEntries.length) {
        const [councilName, poly] = councilEntries[cursor++];
        const url = `${CRIMES_URL}?poly=${encodeURIComponent(poly)}&date=${month}`;
        for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
          try {
            const res = await fetch(url, { headers: { "User-Agent": USER_AGENT } });
            if (res.ok) {
              const crimes = (await res.json()) as CrimeRow[];
              const categoryCounts: Record<string, number> = {};
              for (const crime of crimes) {
                if (!CATEGORY_MAP[crime.category]) continue;
                categoryCounts[crime.category] = (categoryCounts[crime.category] ?? 0) + 1;
              }
              const payload: LgdPayload = { councilName, month, categoryCounts };
              records.push({
                sourceRecordId: `ni-police-${councilName}-${month}`,
                payload,
                fetchedAt: new Date().toISOString(),
              });
              break;
            }
            if (res.status !== 429 || attempt === MAX_ATTEMPTS) {
              console.error(`NiPoliceAdapter: ${councilName} request failed: ${res.status}`);
              break;
            }
          } catch (e) {
            if (attempt === MAX_ATTEMPTS) {
              console.error(`NiPoliceAdapter: ${councilName} fetch threw:`, e);
              break;
            }
          }
          await new Promise((resolve) => setTimeout(resolve, 500 * attempt));
        }
      }
    }

    await Promise.all(Array.from({ length: CONCURRENCY }, () => worker()));

    return records;
  }

  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const { councilName, month, categoryCounts } = record.payload as LgdPayload;

    // Same reasoning as uk_police.ts's own normalize(): one row per
    // ORIGINAL data.police.uk category, not per taxonomy eventType,
    // since several categories collapse onto the same eventType at
    // different severities.
    const districtLocationConfidence = defaultLocationConfidence("DISTRICT");

    const events: SecurityEvent[] = [];
    for (const [category, occurrenceCount] of Object.entries(categoryCounts)) {
      const [eventCategory, eventType, severity] = CATEGORY_MAP[category];
      events.push({
        countryCode: "GB",
        sourceRecordId: `ni-police-${councilName}-${month}-${category}`,
        sourceType: "official",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        originalCategory: category,
        occurredAt: `${month}-01T00:00:00Z`,
        geoPrecision: "DISTRICT",
        locationConfidence: districtLocationConfidence,
        district: councilName,
        occurrenceCount,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "official_confirmed_record",
          locationConfidence: districtLocationConfidence,
        }),
      });
    }

    return Promise.resolve(events);
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(DATES_URL, { headers: { "User-Agent": USER_AGENT } });
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on crimes-street-dates` };
      }
      const dates = (await res.json()) as Array<{ date: string }>;
      let maxYm = "0000-00";
      for (const d of dates) if (d.date > maxYm) maxYm = d.date;
      return { status: "GREEN", lastDataDate: maxYm !== "0000-00" ? `${maxYm}-01` : undefined };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
