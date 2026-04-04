import '../models/live_mandi_rate.dart';
import '../utils/mandi_display_utils.dart';
import 'mandi_home_presenter.dart';

/// Presenter for the All Mandi Rates explorer screen.
///
/// Applies the same canonical normalization as Home but with broader
/// acceptance — all mappable commodities are allowed, not just the
/// Home allowlist.
class MandiAllPresenter {
  const MandiAllPresenter._();

  // ---------------------------------------------------------------------------
  // Row rejection
  // ---------------------------------------------------------------------------

  /// Returns null if the row is renderable, or a rejection reason string.
  static String? rejectReason(LiveMandiRate rate) {
    final trustedPrice = getTrustedDisplayPrice(rate);
    if (trustedPrice <= 0) return 'zero_price';
    if (rate.isRejectedContribution) return 'rejected_contribution';
    if (rate.rowConfidence == MandiRowConfidence.rejected) {
      return 'rejected_confidence';
    }
    if (rate.flags.contains('unit_violation') ||
        rate.flags.contains('critical_unit_violation') ||
        rate.flags.contains('mixed_unit_violation')) {
      return 'unit_violation_flag';
    }

    final commodity = commodityEnglish(rate);
    if (commodity == 'Commodity' || commodity.isEmpty) {
      return 'unmapped_commodity';
    }

    if (!_isValidCommodityUnit(rate.commodityName, rate.unit)) {
      return 'invalid_commodity_unit';
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Canonical English display helpers
  // ---------------------------------------------------------------------------

  /// Canonical English commodity name: "Wheat", "Rice", "Banana", etc.
  /// Returns 'Commodity' if unmappable (caller should reject).
  static String commodityEnglish(LiveMandiRate rate) {
    if (rate.commodityName.trim().isNotEmpty) {
      final canonical = _canonicalizeEnglishCommodity(rate.commodityName);
      if (canonical != null) return canonical;
    }
    if (rate.commodityNameUr.trim().isNotEmpty) {
      final canonical = _canonicalizeEnglishCommodity(rate.commodityNameUr);
      if (canonical != null) return canonical;
    }
    return 'Commodity';
  }

  /// Try multiple strategies to map a raw commodity string to a canonical
  /// English name from [englishToUrduCommodityMap].
  static String? _canonicalizeEnglishCommodity(String raw) {
    // 1) Standard localization path — exact lookup
    final en = getLocalizedCommodityName(raw, MandiDisplayLanguage.english);
    if (en != 'Commodity' &&
        en.isNotEmpty &&
        englishToUrduCommodityMap.containsKey(en.toLowerCase())) {
      return en;
    }

    // 2) Strip parenthesized fragments and retry
    final stripped = raw
        .replaceAll(RegExp(r'\([^)]*\)'), ' ')
        .replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (stripped.isNotEmpty && stripped != raw) {
      final en2 = getLocalizedCommodityName(
        stripped,
        MandiDisplayLanguage.english,
      );
      if (en2 != 'Commodity' &&
          en2.isNotEmpty &&
          englishToUrduCommodityMap.containsKey(en2.toLowerCase())) {
        return en2;
      }
    }

    // 3) Fuzzy: check if any map key is contained in the normalized input.
    //    Try longer keys first for the most specific match.
    final normalized = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final sortedKeys = englishToUrduCommodityMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final key in sortedKeys) {
      if (normalized.contains(key)) {
        return key
            .split(' ')
            .map((w) =>
                w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
      }
    }

    return null;
  }

  /// Canonical English city display: "Lahore, Punjab"
  static String cityEnglish(LiveMandiRate rate) {
    final primary = rate.city.trim().isNotEmpty ? rate.city : rate.district;
    final cityEn = getLocalizedCityName(primary, MandiDisplayLanguage.english);
    final provEn = getLocalizedCityName(
      rate.province,
      MandiDisplayLanguage.english,
    );

    if (cityEn.isEmpty || cityEn == 'Pakistan') {
      return provEn.isNotEmpty && provEn != 'Pakistan' ? provEn : 'Pakistan';
    }
    if (provEn.isNotEmpty &&
        provEn != 'Pakistan' &&
        provEn.toLowerCase() != cityEn.toLowerCase()) {
      return '$cityEn, $provEn';
    }
    return cityEn;
  }

  /// Canonical English unit: "100 kg", "kg", "dozen", etc.
  static String unitEnglish(LiveMandiRate rate) {
    return getLocalizedUnit(
      rate.unit,
      MandiDisplayLanguage.english,
      commodity: rate.commodityName,
    );
  }

  /// Source priority rank for logging.
  static int sourceRank(LiveMandiRate rate) {
    return MandiHomePresenter.sourcePriorityFromRate(rate);
  }

  // ---------------------------------------------------------------------------
  // Commodity-unit validation (broader than Home)
  // ---------------------------------------------------------------------------

  static bool _isValidCommodityUnit(String commodityRaw, String unitRaw) {
    final commodity = commodityRaw.trim().toLowerCase();
    final unitKey = MandiHomePresenter.normalizeHomeUnitKey(unitRaw);
    if (unitKey.isEmpty) return true;

    final isCountUnit = unitKey == 'per_dozen' ||
        unitKey == 'per_tray' ||
        unitKey == 'per_piece' ||
        unitKey == 'per_crate' ||
        unitKey == 'per_peti';

    // Banana / eggs must use count-based units
    if (commodity.contains('banana') || commodity.contains('کیلا')) {
      return isCountUnit;
    }
    if (commodity.contains('egg') || commodity.contains('انڈ')) {
      return isCountUnit;
    }

    // Lemon is the only other commodity sold by count
    if (isCountUnit) {
      return commodity.contains('lemon') ||
          commodity.contains('لیموں') ||
          commodity.contains('nimbu');
    }

    return true;
  }
}
