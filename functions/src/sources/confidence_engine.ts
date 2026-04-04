import {MandiRateFlag, RowConfidence, SourceReliabilityLevel, UnifiedMandiRate, VerificationStatus} from "./types";

export type ConfidenceInputs = {
  sourceReliability: number;
  corroborationCount: number;
  sameCityCorroboration: number;
  multiSourceCorroboration: number;
  duplicateAgreement: number;
  suspiciousSpike: boolean;
  sparseData: boolean;
  incompleteMetadata: boolean;
  weakLocationMatch?: boolean;
  ocrWeakParse?: boolean;
  /** Flags pre-computed by the ingestion pipeline (unit violations, etc.). */
  flags?: MandiRateFlag[];
};

function clamp01(value: number): number {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

function freshnessBonus(status: UnifiedMandiRate["freshnessStatus"]): number {
  if (status === "live") return 0.2;
  if (status === "recent") return 0.14;
  if (status === "aging") return 0.06;
  return -0.15;
}

function officialSourceBonus(sourceId: string): number {
  // FS&CPD = primary (district-wise official daily) → highest bonus
  if (sourceId === "fscpd_official") return 0.30;
  // AMIS = secondary (broader, stricter unit handling)
  if (sourceId === "amis_official") return 0.24;
  if (sourceId === "lahore_official_market_rates") return 0.20;
  if (sourceId === "karachi_official_price_lists") return 0.18;
  return 0;
}

function multiSourceBonus(count: number): number {
  if (count >= 3) return 0.14;
  if (count == 2) return 0.09;
  return 0;
}

function sameCityBonus(count: number): number {
  if (count >= 4) return 0.1;
  if (count >= 2) return 0.06;
  return 0;
}

function toVerificationStatus(score: number, corroborationCount: number): VerificationStatus {
  if (score >= 0.85) return "Official Verified";
  if (score >= 0.7 && corroborationCount > 1) return "Cross-Checked";
  if (score >= 0.5) return "Limited Confidence";
  return "Needs Review";
}

/**
 * Derive the ticker RowConfidence from the numeric score + flags.
 *
 * HARD RULES:
 *  - Any unit_violation flag → "rejected"  (never shown as price in ticker)
 *  - Any critical_unit_violation → "rejected"
 *  - pbs_spi_trend_only → "low"  (pulse message only, no numeric price)
 *  - score >= 0.75, source high, freshness live/recent → "high"
 *  - score >= 0.50 → "medium"
 *  - otherwise → "low"
 */
function toRowConfidence(
  score: number,
  sourceId: string,
  freshnessStatus: UnifiedMandiRate["freshnessStatus"],
  flags: MandiRateFlag[],
): RowConfidence {
  // Hard reject: any unit violation
  if (
    flags.includes("unit_violation") ||
    flags.includes("critical_unit_violation")
  ) {
    return "rejected";
  }
  // PBS SPI is trend-only — never show as numeric price
  if (flags.includes("pbs_spi_trend_only")) return "low";

  const highSourceIds = new Set([
    "fscpd_official",
    "lahore_official_market_rates",
    "karachi_official_price_lists",
    "amis_official",
  ]);
  const isHighSource = highSourceIds.has(sourceId);
  const isFresh = freshnessStatus === "live" || freshnessStatus === "recent";

  if (score >= 0.75 && isHighSource && isFresh) return "high";
  if (score >= 0.75 && isHighSource) return "high"; // aging but high source
  if (score >= 0.50) return "medium";
  return "low";
}

/** Source-level reliability bucket (independent of row freshness). */
function toSourceReliabilityLevel(sourceId: string): SourceReliabilityLevel {
  const high = new Set([
    "fscpd_official",
    "lahore_official_market_rates",
    "karachi_official_price_lists",
    "amis_official",
  ]);
  if (high.has(sourceId)) return "high";
  if (sourceId.startsWith("human_verified")) return "medium";
  return "low";
}

export function scoreConfidence(
  record: UnifiedMandiRate,
  input: ConfidenceInputs,
): {
  score: number;
  reason: string;
  verificationStatus: VerificationStatus;
  rowConfidence: RowConfidence;
  sourceReliabilityLevel: SourceReliabilityLevel;
  flags: MandiRateFlag[];
} {
  const incomingFlags: MandiRateFlag[] = input.flags ?? [];

  let score = 0.45;
  score += officialSourceBonus(record.sourceId);
  score += freshnessBonus(record.freshnessStatus);
  score += input.sourceReliability;
  if (input.corroborationCount > 1) {
    score += Math.min(0.14, (input.corroborationCount - 1) * 0.05);
  }
  score += sameCityBonus(input.sameCityCorroboration);
  score += multiSourceBonus(input.multiSourceCorroboration);
  score += Math.max(-0.12, Math.min(0.12, (input.duplicateAgreement - 0.5) * 0.24));
  if (input.suspiciousSpike) score -= 0.26;
  if (input.sparseData) score -= 0.12;
  if (input.incompleteMetadata) score -= 0.08;
  if (input.weakLocationMatch === true) score -= 0.09;
  if (input.ocrWeakParse === true) score -= 0.08;

  // Unit violations lower score further
  if (incomingFlags.includes("unit_violation")) score -= 0.25;
  if (incomingFlags.includes("critical_unit_violation")) score -= 0.50;

  const finalScore = Number(clamp01(score).toFixed(3));
  const status = toVerificationStatus(finalScore, input.corroborationCount);

  // Build final flags list
  const flags: MandiRateFlag[] = [...incomingFlags];
  if (input.suspiciousSpike && !flags.includes("price_spike")) flags.push("price_spike");
  if (input.sparseData && !flags.includes("sparse_data")) flags.push("sparse_data");
  if (record.freshnessStatus === "stale" && !flags.includes("stale_source")) flags.push("stale_source");
  if (!record.commodityNameUr?.trim() && !flags.includes("no_urdu_label")) flags.push("no_urdu_label");

  const rowConfidence = toRowConfidence(finalScore, record.sourceId, record.freshnessStatus, flags);
  const sourceReliabilityLevel = toSourceReliabilityLevel(record.sourceId);

  // Add low_source_reliability flag if needed
  if (sourceReliabilityLevel === "low" && !flags.includes("low_source_reliability")) {
    flags.push("low_source_reliability");
  }

  const reasonParts = [
    `source=${record.sourceId}`,
    `freshness=${record.freshnessStatus}`,
    `corroboration=${input.corroborationCount}`,
    `sameCity=${input.sameCityCorroboration}`,
    `multiSource=${input.multiSourceCorroboration}`,
    `agreement=${input.duplicateAgreement.toFixed(3)}`,
    `spike=${input.suspiciousSpike ? "yes" : "no"}`,
    `sparse=${input.sparseData ? "yes" : "no"}`,
    `incomplete=${input.incompleteMetadata ? "yes" : "no"}`,
    `weakLocation=${input.weakLocationMatch === true ? "yes" : "no"}`,
    `ocrWeak=${input.ocrWeakParse === true ? "yes" : "no"}`,
    `rowConfidence=${rowConfidence}`,
    `flags=${flags.join(",")}`,
  ];

  return {
    score: finalScore,
    reason: reasonParts.join(";"),
    verificationStatus: status,
    rowConfidence,
    sourceReliabilityLevel,
    flags,
  };
}
