"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.KarachiOfficialAdapter = void 0;
const SOURCE_ID = "karachi_official_price_lists";
const DEFAULT_URL = "https://commissionerkarachi.gos.pk/karachi/pricelist";
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
function looksLikeDateToken(value) {
    const text = String(value ?? "").trim();
    if (!text)
        return false;
    if (/\b\d{2}\d{2}\d{4}\b/.test(text))
        return true;
    if (/\b\d{1,2}[\/\-]\d{1,2}[\/\-]\d{2,4}\b/.test(text))
        return true;
    return false;
}
function detectCommodityIndex(cells) {
    // In Karachi table commodity is usually first text column after serial/date.
    for (let i = 0; i < Math.min(cells.length, 4); i += 1) {
        const cell = cells[i] ?? "";
        if (!cell)
            continue;
        if (looksLikeDateToken(cell))
            continue;
        if (/^\d+$/.test(cell))
            continue;
        return i;
    }
    return 0;
}
function detectWholesalePriceIndex(cells, headerCells) {
    if (headerCells && headerCells.length > 0) {
        for (let i = 0; i < headerCells.length; i += 1) {
            const h = (headerCells[i] ?? "").toLowerCase();
            if (/(wholesale|thok|rate|price)/.test(h) && !/(date|serial|sr\.?\s*no)/.test(h)) {
                return i;
            }
        }
    }
    // Current observed Karachi markup usually places wholesale at 3 or 4.
    if (cells.length > 4)
        return 4;
    if (cells.length > 3)
        return 3;
    return Math.max(1, cells.length - 1);
}
function pickPriceFromRow(cells, startIdx) {
    for (let i = startIdx; i < cells.length; i += 1) {
        const token = cells[i] ?? "";
        if (looksLikeDateToken(token) || token.includes("/"))
            continue;
        const value = toFinite(token);
        if (value != null && value > 0) {
            return { price: value, usedIndex: i };
        }
    }
    for (let i = 0; i < startIdx; i += 1) {
        const token = cells[i] ?? "";
        if (looksLikeDateToken(token) || token.includes("/"))
            continue;
        const value = toFinite(token);
        if (value != null && value > 0) {
            return { price: value, usedIndex: i };
        }
    }
    return { price: null, usedIndex: null };
}
function parseRows(html, now) {
    const out = [];
    const trRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let trMatch;
    let headerCells = null;
    let rowIndex = -1;
    while ((trMatch = trRegex.exec(html)) != null) {
        rowIndex += 1;
        const rowHtml = trMatch[1];
        const tdRegex = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
        const cells = [];
        let tdMatch;
        while ((tdMatch = tdRegex.exec(rowHtml)) != null) {
            cells.push(cleanCell(tdMatch[1]));
        }
        if (cells.length < 2)
            continue;
        const isHeader = /<th/i.test(rowHtml);
        if (isHeader) {
            headerCells = cells;
            continue;
        }
        const indexedCells = cells.map((text, index) => ({ index, text }));
        const rowText = indexedCells.map((c) => `[${c.index}] ${c.text}`).join(" | ");
        const commodityIdx = detectCommodityIndex(cells);
        const commodity = cells[commodityIdx] ?? "";
        const wholesaleIdx = detectWholesalePriceIndex(cells, headerCells);
        const picked = pickPriceFromRow(cells, wholesaleIdx);
        const price = picked.price;
        if (picked.usedIndex != null && looksLikeDateToken(cells[picked.usedIndex] ?? "")) {
            console.warn("[KARACHI_ROW_SKIP_DATE_AS_PRICE]", { rowIndex, rowText, usedIndex: picked.usedIndex });
            continue;
        }
        if (price != null && price > 40000) {
            console.error("[KARACHI_ROW_REJECT_HARD_CAP]", {
                rowIndex,
                commodity,
                price,
                rowText,
                wholesaleIdx,
                usedIndex: picked.usedIndex,
            });
            continue;
        }
        if (!commodity || price == null)
            continue;
        console.log("[KARACHI_ROW_MAP]", {
            rowIndex,
            commodity,
            price,
            commodityIdx,
            wholesaleIdx,
            usedIndex: picked.usedIndex,
            rowText,
        });
        out.push({
            sourceId: SOURCE_ID,
            sourceType: "official_commissioner",
            sourceName: "Karachi Official Price Lists",
            commodityName: commodity,
            categoryName: "fruits_vegetables_essentials",
            subCategoryName: "official_list",
            mandiName: "Karachi Commissioner Price List",
            city: "Karachi",
            district: "Karachi",
            province: "Sindh",
            price,
            previousPrice: null,
            unit: "PKR/kg",
            currency: "PKR",
            trend: "same",
            lastUpdated: now,
            metadata: {
                parser: "html_table_scan",
                sourceRowIndex: rowIndex,
                commodityColumnIndex: commodityIdx,
                wholesaleColumnIndex: wholesaleIdx,
                priceColumnIndex: picked.usedIndex,
                rowText,
            },
        });
    }
    return out;
}
class KarachiOfficialAdapter {
    async fetchRows(context) {
        const sourceUrl = String(process.env.KARACHI_OFFICIAL_SOURCE_URL ?? DEFAULT_URL).trim();
        const response = await fetch(sourceUrl, {
            method: "GET",
            headers: {
                "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                "user-agent": "digital-arhat-functions/1.0",
            },
        });
        if (!response.ok) {
            throw new Error(`karachi_official_http_${response.status}`);
        }
        const html = await response.text();
        const underConstruction = /website\s+is\s+under\s+construction/i.test(html);
        const rows = parseRows(html, context.now).map((item) => ({
            ...item,
            metadata: {
                ...(item.metadata ?? {}),
                sourceUrl,
            },
        }));
        if (rows.length === 0 && underConstruction) {
            throw new Error("karachi_official_source_under_construction");
        }
        context.logger("source_fetched", {
            sourceId: SOURCE_ID,
            rawRows: rows.length,
            sourceUrl,
            underConstruction,
        });
        return rows;
    }
}
exports.KarachiOfficialAdapter = KarachiOfficialAdapter;
