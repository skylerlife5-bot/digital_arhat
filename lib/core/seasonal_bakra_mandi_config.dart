class SeasonalBakraMandiConfig {
  static const bool manualEnabled = true;
  static const bool allowPosting = true;

  // Temporary seasonal window for Eid Bakra Mandi.
  static DateTime get windowStart => DateTime(DateTime.now().year, 5, 20);
  static DateTime get windowEnd => DateTime(DateTime.now().year, 8, 25, 23, 59, 59);

  static const Duration listingLifetime = Duration(days: 30);

  static bool get isInDateWindow {
    final now = DateTime.now();
    return !now.isBefore(windowStart) && !now.isAfter(windowEnd);
  }

  static bool get isEnabled => manualEnabled && isInDateWindow;

  static bool isBakraCategory(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase() == 'bakra_mandi';
  }
}
