export type FutureContributorType =
  | "verified_mandi_reporter"
  | "verified_commission_agent"
  | "verified_dealer"
  | "trusted_local_contributor";

export type FutureContributorSignal = {
  contributorType: FutureContributorType;
  contributorId: string;
  city: string;
  district: string;
  province: string;
  trustScore: number;
  evidenceRefs: string[];
  lastVerifiedAtIso: string | null;
};

export type FutureContributionCandidate = {
  commodityName: string;
  mandiName: string;
  city: string;
  unit: string;
  price: number;
  capturedAtIso: string;
  sourceHint: string;
};

export type FutureContributionAssessment = {
  accepted: boolean;
  contributorTrustScore: number;
  requiresManualReview: boolean;
  reason: string;
};

export type FutureContributorOnboardingHook = {
  contributorId: string;
  contributorType: FutureContributorType;
  inviteCodeVerified: boolean;
  cityAssignmentVerified: boolean;
  specializationTags: string[];
  canSubmitRates: boolean;
  canAccessContributorDashboard: boolean;
};

export type FutureContributorPermissionDecision = {
  allowed: boolean;
  reason: string;
  scope: "city_only" | "district_only" | "province_only" | "blocked";
};

export function evaluateFutureContributionSignal(input: {
  contributor: FutureContributorSignal;
  candidate: FutureContributionCandidate;
}): FutureContributionAssessment {
  const trust = Math.max(0, Math.min(1, input.contributor.trustScore));
  const sparseEvidence = input.contributor.evidenceRefs.length < 1;
  const requiresManualReview = trust < 0.65 || sparseEvidence;

  return {
    accepted: trust >= 0.5,
    contributorTrustScore: Number(trust.toFixed(3)),
    requiresManualReview,
    reason: requiresManualReview
      ? "future_contributor_signal_requires_manual_review"
      : "future_contributor_signal_ready_for_weighted_use",
  };
}

export function evaluateFutureContributorOnboarding(
  hook: FutureContributorOnboardingHook,
): FutureContributorPermissionDecision {
  if (!hook.canSubmitRates) {
    return {
      allowed: false,
      reason: "contributor_submit_permission_disabled",
      scope: "blocked",
    };
  }

  if (!hook.inviteCodeVerified || !hook.cityAssignmentVerified) {
    return {
      allowed: false,
      reason: "contributor_invite_or_city_assignment_unverified",
      scope: "blocked",
    };
  }

  if (hook.contributorType === "trusted_local_contributor") {
    return {
      allowed: true,
      reason: "trusted_local_contributor_city_limited_submission",
      scope: "city_only",
    };
  }

  if (hook.contributorType === "verified_commission_agent") {
    return {
      allowed: true,
      reason: "verified_commission_agent_district_submission_scope",
      scope: "district_only",
    };
  }

  if (hook.contributorType === "verified_dealer") {
    return {
      allowed: true,
      reason: "verified_dealer_district_submission_scope",
      scope: "district_only",
    };
  }

  return {
    allowed: true,
    reason: "verified_mandi_reporter_province_submission_scope",
    scope: "province_only",
  };
}
