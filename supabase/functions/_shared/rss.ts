// BeeAware — shared RSS 2.0 parsing helpers.
//
// Every feed-based adapter in this project (G1's 27 state feeds, BBC,
// and the Portuguese portals under adapters/br/*_news.ts) is the same
// shape: download an RSS 2.0 document, decode its entities, pull out
// <item> blocks. Extracted here once the duplication crossed from
// "structurally similar" into "the exact same regex logic copy-pasted
// byte-for-byte across 7+ files" — g1_news.ts and bbc_news.ts already
// had identical decodeXmlEntities/extractTag/parseFeedItems bodies
// before this file existed.

// Some feeds' <description> carries real markup, not plain text — UOL
// embeds a leading <img .../> tag before the actual sentence, Agência
// Brasil double-encodes whole <p> paragraphs. Stripped unconditionally
// before classification/display: legitimate crime keywords are always
// in the text content, never the markup itself, so this only ever
// removes noise, never signal.
export function stripHtmlTags(text: string): string {
  return text.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

export function decodeXmlEntities(text: string): string {
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&apos;/g, "'")
    .trim();
}

export function extractTag(itemXml: string, tag: string): string | undefined {
  const cdataMatch = new RegExp(`<${tag}[^>]*>\\s*<!\\[CDATA\\[(.*?)\\]\\]>\\s*</${tag}>`, "s").exec(itemXml);
  if (cdataMatch) return decodeXmlEntities(cdataMatch[1]);
  const plainMatch = new RegExp(`<${tag}[^>]*>(.*?)</${tag}>`, "s").exec(itemXml);
  return plainMatch ? decodeXmlEntities(plainMatch[1]) : undefined;
}

export interface RssFeedItem {
  title: string;
  subtitle: string;
  link: string;
  guid: string;
  pubDate?: string;
}

// subtitleTag lets a caller point at whichever tag actually carries a
// second line of text — G1 injects a non-standard "atom:subtitle" tag
// into an otherwise plain RSS 2.0 feed; every other feed checked so far
// (BBC, CNN Brasil, Metrópoles, UOL, Agência Brasil, Diário Online,
// Folha) uses the standard RSS "description".
export function parseFeedItems(xml: string, subtitleTag = "description"): RssFeedItem[] {
  const items: RssFeedItem[] = [];
  const itemRe = /<item>(.*?)<\/item>/gs;
  let match: RegExpExecArray | null;
  while ((match = itemRe.exec(xml))) {
    const itemXml = match[1];
    const title = extractTag(itemXml, "title");
    const link = extractTag(itemXml, "link");
    const guid = extractTag(itemXml, "guid") ?? link;
    if (!title || !link || !guid) continue;
    items.push({
      title,
      subtitle: extractTag(itemXml, subtitleTag) ?? "",
      link,
      guid,
      pubDate: extractTag(itemXml, "pubDate"),
    });
  }
  return items;
}

// Not every feed is UTF-8. Two real cases found live 2026-08-29:
//   - Folha de S.Paulo's "Em cima da hora" feed declares
//     encoding="ISO-8859-1" in its own XML prolog.
//   - UOL's feed (rss.uol.com.br) declares NO encoding in the XML
//     prolog at all — only in its HTTP response header
//     (Content-Type: text/xml;charset=ISO-8859-1).
// Both genuinely ARE Latin-1-encoded; decoding either as UTF-8 (what
// res.text() always does, regardless of what the document or its
// headers declare) garbles every accented character ("Pol�cia" instead
// of "Polícia"). contentTypeHeader (pass the fetch response's own
// Content-Type when calling this) is checked FIRST since it's the more
// authoritative signal per HTTP semantics and is the ONLY signal UOL
// gives; the XML prolog's own encoding= is the fallback for feeds like
// Folha that only declare it there. Defaults to utf-8 when neither is
// present (every other feed this project reads).
export function decodeXmlBytes(buffer: ArrayBuffer, contentTypeHeader?: string | null): string {
  const headerMatch = contentTypeHeader ? /charset=([^;\s]+)/i.exec(contentTypeHeader) : null;
  let encoding = headerMatch?.[1]?.toLowerCase();
  if (!encoding) {
    const asciiPeek = new TextDecoder("ascii").decode(buffer.slice(0, 200));
    const prologMatch = /encoding=["']([^"']+)["']/i.exec(asciiPeek);
    encoding = prologMatch ? prologMatch[1].toLowerCase() : "utf-8";
  }
  try {
    return new TextDecoder(encoding).decode(buffer);
  } catch {
    // An unrecognised/unsupported label (TextDecoder throws on those)
    // shouldn't sink the whole fetch — a feed that's merely mislabeled
    // is still better read as UTF-8 than not read at all.
    return new TextDecoder("utf-8").decode(buffer);
  }
}

// Not every feed's pubDate is real RFC822/English either: UOL's feed
// writes Portuguese weekday/month abbreviations ("Sáb, 29 Ago 2026
// 08:14:25 -0300") — verified live, `new Date()` returns Invalid Date
// for this (it only recognises English month/weekday names). The
// weekday name is redundant with the date itself, so this just drops it
// and translates the month abbreviation, then lets the platform's own
// RFC822 parser handle the (now-English) remainder rather than
// hand-rolling numeric field parsing.
const PT_MONTH_TO_EN: Record<string, string> = {
  jan: "Jan", fev: "Feb", mar: "Mar", abr: "Apr", mai: "May", jun: "Jun",
  jul: "Jul", ago: "Aug", set: "Sep", out: "Oct", nov: "Nov", dez: "Dec",
};

export function parsePossiblyPtBrDate(dateStr: string): Date | undefined {
  const direct = new Date(dateStr);
  if (!Number.isNaN(direct.getTime())) return direct;

  // "{weekday-pt,} DD {month-pt} YYYY HH:MM:SS [tz]" — weekday prefix
  // (with its trailing comma) is optional and simply dropped.
  const match = /^(?:\S+,\s*)?(\d{1,2})\s+([a-zçã]{3})\s+(\d{4})\s+(\d{2}:\d{2}:\d{2})\s*(.*)$/i.exec(
    dateStr.trim(),
  );
  if (!match) return undefined;
  const [, day, monthPt, year, time, tz] = match;
  const monthEn = PT_MONTH_TO_EN[monthPt.toLowerCase()];
  if (!monthEn) return undefined;

  const rebuilt = `${day} ${monthEn} ${year} ${time} ${tz}`.trim();
  const parsed = new Date(rebuilt);
  return Number.isNaN(parsed.getTime()) ? undefined : parsed;
}
