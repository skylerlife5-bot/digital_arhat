"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.LahoreOfficialAdapter = void 0;
const SOURCE_ID = "lahore_official_market_rates";
const DEFAULT_URL = "https://lahore.punjab.gov.pk/vegetables-rate-list";
function cleanCell(input) {
    return input
        .replace(/<[^>]+>/g, " ")
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/\s+/g, " ")
        .trim();
}
function toFinite(value) {
    const parsed = Number.parseFloat(value
        .replace(/,/g, "")
        .replace(/rs\.?/gi, "")
        .replace(/pkr/gi, "")
        .replace(/[^\d.+-]/g, ""));
    return Number.isFinite(parsed) ? parsed : null;
}
function parseRows(html, now) {
    const rows = [];
    const trRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let trMatch;
    while ((trMatch = trRegex.exec(html)) != null) {
        const rowHtml = trMatch[1];
        const tdRegex = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
        const cells = [];
        let tdMatch;
        while ((tdMatch = tdRegex.exec(rowHtml)) != null) {
            cells.push(cleanCell(tdMatch[1]));
        }
        if (cells.length < 2)
            continue;
        const commodity = cells[0];
        const commodityLooksLikeDate = /^(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\s+\d{1,2},\s+\d{4}$/i.test(commodity);
        if (commodityLooksLikeDate)
            continue;
        const hasPriceContext = cells.some((cell) => /\b(rs|pkr|price|kg|dozen|maund)\b/i.test(cell));
        if (!hasPriceContext)
            continue;
        const candidatePrice = cells
            .map((cell) => toFinite(cell))
            .find((price) => price != null && price > 0) ?? null;
        if (!commodity || candidatePrice == null)
            continue;
        rows.push({
            sourceId: SOURCE_ID,
            sourceType: "official_market_committee",
            sourceName: "Lahore Official Market Rates",
            commodityName: commodity,
            categoryName: "fruits_vegetables_essentials",
            subCategoryName: "official_list",
            mandiName: "Lahore Official Market",
            city: "Lahore",
            district: "Lahore",
            province: "Punjab",
            price: candidatePrice,
            previousPrice: null,
            unit: "PKR/kg",
            currency: "PKR",
            trend: "same",
            lastUpdated: now,
            metadata: {
                parser: "html_table_scan",
            },
        });
    }
    return rows;
}
function extractRateSheetLinks(html) {
    const links = [];
    const regex = /href=\"([^\"]*\/system\/files\?file=[^\"]+)\"/gi;
    let match;
    while ((match = regex.exec(html)) != null) {
        const raw = String(match[1] ?? "").trim();
        if (!raw)
            continue;
        links.push(raw);
    }
    return Array.from(new Set(links));
}
class LahoreOfficialAdapter {
    async fetchRows(context) {
        const sourceUrl = String(process.env.LAHORE_OFFICIAL_SOURCE_URL ?? DEFAULT_URL).trim();
        const response = await fetch(sourceUrl, {
            method: "GET",
            headers: {
                "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "user-agent": "digital-arhat-functions/1.0",
            },
        });
        if (!response.ok) {
            throw new Error(`lahore_official_http_${response.status}`);
        }
        const html = await response.text();
        const looksLikeRateList = /view-field-rate-list-date-table-column/i.test(html) &&
            /view-field-retail-price-list-table-column/i.test(html);
        const sheetLinks = extractRateSheetLinks(html);
        const rows = parseRows(html, context.now).map((item) => ({
            ...item,
            metadata: {
                ...(item.metadata ?? {}),
                sourceUrl,
            },
        }));
        if (rows.length === 0 && looksLikeRateList && sheetLinks.length > 0) {
            throw new Error("lahore_official_only_image_rate_lists");
        }
        context.logger("source_fetched", {
            sourceId: SOURCE_ID,
            rawRows: rows.length,
            sourceUrl,
            imageRateSheetLinks: sheetLinks.slice(0, 5),
        });
        return rows;
    }
}
exports.LahoreOfficialAdapter = LahoreOfficialAdapter;
