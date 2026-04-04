"use strict";
/**
 * fscpd_official_adapter.ts
 *
 * Punjab FS&CPD (Food Supplies & Consumer Protection Department)
 * District-wise Daily Notified Rates — PRIMARY trusted ticker source.
 *
 * Source characteristics:
 *  - Official Government of Punjab daily publication
 *  - District-wise coverage (all Punjab districts)
 *  - Machine-readable HTML table
 *  - Published early morning each working day
 *  - Format: District | Commodity | Min Rate | Max Rate | Unit
 *
 * URL is configurable via FSCPD_OFFICIAL_SOURCE_URL environment variable.
 * Fallback: https://www.fscpunjab.gov.pk/notified-rates
 *
 * sourceId:   "fscpd_official"
 * trustLevel: "high"
 * sourceReliability priority: 4 (highest — above Lahore/Karachi/AMIS)
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.FscpdOfficialAdapter = void 0;
const unit_rules_1 = require("./unit_rules");
const SOURCE_ID = "fscpd_official";
const DEFAULT_URL = "https://www.fscpunjab.gov.pk/notified-rates";
const REQUEST_TIMEOUT_MS = 45_000;
const REQUEST_RETRIES = 2;
// ---------------------------------------------------------------------------
// Punjab district canonical names (for normalisation)
// ---------------------------------------------------------------------------
const PUNJAB_DISTRICTS = {
    lahore: "Lahore",
    gujranwala: "Gujranwala",
    faisalabad: "Faisalabad",
    rawalpindi: "Rawalpindi",
    multan: "Multan",
    bahawalpur: "Bahawalpur",
    sargodha: "Sargodha",
    sialkot: "Sialkot",
    gujrat: "Gujrat",
    sheikhupura: "Sheikhupura",
    sahiwal: "Sahiwal",
    okara: "Okara",
    rahim_yar_khan: "Rahim Yar Khan",
    rahimyarkhan: "Rahim Yar Khan",
    kasur: "Kasur",
    nankana: "Nankana Sahib",
    mandi_bahauddin: "Mandi Bahauddin",
    hafizabad: "Hafizabad",
    chiniot: "Chiniot",
    jhelum: "Jhelum",
    chakwal: "Chakwal",
    attock: "Attock",
    khushab: "Khushab",
    mianwali: "Mianwali",
    bhakkar: "Bhakkar",
    khanewal: "Khanewal",
    lodhran: "Lodhran",
    vehari: "Vehari",
    pakpattan: "Pakpattan",
    toba_tek_singh: "Toba Tek Singh",
    tobateksingh: "Toba Tek Singh",
    muzaffargarh: "Muzaffargarh",
    layyah: "Layyah",
    dgkhan: "D.G. Khan",
    dg_khan: "D.G. Khan",
    "d.g.khan": "D.G. Khan",
    deraghazikhan: "D.G. Khan",
    rajanpur: "Rajanpur",
};
function canonicalDistrict(raw) {
    const key = raw.toLowerCase().replace(/\s+/g, "_").replace(/[^a-z0-9_]/g, "");
    return PUNJAB_DISTRICTS[key] ?? raw.trim();
}
// ---------------------------------------------------------------------------
// HTML helpers
// ---------------------------------------------------------------------------
function cleanCell(input) {
    return input
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&#x([0-9a-f]+);/gi, (_m, hex) => String.fromCharCode(Number.parseInt(hex, 16)))
        .replace(/\s+/g, " ")
        .trim();
}
function toPositiveFinite(value) {
    const cleaned = value.replace(/,/g, "").replace(/rs\.?/gi, "").replace(/pkr/gi, "").replace(/[^\d.]/g, "");
    if (!cleaned)
        return null;
    const n = Number.parseFloat(cleaned);
    return Number.isFinite(n) && n > 0 ? n : null;
}
/**
 * Parse the publish date from FS&CPD page. Looks for patterns like:
 *   "Notified Rates 28-03-2026" or "Date: 28/03/2026"
 */
function parsePublishDate(html, now) {
    const dmy = html.match(/(\d{1,2})[-\/](\d{1,2})[-\/](\d{4})/);
    if (dmy) {
        const day = Number.parseInt(dmy[1], 10);
        const month = Number.parseInt(dmy[2], 10);
        const year = Number.parseInt(dmy[3], 10);
        if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            const d = new Date(Date.UTC(year, month - 1, day, 8, 0, 0));
            if (!Number.isNaN(d.getTime()))
                return d;
        }
    }
    // Fallback: today at 08:00 PKT (UTC+5 = UTC−5h offset → UTC 03:00)
    const today = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate(), 3, 0, 0));
    return today;
}
/**
 * Detect the unit from page-level or table-header context.
 * FS&CPD typically publishes rates in PKR per 40kg (maund) or PKR per kg.
 */
function detectPageUnit(html) {
    const lower = html.toLowerCase();
    if (lower.match(/per\s*40\s*kg|per\s*maund|pkr\s*\/\s*40\s*kg|rs\.\s*\/\s*40\s*kg/))
        return "PKR/40Kg";
    if (lower.match(/per\s*100\s*kg|pkr\s*\/\s*100\s*kg/))
        return "PKR/100Kg";
    if (lower.match(/per\s*kg|pkr\s*\/\s*kg/))
        return "PKR/Kg";
    // Default for FS&CPD district rates
    return "PKR/40Kg";
}
/**
 * Parse rows from the FS&CPD HTML notified-rates table.
 *
 * The table typically has columns in one of these formats:
 *   [District, Commodity, Min, Max]
 *   [Commodity, District, Min, Max]
 *   [District, Commodity, Rate]   (single rate)
 *   [#, District, Commodity, Min, Max, Unit]
 *
 * We detect the column order from the <thead> row, falling back to
 * heuristic detection (first non-numeric = district, second = commodity).
 */
function parseHtmlTable(html, pageUnit) {
    const rows = [];
    const tableMatch = html.match(/<table[\s\S]*?<\/table>/gi);
    if (!tableMatch)
        return rows;
    // Use the first substantial table
    for (const tableHtml of tableMatch) {
        const trRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
        let trMatch;
        let headerCols = [];
        let districtCol = -1;
        let commodityCol = -1;
        let minCol = -1;
        let maxCol = -1;
        let rateCol = -1;
        let unitCol = -1;
        let headerParsed = false;
        while ((trMatch = trRegex.exec(tableHtml)) != null) {
            const rowHtml = trMatch[1];
            const cellRegex = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
            const cells = [];
            let cellMatch;
            while ((cellMatch = cellRegex.exec(rowHtml)) != null) {
                cells.push(cleanCell(cellMatch[1]));
            }
            if (cells.length < 2)
                continue;
            // Detect header row (contains <th> or recognisable column labels)
            const isHeaderRow = rowHtml.toLowerCase().includes("<th");
            const looksLikeHeader = cells.some((c) => /district|city|commodity|item|min|max|rate|unit|sr/i.test(c));
            if (!headerParsed && (isHeaderRow || looksLikeHeader)) {
                headerCols = cells.map((c) => c.toLowerCase().trim());
                headerCols.forEach((col, i) => {
                    if (/^(sr|#|no\.?)$/.test(col))
                        return;
                    if (/district|city|mandi/.test(col) && districtCol < 0)
                        districtCol = i;
                    if (/commodity|item|product|description|crop/.test(col) && commodityCol < 0)
                        commodityCol = i;
                    if (/min|minimum/.test(col) && minCol < 0)
                        minCol = i;
                    if (/max|maximum/.test(col) && maxCol < 0)
                        maxCol = i;
                    if (/\brate\b/.test(col) && rateCol < 0)
                        rateCol = i;
                    if (/unit/.test(col) && unitCol < 0)
                        unitCol = i;
                });
                headerParsed = true;
                continue;
            }
            // Data row — skip if majority of cells are empty or all numeric
            const nonEmpty = cells.filter((c) => c.trim() !== "");
            if (nonEmpty.length < 2)
                continue;
            // Heuristic fallback when header could not be parsed
            if (!headerParsed || (districtCol < 0 && commodityCol < 0)) {
                // Auto-detect: first two non-numeric columns are district and commodity
                let firstText = -1;
                let secondText = -1;
                for (let i = 0; i < cells.length; i++) {
                    if (!/^\d/.test(cells[i]) && cells[i].trim()) {
                        if (firstText < 0)
                            firstText = i;
                        else if (secondText < 0) {
                            secondText = i;
                            break;
                        }
                    }
                }
                if (firstText < 0 || secondText < 0)
                    continue;
                districtCol = firstText;
                commodityCol = secondText;
                // Remaining numeric cols = min, max
                const numericCols = cells
                    .map((c, i) => ({ i, v: toPositiveFinite(c) }))
                    .filter((item) => item.v !== null && item.i !== districtCol && item.i !== commodityCol);
                if (numericCols.length >= 1)
                    minCol = numericCols[0].i;
                if (numericCols.length >= 2)
                    maxCol = numericCols[1].i;
            }
            const district = districtCol >= 0 ? cells[districtCol] ?? "" : "";
            const commodity = commodityCol >= 0 ? cells[commodityCol] ?? "" : "";
            if (!district.trim() || !commodity.trim())
                continue;
            // Skip obvious header echoes in data rows
            if (/district|commodity|item|min|max/i.test(commodity))
                continue;
            const minPrice = minCol >= 0 ? toPositiveFinite(cells[minCol] ?? "") : null;
            const maxPrice = maxCol >= 0 ? toPositiveFinite(cells[maxCol] ?? "") : null;
            const ratePrice = rateCol >= 0 ? toPositiveFinite(cells[rateCol] ?? "") : null;
            const unitOverride = unitCol >= 0 ? cells[unitCol] ?? "" : "";
            const effectiveMin = minPrice ?? ratePrice;
            const effectiveMax = maxPrice ?? ratePrice;
            if (effectiveMin === null && effectiveMax === null)
                continue;
            rows.push({
                district: district.trim(),
                commodity: commodity.trim(),
                minPrice: effectiveMin,
                maxPrice: effectiveMax,
                unit: unitOverride.trim() || pageUnit,
            });
        }
        if (rows.length > 0)
            break; // First table that yielded data wins
    }
    return rows;
}
// ---------------------------------------------------------------------------
// HTTP fetch with retry
// ---------------------------------------------------------------------------
async function fetchHtml(url) {
    let lastError;
    for (let attempt = 0; attempt <= REQUEST_RETRIES; attempt++) {
        const ctrl = new AbortController();
        const timer = setTimeout(() => ctrl.abort(), REQUEST_TIMEOUT_MS);
        try {
            const resp = await fetch(url, {
                method: "GET",
                signal: ctrl.signal,
                headers: {
                    accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    "user-agent": "digital-arhat-functions/1.0",
                    "accept-language": "en-PK,en;q=0.8,ur;q=0.5",
                },
            });
            if (!resp.ok)
                throw new Error(`fscpd_http_${resp.status}`);
            return await resp.text();
        }
        catch (err) {
            lastError = err;
            if (attempt >= REQUEST_RETRIES)
                break;
            await new Promise((r) => setTimeout(r, 1_500 * (attempt + 1)));
        }
        finally {
            clearTimeout(timer);
        }
    }
    throw new Error(`fscpd_fetch_failed: ${String(lastError ?? "unknown")}`);
}
// ---------------------------------------------------------------------------
// Adapter
// ---------------------------------------------------------------------------
class FscpdOfficialAdapter {
    async fetchRows(context) {
        const sourceUrl = String(process.env.FSCPD_OFFICIAL_SOURCE_URL ?? DEFAULT_URL).trim();
        const html = await fetchHtml(sourceUrl);
        const publishDate = parsePublishDate(html, context.now);
        const pageUnit = detectPageUnit(html);
        const parsed = parseHtmlTable(html, pageUnit);
        context.logger("fscpd_fetched", {
            sourceId: SOURCE_ID,
            sourceUrl,
            pageUnit,
            publishDate: publishDate.toISOString(),
            rawRows: parsed.length,
        });
        const rows = [];
        for (const item of parsed) {
            const commodity = item.commodity.trim();
            const district = canonicalDistrict(item.district);
            if (!commodity || !district)
                continue;
            const minPrice = item.minPrice;
            const maxPrice = item.maxPrice;
            const avgPrice = minPrice !== null && maxPrice !== null
                ? (minPrice + maxPrice) / 2
                : minPrice ?? maxPrice ?? 0;
            if (avgPrice <= 0)
                continue;
            // Unit validation: reject impossible combos before they enter pipeline
            const unitCheck = (0, unit_rules_1.checkUnitForCommodity)(item.unit, commodity);
            if (!unitCheck.allowed) {
                context.logger("fscpd_unit_rejected", {
                    commodity,
                    district,
                    unit: item.unit,
                    reason: unitCheck.reason,
                });
                continue;
            }
            rows.push({
                sourceId: SOURCE_ID,
                sourceType: "official_national_source",
                sourceName: "Punjab FS&CPD Notified Rates",
                commodityName: commodity,
                categoryName: "crops",
                subCategoryName: "other",
                mandiName: `${district} Mandi`,
                city: district,
                district,
                province: "Punjab",
                price: avgPrice,
                previousPrice: null,
                minPrice,
                maxPrice,
                unit: item.unit,
                currency: "PKR",
                trend: "same",
                lastUpdated: publishDate,
                metadata: {
                    sourceUrl,
                    minPrice,
                    maxPrice,
                    averagePrice: avgPrice,
                    districtNorm: district.toLowerCase(),
                    unitNorm: unitCheck.normalizedUnit,
                    unitValidated: true,
                },
            });
        }
        context.logger("fscpd_parsed", {
            sourceId: SOURCE_ID,
            parsedRows: rows.length,
            rejectedRows: parsed.length - rows.length,
        });
        return rows;
    }
}
exports.FscpdOfficialAdapter = FscpdOfficialAdapter;
