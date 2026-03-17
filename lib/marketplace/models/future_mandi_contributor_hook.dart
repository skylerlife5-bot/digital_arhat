enum FutureMandiContributorType {
  verifiedMandiReporter,
  verifiedCommissionAgent,
  verifiedDealer,
  trustedLocalContributor,
}

class FutureMandiContributorSignal {
  const FutureMandiContributorSignal({
    required this.contributorId,
    required this.type,
    required this.city,
    required this.district,
    required this.province,
    required this.trustScore,
    required this.lastVerifiedAt,
    required this.evidenceRefs,
  });

  final String contributorId;
  final FutureMandiContributorType type;
  final String city;
  final String district;
  final String province;
  final double trustScore;
  final DateTime? lastVerifiedAt;
  final List<String> evidenceRefs;
}

class FutureMandiContributionAssessment {
  const FutureMandiContributionAssessment({
    required this.accepted,
    required this.requiresManualReview,
    required this.reason,
  });

  final bool accepted;
  final bool requiresManualReview;
  final String reason;
}

class FutureMandiContributorOnboardingHook {
  const FutureMandiContributorOnboardingHook({
    required this.contributorId,
    required this.type,
    required this.inviteCodeVerified,
    required this.cityAssignmentVerified,
    required this.specializationTags,
    required this.canSubmitRates,
    required this.canAccessContributorDashboard,
  });

  final String contributorId;
  final FutureMandiContributorType type;
  final bool inviteCodeVerified;
  final bool cityAssignmentVerified;
  final List<String> specializationTags;
  final bool canSubmitRates;
  final bool canAccessContributorDashboard;
}

class FutureMandiContributorPermissionDecision {
  const FutureMandiContributorPermissionDecision({
    required this.allowed,
    required this.reason,
    required this.scope,
  });

  final bool allowed;
  final String reason;
  final String scope;
}

FutureMandiContributionAssessment evaluateFutureMandiContributorSignal(
  FutureMandiContributorSignal signal,
) {
  final hasEvidence = signal.evidenceRefs.isNotEmpty;
  final trust = signal.trustScore.clamp(0.0, 1.0);
  final requiresReview = trust < 0.65 || !hasEvidence;

  return FutureMandiContributionAssessment(
    accepted: trust >= 0.5,
    requiresManualReview: requiresReview,
    reason: requiresReview
        ? 'future_contributor_signal_requires_manual_review'
        : 'future_contributor_signal_ready_for_weighted_use',
  );
}

FutureMandiContributorPermissionDecision evaluateFutureMandiContributorOnboarding(
  FutureMandiContributorOnboardingHook hook,
) {
  if (!hook.canSubmitRates) {
    return const FutureMandiContributorPermissionDecision(
      allowed: false,
      reason: 'contributor_submit_permission_disabled',
      scope: 'blocked',
    );
  }

  if (!hook.inviteCodeVerified || !hook.cityAssignmentVerified) {
    return const FutureMandiContributorPermissionDecision(
      allowed: false,
      reason: 'contributor_invite_or_city_assignment_unverified',
      scope: 'blocked',
    );
  }

  if (hook.type == FutureMandiContributorType.trustedLocalContributor) {
    return const FutureMandiContributorPermissionDecision(
      allowed: true,
      reason: 'trusted_local_contributor_city_limited_submission',
      scope: 'city_only',
    );
  }

  if (hook.type == FutureMandiContributorType.verifiedCommissionAgent ||
      hook.type == FutureMandiContributorType.verifiedDealer) {
    return const FutureMandiContributorPermissionDecision(
      allowed: true,
      reason: 'verified_agent_or_dealer_district_submission_scope',
      scope: 'district_only',
    );
  }

  return const FutureMandiContributorPermissionDecision(
    allowed: true,
    reason: 'verified_mandi_reporter_province_submission_scope',
    scope: 'province_only',
  );
}
