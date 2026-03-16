export type AmisRawScrapeRecord = {
  commodityName: string;
  rawLabel: string;
  commodityId: number;
  mandiName: string;
  city: string;
  district: string;
  province: string;
  price: number;
  unit: string;
  rateDate: Date;
  metadata: Record<string, unknown>;
};

export type AmisScrapeResult = {
  sourceUrl: string;
  dataFormat: "html";
  columns: string[];
  records: AmisRawScrapeRecord[];
  rawRows: number;
  newestTimestamp: Date | null;
};

const AMIS_DEFAULT_BASE_URL = "http://www.amis.pk";
const REQUEST_TIMEOUT_MS = 45000;
const REQUEST_RETRIES = 2;

// Full commodity specs with per-category unit for correct comparability.
// order matters: more specific entries (basmati, irri) must precede generic "rice".
const MANDI_COMMODITY_SPECS: Array<{
  canonical: string;
  aliases: string[];
  category: string;
  subCategory: string;
  unit: string;
}> = [
  { canonical: "Wheat", aliases: ["wheat", "gandum", "\u06af\u0646\u062f\u0645"], category: "crops", subCategory: "wheat", unit: "Rs/100Kg" },
  { canonical: "Basmati Rice", aliases: ["basmati"], category: "crops", subCategory: "basmati_rice", unit: "Rs/100Kg" },
  { canonical: "Irri Rice", aliases: ["irri"], category: "crops", subCategory: "irri_rice", unit: "Rs/100Kg" },
  { canonical: "Rice", aliases: ["rice", "chawal", "\u0686\u0627\u0648\u0644"], category: "crops", subCategory: "rice", unit: "Rs/100Kg" },
  { canonical: "Corn", aliases: ["corn", "maize", "makai", "\u0645\u06a9\u0626\u06cc", "\u0645\u06a9\u06cc"], category: "crops", subCategory: "maize", unit: "Rs/100Kg" },
  { canonical: "Cotton", aliases: ["cotton", "kapas"], category: "crops", subCategory: "cotton", unit: "Rs/100Kg" },
  { canonical: "Sugarcane", aliases: ["sugarcane", "ganna", "\u06af\u0646\u0627"], category: "crops", subCategory: "sugarcane", unit: "Rs/100Kg" },
  { canonical: "Onion", aliases: ["onion", "pyaz", "\u067e\u06cc\u0627\u0632"], category: "vegetables", subCategory: "onion", unit: "Rs/40Kg" },
  { canonical: "Potato", aliases: ["potato", "aloo", "\u0622\u0644\u0648"], category: "vegetables", subCategory: "potato", unit: "Rs/40Kg" },
  { canonical: "Tomato", aliases: ["tomato", "tamatar", "\u0679\u0645\u0627\u0679\u0631"], category: "vegetables", subCategory: "tomato", unit: "Rs/40Kg" },
  { canonical: "Garlic", aliases: ["garlic", "lehsan", "\u0644\u06c1\u0633\u0646"], category: "vegetables", subCategory: "garlic", unit: "Rs/40Kg" },
  { canonical: "Chilli", aliases: ["chilli", "chili", "mirch", "\u0645\u0631\u0686"], category: "vegetables", subCategory: "chilli", unit: "Rs/40Kg" },
  { canonical: "Lentil", aliases: ["lentil", "masoor", "\u0645\u0633\u0648\u0631", "masur"], category: "pulses", subCategory: "masoor", unit: "Rs/100Kg" },
  { canonical: "Chickpea", aliases: ["chickpea", "gram", "chana", "\u0686\u0646\u0627"], category: "pulses", subCategory: "chana", unit: "Rs/100Kg" },
  { canonical: "Mung Bean", aliases: ["mung", "moong", "\u0645\u0648\u0646\u06af"], category: "pulses", subCategory: "mung", unit: "Rs/100Kg" },
  { canonical: "Apple", aliases: ["apple", "seb"], category: "fruits", subCategory: "apple", unit: "Rs/40Kg" },
  { canonical: "Banana", aliases: ["banana", "kela"], category: "fruits", subCategory: "banana", unit: "Rs/dozen" },
  { canonical: "Mango", aliases: ["mango", "aam"], category: "fruits", subCategory: "mango", unit: "Rs/40Kg" },
  { canonical: "Orange", aliases: ["orange", "kino"], category: "fruits", subCategory: "orange", unit: "Rs/40Kg" },
  { canonical: "Coriander", aliases: ["coriander", "dhania"], category: "spices", subCategory: "coriander", unit: "Rs/40Kg" },
  { canonical: "Turmeric", aliases: ["turmeric", "haldi"], category: "spices", subCategory: "turmeric", unit: "Rs/40Kg" },
  { canonical: "Cumin", aliases: ["cumin", "zeera", "zira"], category: "spices", subCategory: "cumin", unit: "Rs/40Kg" },
  { canonical: "DAP", aliases: ["dap", "di ammonium phosphate"], category: "fertilizer", subCategory: "dap", unit: "Rs/50Kg" },
  { canonical: "Urea", aliases: ["urea"], category: "fertilizer", subCategory: "urea", unit: "Rs/50Kg" },
  { canonical: "Wheat Seed", aliases: ["wheat seed", "seed wheat"], category: "seeds", subCategory: "wheat_seed", unit: "Rs/100Kg" },
  { canonical: "Maize Seed", aliases: ["maize seed", "corn seed"], category: "seeds", subCategory: "maize_seed", unit: "Rs/100Kg" },
  { canonical: "Goat", aliases: ["goat", "bakra"], category: "livestock", subCategory: "goat", unit: "Rs/head" },
  { canonical: "Cow", aliases: ["cow", "gai"], category: "livestock", subCategory: "cow", unit: "Rs/head" },
];

type CommodityLink = {
  id: number;
  label: string;
  url: string;
};

type ParsedCityRow = {
  city: string;
  minPrice: number | null;
  maxPrice: number | null;
  fqp: number | null;
  quantity: number | null;
};

function normalizeWhitespace(input: string): string {
  return input.replace(/\s+/g, " ").trim();
}

function decodeHtml(input: string): string {
  return input
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#x([0-9a-f]+);/gi, (_m, hex: string) => String.fromCharCode(Number.parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_m, dec: string) => String.fromCharCode(Number.parseInt(dec, 10)));
}

function stripTags(input: string): string {
  return input.replace(/<[^>]+>/g, " ");
}

function cleanCell(input: string): string {
  return normalizeWhitespace(decodeHtml(stripTags(input)));
}

function toFinite(value: string): number | null {
  const cleaned = value.replace(/,/g, "").replace(/[^\d.+-]/g, "");
  if (!cleaned || cleaned === "-" || cleaned === ".") {
    return null;
  }
  const num = Number.parseFloat(cleaned);
  return Number.isFinite(num) ? num : null;
}

function parseRateDate(html: string): Date | null {
  const match = html.match(/Dated:\s*(\d{2})-(\d{2})-(\d{4})/i);
  if (!match) return null;
  const day = Number.parseInt(match[1], 10);
  const month = Number.parseInt(match[2], 10);
  const year = Number.parseInt(match[3], 10);
  const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
  return Number.isNaN(date.getTime()) ? null : date;
}

function parseUnitLabel(html: string): string | null {
  const text = cleanCell(html).toLowerCase();

  const direct = text.match(/rs\s*\/?\s*(\d+)\s*kg/i);
  if (direct && direct[1]) {
    return `Rs/${direct[1]}Kg`;
  }

  if (text.includes("maund") || text.includes("mond")) return "Rs/40Kg";
  if (text.includes("per kg") || text.includes("/kg")) return "Rs/Kg";
  if (text.includes("dozen") || text.includes("doz")) return "Rs/dozen";
  return null;
}

async function fetchText(url: string): Promise<string> {
  let lastError: unknown = null;
  for (let attempt = 0; attempt <= REQUEST_RETRIES; attempt += 1) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    try {
      const response = await fetch(url, {
        method: "GET",
        signal: controller.signal,
        headers: {
          "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
          "user-agent": "digital-arhat-functions/1.0",
        },
      });
      if (!response.ok) {
        throw new Error(`amis_http_${response.status}`);
      }
      return await response.text();
    } catch (error) {
      lastError = error;
      if (attempt >= REQUEST_RETRIES) {
        throw error;
      }
    } finally {
      clearTimeout(timeout);
    }
  }

  throw new Error(`amis_fetch_failed_${String(lastError ?? "unknown")}`);
}

function parseCommodityLinks(html: string, baseUrl: string): CommodityLink[] {
  const out: CommodityLink[] = [];
  const regex = /<A\s+href='ViewPrices\.aspx\?searchType=0&commodityId=(\d+)'>([\s\S]*?)<\/A>/gi;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(html)) != null) {
    const id = Number.parseInt(match[1], 10);
    if (!Number.isFinite(id)) continue;
    const label = cleanCell(match[2]);
    if (!label) continue;
    out.push({
      id,
      label,
      url: `${baseUrl}/ViewPrices.aspx?searchType=0&commodityId=${id}`,
    });
  }

  const deduped = new Map<number, CommodityLink>();
  for (const link of out) {
    if (!deduped.has(link.id)) {
      deduped.set(link.id, link);
    }
  }
  return Array.from(deduped.values());
}

function matchCommoditySpec(label: string): typeof MANDI_COMMODITY_SPECS[0] | null {
  const value = label.toLowerCase();
  for (const spec of MANDI_COMMODITY_SPECS) {
    if (spec.aliases.some((alias) => value.includes(alias.toLowerCase()))) {
      return spec;
    }
  }
  return null;
}

function parseCityRows(html: string): ParsedCityRow[] {
  const rows: ParsedCityRow[] = [];
  const rowRegex = /<tr[^>]*>\s*<td[^>]*>[\s\S]*?<a\s+href='[^']*searchType=1&commodityId=\d+'>([\s\S]*?)<\/a>[\s\S]*?<\/td>\s*<td[^>]*>[\s\S]*?<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<td[^>]*>([\s\S]*?)<\/td>\s*<\/tr>/gi;
  let match: RegExpExecArray | null;
  while ((match = rowRegex.exec(html)) != null) {
    const city = cleanCell(match[1]);
    if (!city) continue;

    const minPrice = toFinite(cleanCell(match[2]));
    const maxPrice = toFinite(cleanCell(match[3]));
    const fqp = toFinite(cleanCell(match[4]));
    const quantity = toFinite(cleanCell(match[5]));

    const priceCandidate = fqp ?? ((minPrice != null && maxPrice != null) ? (minPrice + maxPrice) / 2 : null);
    if (priceCandidate == null || priceCandidate <= 0) {
      continue;
    }

    rows.push({
      city,
      minPrice,
      maxPrice,
      fqp,
      quantity,
    });
  }

  return rows;
}

export async function scrapeAmisRates(baseUrlEnv?: string): Promise<AmisScrapeResult> {
  const baseUrl = (baseUrlEnv || process.env.AMIS_BASE_URL || AMIS_DEFAULT_BASE_URL).replace(/\/+$/, "");
  const browseUrl = `${baseUrl}/BrowsePrices.aspx?searchType=0`;

  const browseHtml = await fetchText(browseUrl);
  const commodityLinks = parseCommodityLinks(browseHtml, baseUrl);
  if (commodityLinks.length === 0) {
    throw new Error("amis_parse_no_commodity_links");
  }

  const selected = commodityLinks.filter((item) => matchCommoditySpec(item.label) != null);
  if (selected.length === 0) {
    throw new Error("amis_parse_required_commodities_not_found");
  }

  const selectedBySpec = new Map<string, CommodityLink>();
  for (const commodity of selected) {
    const spec = matchCommoditySpec(commodity.label);
    if (!spec) continue;
    if (!selectedBySpec.has(spec.canonical)) {
      selectedBySpec.set(spec.canonical, commodity);
    }
  }
  const selectedUnique = Array.from(selectedBySpec.values());

  const records: AmisRawScrapeRecord[] = [];
  let newestTimestamp: Date | null = null;
  const skippedCommodities: Array<{commodityId: number; label: string; reason: string}> = [];
  for (const commodity of selectedUnique) {
    let commodityHtml = "";
    try {
      commodityHtml = await fetchText(commodity.url);
    } catch (error) {
      skippedCommodities.push({
        commodityId: commodity.id,
        label: commodity.label,
        reason: String(error),
      });
      continue;
    }

    const rateDate = parseRateDate(commodityHtml);
    const unitLabel = parseUnitLabel(commodityHtml);
    const cityRows = parseCityRows(commodityHtml);
    for (const row of cityRows) {
      const effectiveDate = rateDate ?? new Date();
      if (!newestTimestamp || effectiveDate > newestTimestamp) {
        newestTimestamp = effectiveDate;
      }

      const spec = matchCommoditySpec(commodity.label);
      records.push({
        commodityName: commodity.label,
        rawLabel: commodity.label,
        commodityId: commodity.id,
        mandiName: row.city,
        city: row.city,
        district: row.city,
        province: "Punjab",
        price: row.fqp ?? ((row.minPrice ?? 0) + (row.maxPrice ?? 0)) / 2,
        unit: unitLabel ?? spec?.unit ?? "Rs/100Kg",
        rateDate: effectiveDate,
        metadata: {
          sourcePage: commodity.url,
          commodityId: commodity.id,
          rawLabel: commodity.label,
          unitLabel: unitLabel ?? spec?.unit ?? "Rs/100Kg",
          minPrice: row.minPrice,
          maxPrice: row.maxPrice,
          fqp: row.fqp,
          quantity: row.quantity,
        },
      });
    }
  }

  if (records.length === 0) {
    const skipReason = skippedCommodities.slice(0, 3).map((item) => `${item.commodityId}:${item.reason}`).join(";");
    throw new Error(`amis_parse_no_rows${skipReason ? `_${skipReason}` : ""}`);
  }

  return {
    sourceUrl: browseUrl,
    dataFormat: "html",
    columns: ["Dated", "City", "Min", "Max", "FQP", "Quantity"],
    records,
    rawRows: records.length,
    newestTimestamp,
  };
}