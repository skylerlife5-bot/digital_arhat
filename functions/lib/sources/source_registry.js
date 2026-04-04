"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.HUMAN_CONTRIBUTION_SOURCE_REGISTRY = exports.PHASE_B_SOURCE_REGISTRY = exports.OFFICIAL_SOURCE_REGISTRY = void 0;
exports.getEnabledOfficialSources = getEnabledOfficialSources;
exports.getHumanContributionSources = getHumanContributionSources;
const top25_mandi_registry_1 = require("./top25_mandi_registry");
exports.OFFICIAL_SOURCE_REGISTRY = [
    {
        //
        // PRIMARY: Punjab FS&CPD District-wise Notified Rates
        // - Official Government of Punjab daily publication
        // - District-wise coverage across all Punjab districts
        // - Highest source priority (rank 4)
        //
        sourceId: "fscpd_official",
        sourceName: "Punjab FS&CPD Notified Rates",
        sourceFamily: "official_national_source",
        sourceType: "official_national_source",
        province: "Punjab",
        cityCoverage: ["Punjab"],
        categoryCoverage: [
            "crops",
            "vegetables",
            "fruits",
            "pulses",
            "spices",
        ],
        adapterClass: "FscpdOfficialAdapter",
        trustLevel: "high",
        schedulePolicy: "daily",
        enabled: true,
    },
    {
        //
        // SECONDARY: Punjab AMIS
        // - Official mandi-style rates, broader agri coverage
        // - Requires unit validation before ticker display
        //
        sourceId: "amis_official",
        sourceName: "AMIS Official",
        sourceFamily: "official_national_source",
        sourceType: "official_aggregator",
        province: "Punjab",
        cityCoverage: ["Punjab"],
        categoryCoverage: [
            "crops",
            "vegetables",
            "fruits",
            "pulses",
            "spices",
            "fertilizer",
            "seeds",
            "livestock",
        ],
        adapterClass: "AmisOfficialAdapter",
        trustLevel: "high",
        schedulePolicy: "15m",
        enabled: true,
    },
    {
        sourceId: "lahore_official_market_rates",
        sourceName: "Lahore Official Market Rates",
        sourceFamily: "official_city_market_source",
        sourceType: "official_market_committee",
        province: "Punjab",
        cityCoverage: ["Lahore"],
        categoryCoverage: ["fruits", "vegetables", "essentials"],
        adapterClass: "LahoreOfficialAdapter",
        trustLevel: "high",
        schedulePolicy: "hourly",
        enabled: true,
    },
    {
        sourceId: "karachi_official_price_lists",
        sourceName: "Karachi Official Price Lists",
        sourceFamily: "official_commissioner_source",
        sourceType: "official_commissioner",
        province: "Sindh",
        cityCoverage: ["Karachi"],
        categoryCoverage: ["fruits", "vegetables", "essentials"],
        adapterClass: "KarachiOfficialAdapter",
        trustLevel: "high",
        schedulePolicy: "hourly",
        enabled: true,
    },
];
const FUTURE_TOP_CITY_SOURCES = (0, top25_mandi_registry_1.getEnabledTopPriorityMandis)()
    .filter((item) => item.futureReady)
    .map((item) => ({
    sourceId: `future_${item.city.toLowerCase().replace(/[^a-z0-9]+/g, "_")}_source`,
    sourceName: `${item.city} Future Official Source`,
    sourceFamily: item.expectedSourceFamily,
    sourceType: item.expectedSourceFamily,
    province: item.province,
    cityCoverage: [item.city],
    categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
    adapterClass: "FutureUnimplementedAdapter",
    trustLevel: "medium",
    schedulePolicy: "daily",
    enabled: false,
    futureReady: true,
}));
exports.PHASE_B_SOURCE_REGISTRY = [
    ...exports.OFFICIAL_SOURCE_REGISTRY,
    ...FUTURE_TOP_CITY_SOURCES,
];
exports.HUMAN_CONTRIBUTION_SOURCE_REGISTRY = [
    {
        sourceId: "human_verified_network",
        sourceName: "Verified Human Contributor Network",
        sourceFamily: "future_verified_trader_source",
        sourceType: "human_verified",
        province: "Pakistan",
        cityCoverage: ["Pakistan"],
        categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
        adapterClass: "FutureUnimplementedAdapter",
        trustLevel: "medium",
        schedulePolicy: "15m",
        enabled: false,
        futureReady: true,
    },
    {
        sourceId: "human_local_network",
        sourceName: "Trusted Local Contributor Network",
        sourceFamily: "future_verified_dealer_source",
        sourceType: "human_local",
        province: "Pakistan",
        cityCoverage: ["Pakistan"],
        categoryCoverage: ["crops", "fruits", "vegetables", "essentials"],
        adapterClass: "FutureUnimplementedAdapter",
        trustLevel: "low",
        schedulePolicy: "hourly",
        enabled: false,
        futureReady: true,
    },
];
function envEnabled(sourceId) {
    const key = `MANDI_SOURCE_${sourceId.toUpperCase().replace(/[^A-Z0-9]/g, "_")}_ENABLED`;
    const raw = String(process.env[key] ?? "").trim().toLowerCase();
    if (!raw)
        return true;
    return raw === "1" || raw === "true" || raw === "yes";
}
function getEnabledOfficialSources() {
    return exports.PHASE_B_SOURCE_REGISTRY.filter((item) => item.enabled && envEnabled(item.sourceId));
}
function getHumanContributionSources() {
    return exports.HUMAN_CONTRIBUTION_SOURCE_REGISTRY.filter((item) => item.enabled && envEnabled(item.sourceId));
}
