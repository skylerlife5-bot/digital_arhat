"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getBlockedCityRegistry = getBlockedCityRegistry;
// This registry is a hard truth table for top-priority cities that are not live yet.
// It keeps blocked-city reasons explicit until a real adapter is implemented.
const BLOCKED_CITY_LOOKUP = {
    Faisalabad: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Rawalpindi: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Multan: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Bahawalpur: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Gujranwala: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Sargodha: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Gujrat: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    "D.G. Khan": {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Sahiwal: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Okara: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Vehari: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    "Rahim Yar Khan": {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Bhakkar: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Layyah: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Khanewal: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Muzaffargarh: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    "Toba Tek Singh": {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Kabirwala: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Lodhran: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Chichawatni: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Jhelum: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Mianwali: {
        reasonCode: "no_verified_structured_source",
        reason: "No verified structured official endpoint found yet for adapter-grade ingestion.",
        severity: "high",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
    Hyderabad: {
        reasonCode: "city_not_in_live_source_coverage",
        reason: "Expected in top-25 targets but no active source mapped in current live registry.",
        severity: "medium",
        checkedAtIso: "2026-03-14T00:00:00.000Z",
        evidenceUrls: [],
    },
};
function getBlockedCityRegistry(targets) {
    return targets
        .map((target) => {
        const blocked = BLOCKED_CITY_LOOKUP[target.city];
        if (!blocked)
            return null;
        return {
            city: target.city,
            ...blocked,
        };
    })
        .filter((item) => item != null);
}
