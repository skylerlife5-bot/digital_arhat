import {ContributionReviewStatus, UnifiedMandiRate} from "./types";

function isOfficial(record: UnifiedMandiRate): boolean {
  return record.contributorType == "official" ||
    record.sourceType == "official_aggregator" ||
    record.sourceType == "official_market_committee" ||
    record.sourceType == "official_commissioner";
}

function isVerifiedHuman(record: UnifiedMandiRate): boolean {
  return record.contributorType == "verified_mandi_reporter" ||
    record.contributorType == "verified_commission_agent" ||
    record.contributorType == "verified_dealer";
}

function isTrustedLocal(record: UnifiedMandiRate): boolean {
  return record.contributorType == "trusted_local_contributor";
}

function hasStrongCorroboration(record: UnifiedMandiRate): boolean {
  return (record.corroborationCount ?? 0) >= 2 &&
    (record.confidenceScore >= 0.7 || (record.trustScore ?? 0) >= 0.72);
}

function reviewStatus(record: UnifiedMandiRate): ContributionReviewStatus {
  return record.reviewStatus ?? (record.confidenceScore >= 0.8 ? "accepted" : "needs_review");
}

export function priorityRankForRecord(record: UnifiedMandiRate): number {
  if (isOfficial(record) && record.verificationStatus == "Official Verified") return 1;
  if (isOfficial(record) && record.verificationStatus == "Cross-Checked") return 2;

  if (isVerifiedHuman(record) && hasStrongCorroboration(record)) return 3;
  if (isTrustedLocal(record) && hasStrongCorroboration(record)) return 4;
  if (!isOfficial(record) && reviewStatus(record) != "rejected") return 5;
  return 6;
}

export function canPromoteOnHome(
  record: UnifiedMandiRate,
  options: {hasStrongOfficialEquivalent: boolean},
): boolean {
  if (reviewStatus(record) == "rejected") return false;
  const rank = priorityRankForRecord(record);

  if (rank <= 2) return true;

  // Human data is allowed on Home only where official equivalent is weak/missing,
  // or where human corroboration and confidence is clearly strong.
  if (options.hasStrongOfficialEquivalent) {
    return rank <= 4 && (record.confidenceScore >= 0.82 || (record.trustScore ?? 0) >= 0.84);
  }

  return rank <= 4 &&
    record.confidenceScore >= 0.72 &&
    (record.reviewStatus == "accepted" || record.verificationStatus == "Cross-Checked");
}
