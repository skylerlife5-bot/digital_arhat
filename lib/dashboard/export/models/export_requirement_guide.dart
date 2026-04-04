class ExportRequirementGuide {
  const ExportRequirementGuide({
    required this.id,
    required this.country,
    required this.commodity,
    required this.keyRequirements,
    required this.preferredCertifications,
    required this.packagingNotes,
    required this.statusNote,
  });

  final String id;
  final String country;
  final String commodity;
  final List<String> keyRequirements;
  final List<String> preferredCertifications;
  final String packagingNotes;
  final String statusNote;
}