enum AiMandiInsightType {
  nearbyBestMandi,
  movementWarning,
  sellerOpportunity,
  buyerUrgency,
  nearbyComparison,
  categoryDemand,
}

class AiMandiBrainInsight {
  const AiMandiBrainInsight({
    required this.commodity,
    required this.insight,
    required this.action,
    required this.type,
    required this.priority,
    required this.evidenceTags,
    this.mandi,
  });

  final String commodity;
  final String insight;
  final String action;
  final AiMandiInsightType type;
  final int priority;
  final Set<String> evidenceTags;
  final String? mandi;
}
