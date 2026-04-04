class ExportReadyProduct {
  const ExportReadyProduct({
    required this.id,
    required this.commodity,
    required this.suggestedMarkets,
    required this.idealSupplyFormat,
    required this.packagingType,
    required this.shelfLifeNote,
    required this.readinessLevel,
  });

  final String id;
  final String commodity;
  final List<String> suggestedMarkets;
  final String idealSupplyFormat;
  final String packagingType;
  final String shelfLifeNote;
  final String readinessLevel;
}