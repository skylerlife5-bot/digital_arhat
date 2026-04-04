class ExportOpportunity {
  const ExportOpportunity({
    required this.id,
    required this.commodity,
    required this.country,
    this.city,
    required this.buyerType,
    required this.demand,
    this.priceHint,
    required this.verified,
    required this.freshnessHours,
    required this.certificationsRequired,
    required this.featured,
  });

  final String id;
  final String commodity;
  final String country;
  final String? city;
  final String buyerType;
  final String demand;
  final String? priceHint;
  final bool verified;
  final int freshnessHours;
  final List<String> certificationsRequired;
  final bool featured;
}
