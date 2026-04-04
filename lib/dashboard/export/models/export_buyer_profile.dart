class ExportBuyerProfile {
  const ExportBuyerProfile({
    required this.id,
    required this.companyName,
    required this.country,
    required this.city,
    required this.buyerType,
    required this.commodities,
    required this.verified,
    required this.lastActiveHours,
    required this.minOrder,
    required this.certificationsPreferred,
    required this.summary,
  });

  final String id;
  final String companyName;
  final String country;
  final String city;
  final String buyerType;
  final List<String> commodities;
  final bool verified;
  final int lastActiveHours;
  final String minOrder;
  final List<String> certificationsPreferred;
  final String summary;
}