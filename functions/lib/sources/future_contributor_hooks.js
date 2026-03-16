"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateFutureContributionSignal = evaluateFutureContributionSignal;
exports.evaluateFutureContributorOnboarding = evaluateFutureContributorOnboarding;
function evaluateFutureContributionSignal(input) {
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
function evaluateFutureContributorOnboarding(hook) {
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
