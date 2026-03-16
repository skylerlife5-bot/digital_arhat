import {
  ContributorProfile,
  ContributionReviewStatus,
  HumanContributionSubmission,
  RawSourceRow,
  UnifiedMandiRate,
} from "./types";
import {toUnifiedBase} from "./normalization";
import {assessContributorTrust} from "./contributor_trust_engine";
import {assessContributionPenalty} from "./contribution_penalty_engine";
import {assessHumanCorroboration} from "./human_corroboration_engine";
import {canPromoteOnHome, priorityRankForRecord} from "./source_priority_policy";

export type HumanContributionComparableContext = {
  officialComparable: UnifiedMandiRate[];
  trustedHumanComparable: UnifiedMandiRate[];
  hasStrongOfficialEquivalent: boolean;
};

export type HumanContributionDecision = {
  acceptedBySystem: boolean;
  reviewStatus: ContributionReviewStatus;
  verificationStatus: UnifiedMandiRate["verificationStatus"];
  confidenceScore: number;
  confidenceReason: string;
  trustScore: number;
  reliabilityScore: number;
  trustReason: string;
  priorityRank: number;
  homePromotable: boolean;
};

function clamp01(value: number): number {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

function sourceTypeForSubmission(profile: ContributorProfile): "human_verified" | "human_local" {
  if (
    profile.contributorType == "verified_mandi_reporter" ||
    profile.contributorType == "verified_commission_agent" ||
    profile.contributorType == "verified_dealer"
  ) {
    return "human_verified";
  }
  return "human_local";
}

function sourceNameForSubmission(profile: ContributorProfile): string {
  if (sourceTypeForSubmission(profile) == "human_verified") {
    return "Verified Human Contributor";
  }
  return "Trusted Local Contributor";
}

function buildRawRow(submission: HumanContributionSubmission, profile: ContributorProfile): RawSourceRow {
  return {
    sourceId: `human_${profile.contributorId}`,
    sourceType: sourceTypeForSubmission(profile),
    sourceName: sourceNameForSubmission(profile),
    commodityName: submission.commodityName,
    commodityNameUr: submission.commodityNameUr,
    categoryName: submission.categoryName,
    subCategoryName: submission.subCategoryName,
    mandiName: submission.mandiName,
    city: submission.city,
    district: submission.district,
    province: submission.province,
    latitude: submission.latitude,
    longitude: submission.longitude,
    price: submission.price,
    previousPrice: submission.previousPrice,
    minPrice: submission.minPrice,
    maxPrice: submission.maxPrice,
    unit: submission.unit,
    currency: submission.currency,
    trend: "same",
    lastUpdated: submission.submissionTimestamp,
    metadata: {
      ...(submission.metadata ?? {}),
      humanSubmission: true,
      submissionId: submission.submissionId,
    },
  };
}

function verificationFromReview(reviewStatus: ContributionReviewStatus): UnifiedMandiRate["verificationStatus"] {
  if (reviewStatus == "accepted") return "Cross-Checked";
  if (reviewStatus == "limited_confidence") return "Limited Confidence";
  if (reviewStatus == "needs_review") return "Needs Review";
  return "Needs Review";
}

export function evaluateHumanContributionSubmission(input: {
  profile: ContributorProfile;
  submission: HumanContributionSubmission;
  comparable: HumanContributionComparableContext;
  now: Date;
}): {record: UnifiedMandiRate; decision: HumanContributionDecision} {
  const row = buildRawRow(input.submission, input.profile);
  const base = toUnifiedBase(row, input.now);

  const corroboration = assessHumanCorroboration({
    candidatePrice: base.price,
    city: base.city,
    mandiName: base.mandiName,
    unit: base.unit,
    categoryName: base.categoryName,
    subCategoryName: base.subCategoryName,
    officialComparable: input.comparable.officialComparable,
    trustedHumanComparable: input.comparable.trustedHumanComparable,
  });

  const total = Math.max(1, input.profile.totalSubmissions);
  const historicalAcceptanceRate = input.profile.acceptedSubmissions / total;
  const disputeRate = input.profile.disputedSubmissions / total;
  const suspiciousSpikeRate = input.profile.suspiciousSpikeCount / total;
  const cityKey = base.city.trim().toLowerCase();
  const citySpecificReliability = clamp01(input.profile.citySpecificReliability[cityKey] ?? input.profile.reliabilityScore);

  const trust = assessContributorTrust({
    verificationStatus: input.profile.verificationStatus,
    historicalAcceptanceRate,
    agreementWithOfficial: corroboration.officialAgreement,
    agreementWithTrustedContributors: corroboration.trustedContributorAgreement,
    suspiciousSpikeRate,
    disputeRate,
    recencyDays: input.profile.lastSubmissionAt == null
      ? 30
      : Math.max(0, Math.floor((input.now.getTime() - input.profile.lastSubmissionAt.getTime()) / (24 * 60 * 60 * 1000))),
    consistencyScore: clamp01(input.profile.reliabilityScore),
    citySpecificReliability,
  });

  let confidence = 0.35;
  confidence += trust.trustScore * 0.24;
  confidence += corroboration.officialAgreement * 0.24;
  confidence += corroboration.trustedContributorAgreement * 0.17;
  confidence += corroboration.sameCityMandiAlignment ? 0.08 : -0.05;
  confidence += corroboration.stableTaxonomyAlignment ? 0.07 : -0.08;
  confidence -= corroboration.weakCorroboration ? 0.12 : 0;
  confidence -= corroboration.suspiciousDeviation ? 0.14 : 0;

  let reviewStatus: ContributionReviewStatus = "accepted";
  if (confidence < 0.42 || corroboration.suspiciousDeviation) {
    reviewStatus = "rejected";
  } else if (confidence < 0.58 || corroboration.weakCorroboration) {
    reviewStatus = "needs_review";
  } else if (confidence < 0.72) {
    reviewStatus = "limited_confidence";
  }

  const penalty = assessContributionPenalty({
    profile: input.profile,
    reviewStatus,
    suspiciousOutlier: corroboration.suspiciousDeviation,
    consensusContradiction: corroboration.officialAgreement < 0.32,
    spammyRateBehavior: false,
    lowQualityMetadata: !corroboration.stableTaxonomyAlignment,
  });

  confidence -= penalty.trustPenalty;
  confidence = clamp01(confidence);

  if (penalty.shouldSuspend) {
    reviewStatus = "rejected";
  } else if (penalty.shouldMuteTemporarily && reviewStatus == "accepted") {
    reviewStatus = "limited_confidence";
  }

  const verificationStatus = verificationFromReview(reviewStatus);
  const acceptedBySystem = reviewStatus != "rejected";

  const record: UnifiedMandiRate = {
    ...base,
    contributorType: input.profile.contributorType,
    contributorId: input.profile.contributorId,
    contributorVerificationStatus: input.profile.verificationStatus,
    trustScore: trust.trustScore,
    reliabilityScore: trust.reliabilityScore,
    trustLevel: trust.trustLevel,
    trustReason: trust.trustReason,
    reviewStatus,
    corroborationCount: corroboration.corroborationCount,
    disputeCount: input.profile.disputedSubmissions,
    acceptedBySystem,
    acceptedByAdmin: false,
    submissionTimestamp: input.submission.submissionTimestamp,
    confidenceScore: Number(confidence.toFixed(3)),
    confidenceReason: [
      `phaseC_human_intake`,
      corroboration.reason,
      trust.trustReason,
      penalty.reason,
    ].join(";"),
    verificationStatus,
    metadata: {
      ...base.metadata,
      sourceLayer: "human_contribution",
      humanContribution: true,
      corroborationOfficialAgreement: corroboration.officialAgreement,
      corroborationTrustedAgreement: corroboration.trustedContributorAgreement,
      weakCorroboration: corroboration.weakCorroboration,
      suspiciousDeviation: corroboration.suspiciousDeviation,
      penaltyLevel: penalty.penaltyLevel,
      homePromotionBlockedByPenalty: penalty.blockHomePromotion,
    },
  };

  const rank = priorityRankForRecord(record);
  const homePromotable = !penalty.blockHomePromotion && canPromoteOnHome(record, {
    hasStrongOfficialEquivalent: input.comparable.hasStrongOfficialEquivalent,
  });

  record.priorityRank = rank;

  return {
    record,
    decision: {
      acceptedBySystem,
      reviewStatus,
      verificationStatus,
      confidenceScore: Number(confidence.toFixed(3)),
      confidenceReason: record.confidenceReason,
      trustScore: trust.trustScore,
      reliabilityScore: trust.reliabilityScore,
      trustReason: trust.trustReason,
      priorityRank: rank,
      homePromotable,
    },
  };
}
