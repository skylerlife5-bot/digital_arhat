"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.ingestMandiRatesOnDemand = exports.ingestMandiRatesScheduled = void 0;
exports.runMandiRatesIngestionDebug = runMandiRatesIngestionDebug;
const https_1 = require("firebase-functions/v2/https");
const scheduler_1 = require("firebase-functions/v2/scheduler");
const admin = __importStar(require("firebase-admin"));
const firestore_1 = require("firebase-admin/firestore");
const source_registry_1 = require("./sources/source_registry");
const amis_official_adapter_1 = require("./sources/amis_official_adapter");
const fscpd_official_adapter_1 = require("./sources/fscpd_official_adapter");
const lahore_official_adapter_1 = require("./sources/lahore_official_adapter");
const karachi_official_adapter_1 = require("./sources/karachi_official_adapter");
const normalization_1 = require("./sources/normalization");
const dedup_1 = require("./sources/dedup");
const confidence_engine_1 = require("./sources/confidence_engine");
const source_coverage_status_1 = require("./sources/source_coverage_status");
const top25_mandi_registry_1 = require("./sources/top25_mandi_registry");
const blocked_city_registry_1 = require("./sources/blocked_city_registry");
const source_priority_policy_1 = require("./sources/source_priority_policy");
const unit_rules_1 = require("./sources/unit_rules");
const COLLECTION = "mandi_rates";
function getApp() {
    if (admin.apps.length > 0) {
        return admin.app();
    }
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
    return projectId ? admin.initializeApp({ projectId }) : admin.initializeApp();
}
function getDb() {
    return getApp().firestore();
}
function nowIso() {
    return new Date().toISOString();
}
function logger(event, data) {
    console.log(`mandi_phase_a_${event}`, data);
}
function mandiPulseLog(message) {
    console.log(`[MandiPulse] ${message}`);
}
function adapterFor(definition) {
    mandiPulseLog(`source_selected=${definition.sourceId}`);
    if (definition.adapterClass === "FscpdOfficialAdapter")
        return new fscpd_official_adapter_1.FscpdOfficialAdapter();
    if (definition.adapterClass === "AmisOfficialAdapter")
        return new amis_official_adapter_1.AmisOfficialAdapter();
    if (definition.adapterClass === "LahoreOfficialAdapter")
        return new lahore_official_adapter_1.LahoreOfficialAdapter();
    if (definition.adapterClass === "KarachiOfficialAdapter")
        return new karachi_official_adapter_1.KarachiOfficialAdapter();
    if (definition.adapterClass === "FutureUnimplementedAdapter")
        return null;
    return null;
}
function uniqueSample(values, cap) {
    const seen = new Set();
    const out = [];
    for (const raw of values) {
        const value = String(raw ?? "").trim();
        if (!value)
            continue;
        const key = value.toLowerCase();
        if (seen.has(key))
            continue;
        seen.add(key);
        out.push(value);
        if (out.length >= cap)
            break;
    }
    return out;
}
function extractSourceUrls(rows) {
    return uniqueSample(rows.map((row) => String(row.metadata?.sourceUrl ?? "").trim()).filter((item) => !!item), 3);
}
function reliabilityBySource(sourceId) {
    // FS&CPD: highest reliability — district-wise official daily rate
    if (sourceId === "fscpd_official")
        return 0.25;
    if (sourceId === "amis_official")
        return 0.22;
    if (sourceId === "lahore_official_market_rates")
        return 0.18;
    if (sourceId === "karachi_official_price_lists")
        return 0.16;
    return 0.08;
}
function toSourceStats(source) {
    return {
        sourceId: source.sourceId,
        sourceName: source.sourceName,
        sourceType: source.sourceType,
        sourceFamily: source.sourceFamily,
        startedAtIso: nowIso(),
        fetchedRows: 0,
        parsedRows: 0,
        rejectedRows: 0,
        writtenRows: 0,
        sourceUrls: [],
        sampleCities: [],
        sampleCommodities: [],
        failed: false,
        failReason: null,
    };
}
function toFirestorePayload(rate) {
    const sourceType = String(rate.sourceType);
    const reviewStatus = rate.reviewStatus ?? "accepted";
    const acceptedBySystem = rate.acceptedBySystem ?? true;
    const priorityRank = rate.priorityRank ?? (0, source_priority_policy_1.priorityRankForRecord)(rate);
    return {
        id: rate.id,
        cropType: rate.commodityName,
        commodityName: rate.commodityName,
        commodityNameUr: rate.commodityNameUr,
        categoryName: rate.categoryName,
        subCategoryName: rate.subCategoryName,
        mandiName: rate.mandiName,
        city: rate.city,
        district: rate.district,
        province: rate.province,
        latitude: rate.latitude,
        longitude: rate.longitude,
        price: rate.price,
        averagePrice: rate.price,
        previousPrice: rate.previousPrice,
        minPrice: rate.minPrice,
        maxPrice: rate.maxPrice,
        unit: rate.unit,
        currency: rate.currency,
        trend: rate.trend,
        source: rate.source,
        sourceId: rate.sourceId,
        sourceType,
        ingestionSource: sourceType,
        lastUpdated: firestore_1.Timestamp.fromDate(rate.lastUpdated),
        rateDate: firestore_1.Timestamp.fromDate(rate.lastUpdated),
        syncedAt: firestore_1.FieldValue.serverTimestamp(),
        freshnessStatus: rate.freshnessStatus,
        confidenceScore: rate.confidenceScore,
        confidenceReason: rate.confidenceReason,
        verificationStatus: rate.verificationStatus,
        contributorType: rate.contributorType,
        contributorId: rate.contributorId ?? null,
        contributorVerificationStatus: rate.contributorVerificationStatus ?? null,
        trustScore: rate.trustScore ?? null,
        reliabilityScore: rate.reliabilityScore ?? null,
        trustLevel: rate.trustLevel ?? null,
        trustReason: rate.trustReason ?? null,
        reviewStatus,
        corroborationCount: rate.corroborationCount ?? null,
        disputeCount: rate.disputeCount ?? null,
        acceptedBySystem,
        acceptedByAdmin: rate.acceptedByAdmin ?? false,
        submissionTimestamp: rate.submissionTimestamp ? firestore_1.Timestamp.fromDate(rate.submissionTimestamp) : null,
        sourcePriorityRank: priorityRank,
        isNearby: rate.isNearby,
        isAiCleaned: rate.isAiCleaned,
        metadata: rate.metadata,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
        // Market Pulse confidence fields
        rowConfidence: rate.rowConfidence ?? "low",
        sourceReliabilityLevel: rate.sourceReliabilityLevel ?? "low",
        flags: rate.flags ?? [],
    };
}
async function clearCollectionInBatches(db, collectionPath, batchSize = 400) {
    let deleted = 0;
    while (true) {
        const snap = await db.collection(collectionPath).limit(batchSize).get();
        if (snap.empty)
            break;
        const batch = db.batch();
        for (const doc of snap.docs) {
            batch.delete(doc.ref);
        }
        await batch.commit();
        deleted += snap.size;
        if (snap.size < batchSize)
            break;
    }
    return deleted;
}
function isSensitiveCommodityForPriceAlert(rawName, normalizedName) {
    const haystack = `${rawName} ${normalizedName}`.toLowerCase();
    return /(ghee|meat|beef|mutton|chicken|gosht)/.test(haystack);
}
async function runIngestion() {
    const db = getDb();
    const now = new Date();
    const stats = {
        runStartedAt: now.toISOString(),
        runFinishedAt: now.toISOString(),
        totalFetchedRows: 0,
        totalParsedRows: 0,
        totalRejectedRows: 0,
        totalWrittenRows: 0,
        sourceRuns: [],
        blockedCities: [],
        sampleWrittenDocs: [],
        cityCoverageStatus: [],
    };
    const enabledSources = (0, source_registry_1.getEnabledOfficialSources)();
    const collected = [];
    for (const source of enabledSources) {
        const sourceStats = toSourceStats(source);
        stats.sourceRuns.push(sourceStats);
        logger("source_started", {
            sourceId: source.sourceId,
            sourceName: source.sourceName,
            sourceType: source.sourceType,
            sourceFamily: source.sourceFamily,
            schedulePolicy: source.schedulePolicy,
        });
        try {
            const adapter = adapterFor(source);
            if (adapter == null) {
                sourceStats.failed = true;
                sourceStats.failReason = "adapter_not_implemented_future_ready";
                logger("source_failed", {
                    sourceId: source.sourceId,
                    reason: sourceStats.failReason,
                });
                continue;
            }
            const context = {
                now,
                logger: (event, data) => logger(event, data),
            };
            const rows = await adapter.fetchRows(context);
            sourceStats.fetchedRows = rows.length;
            sourceStats.sourceUrls = extractSourceUrls(rows);
            stats.totalFetchedRows += rows.length;
            const parsedRows = [];
            for (const row of rows) {
                const normalizedCity = (0, normalization_1.normalizeLocationToken)(String(row.city ?? row.mandiName ?? ""));
                mandiPulseLog(`normalized_city=${normalizedCity}`);
                const normalizedCommodity = (0, normalization_1.normalizeCommodityName)(String(row.commodityName ?? ""));
                mandiPulseLog(`normalized_commodity=${normalizedCommodity}`);
                if (normalizedCommodity === "unknown") {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog("row_rejected_reason=unknown_commodity");
                    continue;
                }
                if (!row || !Number.isFinite(row.price) || row.price <= 0) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog("row_rejected_reason=invalid_price");
                    continue;
                }
                if (row.price > 40000) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog("row_rejected_reason=hard_sanity_cap_exceeded");
                    logger("price_rejected_hard_cap", {
                        sourceId: source.sourceId,
                        commodity: row.commodityName,
                        city: row.city,
                        district: row.district,
                        unit: row.unit,
                        price: row.price,
                        sourceRowIndex: row.metadata?.sourceRowIndex ?? null,
                    });
                    continue;
                }
                // Unit validation gate: reject impossible commodity-unit combos
                // before they enter the normalization pipeline.
                const unitCheck = (0, unit_rules_1.checkUnitForCommodity)(row.unit ?? "", normalizedCommodity);
                mandiPulseLog(`normalized_unit=${unitCheck.normalizedUnit || String(row.unit ?? "").trim().toLowerCase()}`);
                if (isSensitiveCommodityForPriceAlert(String(row.commodityName ?? ""), normalizedCommodity) &&
                    unitCheck.normalizedUnit === "per_100kg" &&
                    row.price < 5000) {
                    console.error("[AMIS_PRICE_SANITY_ALERT]", {
                        sourceId: source.sourceId,
                        commodityName: row.commodityName,
                        normalizedCommodity,
                        price: row.price,
                        unit: row.unit,
                        normalizedUnit: unitCheck.normalizedUnit,
                        sourcePage: row.metadata?.sourcePage ?? null,
                        sourceRowIndex: row.metadata?.sourceRowIndex ?? null,
                    });
                }
                if (!unitCheck.allowed) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog(`row_rejected_reason=${unitCheck.reason}`);
                    logger("unit_rejected", {
                        sourceId: source.sourceId,
                        commodity: row.commodityName,
                        unit: row.unit,
                        reason: unitCheck.reason,
                    });
                    continue;
                }
                const rawUnitConflictReason = (0, unit_rules_1.detectRawUnitConflict)(unitCheck.normalizedUnit, String(row.metadata?.rawPriceText ?? row.metadata?.priceText ?? ""));
                if (rawUnitConflictReason) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog(`row_rejected_reason=${rawUnitConflictReason}`);
                    continue;
                }
                const sanityReason = (0, unit_rules_1.sanityRejectReason)(normalizedCommodity, unitCheck.normalizedUnit, row.price);
                if (sanityReason) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog(`row_rejected_reason=${sanityReason}`);
                    continue;
                }
                // Pre-annotate critical unit violation flag (belt-and-suspenders)
                const isCritical = (0, unit_rules_1.isCriticalUnitViolation)(normalizedCommodity, row.unit ?? "");
                try {
                    const unified = (0, normalization_1.toUnifiedBase)(row, now);
                    if (unified.freshnessStatus === "stale") {
                        sourceStats.rejectedRows += 1;
                        mandiPulseLog("row_rejected_reason=stale_row");
                        continue;
                    }
                    // Embed unit validation result into metadata for confidence engine
                    parsedRows.push({
                        ...unified,
                        metadata: {
                            ...unified.metadata,
                            unitValidated: unitCheck.allowed,
                            unitCheckReason: unitCheck.reason,
                            unitNormalized: unitCheck.normalizedUnit,
                            criticalUnitViolation: isCritical,
                        },
                    });
                }
                catch (_error) {
                    sourceStats.rejectedRows += 1;
                    mandiPulseLog("row_rejected_reason=normalization_failed");
                }
            }
            sourceStats.parsedRows = parsedRows.length;
            sourceStats.sampleCities = uniqueSample(rows.map((item) => item.city), 5);
            sourceStats.sampleCommodities = uniqueSample(rows.map((item) => item.commodityName), 5);
            stats.totalParsedRows += parsedRows.length;
            stats.totalRejectedRows += sourceStats.rejectedRows;
            collected.push(...parsedRows);
            logger("source_parsed", {
                sourceId: source.sourceId,
                fetchedRows: sourceStats.fetchedRows,
                parsedRows: sourceStats.parsedRows,
                rejectedRows: sourceStats.rejectedRows,
            });
        }
        catch (error) {
            sourceStats.failed = true;
            sourceStats.failReason = String(error);
            logger("source_failed", {
                sourceId: source.sourceId,
                reason: sourceStats.failReason,
            });
        }
    }
    const deduped = (0, dedup_1.dedupeAndAnnotate)(collected).map((item) => {
        // Carry any pre-ingestion flags from metadata into confidence scoring
        const preFlags = [];
        if (item.metadata?.criticalUnitViolation === true) {
            preFlags.push("critical_unit_violation");
        }
        if (item.sourceId === "pbs_spi") {
            preFlags.push("pbs_spi_trend_only");
        }
        const confidence = (0, confidence_engine_1.scoreConfidence)(item, {
            sourceReliability: reliabilityBySource(item.sourceId),
            corroborationCount: item.corroborationCount,
            sameCityCorroboration: item.sameCityCorroboration,
            multiSourceCorroboration: item.multiSourceCorroboration,
            duplicateAgreement: item.duplicateAgreement,
            suspiciousSpike: item.suspiciousSpike,
            sparseData: item.sparseData,
            incompleteMetadata: item.incompleteMetadata,
            weakLocationMatch: !String(item.city ?? "").trim() ||
                !String(item.district ?? "").trim() ||
                String(item.city ?? "").trim().toLowerCase() ===
                    String(item.province ?? "").trim().toLowerCase(),
            ocrWeakParse: String(item.metadata?.parseMethod ?? "").toLowerCase().includes("ocr") &&
                item.duplicateAgreement < 0.55,
            flags: preFlags,
        });
        mandiPulseLog(`confidence=${confidence.score.toFixed(3)} source=${item.sourceId} rowConfidence=${confidence.rowConfidence}`);
        mandiPulseLog(`source_selected=${item.sourceId}`);
        if (preFlags.includes("pbs_spi_trend_only") || confidence.rowConfidence !== "high") {
            mandiPulseLog("fallback_used=true");
        }
        else {
            mandiPulseLog("fallback_used=false");
        }
        return {
            ...item,
            confidenceScore: confidence.score,
            confidenceReason: confidence.reason,
            verificationStatus: confidence.verificationStatus,
            rowConfidence: confidence.rowConfidence,
            sourceReliabilityLevel: confidence.sourceReliabilityLevel,
            flags: confidence.flags,
            reviewStatus: confidence.verificationStatus === "Needs Review" ? "needs_review" : "accepted",
            acceptedBySystem: confidence.verificationStatus !== "Needs Review",
            acceptedByAdmin: false,
            priorityRank: 0,
        };
    });
    // ── Batch-write deduped records to Firestore ──────────────────────────────
    // Firestore allows max 500 operations per batch commit. We chunk accordingly.
    // Preserve coexisting source data (e.g., Karachi + Punjab) by avoiding full
    // collection clears before every source run.
    // const deletedBeforeWrite = await clearCollectionInBatches(db, COLLECTION);
    // logger("collection_cleared", {
    //   collection: COLLECTION,
    //   deletedCount: deletedBeforeWrite,
    // });
    const BATCH_SIZE = 499;
    for (let i = 0; i < deduped.length; i += BATCH_SIZE) {
        const chunk = deduped.slice(i, i + BATCH_SIZE);
        const batch = db.batch();
        for (const record of chunk) {
            const ref = db.collection(COLLECTION).doc(record.id);
            console.log("[AMIS_SAVE_MAP]", {
                docId: record.id,
                sourceId: record.sourceId,
                commodityName: record.commodityName,
                city: record.city,
                mandiName: record.mandiName,
                price: record.price,
                unit: record.unit,
                averagePrice: record.metadata?.averagePrice ?? null,
                minPrice: record.minPrice ?? null,
                maxPrice: record.maxPrice ?? null,
                sourceRowIndex: record.metadata?.sourceRowIndex ?? null,
                sourceTdCount: record.metadata?.sourceTdCount ?? null,
                sourceCityColumnIndex: record.metadata?.sourceCityColumnIndex ?? null,
                sourceMinColumnIndex: record.metadata?.sourceMinColumnIndex ?? null,
                sourceMaxColumnIndex: record.metadata?.sourceMaxColumnIndex ?? null,
                sourceFqpColumnIndex: record.metadata?.sourceFqpColumnIndex ?? null,
                sourceQuantityColumnIndex: record.metadata?.sourceQuantityColumnIndex ?? null,
            });
            batch.set(ref, toFirestorePayload(record), { merge: true });
        }
        try {
            await batch.commit();
            for (const record of chunk) {
                stats.totalWrittenRows += 1;
                if (stats.sampleWrittenDocs.length < 10) {
                    stats.sampleWrittenDocs.push({
                        id: record.id,
                        sourceId: record.sourceId,
                        city: record.city,
                        commodityName: record.commodityName,
                        price: record.price,
                        lastUpdatedIso: record.lastUpdated.toISOString(),
                    });
                }
                const sourceRun = stats.sourceRuns.find((item) => item.sourceId === record.sourceId);
                if (sourceRun) {
                    sourceRun.writtenRows += 1;
                }
            }
        }
        catch (error) {
            logger("batch_write_failed", {
                batchStart: i,
                batchSize: chunk.length,
                reason: String(error),
            });
        }
    }
    stats.runFinishedAt = nowIso();
    stats.blockedCities = (0, blocked_city_registry_1.getBlockedCityRegistry)(top25_mandi_registry_1.TOP_25_MANDI_TARGETS);
    stats.cityCoverageStatus = (0, source_coverage_status_1.buildCityCoverageStatus)({
        targets: top25_mandi_registry_1.TOP_25_MANDI_TARGETS,
        registry: (0, source_registry_1.getEnabledOfficialSources)(),
        sourceRuns: stats.sourceRuns,
        blockedCities: stats.blockedCities,
    });
    await db.collection("system_jobs").doc("mandi_rates_ingestion").set({
        lastRunAt: firestore_1.FieldValue.serverTimestamp(),
        phase: "C",
        status: "completed",
        runStartedAt: stats.runStartedAt,
        runFinishedAt: stats.runFinishedAt,
        totalFetchedRows: stats.totalFetchedRows,
        totalParsedRows: stats.totalParsedRows,
        totalRejectedRows: stats.totalRejectedRows,
        totalWrittenRows: stats.totalWrittenRows,
        sourceRuns: stats.sourceRuns,
        blockedCities: stats.blockedCities,
        sampleWrittenDocs: stats.sampleWrittenDocs,
        cityCoverageStatus: stats.cityCoverageStatus,
    }, { merge: true });
    logger("run_completed", {
        totalFetchedRows: stats.totalFetchedRows,
        totalParsedRows: stats.totalParsedRows,
        totalRejectedRows: stats.totalRejectedRows,
        totalWrittenRows: stats.totalWrittenRows,
    });
    return stats;
}
exports.ingestMandiRatesScheduled = (0, scheduler_1.onSchedule)({
    schedule: "every 15 minutes",
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "1GiB",
}, async () => {
    await runIngestion();
});
exports.ingestMandiRatesOnDemand = (0, https_1.onRequest)({
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "1GiB",
}, async (_req, res) => {
    try {
        const summary = await runIngestion();
        res.status(200).json({ ok: true, summary });
    }
    catch (error) {
        res.status(500).json({ ok: false, error: String(error) });
    }
});
async function runMandiRatesIngestionDebug() {
    return runIngestion();
}
