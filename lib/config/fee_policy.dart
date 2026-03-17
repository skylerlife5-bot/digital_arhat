class FeePolicy {
  const FeePolicy._();

  // Business toggle: buyer-facing bid fee is currently inactive.
  static const bool bidFeeActive = false;

  // Keep rate ready for future activation without hardcoding in UI.
  static const double bidFeeRate = 0.01;
}
