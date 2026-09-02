// BeeAware Brasil roadmap — scheduled ingestion job.
//
// Called by pg_cron (see supabase/migrations/20260821130000_security_
// intelligence_ingestion.sql) once per source at its documented cadence,
// or manually with a specific `adapter` name (or none, to run everything)
// for testing. For each adapter: healthCheck() -> upsert its
// security_sources row -> if healthy, fetch() -> persist raw_events
// (BeeAware Global blueprint Phase 0 — see persistRawEvents()) ->
// normalize() -> upsert into geo_areas (territorial adapters),
// security_events (event adapters), or travel_advisories (advisory
// adapters — BeeAware Global blueprint Phase 1 part 2; a distinct entity
// from SecurityEvent, see adapters/types.ts's TravelAdvisory comment).
//
// Honest current state: IbgeAdapter's normalize() is fully implemented,
// so its scheduled run genuinely writes geo_areas rows. PrfAccidentsAdapter,
// RjIspAdapter, PaSegupAdapter, MgAdapter (Phase 2 — Minas Gerais),
// EsSespAdapter (Phase 2 — Espírito Santo, EXACT-precision with real
// coordinates), AlAdapter (Phase 2 — Alagoas, real per-occurrence unique
// IDs), MtAdapter (Phase 2 — Mato Grosso, real per-occurrence data, but
// genuinely narrower in SCOPE than every other state adapter: every row
// is an occurrence with a female victim specifically, Lei Maria da Penha
// and related statutes — not general crime; see mt_sesp.ts's header for
// why that's the ceiling of what MT's open-data portal publishes) and
// UnodcAdapter (BeeAware Global blueprint Phase 1 — the first
// adapter that isn't Brazil-specific) are also fully real (verified
// against their live sources — see each file's header) and
// write actual security_events rows. FcdoAdapter (Phase 1 part 2) is also
// fully real and writes travel_advisories rows instead. RsSspAdapter
// (Phase 2 hardening) is real too but genuinely flaky — its source file is
// right at this Edge Function's memory ceiling (~12.5% real-mode success
// per attempt, measured), so it's scheduled daily rather than monthly and
// leans on idempotent upserts to retry safely (see
// rs_ssp_cron_daily.sql's comment). SinespAdapter's parsing logic is now
// genuinely real too (a real bulk-download URL was found — not the
// dados.gov.br REST API, whose every listed resource points at a dead
// domain, but a file hosted directly on gov.br, found via web search —
// and real per-occurrence-cell parsing verified locally against the
// actual file), but it is NOT REGISTERED below: fetch() has failed 3/3
// real attempts in production. See sinesp.ts's own header for the full
// diagnosis, including a likely shared root cause with SpVehicleAdapter
// (also built, also not registered, see sp_vehicle.ts). Its data got into
// security_events anyway, once (2026-08-25): a non-Edge-Function machine
// doesn't hit whatever the Edge Function's timing ceiling is, so the same
// bancovde-2026.xlsx GET that fails from here completed in seconds from
// there — see supabase/migrations/20260825150000_sinesp_manual_
// population.sql for the one-off population this produced (3,401 real
// events, all 27 UFs, verified against the live file). Still not on any
// schedule — that migration doesn't change why fetch() fails from this
// Edge Function, so this data will not refresh on its own. RenaestAdapter
// still has working fetch() (real discovery against its live source) but
// normalize() returns [] (see the adapter's file header for why) — so
// its scheduled runs today only keep security_sources health metadata
// current. That's not nothing (it's exactly what the roadmap's source-
// health dashboard, section 12.5, is meant to show), but it's not event
// data yet either. FbspAnuarioAdapter (added 2026-08-25) is also fully
// real — a plain unauthenticated XLSX download, no session/CSRF/Power-BI
// wall like PA-SEGUP or the SSP-SP dead end documented in its own file
// header — and writes actual security_events rows, but at geo_precision
// 'STATE' only (annual totals per UF from the FBSP's own yearbook, not
// per-occurrence or per-municipality): it fills in the 18 states that had
// zero coverage from every other adapter here, but coarser than all of
// them. See fbsp_anuario.ts's header for the full sourcing story.
// PeAdapter (added 2026-08-28, Phase 8 second-wave states) is also fully
// real — a plain unauthenticated XLSX download off sds.pe.gov.br, no
// session/CSRF/WAF gate — and writes actual security_events rows at
// geo_precision 'MUNICIPALITY' (per-victim microdata, no coordinates in
// the source). See pe_sds.ts's header for why CE and BA, tried first for
// this wave, aren't adapters at all / aren't registered.
// GoSspAdapter (added 2026-08-30, Phase 8 second-wave states) is also
// fully real, but a different shape from every other PDF-only dead end
// documented above (BA/CE/SP): SSP-GO's estatisticas page links one small
// PDF per year (2018-2025), each a single clean table of 15 crime
// "naturezas" x 12 months, not just an annual total — genuinely per-month
// state-level data, one tier finer than FbspAnuarioAdapter's annual-only
// coverage for GO. Parsed with a hand-written, dependency-free PDF text-
// with-position extractor (see go_ssp.ts's own header) rather than a
// library — two real dead ends came first: this session's own generic
// PDF-to-text tool silently glues together the last two columns of any
// row whose December and TOTAL values are both short (a content-stream
// artifact, not fixable by better regex), and pdfjs-dist parsed
// correctly but failed at actual `supabase functions deploy` time with
// "Module not found ... build/Release/canvas.node?target=denonext" — a
// native Node canvas addon esm.sh can't resolve for Deno. The custom
// parser (zlib-inflate each content stream via the platform's own
// DecompressionStream, then read off this source's Tm-per-cell text
// positioning) has no such dependency and is verified against all three
// years read (2018/2024/2025: 15/15 rows, every row's checksum against
// its own printed TOTAL matches) plus a real `supabase functions deploy`
// that succeeded.
// MaSspAdapter (added 2026-08-30, Phase 8 second-wave states) is real but
// deliberately narrower than every state adapter above: SSP-MA has
// exactly one statistics page (confirmed via its own WP REST API — no
// PDF bulletins, no CSV/XLSX, no other region), and it only covers
// Grande São Luís (4 municipalities, not the whole state) and only CVLI
// ("Crime Violento Letal Intencional" — homicídio doloso, feminicídio,
// latrocínio, lesão seguida de morte), same closed-category framing
// SSP-BA/SEDS-AL use elsewhere here. dados.ma.gov.br (state open-data
// portal) has zero public-security datasets at all — checked directly.
// Real upside: it's a plain WordPress/Elementor HTML <table> with each
// column's exact "Mmm/YY" label spelled out in its own header row — no
// binary parsing needed, the first HTML-table (rather than CSV/XLSX/PDF)
// adapter in this directory — and each row is already scoped to one
// named municipality, so geo_precision is 'MUNICIPALITY', a tier finer
// than GoSspAdapter/FbspAnuarioAdapter's state-level rows. One real
// parsing trap found and fixed during development: a couple of month
// headers are split across two adjacent <strong> tags with no source
// whitespace (e.g. "Jul/26" as "<strong>J</strong><strong>ul/26</strong>"
// ) — stripping tags to a space instead of "" turned that into "J ul/26"
// and silently dropped/shifted a whole column; verified against the live
// page afterward (11 of 12 months match the source's own printed CVLI
// total exactly — the 12th is the source's own total row disagreeing
// with its own displayed rows by 1, not a parsing bug on this side).
// MsSejuspAdapter (added 2026-08-30, alphabetical sweep of the remaining
// states) is a real win: dados.ms.gov.br is a genuinely populated CKAN
// portal (unlike dados.al.gov.br's exotic /catalogo/ base path) with a
// dedicated SEJUSP organisation, and its CVLI dataset already carries a
// real per-case CÓDIGO IBGE column — no IBGE-name-matching step needed at
// all, a first among this project's CVLI-style adapters. See
// ms_sejusp.ts's own header for a real classification bug found and fixed
// while building this: FATO AGRUPADO concatenates every tag on a case, so
// whole-string regex (this project's usual CLASSIFY_RULES shape) can
// cross-match keywords belonging to two unrelated tags on the same row —
// fixed by splitting into individual tags first and matching by set
// membership instead. AC (Acre — Power BI dashboards only, no exportable
// data) was tried and is a documented dead end (see pe_sds.ts's header,
// alongside CE/BA); AM and AP timed out at the TCP level from this
// environment specifically (DNS resolves, every other .gov.br host tested
// fine) rather than rejecting the request the way CE's WAF or BA's broken
// cert do, so they're left unattempted rather than marked as permanent
// dead ends — worth retrying from a different network path later.
// PrSespAdapter (added 2026-08-30, alphabetical sweep of the remaining
// states) is real but has a genuine, deliberately-accepted limitation:
// PB was a WAF dead end, PI had a real public Metabase API that's broken
// server-side (see pe_sds.ts's header for both), but PR's own quarterly
// crime PDF (13 tables x 23 AISPs x 2 years x 12 months — the richest
// per-region breakdown found in this sweep) has no stable, crawlable
// page linking the current report at all; the URL was only found via a
// Google site: search and is pinned as a snapshot that goes stale every
// quarter with no automated way to refresh it (see pr_sesp.ts's own
// header for the full investigation and the update procedure). Also
// geo_precision is STATE, not MUNICIPALITY: AISP is a multi-municipality
// police command area, and PR's own AISP boundaries aren't loaded into
// geo_areas (only RJ's AISP/RISP/CISP geometry is). Only 8 of the PDF's
// 13 tables are ingested — see the file header for why the 2 broad
// Penal-Code-chapter aggregates, the public-administration-crime table,
// the generic "other crimes" bucket, and the vehicle-recovery table
// (a positive outcome, not an incident) are all skipped.
// RrPcrrAdapter (added 2026-08-31, alphabetical sweep of the remaining
// states) is real and per-victim: policiacivil.rr.gov.br publishes 9 real
// XLSX datasets via a plain WP Download Manager link, no auth/WAF gate.
// Found and fixed a real performance bug in xlsx_lite.ts's shared row
// regex while building this one: the source file's nominal 1,046,342
// <row> elements are almost all empty self-closing `<row .../>` padding
// (an Excel autoFilter artifact — only ~1,808 rows are real), and
// forEachRow's lazy `(.*?)</row>` regex catastrophically backtracks
// across that padding looking for the next real closing tag (confirmed
// hanging past 90s in a timing test). Rather than touch the shared
// reader (used by 8 other adapters, never tested against this failure
// shape), rr_pcrr.ts strips the padding itself before applying the same
// buildCellRegex/parseRowCells primitives xlsx_lite.ts already exports —
// see that file's own header for the full diagnosis.
// UkPoliceAdapter (added 2026-08-31) — the first area-choropleth source
// for a non-Brazil country. data.police.uk's crimes-street API was already
// used live from the Flutter client for point pins (uk_police_api.dart)
// but never persisted server-side, so there was no aggregate to colour an
// area with, unlike RJ/SP's CISP/DP choropleth. Verified live: the same
// API accepts a `poly` param (an arbitrary boundary) instead of
// point+radius, queried per Police Force (43 England & Wales forces, real
// boundaries from ONS Open Geography's "Police Force Areas (December
// 2023) EW BGC", geometry migration 20260831120000). Aggregates per
// (force, month, source category) rather than persisting individual
// crimes —
// same shape as RjIspAdapter — and links to its geo_areas polygon via the
// same name-match trigger (widened for 'POLICE_FORCE' by 20260831130000),
// not a spatial join. Northern Ireland is a known, documented gap: it's
// in data.police.uk's own force list but has no boundary in this EW-only
// ONS dataset. A second, more consequential gap found live: `poly`
// deterministically 503s for the 13 highest crime-volume forces —
// including Metropolitan Police (London) itself — regardless of
// concurrency or retries; isolated down to a result-size ceiling on that
// endpoint, not an area/vertex limit. Those 13 forces are simply skipped
// (no data rather than an undercount), leaving ~30 of 43 forces with real
// colour on the choropleth today. See uk_police.ts's own header for the
// full sourcing story, the two independent polygon simplifications (query
// vs. display), and the category-mapping caveats (data.police.uk's
// "violent-crime" bundles
// everything from common assault to homicide with no way to split it).
// PtCrimeAdapter (added 2026-09-02) — Portugal concelho-level choropleth,
// the second non-Brazil area source after the UK, and finer-grained than
// it (308 concelhos vs. 43 police forces). Unlike UkPoliceAdapter, there's
// no per-area query limit to work around: criminalidade.pt (a third-party
// static mirror of official DGPJ/INE/PORDATA statistics, not the
// government portal itself) publishes the whole country's crime series
// and concelho geometry as two plain JSON files, so fetch() makes exactly
// two HTTP requests total. The real complexity was picking which of the
// 19 published categories are safe to sum without double-counting: only 8
// ("crimes específicos" minus one INE-methodology duplicate) are mutually
// exclusive — the official "Total" and the Penal Code chapter breakdown
// were both rejected for this reason (see pt_crime.ts's header for the
// full reasoning). Also unlike every other adapter here, DGPJ only
// publishes annually — PtCrimeAdapter ingests just the single latest
// available year, both because that's all a per-run ingestion needs and
// because a full historical backfill would be erased the following month
// by this session's own new security_events retention cron.
// EsCrimeAdapter (added 2026-09-03) — Spain, third non-Brazil area source.
// georiesgo.com mirrors the Ministerio del Interior's own Portal
// Estadístico de Criminalidad as a single JSON with geometry AND crime
// counts combined (unlike Portugal's three-file split). Coverage is
// municipio-level but only for the 427 municipios over ~20,000
// inhabitants — that's the Ministerio's own real publication limit below
// province level, not a gap this adapter introduces; there's no
// province-level file on this source, so full national coverage (like
// UkPoliceAdapter's 43 forces) wasn't available without much more work,
// and municipio-level was the trade-off the user chose explicitly. Only
// 11 of 16 published crime fields are safe to sum without double-
// counting (verified by script against all 427 municipios, zero
// exceptions) — see es_crime.ts's header for the full partition proof.
// Cybercrime fields are excluded (no taxonomy bucket, not a physical-
// safety risk). The Ministerio's own balance is a year-to-date
// cumulative figure, not a closed calendar year like Portugal's, so
// sourceRecordId is keyed by year only — a later, more complete balance
// for the same year replaces the earlier one instead of double-counting.
// MadridAccidentsAdapter (added 2026-09-05) — the actual answer to "why
// can't PT/ES have real per-incident hexagon pins like Brazil/UK": their
// NATIONAL crime bodies (DGPJ, Ministerio del Interior) only ever
// publish periodic AGGREGATE counts, never a per-occurrence record with
// a real coordinate — but Madrid's own city open data portal does, for
// traffic accidents specifically (Policía Municipal de Madrid). One row
// per person involved (grouped by num_expediente, classified by the
// worst injury outcome in the group), real UTM coordinates converted to
// WGS84 with a dependency-free formula (verified live against pyproj),
// updated roughly monthly (confirmed live: current data reached 30 June
// 2026, ~2 months behind, comparable lag to UkPoliceAdapter). Barcelona
// has an equally real per-accident dataset but only publishes once a
// full year has already closed — not frequent enough to be worth
// ingesting yet, unlike Madrid's rolling monthly updates. This produces
// real EXACT-precision SecurityEvent rows with latitude/longitude set,
// so it needs NO new RPC or Flutter change at all: nearby_security_events
// already returns any EXACT/STREET row within radius regardless of
// country (its own WHERE clause has no country filter), and
// BrazilSecurityApi.fetchForArea (misleadingly named, genuinely
// country-agnostic) already calls it for every map viewport in the
// world.
// NoticiasAoMinutoAdapter/ElMundoAdapter (added 2026-09-05) — second
// news sources for Portugal and Spain, to raise pin DENSITY. PtNewsAdapter
// (RTP)/EsNewsAdapter (La Vanguardia) proved the pipeline works, but with
// only 6 PT and 20 ES events total after their first real run, most
// concelhos/municípios get 0-1 pin — nowhere near enough for the map's
// cluster layer (2+ nearby pins) to ever show a numbered hexagon the way
// Brazil/UK's much denser sources do. Notícias ao Minuto's own "país"
// feed is a big win here — 490 items in one pull, 139 (28%) genuinely
// classifiable, real concelho names already in the title — found by
// looking for a denser national source the same way Brazil stacks
// several news portals instead of relying on G1 alone. El Mundo's
// "españa" feed is a smaller win (2/53 in a live pull) — a dedicated
// Spanish "sucesos" section was searched for on El Mundo/El País/El
// Español/eldiario.es first (the same pattern that made La Vanguardia's
// own source so effective) but none exist at that URL shape. Both reuse
// every existing piece (classifyPtBrNews/classifyEsNews,
// geo_text_match_generic.ts, CONCELHO_NAME/MUNICIPIO_NAME) — no new
// classifier, matcher, or schema needed, just two more `sourceType:
// 'news'` producers feeding the pipeline nearby_news_pins already reads.
// NiPoliceAdapter (added 2026-09-05) — Northern Ireland choropleth.
// Point-level map pins for Northern Ireland already worked before this
// adapter existed (UkPoliceApi.dart queries data.police.uk by plain
// lat/lng for any viewport, and PSNI publishes through that same
// endpoint) — the real gap was the CHOROPLETH, since UkPoliceAdapter's
// own EW Police Force Area geometry (20260831120000) is explicitly
// England & Wales-only and PSNI has no boundary there. Uses Northern
// Ireland's 11 councils ("Local Government Districts", new geo_area_type
// 'LGD') rather than one national PSNI polygon — confirmed live that a
// single whole-country `poly` query 503s (the same result-size ceiling
// documented on UkPoliceAdapter's 13 highest-volume EW forces, just
// triggered here by total country size), while every one of the 11
// council-sized polys succeeds. Shares UkPoliceAdapter's own CATEGORY_MAP
// (exported from uk_police.ts) since it's the same national
// data.police.uk taxonomy, PSNI included.
// PtNewsAdapter/EsNewsAdapter (added 2026-09-05) — Portugal and Spain's
// first News Intelligence sources, and the actual fix behind an empty
// map for both countries: pt_crime.ts/es_crime.ts only ever wrote annual
// concelho/município AGGREGATES (no point location), so nearby_news_pins
// (20260830120000, widened 20260905090000 to also join by geo_area_id)
// had nothing from either country to resolve into a pin. RTP Notícias'
// "País" feed (PT) and La Vanguardia's dedicated "Sucesos" feed (ES) are
// both plain unauthenticated RSS; PtNewsAdapter reuses Brazil's own
// classifyPtBrNews (pt_news_classifier.ts) as-is since its keyword
// vocabulary is standard Portuguese, not Brazilian slang, while ES needed
// a new es_news_classifier.ts. Both match a concelho/município name in
// the article text via a new geo_text_match_generic.ts (the same
// longest-name/word-boundary/street-prefix logic geo_text_match.ts
// already has for Brazil, generalized off a plain name list instead of
// IbgeMunicipio) against pt_crime.ts's/es_crime.ts's own CONCELHO_NAME/
// MUNICIPIO_NAME lists — an unmatched article is skipped, never given an
// invented precision. See each adapter's own header for the live
// investigation (including why La Vanguardia's dedicated crime section
// was chosen over a general Spanish national feed, which yielded zero
// classifiable items in a real pull).
// FrCrimeAdapter/FrNewsAdapter (added 2026-09-07) — France, the app's
// first non-Iberian European country, added after the user asked
// whether data existed for it. SSMSI (Ministère de l'Intérieur)
// publishes official département-level crime stats (101 areas incl.
// Corsica and 5 overseas départements) on data.gouv.fr with NO
// statistical-secrecy suppression, unlike its own commune-level file —
// the user explicitly chose département over commune granularity for
// that reason. Unlike Portugal/Spain's fixed criminalidade.pt/
// georiesgo.com URLs, data.gouv.fr's own resource URLs are timestamped
// per edition and change every year, so FrCrimeAdapter resolves the
// current CSV URL through the dataset's stable API endpoint at fetch
// time rather than hardcoding a snapshot. France has no equivalent of
// data.police.uk, so — same gap UkPoliceAdapter/NiPoliceAdapter don't
// have — FrNewsAdapter (actu17.fr, a dedicated police/justice/faits-
// divers outlet) was added in the same pass to give France real pins,
// not just a choropleth. Its classifier departs from
// es_news_classifier.ts's plain substring matching in one place: French
// "vol"/"viol" are literal substrings of unrelated words
// ("volontairement", "violent") that would otherwise misclassify —
// see fr_news_classifier.ts's header for the live-confirmed example.
// News Intelligence expansion (2026-08-29): G1NewsAdapter now pulls all
// 27 state-level regional feeds instead of the single diluted national
// one (see g1_news.ts's own header — real coverage gaps, like zero
// classifiable Pará items for this adapter's first two days, motivated
// this). Six new, fully real Portuguese-language sources joined it —
// DiarioOnlineAdapter (Pará/Amazônia-focused, independent of G1),
// CnnBrasilAdapter, MetropolesAdapter, UolAdapter, AgenciaBrasilAdapter,
// FolhaAdapter — all verified live against their real feeds. Unlike G1,
// none of these five national portals has a structural per-article
// location signal, so they share a text-based state/city detector
// (national_pt_news.ts) and simply skip an article when no state can be
// named, rather than writing an unlocatable row nothing would ever show.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { IbgeAdapter } from "../_shared/adapters/br/ibge.ts";
// SinespAdapter (sinesp.ts) is built and correct — real bulk-download URL
// found, real parsing verified locally against the actual file — but not
// registered. fetch() has never completed in production despite three
// rounds of mitigation (default region, sa-east-1 pinning, chunked
// downloading); see the file's own header for the full diagnostic trail
// and why the remaining bottleneck looks like the origin server's own
// fixed overhead rather than anything fixable from this project's side.
// import { SinespAdapter } from "../_shared/adapters/br/sinesp.ts";
import { RenaestAdapter } from "../_shared/adapters/br/renaest.ts";
import { PrfAccidentsAdapter } from "../_shared/adapters/br/prf.ts";
import { RjIspAdapter } from "../_shared/adapters/br/rj_isp.ts";
import { PaSegupAdapter } from "../_shared/adapters/br/pa_segup.ts";
import { MgAdapter } from "../_shared/adapters/br/mg_ssp.ts";
import { EsSespAdapter } from "../_shared/adapters/br/es_sesp.ts";
import { AlAdapter } from "../_shared/adapters/br/al_seds.ts";
import { MtAdapter } from "../_shared/adapters/br/mt_sesp.ts";
import { DfAdapter } from "../_shared/adapters/br/df_ssp.ts";
import { PeAdapter } from "../_shared/adapters/br/pe_sds.ts";
import { GoSspAdapter } from "../_shared/adapters/br/go_ssp.ts";
import { MaSspAdapter } from "../_shared/adapters/br/ma_ssp.ts";
import { MsSejuspAdapter } from "../_shared/adapters/br/ms_sejusp.ts";
import { PrSespAdapter } from "../_shared/adapters/br/pr_sesp.ts";
import { RrPcrrAdapter } from "../_shared/adapters/br/rr_pcrr.ts";
// BaAdapter (ba_ssp.ts) is built and correct but not registered — the
// source server's TLS certificate chain is genuinely broken, see the
// file's own header for the openssl-verified detail. CE (SSPDS/SUPESP)
// was tried too and has no adapter file at all — every ce.gov.br host
// (sspds, supesp, cearatransparente) sits behind an F5/Volterra WAF that
// hard-rejects the request before any adapter code could run, see
// pe_sds.ts's own header for the confirmed detail.
import { G1NewsAdapter } from "../_shared/adapters/br/g1_news.ts";
import { DiarioOnlineAdapter } from "../_shared/adapters/br/diario_online_news.ts";
import { CnnBrasilAdapter } from "../_shared/adapters/br/cnn_brasil_news.ts";
import { MetropolesAdapter } from "../_shared/adapters/br/metropoles_news.ts";
import { UolAdapter } from "../_shared/adapters/br/uol_news.ts";
import { AgenciaBrasilAdapter } from "../_shared/adapters/br/agencia_brasil_news.ts";
import { FolhaAdapter } from "../_shared/adapters/br/folha_news.ts";
import { BbcNewsAdapter } from "../_shared/adapters/global/bbc_news.ts";
import { UnodcAdapter } from "../_shared/adapters/global/unodc.ts";
import { UkPoliceAdapter } from "../_shared/adapters/global/uk_police.ts";
import { NiPoliceAdapter } from "../_shared/adapters/global/ni_police.ts";
import { PtCrimeAdapter } from "../_shared/adapters/global/pt_crime.ts";
import { EsCrimeAdapter } from "../_shared/adapters/global/es_crime.ts";
import { PtNewsAdapter } from "../_shared/adapters/global/pt_news.ts";
import { EsNewsAdapter } from "../_shared/adapters/global/es_news.ts";
import { NoticiasAoMinutoAdapter } from "../_shared/adapters/global/pt_news_minuto.ts";
import { ElMundoAdapter } from "../_shared/adapters/global/es_news_elmundo.ts";
import { MadridAccidentsAdapter } from "../_shared/adapters/global/madrid_accidents.ts";
import { FrCrimeAdapter } from "../_shared/adapters/global/fr_crime.ts";
import { FrNewsAdapter } from "../_shared/adapters/global/fr_news.ts";
import { FcdoAdapter } from "../_shared/adapters/global/fcdo_travel_advisory.ts";
import { RsSspAdapter } from "../_shared/adapters/br/rs_ssp.ts";
import { FbspAnuarioAdapter } from "../_shared/adapters/br/fbsp_anuario.ts";
// SpVehicleAdapter (sp_vehicle.ts) is built and correct but not
// registered — every real attempt (default region, sa-east-1, chunked
// downloading) has failed fast (~2-4s), a different and still-unexplained
// shape of failure from SinespAdapter's (likely a connection-level
// rejection rather than a resource/timing limit — see the file's own
// header).
// import { SpVehicleAdapter } from "../_shared/adapters/br/sp_vehicle.ts";
import type {
  RawSecurityRecord,
  SecurityEvent,
  SecuritySource,
  SecuritySourceAdapter,
  SourceHealth,
  TerritorialSourceAdapter,
  TravelAdvisory,
  TravelAdvisoryAdapter,
} from "../_shared/adapters/types.ts";

const territorialAdapters: Record<string, TerritorialSourceAdapter> = {
  IbgeAdapter: new IbgeAdapter(),
};

const advisoryAdapters: Record<string, TravelAdvisoryAdapter> = {
  FcdoAdapter: new FcdoAdapter(),
};

const eventAdapters: Record<string, SecuritySourceAdapter> = {
  RenaestAdapter: new RenaestAdapter(),
  PrfAccidentsAdapter: new PrfAccidentsAdapter(),
  RjIspAdapter: new RjIspAdapter(),
  PaSegupAdapter: new PaSegupAdapter(),
  MgAdapter: new MgAdapter(),
  EsSespAdapter: new EsSespAdapter(),
  AlAdapter: new AlAdapter(),
  MtAdapter: new MtAdapter(),
  DfAdapter: new DfAdapter(),
  PeAdapter: new PeAdapter(),
  GoSspAdapter: new GoSspAdapter(),
  MaSspAdapter: new MaSspAdapter(),
  MsSejuspAdapter: new MsSejuspAdapter(),
  PrSespAdapter: new PrSespAdapter(),
  RrPcrrAdapter: new RrPcrrAdapter(),
  G1NewsAdapter: new G1NewsAdapter(),
  DiarioOnlineAdapter: new DiarioOnlineAdapter(),
  CnnBrasilAdapter: new CnnBrasilAdapter(),
  MetropolesAdapter: new MetropolesAdapter(),
  UolAdapter: new UolAdapter(),
  AgenciaBrasilAdapter: new AgenciaBrasilAdapter(),
  FolhaAdapter: new FolhaAdapter(),
  BbcNewsAdapter: new BbcNewsAdapter(),
  UnodcAdapter: new UnodcAdapter(),
  UkPoliceAdapter: new UkPoliceAdapter(),
  NiPoliceAdapter: new NiPoliceAdapter(),
  PtCrimeAdapter: new PtCrimeAdapter(),
  EsCrimeAdapter: new EsCrimeAdapter(),
  PtNewsAdapter: new PtNewsAdapter(),
  EsNewsAdapter: new EsNewsAdapter(),
  NoticiasAoMinutoAdapter: new NoticiasAoMinutoAdapter(),
  ElMundoAdapter: new ElMundoAdapter(),
  MadridAccidentsAdapter: new MadridAccidentsAdapter(),
  FrCrimeAdapter: new FrCrimeAdapter(),
  FrNewsAdapter: new FrNewsAdapter(),
  RsSspAdapter: new RsSspAdapter(),
  FbspAnuarioAdapter: new FbspAnuarioAdapter(),
};

async function upsertSourceRegistry(
  supabase: SupabaseClient,
  source: SecuritySource,
  health: SourceHealth,
): Promise<string | null> {
  const now = new Date().toISOString();
  const { data, error } = await supabase
    .from("security_sources")
    .upsert(
      {
        country_code: source.countryCode,
        state_code: source.stateCode ?? null,
        name: source.name,
        organisation: source.organisation ?? null,
        source_type: source.sourceType,
        source_url: source.sourceUrl ?? null,
        adapter_name: source.adapterName,
        adapter_version: source.adapterVersion,
        refresh_frequency: source.refreshFrequency ?? null,
        last_check: now,
        ...(health.status !== "RED" ? { last_success: now } : {}),
        last_data_date: health.lastDataDate ?? null,
        active: true,
      },
      { onConflict: "adapter_name" },
    )
    .select("id")
    .single();

  if (error) {
    console.error(`security_sources upsert failed for ${source.adapterName}:`, error.message);
    return null;
  }
  return data?.id ?? null;
}

// BeeAware Global blueprint — raw_events (Phase 0). Every adapter's
// fetch() already returns this same RawSecurityRecord[] shape, so this
// persists replay-capable raw payloads for any adapter with zero changes
// to the adapter files themselves. payload is bytea, sent as Postgres's
// standard `\x`-prefixed hex text (PostgREST casts a hex-prefixed string
// to bytea on insert) — chosen over base64 because it's the format
// Postgres itself uses natively, not a workaround.
function toBytes(payload: unknown): Uint8Array {
  if (payload instanceof Uint8Array) return payload;
  const text = typeof payload === "string" ? payload : JSON.stringify(payload);
  return new TextEncoder().encode(text);
}

// Genuinely necessary, not just tidy: Array.from(bytes, fn).join("") — a
// reasonable-looking first attempt — hit WORKER_RESOURCE_LIMIT on
// RjIspAdapter's ~7MB raw CSV text payload. Millions of individual
// 2-character string objects (one per byte) plus the array holding them
// is a large multiple of the input size in V8, not the ~2x hex encoding
// itself implies. This writes straight into one pre-sized byte buffer
// (ASCII hex digits are valid UTF-8) and decodes it once — no
// intermediate per-byte allocations.
const HEX_DIGITS = "0123456789abcdef";

function toHex(bytes: Uint8Array): string {
  const hexBytes = new Uint8Array(bytes.length * 2);
  for (let i = 0; i < bytes.length; i++) {
    const byte = bytes[i];
    hexBytes[i * 2] = HEX_DIGITS.charCodeAt(byte >> 4);
    hexBytes[i * 2 + 1] = HEX_DIGITS.charCodeAt(byte & 0x0f);
  }
  return new TextDecoder().decode(hexBytes);
}

async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return toHex(new Uint8Array(digest));
}

async function persistRawEvents(
  supabase: SupabaseClient,
  sourceId: string | null,
  adapterName: string,
  records: RawSecurityRecord[],
): Promise<void> {
  if (records.length === 0) return;

  // toHex() itself is cheap (linear, pre-sized buffer — see its own
  // comment), but for a genuinely large payload the hex string it
  // produces (2x the input) plus the original bytes plus whatever the
  // adapter's own normalize() needs concurrently (RsSspAdapter's 95MB
  // decompressed CSV, streamed but still substantial) can combine to
  // cross the Edge Function's memory budget — confirmed live: RsSspAdapter
  // debug mode, which worked before raw_events existed, started hitting
  // WORKER_RESOURCE_LIMIT once persistRawEvents ran unconditionally ahead
  // of it. Every other adapter's payload measured well under this
  // (RjIspAdapter's ~7MB text was the previous largest, confirmed working)
  // — skip raw persistence above that, rather than lower the bar for
  // everyone. The source file itself stays downloadable from SSP-RS's own
  // site if a raw copy is ever needed, unlike a live API response.
  const RAW_PAYLOAD_SIZE_LIMIT = 8_000_000;

  const rows = (
    await Promise.all(
      records.map(async (record) => {
        const bytes = toBytes(record.payload);
        if (bytes.length > RAW_PAYLOAD_SIZE_LIMIT) {
          console.warn(
            `raw_events: skipping ${adapterName}/${record.sourceRecordId} — ${bytes.length} bytes exceeds the ${RAW_PAYLOAD_SIZE_LIMIT}-byte raw-persistence limit`,
          );
          return null;
        }
        return {
          source_id: sourceId,
          source_record_id: record.sourceRecordId,
          payload: `\\x${toHex(bytes)}`,
          checksum: await sha256Hex(bytes),
          adapter_name: adapterName,
        };
      }),
    )
  ).filter((row) => row !== null);

  if (rows.length === 0) return;

  const { error } = await supabase.from("raw_events").insert(rows);
  if (error) console.error(`raw_events insert failed for ${adapterName}:`, error.message);
}

async function runTerritorialAdapter(supabase: SupabaseClient, adapter: TerritorialSourceAdapter) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, areasWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);
  let written = 0;
  for (const record of records) {
    const areas = await adapter.normalize(record);
    for (const area of areas) {
      const { error } = await supabase.from("geo_areas").upsert(
        {
          country_code: area.countryCode,
          state_code: area.stateCode ?? null,
          city_ibge_code: area.cityIbgeCode ?? null,
          area_type: area.areaType,
          name: area.name,
          geometry: area.geometry ?? null,
          source: area.source,
          source_version: area.sourceVersion ?? null,
        },
        { onConflict: "country_code,state_code,city_ibge_code,area_type" },
      );
      if (!error) written++;
      else console.error(`geo_areas upsert failed for ${area.name}:`, error.message);
    }
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, areasWritten: written };
}

function mapAdvisoryToRow(sourceId: string | null, advisory: TravelAdvisory) {
  return {
    source_id: sourceId,
    country_code: advisory.countryCode,
    country_slug: advisory.countrySlug,
    issuer: advisory.issuer,
    level: advisory.level,
    raw_alert_status: advisory.rawAlertStatus,
    summary: advisory.summary ?? null,
    source_url: advisory.sourceUrl ?? null,
    effective_at: advisory.effectiveAt ?? null,
  };
}

async function runAdvisoryAdapter(supabase: SupabaseClient, adapter: TravelAdvisoryAdapter, debug = false) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, advisoriesWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);

  if (debug) {
    const normalized: TravelAdvisory[] = [];
    for (const record of records) {
      normalized.push(...(await adapter.normalize(record)));
    }
    return {
      adapter: source.adapterName,
      health,
      recordsSeen: records.length,
      advisoriesNormalized: normalized.length,
      sample: normalized.slice(0, 3),
    };
  }

  let written = 0;
  const rows: ReturnType<typeof mapAdvisoryToRow>[] = [];
  for (const record of records) {
    const advisories = await adapter.normalize(record);
    for (const advisory of advisories) rows.push(mapAdvisoryToRow(sourceId, advisory));
  }

  for (let i = 0; i < rows.length; i += EVENT_BATCH_SIZE) {
    const batch = rows.slice(i, i + EVENT_BATCH_SIZE);
    const { error } = await supabase
      .from("travel_advisories")
      .upsert(batch, { onConflict: "source_id,country_code" });
    if (!error) written += batch.length;
    else console.error(`travel_advisories batch upsert failed (rows ${i}-${i + batch.length}):`, error.message);
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, advisoriesWritten: written };
}

// Not yet exercised against real rows — SinespAdapter/RenaestAdapter/
// PrfAccidentsAdapter's normalize() all return [] today (see their file
// headers), so this never actually runs with real data yet. Written for
// when normalize() is filled in, using EWKT text for the point geometry
// (PostgREST/PostGIS accept `SRID=4326;POINT(lng lat)` on a geometry
// column) — worth a real insert test once there's an event to insert.
function mapEventToRow(sourceId: string | null, event: SecurityEvent) {
  return {
    country_code: event.countryCode,
    state_code: event.stateCode ?? null,
    city_ibge_code: event.cityIbgeCode ?? null,
    source_id: sourceId,
    source_record_id: event.sourceRecordId,
    source_type: event.sourceType,
    event_category: event.eventCategory,
    event_type: event.eventType,
    event_subtype: event.eventSubtype ?? null,
    original_category: event.originalCategory ?? null,
    occurred_at: event.occurredAt ?? null,
    reported_at: event.reportedAt ?? null,
    published_at: event.publishedAt ?? null,
    location:
      event.latitude != null && event.longitude != null
        ? `SRID=4326;POINT(${event.longitude} ${event.latitude})`
        : null,
    geo_precision: event.geoPrecision,
    location_confidence: event.locationConfidence ?? null,
    neighborhood: event.neighborhood ?? null,
    district: event.district ?? null,
    city: event.city ?? null,
    state: event.state ?? null,
    occurrence_count: event.occurrenceCount ?? 1,
    victim_count: event.victimCount ?? null,
    severity: event.severity ?? null,
    confidence_score: event.confidenceScore ?? null,
    raw_payload: event.rawPayload ?? null,
  };
}

// PRF's single "grouped by occurrence" file already carries ~34k rows for
// the current year alone — one upsert call per row (as this used to do)
// means ~34k sequential round trips to PostgREST, which is both slow and
// a real risk of running past the Edge Function's execution limit. Batch
// instead: PostgREST/supabase-js upsert() accepts an array and turns it
// into one bulk statement, so this is ~34k/EVENT_BATCH_SIZE calls.
const EVENT_BATCH_SIZE = 500;

async function runEventAdapter(supabase: SupabaseClient, adapter: SecuritySourceAdapter, debug = false) {
  const source = adapter.source();
  const health = await adapter.healthCheck();
  const sourceId = await upsertSourceRegistry(supabase, source, health);

  if (health.status === "RED") {
    return { adapter: source.adapterName, health, eventsWritten: 0 };
  }

  const records = await adapter.fetch();
  await persistRawEvents(supabase, sourceId, source.adapterName, records);
  // debug:true runs fetch() + normalize() but skips the DB write, and
  // returns a small sample instead of every event (a full binary
  // payload or tens of thousands of rows echoed as JSON is its own way
  // to blow the response size/memory budget) — for inspecting what an
  // adapter actually produces without needing a separate script or DB
  // access.
  if (debug) {
    const normalized: SecurityEvent[] = [];
    for (const record of records) {
      normalized.push(...(await adapter.normalize(record)));
    }
    return {
      adapter: source.adapterName,
      health,
      recordsSeen: records.length,
      eventsNormalized: normalized.length,
      sample: normalized.slice(0, 3),
    };
  }
  let written = 0;
  for (const record of records) {
    const events = await adapter.normalize(record);

    // Postgres rejects an entire multi-row upsert with "ON CONFLICT DO
    // UPDATE command cannot affect row a second time" the moment two rows
    // in the SAME statement share a conflict key — found in production
    // with PaSegupAdapter, whose sourceRecordId is a composite fingerprint
    // (no real unique ID in the source data) with a documented small
    // collision rate. Two colliding rows landing in the same batch was
    // silently failing that whole 500-row batch (only the last, smaller
    // batch without a collision got through). Dedupe by key before
    // batching so this can't happen for any adapter, not just this one.
    // Built directly from `events` (skipping a separate intermediate
    // `rows` array) since RsSspAdapter's row count made every extra
    // full-array copy here matter — see its file header for the memory
    // budget this ingestion job runs under.
    const bySourceRecordId = new Map<string, ReturnType<typeof mapEventToRow>>();
    for (const event of events) {
      bySourceRecordId.set(event.sourceRecordId, mapEventToRow(sourceId, event));
    }
    const dedupedRows = [...bySourceRecordId.values()];

    for (let i = 0; i < dedupedRows.length; i += EVENT_BATCH_SIZE) {
      const batch = dedupedRows.slice(i, i + EVENT_BATCH_SIZE);
      const { error } = await supabase
        .from("security_events")
        .upsert(batch, { onConflict: "source_id,source_record_id" });
      if (!error) written += batch.length;
      else console.error(`security_events batch upsert failed (rows ${i}-${i + batch.length}):`, error.message);
    }
  }

  return { adapter: source.adapterName, health, recordsSeen: records.length, eventsWritten: written };
}

// One-off (not cron-scheduled) backfill: populates geometry on the
// municipality geo_areas rows IbgeAdapter's regular sync already created
// (identity only, geometry left null — see ibge.ts). Triggered manually
// with {"action": "backfill-geometry", "stateCode": "RJ"} rather than
// running for every state automatically, since it's only needed where a
// choropleth actually consumes it (RJ today, for RjIspAdapter).
async function backfillGeometry(supabase: SupabaseClient, stateCode: string) {
  const ibge = new IbgeAdapter();
  const rows = await ibge.fetchAndNormalizeGeometry(stateCode);

  let written = 0;
  for (const row of rows) {
    const { error } = await supabase
      .from("geo_areas")
      .update({ geometry: row.geometry, source_version: row.sourceVersion })
      .eq("city_ibge_code", row.cityIbgeCode)
      .eq("area_type", "MUNICIPALITY");
    if (!error) written++;
    else console.error(`geo_areas geometry update failed for ${row.cityIbgeCode}:`, error.message);
  }

  return { stateCode, municipalitiesSeen: rows.length, geometryWritten: written };
}

// One-off (not cron-scheduled) backfill: populates geo_areas.population
// (Safety Pulse / Historical Safety, roadmap Phase 5) via IBGE's SIDRA
// aggregates. Same shape as backfillGeometry above, but loops all 27 UFs
// when stateCode is omitted — unlike geometry (only needed where a
// choropleth already consumes it), Historical Safety needs population
// everywhere security_events has data, and 27 lightweight JSON calls
// comfortably fits one invocation. Triggered with
// {"action": "backfill-population"} (all UFs) or
// {"action": "backfill-population", "stateCode": "RJ"} (one).
const ALL_UF_CODES = [
  "RO", "AC", "AM", "RR", "PA", "AP", "TO",
  "MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA",
  "MG", "ES", "RJ", "SP",
  "PR", "SC", "RS",
  "MS", "MT", "GO", "DF",
];

async function backfillPopulation(supabase: SupabaseClient, stateCode?: string) {
  const ibge = new IbgeAdapter();
  const stateCodes = stateCode ? [stateCode] : ALL_UF_CODES;

  // One bulk_update_population() RPC call per state (27 total for a
  // national run), not one .update() per municipality — an earlier
  // version did exactly that (~5570 sequential round trips for a
  // national run) and hit WORKER_RESOURCE_LIMIT for real, the same
  // "one round trip per row" problem this project already fixed for
  // PRF's events (see EVENT_BATCH_SIZE above). bulk_update_population
  // does the whole state's worth of rows in one UPDATE...FROM statement.
  let municipalitiesSeen = 0;
  let populationWritten = 0;
  for (const uf of stateCodes) {
    const rows = await ibge.fetchAndNormalizePopulation(uf);
    municipalitiesSeen += rows.length;
    if (rows.length === 0) continue;

    const { data, error } = await supabase.rpc("bulk_update_population", {
      updates: rows.map((r) => ({ city_ibge_code: r.cityIbgeCode, population: r.population })),
    });
    if (!error) populationWritten += (data as number) ?? 0;
    else console.error(`bulk_update_population failed for ${uf}:`, error.message);
  }

  return { stateCodes, municipalitiesSeen, populationWritten };
}

// One-off (not cron-scheduled) backfill: pulls ONE past, non-overlapping
// month of real Belém history via PaSegupAdapter.fetchAndNormalizeMonth
// (see that method's own header for why this can't just widen the
// regular trailing-1-month window in a single request). Triggered with
// {"action": "backfill-pa-segup-month", "monthsAgo": 2} — one invocation
// per month, not looped internally, since /download_recorte's own
// regeneration latency (60-500s+ observed) makes several sequential
// pulls in one invocation a real risk. Same batched-upsert-with-dedupe
// logic runEventAdapter uses for its regular real-mode writes.
async function backfillPaSegupMonth(supabase: SupabaseClient, monthsAgo: number) {
  const adapter = new PaSegupAdapter();
  const source = adapter.source();
  const sourceId = await upsertSourceRegistry(supabase, source, await adapter.healthCheck());

  const events = await adapter.fetchAndNormalizeMonth(monthsAgo);

  const bySourceRecordId = new Map<string, ReturnType<typeof mapEventToRow>>();
  for (const event of events) {
    bySourceRecordId.set(event.sourceRecordId, mapEventToRow(sourceId, event));
  }
  const dedupedRows = [...bySourceRecordId.values()];

  let written = 0;
  for (let i = 0; i < dedupedRows.length; i += EVENT_BATCH_SIZE) {
    const batch = dedupedRows.slice(i, i + EVENT_BATCH_SIZE);
    const { error } = await supabase
      .from("security_events")
      .upsert(batch, { onConflict: "source_id,source_record_id" });
    if (!error) written += batch.length;
    else console.error(`security_events batch upsert failed (backfill month ${monthsAgo}, rows ${i}-${i + batch.length}):`, error.message);
  }

  return { monthsAgo, eventsSeen: events.length, eventsWritten: written };
}

Deno.serve(async (req) => {
  // This runs real external HTTP fetches and DB writes on every call —
  // it must only be triggerable by pg_cron (via Vault, see the
  // use-vault-for-cron-auth migration) or a trusted manual invocation with
  // that same token, never by an arbitrary request.
  //
  // Deliberately NOT compared against Deno.env SUPABASE_SERVICE_ROLE_KEY:
  // on this project that reserved env var holds a stale value that no
  // longer matches the project's current legacy service_role key (verified
  // by hand — same sha256 mismatch against `supabase secrets list`'s
  // digest — and Supabase doesn't let user code refresh it, `secrets set
  // SUPABASE_SERVICE_ROLE_KEY=...` is rejected as a reserved name). A
  // dedicated secret we set ourselves avoids depending on that.
  const auth = req.headers.get("Authorization") ?? "";
  const authToken = Deno.env.get("INGEST_FUNCTION_AUTH_TOKEN");
  if (!authToken || auth !== `Bearer ${authToken}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, serviceRoleKey);

  let body: { adapter?: string; action?: string; stateCode?: string; debug?: boolean; monthsAgo?: number } = {};
  try {
    body = await req.json();
  } catch {
    // No body / not JSON -> run every adapter.
  }

  if (body.action === "backfill-geometry") {
    if (!body.stateCode) {
      return new Response(JSON.stringify({ ok: false, error: "stateCode required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    const result = await backfillGeometry(supabase, body.stateCode);
    return new Response(JSON.stringify({ ok: true, result }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (body.action === "backfill-population") {
    const result = await backfillPopulation(supabase, body.stateCode);
    return new Response(JSON.stringify({ ok: true, result }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  if (body.action === "backfill-pa-segup-month") {
    if (!body.monthsAgo) {
      return new Response(JSON.stringify({ ok: false, error: "monthsAgo required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }
    try {
      const result = await backfillPaSegupMonth(supabase, body.monthsAgo);
      return new Response(JSON.stringify({ ok: true, result }), {
        headers: { "Content-Type": "application/json" },
      });
    } catch (e) {
      // A thrown error here otherwise surfaces as an opaque platform 500
      // with no message — this action is invoked manually/interactively
      // (not by cron), so a real error message matters more here than
      // for the regular scheduled adapter runs.
      return new Response(JSON.stringify({ ok: false, error: String(e) }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }
  }

  const results: Record<string, unknown> = {};

  for (const [name, adapter] of Object.entries(territorialAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runTerritorialAdapter(supabase, adapter);
  }

  for (const [name, adapter] of Object.entries(eventAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runEventAdapter(supabase, adapter, body.debug === true);
  }

  for (const [name, adapter] of Object.entries(advisoryAdapters)) {
    if (body.adapter && body.adapter !== name) continue;
    results[name] = await runAdvisoryAdapter(supabase, adapter, body.debug === true);
  }

  return new Response(JSON.stringify({ ok: true, results }), {
    headers: { "Content-Type": "application/json" },
  });
});
