// BeeAware Global blueprint — DeNewsAdapter, Germany's first News
// Intelligence source. fr_news.ts/es_news.ts are the direct model for
// this file's shape.
//
// Investigated live (2026-09-08): presseportal.de/rss/blaulicht.rss2 —
// "Blaulicht" (blue light — police/fire/customs press releases) — is a
// NATIONWIDE aggregator of real German police press releases (unlike
// France's actu17.fr or Spain's La Vanguardia, which are single
// outlets), confirmed live with genuine items from several different
// states (Rheinland-Pfalz, Bayern, Nordrhein-Westfalen, Niedersachsen)
// in one pull. No `<category>` tag on this feed (confirmed live, always
// empty) — no exclusion list needed the way ES/FR's feeds required.
//
// Unlike France, where the département name itself routinely appeared
// in article text, German press releases name the CITY/Kreis
// ("Meerbusch", "Augsburg"), not the Bundesland — so resolving a
// Bundesland requires a city->state lookup. CITY_TO_BUNDESLAND below is
// derived from BKA's own Kreis-level PKS file (all ~400 Kreise/
// independent cities, each carrying an official Gemeindeschlüssel whose
// leading 1-2 digits ARE the standard Land code) — not a separate,
// unofficial city list. 21 of the ~400 names are duplicated (e.g.
// "München" the independent city and the separately-listed "München"
// rural Kreis around it) — confirmed live that every one of these
// duplicate pairs shares the SAME Bundesland, so collapsing them into
// one map entry causes no cross-state misattribution.
//
// German press releases follow a structured wire-service dateline —
// every `<description>` observed starts with "Stadtname (ots) - ..."
// ("ots" = Original-Text-Service) — confirmed live across a real pull.
// extractDateline() reads this directly rather than relying purely on
// free-text scanning, which is both more precise and (being a
// non-recursive substring match at a fixed position) cheaper than
// findAreaName's own longest-match scan; findAreaName is still used as
// a fallback for the — presumably rare — item that doesn't follow the
// dateline convention, or whose dateline city isn't one of the ~400 in
// this map (many small towns named in a press release aren't
// themselves a Kreis, e.g. "Meerbusch" — a town inside Rhein-Kreis
// Neuss — seen live in a real item with no Kreis name anywhere in the
// text; skipped rather than given an invented precision, same rule
// every other country's news adapter already follows).
export const CITY_TO_BUNDESLAND: Record<string, string> = {
  "Aachen": "Nordrhein-Westfalen",
  "Ahrweiler": "Rheinland-Pfalz",
  "Aichach-Friedberg": "Bayern",
  "Alb-Donau-Kreis": "Baden-Württemberg",
  "Altenburger Land": "Thüringen",
  "Altenkirchen (Westerwald)": "Rheinland-Pfalz",
  "Altmarkkreis Salzwedel": "Sachsen-Anhalt",
  "Altötting": "Bayern",
  "Alzey-Worms": "Rheinland-Pfalz",
  "Amberg": "Bayern",
  "Amberg-Sulzbach": "Bayern",
  "Ammerland": "Niedersachsen",
  "Anhalt-Bitterfeld": "Sachsen-Anhalt",
  "Ansbach": "Bayern",
  "Aschaffenburg": "Bayern",
  "Augsburg": "Bayern",
  "Aurich": "Niedersachsen",
  "Bad Dürkheim": "Rheinland-Pfalz",
  "Bad Kissingen": "Bayern",
  "Bad Kreuznach": "Rheinland-Pfalz",
  "Bad Tölz-Wolfratshausen": "Bayern",
  "Baden-Baden": "Baden-Württemberg",
  "Bamberg": "Bayern",
  "Barnim": "Brandenburg",
  "Bautzen": "Sachsen",
  "Bayreuth": "Bayern",
  "Berchtesgadener Land": "Bayern",
  "Bergstraße": "Hessen",
  "Berlin": "Berlin",
  "Bernkastel-Wittlich": "Rheinland-Pfalz",
  "Biberach": "Baden-Württemberg",
  "Bielefeld": "Nordrhein-Westfalen",
  "Birkenfeld": "Rheinland-Pfalz",
  "Böblingen": "Baden-Württemberg",
  "Bochum": "Nordrhein-Westfalen",
  "Bodenseekreis": "Baden-Württemberg",
  "Bonn": "Nordrhein-Westfalen",
  "Börde": "Sachsen-Anhalt",
  "Borken": "Nordrhein-Westfalen",
  "Bottrop": "Nordrhein-Westfalen",
  "Brandenburg an der Havel": "Brandenburg",
  "Braunschweig": "Niedersachsen",
  "Breisgau-Hochschwarzwald": "Baden-Württemberg",
  "Bremen": "Bremen",
  "Bremerhaven": "Bremen",
  "Burgenlandkreis": "Sachsen-Anhalt",
  "Calw": "Baden-Württemberg",
  "Celle": "Niedersachsen",
  "Cham": "Bayern",
  "Chemnitz": "Sachsen",
  "Cloppenburg": "Niedersachsen",
  "Coburg": "Bayern",
  "Cochem-Zell": "Rheinland-Pfalz",
  "Coesfeld": "Nordrhein-Westfalen",
  "Cottbus": "Brandenburg",
  "Cuxhaven": "Niedersachsen",
  "Dachau": "Bayern",
  "Dahme-Spreewald": "Brandenburg",
  "Darmstadt": "Hessen",
  "Darmstadt-Dieburg": "Hessen",
  "Deggendorf": "Bayern",
  "Delmenhorst": "Niedersachsen",
  "Dessau-Roßlau": "Sachsen-Anhalt",
  "Diepholz": "Niedersachsen",
  "Dillingen a.d.Donau": "Bayern",
  "Dingolfing-Landau": "Bayern",
  "Dithmarschen": "Schleswig-Holstein",
  "Donau-Ries": "Bayern",
  "Donnersbergkreis": "Rheinland-Pfalz",
  "Dortmund": "Nordrhein-Westfalen",
  "Dresden": "Sachsen",
  "Duisburg": "Nordrhein-Westfalen",
  "Düren": "Nordrhein-Westfalen",
  "Düsseldorf": "Nordrhein-Westfalen",
  "Ebersberg": "Bayern",
  "Eichsfeld": "Thüringen",
  "Eichstätt": "Bayern",
  "Eifelkreis Bitburg-Prüm": "Rheinland-Pfalz",
  "Elbe-Elster": "Brandenburg",
  "Emden": "Niedersachsen",
  "Emmendingen": "Baden-Württemberg",
  "Emsland": "Niedersachsen",
  "Ennepe-Ruhr-Kreis": "Nordrhein-Westfalen",
  "Enzkreis": "Baden-Württemberg",
  "Erding": "Bayern",
  "Erfurt": "Thüringen",
  "Erlangen": "Bayern",
  "Erlangen-Höchstadt": "Bayern",
  "Erzgebirgskreis": "Sachsen",
  "Essen": "Nordrhein-Westfalen",
  "Esslingen": "Baden-Württemberg",
  "Euskirchen": "Nordrhein-Westfalen",
  "Flensburg": "Schleswig-Holstein",
  "Forchheim": "Bayern",
  "Frankenthal (Pfalz)": "Rheinland-Pfalz",
  "Frankfurt (Oder)": "Brandenburg",
  "Frankfurt am Main": "Hessen",
  "Freiburg im Breisgau": "Baden-Württemberg",
  "Freising": "Bayern",
  "Freudenstadt": "Baden-Württemberg",
  "Freyung-Grafenau": "Bayern",
  "Friesland": "Niedersachsen",
  "Fulda": "Hessen",
  "Fürstenfeldbruck": "Bayern",
  "Fürth": "Bayern",
  "Garmisch-Partenkirchen": "Bayern",
  "Gelsenkirchen": "Nordrhein-Westfalen",
  "Gera": "Thüringen",
  "Germersheim": "Rheinland-Pfalz",
  "Gießen": "Hessen",
  "Gifhorn": "Niedersachsen",
  "Göppingen": "Baden-Württemberg",
  "Görlitz": "Sachsen",
  "Goslar": "Niedersachsen",
  "Gotha": "Thüringen",
  "Göttingen": "Niedersachsen",
  "Grafschaft Bentheim": "Niedersachsen",
  "Greiz": "Thüringen",
  "Groß-Gerau": "Hessen",
  "Günzburg": "Bayern",
  "Gütersloh": "Nordrhein-Westfalen",
  "Hagen": "Nordrhein-Westfalen",
  "Halle (Saale)": "Sachsen-Anhalt",
  "Hamburg": "Hamburg",
  "Hameln-Pyrmont": "Niedersachsen",
  "Hamm": "Nordrhein-Westfalen",
  "Harburg": "Niedersachsen",
  "Harz": "Sachsen-Anhalt",
  "Haßberge": "Bayern",
  "Havelland": "Brandenburg",
  "Heidekreis": "Niedersachsen",
  "Heidelberg": "Baden-Württemberg",
  "Heidenheim": "Baden-Württemberg",
  "Heilbronn": "Baden-Württemberg",
  "Heinsberg": "Nordrhein-Westfalen",
  "Helmstedt": "Niedersachsen",
  "Herford": "Nordrhein-Westfalen",
  "Herne": "Nordrhein-Westfalen",
  "Hersfeld-Rotenburg": "Hessen",
  "Herzogtum Lauenburg": "Schleswig-Holstein",
  "Hildburghausen": "Thüringen",
  "Hildesheim": "Niedersachsen",
  "Hochsauerlandkreis": "Nordrhein-Westfalen",
  "Hochtaunuskreis": "Hessen",
  "Hof": "Bayern",
  "Hohenlohekreis": "Baden-Württemberg",
  "Holzminden": "Niedersachsen",
  "Höxter": "Nordrhein-Westfalen",
  "Ilm-Kreis": "Thüringen",
  "Ingolstadt": "Bayern",
  "Jena": "Thüringen",
  "Jerichower Land": "Sachsen-Anhalt",
  "Kaiserslautern": "Rheinland-Pfalz",
  "Karlsruhe": "Baden-Württemberg",
  "Kassel": "Hessen",
  "Kaufbeuren": "Bayern",
  "Kelheim": "Bayern",
  "Kempten (Allgäu)": "Bayern",
  "Kiel": "Schleswig-Holstein",
  "Kitzingen": "Bayern",
  "Kleve": "Nordrhein-Westfalen",
  "Koblenz": "Rheinland-Pfalz",
  "Köln": "Nordrhein-Westfalen",
  "Konstanz": "Baden-Württemberg",
  "Krefeld": "Nordrhein-Westfalen",
  "Kronach": "Bayern",
  "Kulmbach": "Bayern",
  "Kusel": "Rheinland-Pfalz",
  "Kyffhäuserkreis": "Thüringen",
  "Lahn-Dill-Kreis": "Hessen",
  "Landau in der Pfalz": "Rheinland-Pfalz",
  "Landkreis Rostock": "Mecklenburg-Vorpommern",
  "Landsberg am Lech": "Bayern",
  "Landshut": "Bayern",
  "Leer": "Niedersachsen",
  "Leipzig": "Sachsen",
  "Leverkusen": "Nordrhein-Westfalen",
  "Lichtenfels": "Bayern",
  "Limburg-Weilburg": "Hessen",
  "Lindau (Bodensee)": "Bayern",
  "Lippe": "Nordrhein-Westfalen",
  "Lörrach": "Baden-Württemberg",
  "Lübeck": "Schleswig-Holstein",
  "Lüchow-Dannenberg": "Niedersachsen",
  "Ludwigsburg": "Baden-Württemberg",
  "Ludwigshafen am Rhein": "Rheinland-Pfalz",
  "Ludwigslust-Parchim": "Mecklenburg-Vorpommern",
  "Lüneburg": "Niedersachsen",
  "Magdeburg": "Sachsen-Anhalt",
  "Main-Kinzig-Kreis": "Hessen",
  "Main-Spessart": "Bayern",
  "Main-Tauber-Kreis": "Baden-Württemberg",
  "Main-Taunus-Kreis": "Hessen",
  "Mainz": "Rheinland-Pfalz",
  "Mainz-Bingen": "Rheinland-Pfalz",
  "Mannheim": "Baden-Württemberg",
  "Mansfeld-Südharz": "Sachsen-Anhalt",
  "Marburg-Biedenkopf": "Hessen",
  "Märkisch-Oderland": "Brandenburg",
  "Märkischer Kreis": "Nordrhein-Westfalen",
  "Mayen-Koblenz": "Rheinland-Pfalz",
  "Mecklenburgische Seenplatte": "Mecklenburg-Vorpommern",
  "Meißen": "Sachsen",
  "Memmingen": "Bayern",
  "Merzig-Wadern": "Saarland",
  "Mettmann": "Nordrhein-Westfalen",
  "Miesbach": "Bayern",
  "Miltenberg": "Bayern",
  "Minden-Lübbecke": "Nordrhein-Westfalen",
  "Mittelsachsen": "Sachsen",
  "Mönchengladbach": "Nordrhein-Westfalen",
  "Mühldorf a.Inn": "Bayern",
  "Mülheim an der Ruhr": "Nordrhein-Westfalen",
  "München": "Bayern",
  "Münster": "Nordrhein-Westfalen",
  "Neckar-Odenwald-Kreis": "Baden-Württemberg",
  "Neu-Ulm": "Bayern",
  "Neuburg-Schrobenhausen": "Bayern",
  "Neumarkt i.d.OPf.": "Bayern",
  "Neumünster": "Schleswig-Holstein",
  "Neunkirchen": "Saarland",
  "Neustadt a.d.Aisch-Bad Windsheim": "Bayern",
  "Neustadt a.d.Waldnaab": "Bayern",
  "Neustadt an der Weinstraße": "Rheinland-Pfalz",
  "Neuwied": "Rheinland-Pfalz",
  "Nienburg (Weser)": "Niedersachsen",
  "Nordfriesland": "Schleswig-Holstein",
  "Nordhausen": "Thüringen",
  "Nordsachsen": "Sachsen",
  "Nordwestmecklenburg": "Mecklenburg-Vorpommern",
  "Northeim": "Niedersachsen",
  "Nürnberg": "Bayern",
  "Nürnberger Land": "Bayern",
  "Oberallgäu": "Bayern",
  "Oberbergischer Kreis": "Nordrhein-Westfalen",
  "Oberhausen": "Nordrhein-Westfalen",
  "Oberhavel": "Brandenburg",
  "Oberspreewald-Lausitz": "Brandenburg",
  "Odenwaldkreis": "Hessen",
  "Oder-Spree": "Brandenburg",
  "Offenbach": "Hessen",
  "Offenbach am Main": "Hessen",
  "Oldenburg": "Niedersachsen",
  "Oldenburg (Oldenburg)": "Niedersachsen",
  "Olpe": "Nordrhein-Westfalen",
  "Ortenaukreis": "Baden-Württemberg",
  "Osnabrück": "Niedersachsen",
  "Ostalbkreis": "Baden-Württemberg",
  "Ostallgäu": "Bayern",
  "Osterholz": "Niedersachsen",
  "Ostholstein": "Schleswig-Holstein",
  "Ostprignitz-Ruppin": "Brandenburg",
  "Paderborn": "Nordrhein-Westfalen",
  "Passau": "Bayern",
  "Peine": "Niedersachsen",
  "Pfaffenhofen a.d.Ilm": "Bayern",
  "Pforzheim": "Baden-Württemberg",
  "Pinneberg": "Schleswig-Holstein",
  "Pirmasens": "Rheinland-Pfalz",
  "Plön": "Schleswig-Holstein",
  "Potsdam": "Brandenburg",
  "Potsdam-Mittelmark": "Brandenburg",
  "Prignitz": "Brandenburg",
  "Rastatt": "Baden-Württemberg",
  "Ravensburg": "Baden-Württemberg",
  "Recklinghausen": "Nordrhein-Westfalen",
  "Regen": "Bayern",
  "Regensburg": "Bayern",
  "Region Hannover": "Niedersachsen",
  "Regionalverband Saarbrücken": "Saarland",
  "Rems-Murr-Kreis": "Baden-Württemberg",
  "Remscheid": "Nordrhein-Westfalen",
  "Rendsburg-Eckernförde": "Schleswig-Holstein",
  "Reutlingen": "Baden-Württemberg",
  "Rhein-Erft-Kreis": "Nordrhein-Westfalen",
  "Rhein-Hunsrück-Kreis": "Rheinland-Pfalz",
  "Rhein-Kreis Neuss": "Nordrhein-Westfalen",
  "Rhein-Lahn-Kreis": "Rheinland-Pfalz",
  "Rhein-Neckar-Kreis": "Baden-Württemberg",
  "Rhein-Pfalz-Kreis": "Rheinland-Pfalz",
  "Rhein-Sieg-Kreis": "Nordrhein-Westfalen",
  "Rheingau-Taunus-Kreis": "Hessen",
  "Rheinisch-Bergischer Kreis": "Nordrhein-Westfalen",
  "Rhön-Grabfeld": "Bayern",
  "Rosenheim": "Bayern",
  "Rostock": "Mecklenburg-Vorpommern",
  "Rotenburg (Wümme)": "Niedersachsen",
  "Roth": "Bayern",
  "Rottal-Inn": "Bayern",
  "Rottweil": "Baden-Württemberg",
  "Saale-Holzland-Kreis": "Thüringen",
  "Saale-Orla-Kreis": "Thüringen",
  "Saalekreis": "Sachsen-Anhalt",
  "Saalfeld-Rudolstadt": "Thüringen",
  "Saarlouis": "Saarland",
  "Saarpfalz-Kreis": "Saarland",
  "Sächsische Schweiz-Osterzgebirge": "Sachsen",
  "Salzgitter": "Niedersachsen",
  "Salzlandkreis": "Sachsen-Anhalt",
  "Schaumburg": "Niedersachsen",
  "Schleswig-Flensburg": "Schleswig-Holstein",
  "Schmalkalden-Meiningen": "Thüringen",
  "Schwabach": "Bayern",
  "Schwäbisch Hall": "Baden-Württemberg",
  "Schwalm-Eder-Kreis": "Hessen",
  "Schwandorf": "Bayern",
  "Schwarzwald-Baar-Kreis": "Baden-Württemberg",
  "Schweinfurt": "Bayern",
  "Schwerin": "Mecklenburg-Vorpommern",
  "Segeberg": "Schleswig-Holstein",
  "Siegen-Wittgenstein": "Nordrhein-Westfalen",
  "Sigmaringen": "Baden-Württemberg",
  "Soest": "Nordrhein-Westfalen",
  "Solingen": "Nordrhein-Westfalen",
  "Sömmerda": "Thüringen",
  "Sonneberg": "Thüringen",
  "Speyer": "Rheinland-Pfalz",
  "Spree-Neiße": "Brandenburg",
  "St. Wendel": "Saarland",
  "Stade": "Niedersachsen",
  "Starnberg": "Bayern",
  "Steinburg": "Schleswig-Holstein",
  "Steinfurt": "Nordrhein-Westfalen",
  "Stendal": "Sachsen-Anhalt",
  "Stormarn": "Schleswig-Holstein",
  "Straubing": "Bayern",
  "Straubing-Bogen": "Bayern",
  "Stuttgart": "Baden-Württemberg",
  "Südliche Weinstraße": "Rheinland-Pfalz",
  "Südwestpfalz": "Rheinland-Pfalz",
  "Suhl": "Thüringen",
  "Teltow-Fläming": "Brandenburg",
  "Tirschenreuth": "Bayern",
  "Traunstein": "Bayern",
  "Trier": "Rheinland-Pfalz",
  "Trier-Saarburg": "Rheinland-Pfalz",
  "Tübingen": "Baden-Württemberg",
  "Tuttlingen": "Baden-Württemberg",
  "Uckermark": "Brandenburg",
  "Uelzen": "Niedersachsen",
  "Ulm": "Baden-Württemberg",
  "Unna": "Nordrhein-Westfalen",
  "Unstrut-Hainich-Kreis": "Thüringen",
  "Unterallgäu": "Bayern",
  "Vechta": "Niedersachsen",
  "Verden": "Niedersachsen",
  "Viersen": "Nordrhein-Westfalen",
  "Vogelsbergkreis": "Hessen",
  "Vogtlandkreis": "Sachsen",
  "Vorpommern-Greifswald": "Mecklenburg-Vorpommern",
  "Vorpommern-Rügen": "Mecklenburg-Vorpommern",
  "Vulkaneifel": "Rheinland-Pfalz",
  "Waldeck-Frankenberg": "Hessen",
  "Waldshut": "Baden-Württemberg",
  "Warendorf": "Nordrhein-Westfalen",
  "Wartburgkreis": "Thüringen",
  "Weiden i.d.OPf.": "Bayern",
  "Weilheim-Schongau": "Bayern",
  "Weimar": "Thüringen",
  "Weimarer Land": "Thüringen",
  "Weißenburg-Gunzenhausen": "Bayern",
  "Werra-Meißner-Kreis": "Hessen",
  "Wesel": "Nordrhein-Westfalen",
  "Wesermarsch": "Niedersachsen",
  "Westerwaldkreis": "Rheinland-Pfalz",
  "Wetteraukreis": "Hessen",
  "Wiesbaden": "Hessen",
  "Wilhelmshaven": "Niedersachsen",
  "Wittenberg": "Sachsen-Anhalt",
  "Wittmund": "Niedersachsen",
  "Wolfenbüttel": "Niedersachsen",
  "Wolfsburg": "Niedersachsen",
  "Worms": "Rheinland-Pfalz",
  "Wunsiedel i.Fichtelgebirge": "Bayern",
  "Wuppertal": "Nordrhein-Westfalen",
  "Würzburg": "Bayern",
  "Zollernalbkreis": "Baden-Württemberg",
  "Zweibrücken": "Rheinland-Pfalz",
  "Zwickau": "Sachsen",
};

import { classifyDeNews } from "./de_news_classifier.ts";
import { parseFeedItems } from "../../rss.ts";
import { findAreaName, stripAccentsLower } from "./geo_text_match_generic.ts";
import { computeConfidenceScore, defaultLocationConfidence } from "../../confidence.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
} from "../types.ts";

const FEED_URL = "https://www.presseportal.de/rss/blaulicht.rss2";
const CITY_NAMES = Object.keys(CITY_TO_BUNDESLAND);

// Matches the wire-service dateline at the start of a description, e.g.
// "Meerbusch (ots) - In der Zeit von..." -> "Meerbusch". See file header.
const DATELINE_RE = /^\s*([^(]{1,50}?)\s*\(ots\)/;

function resolveBundesland(title: string, description: string): string | undefined {
  const datelineMatch = DATELINE_RE.exec(description);
  const dateline = datelineMatch?.[1]?.trim();
  if (dateline && CITY_TO_BUNDESLAND[dateline]) return CITY_TO_BUNDESLAND[dateline];

  const matchedCity = findAreaName(stripAccentsLower(`${title} ${description}`), CITY_NAMES);
  return matchedCity ? CITY_TO_BUNDESLAND[matchedCity] : undefined;
}

export class DeNewsAdapter implements SecuritySourceAdapter {
  source(): SecuritySource {
    return {
      countryCode: "DE",
      name: "Presseportal — Blaulicht",
      organisation: "news aktuell GmbH (Presseportal)",
      sourceType: "news",
      sourceUrl: FEED_URL,
      adapterName: "DeNewsAdapter",
      adapterVersion: "0.1.0",
      refreshFrequency: "every 4 hours",
    };
  }

  async fetch(_since?: Date): Promise<RawSecurityRecord[]> {
    const res = await fetch(FEED_URL);
    if (!res.ok) {
      throw new Error(`Presseportal Blaulicht feed request failed: ${res.status}`);
    }
    return [
      {
        sourceRecordId: "presseportal-blaulicht-feed",
        payload: await res.text(),
        fetchedAt: new Date().toISOString(),
      },
    ];
  }

  async normalize(record: RawSecurityRecord): Promise<SecurityEvent[]> {
    const xml = record.payload as string;
    const items = parseFeedItems(xml);
    const stateLocationConfidence = defaultLocationConfidence("STATE");

    const events: SecurityEvent[] = [];
    for (const item of items) {
      const mapped = classifyDeNews(item.title, item.subtitle);
      if (!mapped) continue;
      const [eventCategory, eventType, severity] = mapped;

      const bundesland = resolveBundesland(item.title, item.subtitle);
      if (!bundesland) continue;

      const occurredAt = item.pubDate ? new Date(item.pubDate) : undefined;
      if (!occurredAt || Number.isNaN(occurredAt.getTime())) continue;

      events.push({
        countryCode: "DE",
        sourceRecordId: item.guid,
        sourceType: "news",
        eventCategory: eventCategory as SecurityEvent["eventCategory"],
        eventType,
        occurredAt: occurredAt.toISOString(),
        publishedAt: occurredAt.toISOString(),
        geoPrecision: "STATE",
        locationConfidence: stateLocationConfidence,
        district: bundesland,
        occurrenceCount: 1,
        severity,
        confidenceScore: computeConfidenceScore({
          reliabilityGrade: "established_local_journalism",
          locationConfidence: stateLocationConfidence,
        }),
        rawPayload: { title: item.title, subtitle: item.subtitle, link: item.link },
      });
    }
    return events;
  }

  async healthCheck(): Promise<SourceHealth> {
    try {
      const res = await fetch(FEED_URL);
      if (!res.ok) {
        return { status: "RED", message: `HTTP ${res.status} on feed` };
      }
      const xml = await res.text();
      const items = parseFeedItems(xml);
      if (items.length === 0) {
        return { status: "RED", message: "No <item> entries found — feed markup may have changed" };
      }
      return { status: "GREEN", lastDataDate: new Date().toISOString().slice(0, 10) };
    } catch (e) {
      return { status: "RED", message: String(e) };
    }
  }
}
