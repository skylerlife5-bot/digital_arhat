import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as admin from "firebase-admin";
import {FieldValue, Timestamp} from "firebase-admin/firestore";
import {
  AdapterContext,
  OfficialSourceAdapter,
  RawSourceRow,
  SourceDefinition,
  SourceRunStats,
  UnifiedMandiRate,
} from "./sources/types";
import {getEnabledOfficialSources} from "./sources/source_registry";
import {AmisOfficialAdapter} from "./sources/amis_official_adapter";
import {LahoreOfficialAdapter} from "./sources/lahore_official_adapter";
import {KarachiOfficialAdapter} from "./sources/karachi_official_adapter";
import {toUnifiedBase} from "./sources/normalization";
import {dedupeAndAnnotate} from "./sources/dedup";
import {scoreConfidence} from "./sources/confidence_engine";
import {buildCityCoverageStatus} from "./sources/source_coverage_status";
import {TOP_25_MANDI_TARGETS} from "./sources/top25_mandi_registry";
import {BlockedCityEntry, getBlockedCityRegistry} from "./sources/blocked_city_registry";
import {priorityRankForRecord} from "./sources/source_priority_policy";

type IngestionStats = {
  runStartedAt: string;
  runFinishedAt: string;
  totalFetchedRows: number;
  totalParsedRows: number;
  totalRejectedRows: number;
  totalWrittenRows: number;
  sourceRuns: SourceRunStats[];
  blockedCities: BlockedCityEntry[];
  sampleWrittenDocs: Array<{
    id: string;
    sourceId: string;
    city: string;
    commodityName: string;
    price: number;
    lastUpdatedIso: string;
  }>;
  cityCoverageStatus: ReturnType<typeof buildCityCoverageStatus>;
};

const COLLECTION = "mandi_rates";

function getApp(): admin.app.App {
  if (admin.apps.length > 0) {
    return admin.app();
  }

  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT;
  return projectId ? admin.initializeApp({projectId}) : admin.initializeApp();
}

function getDb(): FirebaseFirestore.Firestore {
  return getApp().firestore();
}

function nowIso(): string {
  return new Date().toISOString();
}

function logger(event: string, data: Record<string, unknown>): void {
  console.log(`mandi_phase_a_${event}`, data);
}

function adapterFor(definition: SourceDefinition): OfficialSourceAdapter | null {
  if (definition.adapterClass === "AmisOfficialAdapter") return new AmisOfficialAdapter();
  if (definition.adapterClass === "LahoreOfficialAdapter") return new LahoreOfficialAdapter();
  if (definition.adapterClass === "KarachiOfficialAdapter") return new KarachiOfficialAdapter();
  if (definition.adapterClass === "FutureUnimplementedAdapter") return null;
  return null;
}

function uniqueSample(values: string[], cap: number): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const raw of values) {
    const value = String(raw ?? "").trim();
    if (!value) continue;
    const key = value.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(value);
    if (out.length >= cap) break;
  }
  return out;
}

function extractSourceUrls(rows: RawSourceRow[]): string[] {
  return uniqueSample(
    rows.map((row) => String(row.metadata?.sourceUrl ?? "").trim()).filter((item) => !!item),
    3,
  );
}

function reliabilityBySource(sourceId: string): number {
  if (sourceId === "amis_official") return 0.18;
  if (sourceId === "lahore_official_market_rates") return 0.2;
  if (sourceId === "karachi_official_price_lists") return 0.2;
  return 0.08;
}

function toSourceStats(source: SourceDefinition): SourceRunStats {
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

function toFirestorePayload(rate: UnifiedMandiRate): Record<string, unknown> {
  const sourceType = String(rate.sourceType);
  const reviewStatus = rate.reviewStatus ?? "accepted";
  const acceptedBySystem = rate.acceptedBySystem ?? true;
  const priorityRank = rate.priorityRank ?? priorityRankForRecord(rate);
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
    lastUpdated: Timestamp.fromDate(rate.lastUpdated),
    rateDate: Timestamp.fromDate(rate.lastUpdated),
    syncedAt: FieldValue.serverTimestamp(),
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
    submissionTimestamp: rate.submissionTimestamp ? Timestamp.fromDate(rate.submissionTimestamp) : null,
    sourcePriorityRank: priorityRank,
    isNearby: rate.isNearby,
    isAiCleaned: rate.isAiCleaned,
    metadata: rate.metadata,
    updatedAt: FieldValue.serverTimestamp(),
  };
}

async function runIngestion(): Promise<IngestionStats> {
  const db = getDb();
  const now = new Date();

  const stats: IngestionStats = {
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

  const enabledSources = getEnabledOfficialSources();
  const collected: UnifiedMandiRate[] = [];

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
      const context: AdapterContext = {
        now,
        logger: (event, data) => logger(event, data),
      };

      const rows = await adapter.fetchRows(context);
      sourceStats.fetchedRows = rows.length;
      sourceStats.sourceUrls = extractSourceUrls(rows);
      stats.totalFetchedRows += rows.length;

      const parsedRows: UnifiedMandiRate[] = [];
      for (const row of rows) {
        if (!row || !Number.isFinite(row.price) || row.price <= 0) {
          sourceStats.rejectedRows += 1;
          continue;
        }

        try {
          const unified = toUnifiedBase(row as RawSourceRow, now);
          parsedRows.push(unified);
        } catch (_error) {
          sourceStats.rejectedRows += 1;
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
    } catch (error) {
      sourceStats.failed = true;
      sourceStats.failReason = String(error);
      logger("source_failed", {
        sourceId: source.sourceId,
        reason: sourceStats.failReason,
      });
    }
  }

  const deduped = dedupeAndAnnotate(collected).map((item) => {
    const confidence = scoreConfidence(item, {
      sourceReliability: reliabilityBySource(item.sourceId),
      corroborationCount: item.corroborationCount,
      sameCityCorroboration: item.sameCityCorroboration,
      multiSourceCorroboration: item.multiSourceCorroboration,
      duplicateAgreement: item.duplicateAgreement,
      suspiciousSpike: item.suspiciousSpike,
      sparseData: item.sparseData,
      incompleteMetadata: item.incompleteMetadata,
    });

    return {
      ...item,
      confidenceScore: confidence.score,
      confidenceReason: confidence.reason,
      verificationStatus: confidence.verificationStatus,
      reviewStatus: confidence.verificationStatus === "Needs Review" ? "needs_review" : "accepted",
      acceptedBySystem: confidence.verificationStatus !== "Needs Review",
      acceptedByAdmin: false,
      priorityRank: 0,
    } as UnifiedMandiRate;
  });

  for (const record of deduped) {
    try {
      await db.collection(COLLECTION).doc(record.id).set(toFirestorePayload(record), {merge: true});
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
    } catch (error) {
      logger("record_write_failed", {
        sourceId: record.sourceId,
        id: record.id,
        reason: String(error),
      });
    }
  }

  stats.runFinishedAt = nowIso();
  stats.blockedCities = getBlockedCityRegistry(TOP_25_MANDI_TARGETS);
  stats.cityCoverageStatus = buildCityCoverageStatus({
    targets: TOP_25_MANDI_TARGETS,
    registry: getEnabledOfficialSources(),
    sourceRuns: stats.sourceRuns,
    blockedCities: stats.blockedCities,
  });

  await db.collection("system_jobs").doc("mandi_rates_ingestion").set({
    lastRunAt: FieldValue.serverTimestamp(),
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
  }, {merge: true});

  logger("run_completed", {
    totalFetchedRows: stats.totalFetchedRows,
    totalParsedRows: stats.totalParsedRows,
    totalRejectedRows: stats.totalRejectedRows,
    totalWrittenRows: stats.totalWrittenRows,
  });

  return stats;
}

export const ingestMandiRatesScheduled = onSchedule(
  {
    schedule: "every 15 minutes",
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "1GiB",
  },
  async () => {
    await runIngestion();
  },
);

export const ingestMandiRatesOnDemand = onRequest(
  {
    region: "asia-south1",
    timeoutSeconds: 300,
    memory: "1GiB",
  },
  async (_req, res) => {
    try {
      const summary = await runIngestion();
      res.status(200).json({ok: true, summary});
    } catch (error) {
      res.status(500).json({ok: false, error: String(error)});
    }
  },
);

export async function runMandiRatesIngestionDebug(): Promise<IngestionStats> {
  return runIngestion();
}
