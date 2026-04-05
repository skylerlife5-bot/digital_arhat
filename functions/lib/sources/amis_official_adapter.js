"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.AmisOfficialAdapter = void 0;
const amis_scraper_1 = require("./amis_scraper");
const fscpd_official_adapter_1 = require("./fscpd_official_adapter");
const lahore_official_adapter_1 = require("./lahore_official_adapter");
const SOURCE_ID = "amis_official";
function isLahoreRow(row) {
    const city = String(row.city ?? "").toLowerCase();
    const district = String(row.district ?? "").toLowerCase();
    const mandi = String(row.mandiName ?? "").toLowerCase();
    return city.includes("lahore") || district.includes("lahore") || mandi.includes("lahore");
}
async function fallbackLahoreRows(context) {
    try {
        const fscpd = new fscpd_official_adapter_1.FscpdOfficialAdapter();
        const fscpdRows = await fscpd.fetchRows(context);
        const lahoreOnly = fscpdRows.filter(isLahoreRow);
        if (lahoreOnly.length > 0) {
            return lahoreOnly.map((row) => ({
                ...row,
                metadata: {
                    ...(row.metadata ?? {}),
                    fallbackFrom: SOURCE_ID,
                    fallbackStrategy: "fscpd_lahore_filter",
                },
            }));
        }
    }
    catch (_err) {
        // Fall through to Lahore official adapter.
    }
    try {
        const lahore = new lahore_official_adapter_1.LahoreOfficialAdapter();
        const lahoreRows = await lahore.fetchRows(context);
        const lahoreOnly = lahoreRows.filter(isLahoreRow);
        return lahoreOnly.map((row) => ({
            ...row,
            metadata: {
                ...(row.metadata ?? {}),
                fallbackFrom: SOURCE_ID,
                fallbackStrategy: "lahore_official",
            },
        }));
    }
    catch (_err) {
        return [];
    }
}
class AmisOfficialAdapter {
    async fetchRows(context) {
        let result = null;
        let amisError = null;
        try {
            result = await (0, amis_scraper_1.scrapeAmisRates)();
        }
        catch (error) {
            amisError = String(error);
        }
        if (!result || result.records.length === 0) {
            const fallbackRows = await fallbackLahoreRows(context);
            context.logger("source_fetched", {
                sourceId: SOURCE_ID,
                rawRows: fallbackRows.length,
                newestTimestamp: null,
                sourceUrl: null,
                fallbackUsed: true,
                fallbackReason: amisError ?? "amis_empty_records",
                fallbackCity: "Lahore",
            });
            return fallbackRows;
        }
        context.logger("source_fetched", {
            sourceId: SOURCE_ID,
            rawRows: result.rawRows,
            newestTimestamp: result.newestTimestamp?.toISOString() ?? null,
            sourceUrl: result.sourceUrl,
            fallbackUsed: false,
        });
        return result.records
            .map((item) => {
            const commodity = String(item.commodityName ?? "").trim();
            const mandiName = String(item.mandiName ?? item.city ?? "").trim();
            const city = String(item.city ?? "").trim();
            const price = Number(item.price ?? 0);
            if (!commodity || !mandiName || !city || !Number.isFinite(price) || price <= 0) {
                return null;
            }
            const avgPriceRaw = Number(item.metadata["averagePrice"] ?? item.metadata["average"] ?? 0);
            const minPriceRaw = Number(item.metadata["minPrice"] ?? 0);
            const maxPriceRaw = Number(item.metadata["maxPrice"] ?? 0);
            return {
                sourceId: SOURCE_ID,
                sourceType: "official_aggregator",
                sourceName: "AMIS Official",
                commodityName: commodity,
                categoryName: "crops",
                subCategoryName: "other",
                mandiName,
                city,
                district: String(item.district ?? city),
                province: String(item.province ?? "Punjab"),
                price,
                previousPrice: null,
                minPrice: Number.isFinite(minPriceRaw) && minPriceRaw > 0 ? minPriceRaw : null,
                maxPrice: Number.isFinite(maxPriceRaw) && maxPriceRaw > 0 ? maxPriceRaw : null,
                unit: String(item.unit ?? "PKR/100kg"),
                currency: "PKR",
                trend: "same",
                lastUpdated: item.rateDate instanceof Date ? item.rateDate : context.now,
                metadata: {
                    ...item.metadata,
                    sourceUrl: result.sourceUrl,
                    sourceColumns: result.columns,
                    commodityRefId: item.commodityId,
                    averagePrice: Number.isFinite(avgPriceRaw) && avgPriceRaw > 0 ? avgPriceRaw : null,
                },
            };
        })
            .filter((item) => item != null);
    }
}
exports.AmisOfficialAdapter = AmisOfficialAdapter;
