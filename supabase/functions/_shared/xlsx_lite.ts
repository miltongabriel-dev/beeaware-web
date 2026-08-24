// BeeAware Global blueprint — minimal streaming XLSX reader.
//
// Built for UnodcAdapter (unodc.ts), whose source file is legitimately
// large: 126083 rows / 61.5MB of raw sheet XML. The `xlsx` (SheetJS)
// package every other XLSX-based adapter uses (pa_segup.ts) builds a
// full per-cell object model of the workbook — fine at pa_segup.ts's
// scale (8083 rows, ~200MB), but measured at 300-550MB RSS for this
// file regardless of SheetJS's own large-file options (dense mode,
// single-sheet filtering), and the deployed function failed with
// WORKER_RESOURCE_LIMIT. This reader only ever holds the small pieces
// of a workbook fully in memory (sharedStrings.xml — 19KB/739 entries
// for the real UNODC file; workbook.xml and its rels — a few KB) and
// streams the actual row data the same way rs_ssp.ts streams its CSV:
// read decompressed text in chunks, process every complete `<row>...
// </row>` found so far, keep the trailing partial row as leftover for
// the next chunk. Verified against the real UNODC file: identical
// results to SheetJS (Brazil 2024: 39625), ~233MB in a synchronous
// Node proxy test with no GC breathing room between chunks — expected
// to do better in production, where each chunk read is a real awaited
// stream read Deno's GC can run between, the same gap that made
// rs_ssp.ts's real deployment (123MB) beat its own synchronous Node
// estimate.
//
// Deliberately not a general XLSX library: no styles, no formulas
// (beyond skipping their cached <f> results), no merged cells, no
// dates-as-serials handling. Just enough to stream simple exported data
// tables — exactly what every source this app touches actually
// publishes.

function readUInt16LE(view: DataView, offset: number): number {
  return view.getUint16(offset, true);
}
function readUInt32LE(view: DataView, offset: number): number {
  return view.getUint32(offset, true);
}

export interface ZipEntry {
  compressedOffset: number;
  compressedSize: number;
  method: number;
}

// Same central-directory approach as rs_ssp.ts's locateSingleZipEntry,
// generalised to return every entry (an XLSX is a multi-file zip —
// sheet XML, sharedStrings.xml, workbook.xml, its rels, styles, etc. —
// not the single-file archives PRF/RS-SSP/PA-SEGUP download).
export function locateZipEntries(zipBytes: Uint8Array): Map<string, ZipEntry> {
  const view = new DataView(zipBytes.buffer, zipBytes.byteOffset, zipBytes.byteLength);

  const EOCD_SIGNATURE = 0x06054b50;
  let eocdOffset = -1;
  const searchStart = Math.max(0, zipBytes.length - 65557);
  for (let i = zipBytes.length - 22; i >= searchStart; i--) {
    if (readUInt32LE(view, i) === EOCD_SIGNATURE) {
      eocdOffset = i;
      break;
    }
  }
  if (eocdOffset === -1) {
    throw new Error("xlsx_lite: End Of Central Directory record not found");
  }

  const entryCount = readUInt16LE(view, eocdOffset + 10);
  let centralDirOffset = readUInt32LE(view, eocdOffset + 16);

  const CENTRAL_DIR_SIGNATURE = 0x02014b50;
  const LOCAL_FILE_SIGNATURE = 0x04034b50;
  const entries = new Map<string, ZipEntry>();
  const decoder = new TextDecoder();

  for (let i = 0; i < entryCount; i++) {
    if (readUInt32LE(view, centralDirOffset) !== CENTRAL_DIR_SIGNATURE) {
      throw new Error(`xlsx_lite: central directory signature mismatch at entry ${i}`);
    }
    const method = readUInt16LE(view, centralDirOffset + 10);
    const compressedSize = readUInt32LE(view, centralDirOffset + 20);
    const fileNameLength = readUInt16LE(view, centralDirOffset + 28);
    const extraFieldLength = readUInt16LE(view, centralDirOffset + 30);
    const commentLength = readUInt16LE(view, centralDirOffset + 32);
    const localHeaderOffset = readUInt32LE(view, centralDirOffset + 42);
    const nameBytes = zipBytes.subarray(centralDirOffset + 46, centralDirOffset + 46 + fileNameLength);
    const name = decoder.decode(nameBytes);

    if (readUInt32LE(view, localHeaderOffset) !== LOCAL_FILE_SIGNATURE) {
      throw new Error(`xlsx_lite: local file header signature mismatch for ${name}`);
    }
    const localNameLength = readUInt16LE(view, localHeaderOffset + 26);
    const localExtraLength = readUInt16LE(view, localHeaderOffset + 28);
    const compressedOffset = localHeaderOffset + 30 + localNameLength + localExtraLength;

    entries.set(name, { compressedOffset, compressedSize, method });
    centralDirOffset += 46 + fileNameLength + extraFieldLength + commentLength;
  }

  return entries;
}

async function decompressStream(zipBytes: Uint8Array, entry: ZipEntry): Promise<ReadableStream<Uint8Array>> {
  const compressed = zipBytes.subarray(entry.compressedOffset, entry.compressedOffset + entry.compressedSize);
  if (entry.method === 0) {
    return new Blob([compressed]).stream();
  }
  if (entry.method !== 8) {
    throw new Error(`xlsx_lite: unsupported compression method ${entry.method}`);
  }
  return new Blob([compressed]).stream().pipeThrough(new DecompressionStream("deflate-raw"));
}

// For small entries only (sharedStrings.xml/workbook.xml/rels — a few KB
// to tens of KB for every real file seen so far). Never use this on a
// sheet's own XML — that's what forEachRow is for.
export async function inflateEntrySync(zipBytes: Uint8Array, entry: ZipEntry): Promise<string> {
  const stream = await decompressStream(zipBytes, entry);
  return new Response(stream).text();
}

// Streams one worksheet's XML, calling onRow(cellsByColumnIndex) for
// every complete <row>...</row> found — never holding more than one
// chunk of decompressed text plus a small leftover tail at once,
// regardless of the sheet's total size. cellsByColumnIndex[0] is column
// A, [1] is column B, etc.; a shared string cell (t="s") is resolved
// through sharedStrings before the callback runs, so callers never see
// raw string-table indices.
export async function forEachRow(
  zipBytes: Uint8Array,
  entry: ZipEntry,
  sharedStrings: string[],
  onRow: (cells: (string | undefined)[]) => void,
): Promise<void> {
  const cellRe = buildCellRegex();
  await forEachRowRaw(zipBytes, entry, (rowInnerXml) => {
    onRow(parseRowCells(rowInnerXml, cellRe, sharedStrings));
  });
}

// Same chunked row-boundary streaming as forEachRow, but hands the caller
// the raw <row>...</row> inner XML instead of a fully cell-parsed array.
// Exists for sp_vehicle.ts: parseRowCells' per-cell regex (cellRe below)
// costs real CPU per column it has to consider, and that source's rows
// are unusually wide (55 columns, vs every other adapter's much narrower
// sheets) — expensive enough per row, at this source's real row count, to
// have measurably hit this Edge Function's resource ceiling running the
// full parse on every row just to inspect two of them. Skipping the
// per-cell parse for rows a caller can already tell (via a much cheaper
// targeted check on the raw XML) it doesn't need avoids paying that cost
// on rows it will discard anyway.
export async function forEachRowRaw(
  zipBytes: Uint8Array,
  entry: ZipEntry,
  onRawRow: (rowInnerXml: string) => void,
): Promise<void> {
  const stream = await decompressStream(zipBytes, entry);
  const reader = stream.getReader();
  const decoder = new TextDecoder();

  const rowRe = /<row[^>]*>(.*?)<\/row>/gs;
  let leftover = "";

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunkText = leftover + decoder.decode(value, { stream: true });
    const lastRowEnd = chunkText.lastIndexOf("</row>");
    if (lastRowEnd === -1) {
      leftover = chunkText;
      continue;
    }

    const processable = chunkText.slice(0, lastRowEnd + "</row>".length);
    leftover = chunkText.slice(lastRowEnd + "</row>".length);

    rowRe.lastIndex = 0;
    let rowMatch: RegExpExecArray | null;
    while ((rowMatch = rowRe.exec(processable))) {
      onRawRow(rowMatch[1]);
    }
  }

  if (leftover.trim().length > 0) {
    const finalMatch = /<row[^>]*>(.*?)<\/row>/s.exec(leftover);
    if (finalMatch) onRawRow(finalMatch[1]);
  }
}

// A fresh cellRe instance per caller — global regexes carry lastIndex
// state, so forEachRow and any direct parseRowCells caller (sp_vehicle.ts,
// sinesp.ts) each need their own instance rather than sharing one.
// Matches either a <v>value</v> cell (shared-string index or a plain
// number/date serial) or an inline-string cell (<is><t>text</t></is>,
// used by sources with no sharedStrings.xml at all, e.g. sinesp.ts) —
// group 3 is the <v> capture, group 4 the inline-string capture;
// parseRowCells picks whichever one matched.
export function buildCellRegex(): RegExp {
  return /<c r="([A-Z]+)\d+"[^>]*?(?:\st="(\w+)")?[^>]*>(?:<f>.*?<\/f>)?(?:<v>(.*?)<\/v>|<is><t[^>]*>(.*?)<\/t><\/is>)<\/c>/gs;
}

function columnIndex(columnLetters: string): number {
  let index = 0;
  for (let i = 0; i < columnLetters.length; i++) {
    index = index * 26 + (columnLetters.charCodeAt(i) - 64);
  }
  return index - 1; // A -> 0
}

const XML_ENTITIES: Record<string, string> = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };

function decodeXmlEntities(text: string): string {
  return text.replace(/&(amp|lt|gt|quot|apos);/g, (_, name) => XML_ENTITIES[name]);
}

export function parseRowCells(
  rowInnerXml: string,
  cellRe: RegExp,
  sharedStrings: string[],
): (string | undefined)[] {
  const cells: (string | undefined)[] = [];
  cellRe.lastIndex = 0;
  let cellMatch: RegExpExecArray | null;
  while ((cellMatch = cellRe.exec(rowInnerXml))) {
    const [, columnLetters, type, vValue, inlineValue] = cellMatch;
    const idx = columnIndex(columnLetters);
    if (type === "s") {
      cells[idx] = sharedStrings[Number(vValue)];
    } else if (type === "inlineStr") {
      // <c t="inlineStr"><is><t>text</t></is></c> — a cell that carries its
      // own string inline rather than through the shared-strings table.
      // First seen in SINESP's bancovde export (sinesp.ts), which has no
      // sharedStrings.xml at all.
      cells[idx] = inlineValue !== undefined ? decodeXmlEntities(inlineValue) : undefined;
    } else {
      cells[idx] = vValue !== undefined ? decodeXmlEntities(vValue) : undefined;
    }
  }
  return cells;
}

// sharedStrings.xml's <si> entries are usually a single <t>text</t>, but
// rich-text cells split one string across multiple <r><t>...</t></r>
// runs — concatenated here so callers always get the whole string.
export function parseSharedStrings(xml: string): string[] {
  const strings: string[] = [];
  const siRe = /<si>(.*?)<\/si>/gs;
  const tRe = /<t[^>]*>(.*?)<\/t>/gs;
  let siMatch: RegExpExecArray | null;
  while ((siMatch = siRe.exec(xml))) {
    let text = "";
    tRe.lastIndex = 0;
    let tMatch: RegExpExecArray | null;
    while ((tMatch = tRe.exec(siMatch[1]))) text += tMatch[1];
    strings.push(decodeXmlEntities(text));
  }
  return strings;
}

// Resolves a sheet NAME (e.g. "data_cts_intentional_homicide") to its
// entry in the zip, via workbook.xml's <sheet name=.. r:id=..> and
// xl/_rels/workbook.xml.rels' Id -> Target mapping — not a hardcoded
// "sheet1.xml" guess, which would silently break if UNODC ever reorders
// sheets in a future export.
export async function resolveSheetEntry(
  zipBytes: Uint8Array,
  entries: Map<string, ZipEntry>,
  sheetName: string,
): Promise<ZipEntry | undefined> {
  const workbookEntry = entries.get("xl/workbook.xml");
  const relsEntry = entries.get("xl/_rels/workbook.xml.rels");
  if (!workbookEntry || !relsEntry) return undefined;

  const workbookXml = await inflateEntrySync(zipBytes, workbookEntry);
  const sheetMatch = new RegExp(`<sheet[^>]*name="${sheetName}"[^>]*r:id="(rId\\d+)"`).exec(workbookXml);
  if (!sheetMatch) return undefined;
  const rId = sheetMatch[1];

  const relsXml = await inflateEntrySync(zipBytes, relsEntry);
  const relMatch = new RegExp(`<Relationship Id="${rId}"[^>]*Target="([^"]+)"`).exec(relsXml);
  if (!relMatch) return undefined;

  return entries.get(`xl/${relMatch[1]}`);
}
