"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dedupeAndAnnotate = dedupeAndAnnotate;
const normalization_1 = require("./normalization");
const SOURCE_PRIORITY = {
    lahore_official_market_rates: 3,
    karachi_official_price_lists: 3,
    amis_official: 2,
};
function freshnessRank(status) {
    if (status === "live")
        return 4;
    if (status === "recent")
        return 3;
    if (status === "aging")
        return 2;
    return 1;
}
function chooseBetter(a, b) {
    const priorityA = SOURCE_PRIORITY[a.sourceId] ?? 1;
    const priorityB = SOURCE_PRIORITY[b.sourceId] ?? 1;
    if (priorityA !== priorityB)
        return priorityA > priorityB ? a : b;
    const freshnessA = freshnessRank(a.freshnessStatus);
    const freshnessB = freshnessRank(b.freshnessStatus);
    if (freshnessA !== freshnessB)
        return freshnessA > freshnessB ? a : b;
    if (a.lastUpdated.getTime() !== b.lastUpdated.getTime()) {
        return a.lastUpdated > b.lastUpdated ? a : b;
    }
    return a;
}
function comparableKey(item) {
    return [
        (0, normalization_1.normalizeCommodityName)(item.commodityName).toLowerCase(),
        (0, normalization_1.normalizeUnit)(item.unit),
        (item.categoryName || "").toLowerCase(),
        (item.subCategoryName || "").toLowerCase(),
        (0, normalization_1.normalizeLocationToken)(item.city),
        (0, normalization_1.normalizeLocationToken)(item.mandiName),
    ].join("|");
}
function cityCommodityKey(item) {
    return [
        (0, normalization_1.normalizeCommodityName)(item.commodityName).toLowerCase(),
        (0, normalization_1.normalizeUnit)(item.unit),
        (0, normalization_1.normalizeLocationToken)(item.city),
    ].join("|");
}
function mandiCommodityKey(item) {
    return [
        (0, normalization_1.normalizeCommodityName)(item.commodityName).toLowerCase(),
        (0, normalization_1.normalizeUnit)(item.unit),
        (0, normalization_1.normalizeLocationToken)(item.mandiName),
    ].join("|");
}
function metadataIncomplete(item) {
    return !item.city.trim() ||
        !item.mandiName.trim() ||
        !item.categoryName.trim() ||
        !item.subCategoryName.trim() ||
        !item.unit.trim();
}
function dedupeAndAnnotate(input) {
    const grouped = new Map();
    const cityGrouped = new Map();
    const mandiGrouped = new Map();
    for (const item of input) {
        const key = comparableKey(item);
        const arr = grouped.get(key) ?? [];
        arr.push(item);
        grouped.set(key, arr);
        const cityKey = cityCommodityKey(item);
        const cityArr = cityGrouped.get(cityKey) ?? [];
        cityArr.push(item);
        cityGrouped.set(cityKey, cityArr);
        const mandiKey = mandiCommodityKey(item);
        const mandiArr = mandiGrouped.get(mandiKey) ?? [];
        mandiArr.push(item);
        mandiGrouped.set(mandiKey, mandiArr);
    }
    const out = [];
    for (const rates of grouped.values()) {
        if (rates.length === 0)
            continue;
        const selected = rates.reduce((best, next) => chooseBetter(best, next));
        const corroborationCount = rates.length;
        const sameCityCorroboration = cityGrouped.get(cityCommodityKey(selected))?.length ?? 1;
        const sameMandiCorroboration = mandiGrouped.get(mandiCommodityKey(selected))?.length ?? 1;
        const uniqueSourceIds = new Set(rates.map((item) => item.sourceId).filter((item) => item.trim()));
        const multiSourceCorroboration = uniqueSourceIds.size;
        const prices = rates.map((item) => item.price).filter((value) => value > 0);
        const avg = prices.reduce((sum, value) => sum + value, 0) / (prices.length || 1);
        const deviation = avg > 0 ? Math.abs(selected.price - avg) / avg : 0;
        const duplicateAgreement = Math.max(0, 1 - Math.min(1, deviation));
        const incompleteMetadata = metadataIncomplete(selected);
        out.push({
            ...selected,
            corroborationCount,
            sameCityCorroboration,
            sameMandiCorroboration,
            multiSourceCorroboration,
            duplicateAgreement: Number(duplicateAgreement.toFixed(3)),
            sparseData: rates.length < 2 || uniqueSourceIds.size < 1,
            suspiciousSpike: deviation > 0.6,
            incompleteMetadata,
            metadata: {
                ...selected.metadata,
                comparableBucketSize: rates.length,
                sameCityBucketSize: sameCityCorroboration,
                sameMandiBucketSize: sameMandiCorroboration,
                multiSourceBucketSize: multiSourceCorroboration,
                duplicateAgreement: Number(duplicateAgreement.toFixed(3)),
                incompleteMetadata,
                comparableAvgPrice: Number(avg.toFixed(2)),
                comparableDeviation: Number(deviation.toFixed(3)),
            },
        });
    }
    return out;
}
