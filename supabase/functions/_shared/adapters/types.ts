// BeeAware Brasil roadmap — adapter contract (sections 2.1 and 8.2).
//
// One adapter per source (SinespAdapter, PaSegupAdapter, SpSspAdapter...).
// Nothing outside this file — no Edge Function, no Flutter code — should
// need to know that one state publishes CSV, another CKAN, another a
// spreadsheet. That difference lives entirely inside fetch()/normalize().
//
// This is Phase 0 scaffolding: the contract and a registry, no real
// adapters yet. IBGE/SINESP/PRF/RENAEST (Phase 1, roadmap 11.2) are the
// first implementations.

import type {
  EventCategory,
  GeoAreaType,
  GeoPrecision,
  SourceType,
} from "../taxonomy.ts";

export interface SecuritySource {
  id?: string; // set once the source row exists in security_sources
  countryCode: string;
  stateCode?: string;
  name: string;
  organisation?: string;
  sourceType: SourceType;
  sourceUrl?: string;
  adapterName: string;
  adapterVersion: string;
  refreshFrequency?: string;
}

// The untouched shape returned by fetch() — whatever the source actually
// sends back (a CSV row, a CKAN resource entry, a JSON record). Kept as
// `unknown` on purpose: normalize() is the only place that should know its
// real shape.
export interface RawSecurityRecord {
  sourceRecordId: string;
  payload: unknown;
  fetchedAt: string; // ISO timestamp
}

// The normalized shape an adapter produces — maps 1:1 onto
// security_events, camelCase here because that's idiomatic TS; the
// insert step at the call site is responsible for the camelCase ->
// snake_case column mapping, not the adapter.
export interface SecurityEvent {
  countryCode: string;
  stateCode?: string;
  cityIbgeCode?: string;
  sourceRecordId: string;
  sourceType: SourceType;
  eventCategory: EventCategory;
  eventType: string;
  eventSubtype?: string;
  originalCategory?: string;
  occurredAt?: string;
  reportedAt?: string;
  publishedAt?: string;
  latitude?: number;
  longitude?: number;
  geoPrecision: GeoPrecision;
  locationConfidence?: number;
  neighborhood?: string;
  district?: string;
  city?: string;
  state?: string;
  occurrenceCount?: number;
  victimCount?: number;
  severity?: string;
  confidenceScore?: number;
  rawPayload?: unknown;
}

export type SourceHealthStatus = "GREEN" | "AMBER" | "RED";

export interface SourceHealth {
  status: SourceHealthStatus;
  lastDataDate?: string;
  message?: string;
}

export interface SecuritySourceAdapter {
  source(): SecuritySource;
  fetch(since?: Date): Promise<RawSecurityRecord[]>;
  normalize(record: RawSecurityRecord): Promise<SecurityEvent[]>;
  healthCheck(): Promise<SourceHealth>;
}

// IBGE isn't a crime/incident feed — it's the territorial identity layer
// (roadmap 3.2), so it doesn't fit SecuritySourceAdapter's
// normalize() -> SecurityEvent[] shape. Forcing municipality/state rows
// through that interface would misrepresent what they are; this sibling
// interface produces geo_areas rows instead.
export interface GeoArea {
  countryCode: string;
  stateCode?: string;
  cityIbgeCode?: string;
  areaType: GeoAreaType;
  name: string;
  // GeoJSON geometry (Point/Polygon/MultiPolygon) in WGS84 — matches the
  // geometry(Geometry, 4326) column in geo_areas.
  geometry?: unknown;
  parentAreaId?: string;
  source: string;
  sourceVersion?: string;
}

export interface TerritorialSourceAdapter {
  source(): SecuritySource;
  fetch(stateCode?: string): Promise<RawSecurityRecord[]>;
  normalize(record: RawSecurityRecord): Promise<GeoArea[]>;
  healthCheck(): Promise<SourceHealth>;
}

// ===== Registries =====
// registerAdapter(new PaSegupAdapter()) is the pattern the roadmap uses
// (section 2.1) — a plain in-memory map is enough for Phase 0/1. Whatever
// process ends up running ingestion (a scheduled Edge Function, most
// likely) imports the adapters it needs and calls this to register them
// before iterating getAdapters().
const registry = new Map<string, SecuritySourceAdapter>();
const territorialRegistry = new Map<string, TerritorialSourceAdapter>();

export function registerAdapter(adapter: SecuritySourceAdapter): void {
  const { adapterName } = adapter.source();
  registry.set(adapterName, adapter);
}

export function getAdapter(adapterName: string): SecuritySourceAdapter | undefined {
  return registry.get(adapterName);
}

export function getAdapters(): SecuritySourceAdapter[] {
  return Array.from(registry.values());
}

export function registerTerritorialAdapter(adapter: TerritorialSourceAdapter): void {
  const { adapterName } = adapter.source();
  territorialRegistry.set(adapterName, adapter);
}

export function getTerritorialAdapters(): TerritorialSourceAdapter[] {
  return Array.from(territorialRegistry.values());
}
