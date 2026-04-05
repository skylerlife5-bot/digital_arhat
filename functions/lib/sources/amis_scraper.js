"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AMIS_COMMODITY_TO_APP_KEY = void 0;
exports.scrapeAmisRates = scrapeAmisRates;
const AMIS_DEFAULT_BASE_URL = "http://www.amis.pk";
const REQUEST_TIMEOUT_MS = 45000;
const REQUEST_RETRIES = 2;
// ---------------------------------------------------------------------------
// AMIS → App Commodity Key Mapping
// Translates AMIS display names to our canonical internal app keys.
// These keys match homeCommodityAllowlist in mandi_home_presenter.dart.
// ---------------------------------------------------------------------------
exports.AMIS_COMMODITY_TO_APP_KEY = {
    "Wheat": "wheat",
    "Basmati Rice": "rice_basmati",
    "Irri Rice": "rice_irri",
    "Rice": "rice_irri",
    "Sugar": "sugar",
    "Flour": "flour",
    "Potato": "potato",
    "Tomato": "tomato",
    "Onion": "onion",
    "Garlic": "garlic",
    "Ginger": "ginger",
    "Peas": "peas",
    "Cauliflower": "cauliflower",
    "Cabbage": "cabbage",
    "Carrot": "carrot",
    "Spinach": "spinach",
    "Okra": "ladyfinger",
    "Chilli": "green_chili",
    "Apple": "apple",
    "Banana": "banana",
    "Mango": "mango",
    "Orange": "orange",
    "Kinnow": "citrus",
    "Guava": "guava",
    "Grapes": "grapes",
    "Pomegranate": "pomegranate",
    "Lentil": "lentil_masoor",
    "Chickpea": "gram",
    "Mung Bean": "lentil_moong",
    "Black Gram": "lentil_mash",
    "Live Chicken": "live_chicken",
    "Broiler": "live_chicken",
    "Chicken": "chicken_meat",
    "Beef": "beef",
    "Mutton": "mutton",
    "Eggs": "eggs",
    "Milk": "milk",
    "Cooking Oil": "cooking_oil_5l",
    "Ghee": "desi_ghee_1kg",
};
// Full commodity specs with per-category unit for correct comparability.
// order matters: more specific entries (basmati, irri) must precede generic "rice".
const MANDI_COMMODITY_SPECS = [
    // Grains / Crops
    { canonical: "Wheat", appKey: "wheat", aliases: ["wheat", "gandum", "\u06af\u0646\u062f\u0645"], category: "crops", subCategory: "wheat", unit: "Rs/100Kg" },
    { canonical: "Basmati Rice", appKey: "rice_basmati", aliases: ["basmati"], category: "crops", subCategory: "basmati_rice", unit: "Rs/100Kg" },
    { canonical: "Irri Rice", appKey: "rice_irri", aliases: ["irri"], category: "crops", subCategory: "irri_rice", unit: "Rs/100Kg" },
    { canonical: "Rice", appKey: "rice_irri", aliases: ["rice", "chawal", "\u0686\u0627\u0648\u0644"], category: "crops", subCategory: "rice", unit: "Rs/100Kg" },
    { canonical: "Sugar", appKey: "sugar", aliases: ["sugar", "cheeni", "refined sugar", "\u0686\u06cc\u0646\u06cc"], category: "crops", subCategory: "sugar", unit: "Rs/100Kg" },
    { canonical: "Flour", appKey: "flour", aliases: ["flour", "atta", "wheat flour", "\u0622\u0679\u0627"], category: "essentials", subCategory: "flour", unit: "Rs/20Kg" },
    // Livestock / Meats
    { canonical: "Live Chicken", appKey: "live_chicken", aliases: ["live chicken", "broiler", "zinda murgi", "\u0632\u0646\u062f\u06c1 \u0645\u0631\u063a\u06cc", "murgi", "poultry", "chicken live", "chicken (live)"], category: "livestock", subCategory: "chicken_live", unit: "Rs/Kg" },
    { canonical: "Chicken", appKey: "chicken_meat", aliases: ["chicken meat", "murgi ka gosht", "\u0645\u0631\u063a\u06cc", "dressed chicken", "chicken (dressed)"], category: "livestock", subCategory: "chicken_meat", unit: "Rs/Kg" },
    { canonical: "Beef", appKey: "beef", aliases: ["beef", "bada gosht", "\u0628\u0691\u0627 \u06af\u0648\u0634\u062a", "cow meat", "gai gosht"], category: "livestock", subCategory: "beef", unit: "Rs/Kg" },
    { canonical: "Mutton", appKey: "mutton", aliases: ["mutton", "chota gosht", "\u0686\u06be\u0648\u0679\u0627 \u06af\u0648\u0634\u062a", "bakra gosht", "goat meat", "lamb"], category: "livestock", subCategory: "mutton", unit: "Rs/Kg" },
    // Daily Essentials
    { canonical: "Eggs", appKey: "eggs", aliases: ["eggs", "egg", "anda", "\u0627\u0646\u0688\u06d2", "\u0627\u0646\u0688\u0627"], category: "essentials", subCategory: "eggs", unit: "Rs/dozen" },
    { canonical: "Milk", appKey: "milk", aliases: ["milk", "doodh", "\u062f\u0648\u062f\u06be", "fresh milk"], category: "essentials", subCategory: "milk", unit: "Rs/litre" },
    { canonical: "Cooking Oil", appKey: "cooking_oil_5l", aliases: ["cooking oil", "sunflower oil", "refined oil", "\u062a\u06cc\u0644", "khana pakane ka tail"], category: "essentials", subCategory: "cooking_oil", unit: "Rs/5litre" },
    { canonical: "Ghee", appKey: "desi_ghee_1kg", aliases: ["ghee", "desi ghee", "\u06af\u06be\u06cc", "vanaspati", "dalda"], category: "essentials", subCategory: "ghee", unit: "Rs/Kg" },
    // Vegetables
    { canonical: "Onion", appKey: "onion", aliases: ["onion", "pyaz", "\u067e\u06cc\u0627\u0632"], category: "vegetables", subCategory: "onion", unit: "Rs/40Kg" },
    { canonical: "Potato", appKey: "potato", aliases: ["potato", "aloo", "\u0622\u0644\u0648"], category: "vegetables", subCategory: "potato", unit: "Rs/40Kg" },
    { canonical: "Tomato", appKey: "tomato", aliases: ["tomato", "tamatar", "\u0679\u0645\u0627\u0679\u0631"], category: "vegetables", subCategory: "tomato", unit: "Rs/40Kg" },
    { canonical: "Garlic", appKey: "garlic", aliases: ["garlic", "lehsan", "\u0644\u06c1\u0633\u0646"], category: "vegetables", subCategory: "garlic", unit: "Rs/40Kg" },
    { canonical: "Ginger", appKey: "ginger", aliases: ["ginger", "adrak", "\u0627\u062f\u0631\u06a9"], category: "vegetables", subCategory: "ginger", unit: "Rs/40Kg" },
    { canonical: "Peas", appKey: "peas", aliases: ["peas", "matar", "\u0645\u0679\u0631", "green peas"], category: "vegetables", subCategory: "peas", unit: "Rs/40Kg" },
    { canonical: "Cauliflower", appKey: "cauliflower", aliases: ["cauliflower", "gobhi", "\u067e\u06be\u0648\u0644 \u06af\u0648\u0628\u06be\u06cc", "phool gobhi"], category: "vegetables", subCategory: "cauliflower", unit: "Rs/40Kg" },
    { canonical: "Cabbage", appKey: "cabbage", aliases: ["cabbage", "band gobhi", "\u0628\u0646\u062f \u06af\u0648\u0628\u06be\u06cc"], category: "vegetables", subCategory: "cabbage", unit: "Rs/40Kg" },
    { canonical: "Carrot", appKey: "carrot", aliases: ["carrot", "gajar", "\u06af\u0627\u062c\u0631"], category: "vegetables", subCategory: "carrot", unit: "Rs/40Kg" },
    { canonical: "Spinach", appKey: "spinach", aliases: ["spinach", "palak", "\u067e\u0627\u0644\u06a9"], category: "vegetables", subCategory: "spinach", unit: "Rs/40Kg" },
    { canonical: "Okra", appKey: "ladyfinger", aliases: ["okra", "bhindi", "\u0628\u06be\u0646\u0688\u06cc", "lady finger", "ladyfinger"], category: "vegetables", subCategory: "okra", unit: "Rs/40Kg" },
    { canonical: "Chilli", appKey: "green_chili", aliases: ["chilli", "chili", "mirch", "\u0645\u0631\u0686", "green chilli", "hari mirch", "\u06c1\u0631\u06cc \u0645\u0631\u0686"], category: "vegetables", subCategory: "chilli", unit: "Rs/40Kg" },
    // Pulses
    { canonical: "Lentil", appKey: "lentil_masoor", aliases: ["lentil", "masoor", "\u0645\u0633\u0648\u0631", "masur", "masoor dal", "red lentil"], category: "pulses", subCategory: "masoor", unit: "Rs/100Kg" },
    { canonical: "Chickpea", appKey: "gram", aliases: ["chickpea", "gram", "chana", "\u0686\u0646\u0627"], category: "pulses", subCategory: "chana", unit: "Rs/100Kg" },
    { canonical: "Mung Bean", appKey: "lentil_moong", aliases: ["mung", "moong", "\u0645\u0648\u0646\u06af", "moong dal", "mung bean", "mung dal"], category: "pulses", subCategory: "mung", unit: "Rs/100Kg" },
    { canonical: "Black Gram", appKey: "lentil_mash", aliases: ["black gram", "urad", "mash", "\u0645\u0627\u0634", "urad dal", "mash dal"], category: "pulses", subCategory: "mash", unit: "Rs/100Kg" },
    // Fruits
    { canonical: "Apple", appKey: "apple", aliases: ["apple", "seb", "\u0633\u06cc\u0628"], category: "fruits", subCategory: "apple", unit: "Rs/40Kg" },
    { canonical: "Banana", appKey: "banana", aliases: ["banana", "kela", "\u06a9\u06cc\u0644\u0627"], category: "fruits", subCategory: "banana", unit: "Rs/dozen" },
    { canonical: "Mango", appKey: "mango", aliases: ["mango", "aam", "\u0622\u0645"], category: "fruits", subCategory: "mango", unit: "Rs/40Kg" },
    { canonical: "Orange", appKey: "orange", aliases: ["orange", "kino", "\u0633\u0646\u06af\u062a\u0631\u06c1"], category: "fruits", subCategory: "orange", unit: "Rs/40Kg" },
    { canonical: "Kinnow", appKey: "citrus", aliases: ["kinnow", "kinow", "\u0645\u0627\u0644\u0679\u0627", "malta"], category: "fruits", subCategory: "kinnow", unit: "Rs/40Kg" },
    { canonical: "Guava", appKey: "guava", aliases: ["guava", "amrood", "\u0627\u0645\u0631\u0648\u062f"], category: "fruits", subCategory: "guava", unit: "Rs/40Kg" },
    { canonical: "Grapes", appKey: "grapes", aliases: ["grapes", "angoor", "\u0627\u0646\u06af\u0648\u0631"], category: "fruits", subCategory: "grapes", unit: "Rs/40Kg" },
    { canonical: "Pomegranate", appKey: "pomegranate", aliases: ["pomegranate", "anar", "\u0627\u0646\u0627\u0631"], category: "fruits", subCategory: "pomegranate", unit: "Rs/40Kg" },
];
function normalizeWhitespace(input) {
    return input.replace(/\s+/g, " ").trim();
}
function decodeHtml(input) {
    return input
        .replace(/&nbsp;/gi, " ")
        .replace(/&amp;/gi, "&")
        .replace(/&quot;/gi, '"')
        .replace(/&#39;/gi, "'")
        .replace(/&lt;/gi, "<")
        .replace(/&gt;/gi, ">")
        .replace(/&#x([0-9a-f]+);/gi, (_m, hex) => String.fromCharCode(Number.parseInt(hex, 16)))
        .replace(/&#(\d+);/g, (_m, dec) => String.fromCharCode(Number.parseInt(dec, 10)));
}
function stripTags(input) {
    return input.replace(/<[^>]+>/g, " ");
}
function cleanCell(input) {
    return normalizeWhitespace(decodeHtml(stripTags(input)));
}
function toFinite(value) {
    const cleaned = value.replace(/,/g, "").replace(/[^\d.+-]/g, "");
    if (!cleaned || cleaned === "-" || cleaned === ".") {
        return null;
    }
    const num = Number.parseFloat(cleaned);
    return Number.isFinite(num) ? num : null;
}
function parseRateDate(html) {
    const match = html.match(/Dated:\s*(\d{2})-(\d{2})-(\d{4})/i);
    if (!match)
        return null;
    const day = Number.parseInt(match[1], 10);
    const month = Number.parseInt(match[2], 10);
    const year = Number.parseInt(match[3], 10);
    const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0));
    return Number.isNaN(date.getTime()) ? null : date;
}
function parseUnitLabel(html) {
    const text = cleanCell(html).toLowerCase();
    const direct = text.match(/rs\s*\/?\s*(\d+)\s*kg/i);
    if (direct && direct[1]) {
        return `Rs/${direct[1]}Kg`;
    }
    if (text.includes("maund") || text.includes("mond"))
        return "Rs/40Kg";
    if (text.includes("per kg") || text.includes("/kg"))
        return "Rs/Kg";
    if (text.includes("dozen") || text.includes("doz"))
        return "Rs/dozen";
    return null;
}
async function fetchText(url) {
    let lastError = null;
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
        }
        catch (error) {
            lastError = error;
            if (attempt >= REQUEST_RETRIES) {
                throw error;
            }
        }
        finally {
            clearTimeout(timeout);
        }
    }
    throw new Error(`amis_fetch_failed_${String(lastError ?? "unknown")}`);
}
function parseCommodityLinks(html, baseUrl) {
    const out = [];
    const regex = /<A\s+href='ViewPrices\.aspx\?searchType=0&commodityId=(\d+)'>([\s\S]*?)<\/A>/gi;
    let match;
    while ((match = regex.exec(html)) != null) {
        const id = Number.parseInt(match[1], 10);
        if (!Number.isFinite(id))
            continue;
        const label = cleanCell(match[2]);
        if (!label)
            continue;
        out.push({
            id,
            label,
            url: `${baseUrl}/ViewPrices.aspx?searchType=0&commodityId=${id}`,
        });
    }
    const deduped = new Map();
    for (const link of out) {
        if (!deduped.has(link.id)) {
            deduped.set(link.id, link);
        }
    }
    return Array.from(deduped.values());
}
function matchCommoditySpec(label) {
    const value = label.toLowerCase();
    for (const spec of MANDI_COMMODITY_SPECS) {
        if (spec.aliases.some((alias) => value.includes(alias.toLowerCase()))) {
            return spec;
        }
    }
    return null;
}
function extractTdCells(rowHtml) {
    const cells = [];
    const cellRegex = /<t[dh][^>]*>([\s\S]*?)<\/t[dh]>/gi;
    let cellMatch;
    while ((cellMatch = cellRegex.exec(rowHtml)) != null) {
        cells.push(cellMatch[1]);
    }
    return cells;
}
function normalizeHeaderToken(raw) {
    return cleanCell(raw)
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, " ")
        .trim();
}
function resolveColumnIndexes(headerCells) {
    let cityIdx = -1;
    let minIdx = -1;
    let maxIdx = -1;
    let fqpIdx = -1;
    let quantityIdx = -1;
    for (let i = 0; i < headerCells.length; i += 1) {
        const token = normalizeHeaderToken(headerCells[i]);
        if (cityIdx === -1 && /(market|city|mandi|district)/.test(token))
            cityIdx = i;
        if (minIdx === -1 && /\bmin(imum)?\b/.test(token))
            minIdx = i;
        if (maxIdx === -1 && /\bmax(imum)?\b/.test(token))
            maxIdx = i;
        if (fqpIdx === -1 && /(fqp|avg|average|rate|price)/.test(token))
            fqpIdx = i;
        if (quantityIdx === -1 && /(quantity|arrival|arrivals)/.test(token))
            quantityIdx = i;
    }
    return { cityIdx, minIdx, maxIdx, fqpIdx, quantityIdx };
}
function parseCityRows(html, context) {
    const rows = [];
    const trRegex = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let match;
    let rowIndex = -1;
    let detectedHeader = null;
    while ((match = trRegex.exec(html)) != null) {
        rowIndex += 1;
        const trHtml = match[1];
        const tdCells = extractTdCells(trHtml);
        if (tdCells.length === 0)
            continue;
        // Lock column order from the first probable header row.
        if (!detectedHeader) {
            const joinedHeaders = tdCells.map((cell) => normalizeHeaderToken(cell)).join("|");
            if (/(fqp|average|avg|price|rate)/.test(joinedHeaders) && /(city|market|mandi|district)/.test(joinedHeaders)) {
                detectedHeader = resolveColumnIndexes(tdCells);
                console.log("[AMIS_COLMAP]", {
                    commodityId: context.commodityId,
                    commodityLabel: context.commodityLabel,
                    sourceUrl: context.sourceUrl,
                    rowIndex,
                    tdCount: tdCells.length,
                    cityIdx: detectedHeader.cityIdx,
                    minIdx: detectedHeader.minIdx,
                    maxIdx: detectedHeader.maxIdx,
                    fqpIdx: detectedHeader.fqpIdx,
                    quantityIdx: detectedHeader.quantityIdx,
                });
                continue;
            }
        }
        // Data rows should carry city links for searchType=1.
        if (!/searchType=1&commodityId=\d+/i.test(trHtml))
            continue;
        const indexedCells = tdCells.map((cell, idx) => ({
            index: idx,
            text: cleanCell(cell),
        }));
        const rowText = indexedCells.map((cell) => `[${cell.index}] ${cell.text}`).join(" | ");
        console.log("[AMIS_ROW_RAW]", {
            commodityId: context.commodityId,
            commodityLabel: context.commodityLabel,
            rowIndex,
            tdCount: tdCells.length,
            rowText,
            indexedCells,
        });
        if (!detectedHeader) {
            console.error("[AMIS_ROW_SKIP_NO_HEADER_MAP]", {
                commodityId: context.commodityId,
                commodityLabel: context.commodityLabel,
                rowIndex,
                rowText,
            });
            continue;
        }
        const colMap = detectedHeader;
        if (colMap.cityIdx < 0 ||
            colMap.fqpIdx < 0 ||
            colMap.cityIdx >= tdCells.length ||
            colMap.fqpIdx >= tdCells.length) {
            console.error("[AMIS_ROW_SKIP_BAD_COLMAP]", {
                commodityId: context.commodityId,
                commodityLabel: context.commodityLabel,
                rowIndex,
                tdCount: tdCells.length,
                cityIdx: colMap.cityIdx,
                fqpIdx: colMap.fqpIdx,
                rowText,
            });
            continue;
        }
        const cityRaw = tdCells[colMap.cityIdx] ?? tdCells[0] ?? "";
        const minRaw = tdCells[colMap.minIdx] ?? "";
        const maxRaw = tdCells[colMap.maxIdx] ?? "";
        const fqpRaw = tdCells[colMap.fqpIdx] ?? "";
        const qtyRaw = tdCells[colMap.quantityIdx] ?? "";
        const city = cleanCell(cityRaw);
        if (!city)
            continue;
        const minPrice = toFinite(cleanCell(minRaw));
        const maxPrice = toFinite(cleanCell(maxRaw));
        const fqp = toFinite(cleanCell(fqpRaw));
        const quantity = toFinite(cleanCell(qtyRaw));
        if (fqp == null || fqp <= 0) {
            console.error("[AMIS_ROW_SKIP_PRICE_MISSING]", {
                commodityId: context.commodityId,
                commodityLabel: context.commodityLabel,
                rowIndex,
                city,
                fqpRaw: cleanCell(fqpRaw),
                rowText,
            });
            continue;
        }
        console.log("[AMIS_ROW_PARSE]", {
            commodityId: context.commodityId,
            commodityLabel: context.commodityLabel,
            rowIndex,
            tdCount: tdCells.length,
            city,
            minPrice,
            maxPrice,
            fqp,
            quantity,
            selectedPrice: fqp,
            cityColumnIndex: colMap.cityIdx,
            minColumnIndex: colMap.minIdx,
            maxColumnIndex: colMap.maxIdx,
            fqpColumnIndex: colMap.fqpIdx,
            quantityColumnIndex: colMap.quantityIdx,
        });
        rows.push({
            city,
            rowIndex,
            cityColumnIndex: colMap.cityIdx,
            minColumnIndex: colMap.minIdx,
            maxColumnIndex: colMap.maxIdx,
            fqpColumnIndex: colMap.fqpIdx,
            quantityColumnIndex: colMap.quantityIdx,
            tdCount: tdCells.length,
            minPrice,
            maxPrice,
            fqp,
            quantity,
        });
    }
    return rows;
}
async function scrapeAmisRates(baseUrlEnv) {
    const baseUrl = (baseUrlEnv || process.env.AMIS_BASE_URL || AMIS_DEFAULT_BASE_URL).replace(/\/+$/, "");
    const browseUrl = `${baseUrl}/BrowsePrices.aspx?searchType=0`;
    const browseHtml = await fetchText(browseUrl);
    const commodityLinks = parseCommodityLinks(browseHtml, baseUrl);
    if (commodityLinks.length === 0) {
        console.warn("[AMIS_SOURCE_EMPTY]", {
            reason: "no_commodity_links",
            sourceUrl: browseUrl,
        });
        return {
            sourceUrl: browseUrl,
            dataFormat: "html",
            columns: ["Dated", "City", "Min", "Max", "FQP", "Quantity"],
            records: [],
            rawRows: 0,
            newestTimestamp: null,
        };
    }
    const selected = commodityLinks.filter((item) => matchCommoditySpec(item.label) != null);
    if (selected.length === 0) {
        console.warn("[AMIS_SOURCE_EMPTY]", {
            reason: "required_commodities_not_found",
            sourceUrl: browseUrl,
            discoveredCommodityLinks: commodityLinks.length,
        });
        return {
            sourceUrl: browseUrl,
            dataFormat: "html",
            columns: ["Dated", "City", "Min", "Max", "FQP", "Quantity"],
            records: [],
            rawRows: 0,
            newestTimestamp: null,
        };
    }
    const selectedBySpec = new Map();
    for (const commodity of selected) {
        const spec = matchCommoditySpec(commodity.label);
        if (!spec)
            continue;
        if (!selectedBySpec.has(spec.canonical)) {
            selectedBySpec.set(spec.canonical, commodity);
        }
    }
    const selectedUnique = Array.from(selectedBySpec.values());
    const records = [];
    let newestTimestamp = null;
    const skippedCommodities = [];
    for (const commodity of selectedUnique) {
        let commodityHtml = "";
        try {
            commodityHtml = await fetchText(commodity.url);
        }
        catch (error) {
            skippedCommodities.push({
                commodityId: commodity.id,
                label: commodity.label,
                reason: String(error),
            });
            continue;
        }
        const rateDate = parseRateDate(commodityHtml);
        const unitLabel = parseUnitLabel(commodityHtml);
        const cityRows = parseCityRows(commodityHtml, {
            commodityId: commodity.id,
            commodityLabel: commodity.label,
            sourceUrl: commodity.url,
        });
        for (const row of cityRows) {
            const effectiveDate = rateDate ?? new Date();
            if (!newestTimestamp || effectiveDate > newestTimestamp) {
                newestTimestamp = effectiveDate;
            }
            const spec = matchCommoditySpec(commodity.label);
            const appKey = spec?.appKey ?? "";
            records.push({
                commodityName: spec?.canonical ?? commodity.label,
                rawLabel: commodity.label,
                commodityId: commodity.id,
                mandiName: row.city,
                city: row.city,
                district: row.city,
                province: "Punjab",
                price: row.fqp ?? 0,
                unit: unitLabel ?? spec?.unit ?? "Rs/100Kg",
                rateDate: effectiveDate,
                metadata: {
                    sourcePage: commodity.url,
                    commodityId: commodity.id,
                    sourceRowIndex: row.rowIndex,
                    sourceTdCount: row.tdCount,
                    sourceCityColumnIndex: row.cityColumnIndex,
                    sourceMinColumnIndex: row.minColumnIndex,
                    sourceMaxColumnIndex: row.maxColumnIndex,
                    sourceFqpColumnIndex: row.fqpColumnIndex,
                    sourceQuantityColumnIndex: row.quantityColumnIndex,
                    rawLabel: commodity.label,
                    canonicalLabel: spec?.canonical ?? commodity.label,
                    appKey,
                    commodityKey: appKey,
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
        console.warn("[AMIS_SOURCE_EMPTY]", {
            reason: "no_city_rows",
            sourceUrl: browseUrl,
            skippedCommodities: skippedCommodities.slice(0, 10),
            skipReason,
        });
        return {
            sourceUrl: browseUrl,
            dataFormat: "html",
            columns: ["Dated", "City", "Min", "Max", "FQP", "Quantity"],
            records: [],
            rawRows: 0,
            newestTimestamp: null,
        };
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
