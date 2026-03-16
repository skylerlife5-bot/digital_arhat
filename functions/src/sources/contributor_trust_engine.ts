import {
  ContributorProfile,
  ContributorTrustLevel,
  ContributorVerificationStatus,
} from "./types";

export type ContributorTrustInputs = {
  verificationStatus: ContributorVerificationStatus;
  historicalAcceptanceRate: number;
  agreementWithOfficial: number;
  agreementWithTrustedContributors: number;
  suspiciousSpikeRate: number;
  disputeRate: number;
  recencyDays: number;
  consistencyScore: number;
  citySpecificReliability: number;
};

export type ContributorTrustAssessment = {
  trustScore: number;
  reliabilityScore: number;
  trustLevel: ContributorTrustLevel;
  trustReason: string;
};

function clamp01(value: number): number {
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

function verificationBase(status: ContributorVerificationStatus): number {
  if (status === "verified") return 0.3;
  if (status === "provisional") return 0.18;
  if (status === "pending") return 0.08;
  if (status === "suspended" || status === "revoked") return -0.35;
  return 0;
}

function toTrustLevel(score: number): ContributorTrustLevel {
  if (score >= 0.8) return "high";
  if (score >= 0.6) return "medium";
  if (score >= 0.38) return "low";
  return "blocked";
}

export function assessContributorTrust(input: ContributorTrustInputs): ContributorTrustAssessment {
  let score = 0.25;
  score += verificationBase(input.verificationStatus);
  score += clamp01(input.historicalAcceptanceRate) * 0.16;
  score += clamp01(input.agreementWithOfficial) * 0.2;
  score += clamp01(input.agreementWithTrustedContributors) * 0.12;
  score += clamp01(input.consistencyScore) * 0.11;
  score += clamp01(input.citySpecificReliability) * 0.08;

  const recencyBonus = input.recencyDays <= 14 ? 0.04 : input.recencyDays <= 45 ? 0.02 : -0.03;
  score += recencyBonus;

  score -= clamp01(input.suspiciousSpikeRate) * 0.22;
  score -= clamp01(input.disputeRate) * 0.12;

  const trustScore = Number(clamp01(score).toFixed(3));
  const reliabilityScore = Number(
    clamp01((
      clamp01(input.historicalAcceptanceRate) * 0.45 +
      clamp01(input.agreementWithOfficial) * 0.35 +
      clamp01(input.consistencyScore) * 0.2
    )).toFixed(3),
  );
  const trustLevel = toTrustLevel(trustScore);
  const trustReason = [
    `verification=${input.verificationStatus}`,
    `acceptance=${clamp01(input.historicalAcceptanceRate).toFixed(3)}`,
    `officialAgreement=${clamp01(input.agreementWithOfficial).toFixed(3)}`,
    `trustedAgreement=${clamp01(input.agreementWithTrustedContributors).toFixed(3)}`,
    `consistency=${clamp01(input.consistencyScore).toFixed(3)}`,
    `cityReliability=${clamp01(input.citySpecificReliability).toFixed(3)}`,
    `spikes=${clamp01(input.suspiciousSpikeRate).toFixed(3)}`,
    `disputes=${clamp01(input.disputeRate).toFixed(3)}`,
  ].join(";");

  return {
    trustScore,
    reliabilityScore,
    trustLevel,
    trustReason,
  };
}

export function nextProfileFromTrustAssessment(
  profile: ContributorProfile,
  trust: ContributorTrustAssessment,
): ContributorProfile {
  return {
    ...profile,
    trustScore: trust.trustScore,
    reliabilityScore: trust.reliabilityScore,
    metadata: {
      ...profile.metadata,
      lastTrustReason: trust.trustReason,
    },
  };
}
