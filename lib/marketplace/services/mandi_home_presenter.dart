import 'package:flutter/foundation.dart';

import '../models/live_mandi_rate.dart';
import '../utils/mandi_display_utils.dart';

enum MandiHomeRenderPath { ticker, snapshot, card }

class HomeMandiDisplayRow {
  const HomeMandiDisplayRow({
    required this.commodityDisplay,
    required this.cityDisplay,
    required this.priceDisplay,
    required this.unitDisplay,
    required this.fullTickerLine,
    required this.fullSnapshotLine,
    required this.sourceSelected,
    required this.confidence,
    required this.isFallback,
    required this.rejectReason,
    required this.isRenderable,
  });

  final String commodityDisplay;
  final String cityDisplay;
  final String priceDisplay;
  final String unitDisplay;
  final String fullTickerLine;
  final String fullSnapshotLine;
  final String sourceSelected;
  final double confidence;
  final bool isFallback;
  final String? rejectReason;
  final bool isRenderable;
}

class MandiHomePresenter {
  const MandiHomePresenter._();

  static final RegExp _urduDigits = RegExp(r'[\u06F0-\u06F9\u0660-\u0669]');

  static const Set<String> homeCommodityAllowlist = <String>{
    'live_chicken',
    'chicken_meat',
    'beef',
    'mutton',
    'wheat',
    'milk',
    'eggs',
    'potato',
    'tomato',
    'onion',
    'rice',
    'lentils',
    'sugar',
    'gram',
    'garlic',
    'ginger',
  };

  /// Priority tiers for Home commodity ranking.
  /// Lower number = higher priority. Used by diversity layer.
  static const Map<String, int> commodityPriority = <String, int>{
    'live_chicken': 1,
    'chicken_meat': 2,
    'beef': 3,
    'mutton': 4,
    'potato': 5,
    'onion': 6,
    'tomato': 7,
    'garlic': 8,
    'ginger': 9,
    'milk': 10,
    'wheat': 11,
    'rice': 12,
    'lentils': 13,
    'sugar': 14,
    'gram': 15,
    'eggs': 16,
  };

  /// Soft cap: max rows per commodity in ticker candidate pool.
  static const int tickerCommodityCap = 2;

  /// Soft cap: max rows per commodity in snapshot visible list.
  static const int snapshotCommodityCap = 1;

  static const Map<String, List<String>> _commoditySynonyms =
      <String, List<String>>{
        'live_chicken': <String>[
          'live chicken',
          'zinda murghi',
          'zinda murgi',
          'زندہ مرغی',
          'مرغی زندہ',
          'broiler live',
          'broiler',
          'chicken live',
        ],
        'chicken_meat': <String>[
          'chicken meat',
          'murghi ka gosht',
          'murgi ka gosht',
          'مرغی کا گوشت',
        ],
        'beef': <String>['beef', 'bara gosht', 'bara ghost', 'بڑا گوشت'],
        'mutton': <String>[
          'mutton',
          'chhota gosht',
          'chota gosht',
          'چھوٹا گوشت',
        ],
        'wheat': <String>['wheat', 'gehun', 'gandum', 'گندم'],
        'milk': <String>['milk', 'doodh', 'دودھ', 'cow milk', 'buffalo milk'],
        'rice': <String>['rice', 'chawal', 'دھان', 'چاول', 'paddy'],
        'potato': <String>['potato', 'aloo', 'aalu', 'alu', 'آلو'],
        'onion': <String>['onion', 'pyaz', 'piaz', 'پیاز'],
        'tomato': <String>['tomato', 'tamatar', 'tomatar', 'ٹماٹر'],
        'eggs': <String>['egg', 'eggs', 'anda', 'anday', 'انڈا', 'انڈے'],
        'lentils': <String>['lentils', 'lentil', 'daal', 'dal', 'دال', 'دالیں'],
        'sugar': <String>['sugar', 'chini', 'cheeni', 'چینی'],
        'gram': <String>['gram', 'chickpea', 'chana', 'چنا'],
        'garlic': <String>['garlic', 'lehsan', 'lahsun', 'لہسن'],
        'ginger': <String>['ginger', 'adrak', 'ادرک'],
      };

  static String normalizeCommodityText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF\s]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeCommodityKey(String raw) {
    final candidate = normalizeCommodityText(raw);
    if (candidate.isEmpty) return '';

    for (final entry in _commoditySynonyms.entries) {
      for (final synonym in entry.value) {
        final normalizedSynonym = normalizeCommodityText(synonym);
        if (normalizedSynonym.isEmpty) continue;
        if (candidate == normalizedSynonym ||
            candidate.contains(normalizedSynonym)) {
          return entry.key;
        }
      }
    }

    return '';
  }

  static bool isAllowlistedCommodity(String commodityKey) {
    return homeCommodityAllowlist.contains(commodityKey);
  }

  static String commodityDisplayUrdu(String commodityKey) {
    switch (commodityKey) {
      case 'live_chicken':
        return 'زندہ مرغی';
      case 'chicken_meat':
        return 'مرغی کا گوشت';
      case 'beef':
        return 'بڑا گوشت';
      case 'mutton':
        return 'چھوٹا گوشت';
      case 'wheat':
        return 'گندم';
      case 'milk':
        return 'دودھ';
      case 'rice':
        return 'چاول';
      case 'potato':
        return 'آلو';
      case 'onion':
        return 'پیاز';
      case 'tomato':
        return 'ٹماٹر';
      case 'eggs':
        return 'انڈے';
      case 'lentils':
        return 'دالیں';
      case 'sugar':
        return 'چینی';
      case 'gram':
        return 'چنا';
      case 'garlic':
        return 'لہسن';
      case 'ginger':
        return 'ادرک';
      default:
        return '';
    }
  }

  static String normalizeHomeUnitKey(String unitRaw) {
    final unit = _normalizeDigitsToAscii(unitRaw.trim().toLowerCase());
    if (unit.isEmpty) return '';

    final compact = unit
        .replaceAll(RegExp(r'[\s\/_\-]+'), '')
        .replaceAll('rupees', '')
        .replaceAll('pkr/', '')
        .replaceAll('pkrper', '')
        .replaceAll('rs', '')
        .replaceAll('pkr', '');

    final hasKg =
        unit.contains('kg') || unit.contains('kilo') || unit.contains('کلو');
    final compactHasKg = compact.contains('kg');
    if ((hasKg || compactHasKg) && compact.contains('100')) return 'per_100kg';
    if ((hasKg || compactHasKg) && compact.contains('50')) return 'per_50kg';
    if ((hasKg || compactHasKg) && compact.contains('40')) return 'per_40kg';
    if (hasKg && unit.contains('100')) return 'per_100kg';
    if (hasKg && unit.contains('50')) return 'per_50kg';
    if (hasKg && unit.contains('40')) return 'per_40kg';
    if (unit.contains('maund') ||
        unit.contains('mond') ||
        unit.contains('mann')) {
      return 'per_40kg';
    }
    if (unit.contains('dozen') ||
        unit.contains('doz') ||
        unit.contains('درجن')) {
      return 'per_dozen';
    }
    if (unit.contains('tray') || unit.contains('ٹری')) return 'per_tray';
    if (unit.contains('crate') || unit.contains('کریٹ')) return 'per_crate';
    if (unit.contains('peti') ||
        unit.contains('پیٹی') ||
        unit.contains('پيٹی')) {
      return 'per_peti';
    }
    if (unit.contains('liter') ||
        unit.contains('litre') ||
        unit.contains('ltr') ||
        unit.contains('l ') ||
        unit.endsWith('l') ||
        unit.contains('لیٹر') ||
        unit.contains('لٹر')) {
      return 'per_litre';
    }
    if (hasKg) return 'per_kg';
    if (unit.contains('piece') ||
        unit.contains('عدد') ||
        unit == 'pc' ||
        unit == 'pcs') {
      return 'per_piece';
    }
    return '';
  }

  static String defaultUnitKeyForCommodity(String commodityKey) {
    switch (commodityKey) {
      case 'wheat':
      case 'gram':
      case 'potato':
      case 'onion':
      case 'tomato':
      case 'rice':
      case 'lentils':
        return 'per_40kg';
      case 'sugar':
        return 'per_50kg';
      case 'live_chicken':
      case 'chicken_meat':
      case 'beef':
      case 'mutton':
      case 'garlic':
      case 'ginger':
        return 'per_kg';
      case 'milk':
        return 'per_litre';
      case 'eggs':
        return 'per_dozen';
      default:
        return '';
    }
  }

  static bool _isSafeForDefault40Kg(String commodityKey) {
    switch (commodityKey) {
      case 'wheat':
      case 'rice':
      case 'lentils':
      case 'sugar':
      case 'gram':
      case 'potato':
      case 'tomato':
      case 'onion':
      case 'garlic':
      case 'ginger':
        return true;
      default:
        return false;
    }
  }

  static String resolveUnitKeyForCommodity({
    required String commodityKey,
    required String unitRaw,
  }) {
    final parsed = normalizeHomeUnitKey(unitRaw);
    if (parsed.isNotEmpty) {
      if (parsed == 'per_100kg' && _isSafeForDefault40Kg(commodityKey)) {
        return 'per_40kg';
      }
      return parsed;
    }
    return defaultUnitKeyForCommodity(commodityKey);
  }

  static String _normalizeDigitsToAscii(String input) {
    if (!_urduDigits.hasMatch(input)) {
      return input;
    }

    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x06F0 && rune <= 0x06F9) {
        buffer.writeCharCode(0x30 + (rune - 0x06F0));
        continue;
      }
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + (rune - 0x0660));
        continue;
      }
      buffer.writeCharCode(rune);
    }
    return buffer.toString();
  }

  static bool isAllowedUnitForCommodity(String commodityKey, String unitKey) {
    switch (commodityKey) {
      case 'eggs':
        return unitKey == 'per_dozen' || unitKey == 'per_tray';
      case 'live_chicken':
      case 'chicken_meat':
      case 'beef':
      case 'mutton':
        return unitKey == 'per_kg';
      case 'milk':
        return unitKey == 'per_litre';
      case 'lentils':
      case 'sugar':
      case 'gram':
      case 'potato':
      case 'onion':
      case 'tomato':
      case 'wheat':
      case 'rice':
      case 'garlic':
      case 'ginger':
        return unitKey == 'per_kg' ||
            unitKey == 'per_40kg' ||
            unitKey == 'per_50kg' ||
            unitKey == 'per_100kg';
      default:
        return false;
    }
  }

  static List<LiveMandiRate> filterRatesByUserCity({
    required List<LiveMandiRate> rates,
    required String userCity,
  }) {
    final city = normalizeCommodityText(userCity);
    if (city.isEmpty) return rates;

    return rates.where((rate) {
      final rateCity = normalizeCommodityText(rate.city);
      return rateCity == city;
    }).toList(growable: false);
  }

  /// Source trust is checked upstream during parsing.
  /// These helpers are used by non-Home surfaces for ranking.
  static int sourcePriorityFromRaw({
    required String sourceId,
    required String sourceType,
    required String source,
  }) {
    final raw = <String>[
      sourceId,
      sourceType,
      source,
    ].map((e) => e.trim().toLowerCase()).join('|');

    final isPunjab = raw.contains('punjab') || raw.contains('lahore');
    final isSindh = raw.contains('sindh') || raw.contains('karachi');
    final isOfficial =
        raw.contains('official') ||
        raw.contains('commissioner') ||
        raw.contains('market');

    if (raw.contains('fscpd') ||
        raw.contains('fs&cpd') ||
        (raw.contains('food') && isPunjab)) {
      return 1;
    }
    if (raw.contains('amis') && isPunjab) return 2;
    if (raw.contains('lahore') && isOfficial) return 3;
    if ((raw.contains('karachi') || isSindh) && isOfficial) return 4;
    if (raw.contains('pbs') || raw.contains('spi')) return 5;
    return 99;
  }

  static int sourcePriorityFromRate(LiveMandiRate rate) {
    return sourcePriorityFromRaw(
      sourceId: rate.sourceId,
      sourceType: rate.sourceType,
      source: rate.source,
    );
  }

  static bool isWheatRate(LiveMandiRate rate) {
    final canonicalCandidates = <String>[
      rate.commodityRefId,
      '${rate.metadata['canonicalId'] ?? ''}',
      '${rate.metadata['canonical_id'] ?? ''}',
      '${rate.metadata['canonicalCommodityId'] ?? ''}',
      '${rate.metadata['commodityCanonicalId'] ?? ''}',
    ];
    for (final value in canonicalCandidates) {
      if (value.trim().toUpperCase() == 'WHEAT_GENERIC') {
        return true;
      }
    }

    final mergedRaw =
        '${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}';
    return normalizeCommodityKey(mergedRaw) == 'wheat';
  }

  static bool isWheat40KgRate(LiveMandiRate rate) {
    if (!isWheatRate(rate)) return false;
    final unitKey = resolveUnitKeyForCommodity(
      commodityKey: 'wheat',
      unitRaw: rate.unit,
    );
    return unitKey == 'per_40kg';
  }

  static LiveMandiRate? pickBestWheatLeadCandidate(
    List<LiveMandiRate> rates, {
    bool requireTickerEligibility = false,
  }) {
    final wheat = rates
        .where(isWheatRate)
        .where((r) => !requireTickerEligibility || r.isTickerPriceEligible)
        .toList(growable: false);
    if (wheat.isEmpty) return null;

    final ranked = List<LiveMandiRate>.from(wheat)
      ..sort((a, b) {
        final a40 = isWheat40KgRate(a);
        final b40 = isWheat40KgRate(b);
        if (a40 != b40) return b40 ? 1 : -1;

        final aFresh =
            a.freshnessStatus == MandiFreshnessStatus.live ||
            a.freshnessStatus == MandiFreshnessStatus.recent;
        final bFresh =
            b.freshnessStatus == MandiFreshnessStatus.live ||
            b.freshnessStatus == MandiFreshnessStatus.recent;
        if (aFresh != bFresh) return bFresh ? 1 : -1;

        final confidenceCmp = b.confidenceScore.compareTo(a.confidenceScore);
        if (confidenceCmp != 0) return confidenceCmp;

        final sourceCmp = sourcePriorityFromRate(
          a,
        ).compareTo(sourcePriorityFromRate(b));
        if (sourceCmp != 0) return sourceCmp;

        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    return ranked.first;
  }

  static List<LiveMandiRate> forceWheatLeadInDisplayList(
    List<LiveMandiRate> items, {
    int? maxItems,
    bool requireTickerEligibility = false,
  }) {
    if (items.isEmpty) return const <LiveMandiRate>[];

    final lead = pickBestWheatLeadCandidate(
      items,
      requireTickerEligibility: requireTickerEligibility,
    );
    if (lead == null) {
      if (maxItems == null) return List<LiveMandiRate>.from(items);
      return List<LiveMandiRate>.from(items.take(maxItems));
    }

    final ordered = List<LiveMandiRate>.from(items);
    final existing = ordered.indexWhere((row) => row.id == lead.id);
    if (existing >= 0) {
      final moved = ordered.removeAt(existing);
      ordered.insert(0, moved);
    } else {
      if (maxItems != null && ordered.length >= maxItems) {
        final removable = ordered.lastIndexWhere((row) => !isWheatRate(row));
        if (removable >= 0) {
          ordered.removeAt(removable);
        } else {
          ordered.removeLast();
        }
      }
      ordered.insert(0, lead);
    }

    if (maxItems != null && ordered.length > maxItems) {
      return List<LiveMandiRate>.from(ordered.take(maxItems));
    }
    return ordered;
  }

  static String _cleanCityUrdu({
    required String city,
    required String district,
    required String province,
  }) {
    return enforceUrduOnlyText(
      getLocalizedPrimaryLocation(
        city: city,
        district: district,
        province: province,
        language: MandiDisplayLanguage.urdu,
      ),
      fallback: 'پاکستان',
    );
  }

  static String _resolveUnitDisplay({required String unitKey}) {
    switch (unitKey) {
      case 'per_40kg':
        return '40 کلو';
      case 'per_50kg':
        return '50 کلو';
      case 'per_100kg':
        return '100 کلو';
      case 'per_litre':
        return 'لیٹر';
      case 'per_dozen':
        return 'درجن';
      case 'per_tray':
        return 'ٹری';
      case 'per_crate':
        return 'کریٹ';
      case 'per_peti':
        return 'پیٹی';
      case 'per_piece':
        return 'عدد';
      case 'per_kg':
      default:
        return 'کلو';
    }
  }

  static HomeMandiDisplayRow buildDisplayRow({
    required String commodityRaw,
    String? urduName,
    String? commodityNameUr,
    required String city,
    required String district,
    required String province,
    required String unitRaw,
    required double price,
    required String sourceSelected,
    required double confidence,
    required MandiHomeRenderPath renderPath,
  }) {
    final commodityForDetection =
      '${urduName ?? ''} ${commodityNameUr ?? ''} $commodityRaw'.trim();
    final commodityKey = normalizeCommodityKey(commodityForDetection);
    final unitKey = resolveUnitKeyForCommodity(
      commodityKey: commodityKey,
      unitRaw: unitRaw,
    );
    debugPrint('[MandiHome] parsed_commodity_raw=$commodityRaw');
    debugPrint('[MandiHome] parsed_commodity_normalized=$commodityKey');
    debugPrint('[MandiHome] parsed_unit_raw=$unitRaw');
    debugPrint('[MandiHome] parsed_unit_normalized=$unitKey');
    if (commodityKey.isEmpty || !isAllowlistedCommodity(commodityKey)) {
      debugPrint(
        '[MandiHome] home_reject_reason=commodity_not_allowlisted commodity=$commodityRaw',
      );
      return _rejected('commodity_not_allowlisted', sourceSelected, confidence);
    }

    final String explicitUrdu =
      (urduName ?? commodityNameUr ?? '').trim();
    final commodityDisplay = explicitUrdu.isNotEmpty
      ? enforceUrduOnlyText(explicitUrdu, fallback: commodityDisplayUrdu(commodityKey))
      : commodityDisplayUrdu(commodityKey);
    if (commodityDisplay.isEmpty || commodityDisplay == 'اجناس') {
      debugPrint(
        '[MandiHome] home_reject_reason=ajnas_fallback commodity=$commodityRaw',
      );
      return _rejected('ajnas_fallback', sourceSelected, confidence);
    }

    debugPrint(
      '[MandiHome] commodity_unit_validation=commodity=$commodityKey '
      'unitKey=$unitKey allowed=${isAllowedUnitForCommodity(commodityKey, unitKey)}',
    );
    if (unitKey.isEmpty || !isAllowedUnitForCommodity(commodityKey, unitKey)) {
      debugPrint(
        '[MandiHome] home_reject_reason=commodity_unit_mismatch commodity=$commodityKey unit=$unitRaw',
      );
      return _rejected('commodity_unit_mismatch', sourceSelected, confidence);
    }

    final cityDisplay = _cleanCityUrdu(
      city: city,
      district: district,
      province: province,
    );

    final unitDisplay = _resolveUnitDisplay(unitKey: unitKey);

    // -----------------------------------------------------------------------
    // 40 kg price conversion (display layer ONLY — raw data is never mutated).
    //
    // resolveUnitKeyForCommodity() silently maps per_100kg → per_40kg for
    // "safe" commodities (wheat, potato, etc.).  Without this block the UI
    // would show the 100 kg source price alongside a "40 کلو" label, which
    // is a data-integrity failure.
    //
    // Math proof:
    //   rawPrice = 6250 Rs / 100 kg
    //   displayPrice = (6250 / 100) * 40 = 2500 Rs / 40 kg   ✓
    // -----------------------------------------------------------------------
    final String _rawParsedUnitKey = normalizeHomeUnitKey(unitRaw);
    final double _effectivePrice;
    if (commodityKey == 'sugar') {
      if (_rawParsedUnitKey == 'per_100kg') {
        _effectivePrice = (price / 100.0) * 50.0;
      } else if (_rawParsedUnitKey == 'per_kg') {
        _effectivePrice = price * 50.0;
      } else {
        _effectivePrice = price;
      }
      debugPrint(
        '[MandiHome] sugar_conversion '
        'rawUnit=$_rawParsedUnitKey rawPrice=${price.toStringAsFixed(0)} '
        'displayPrice=${_effectivePrice.toStringAsFixed(0)}',
      );
    } else if (_rawParsedUnitKey == 'per_100kg' && unitKey == 'per_40kg') {
      _effectivePrice = (price / 100.0) * 40.0;
      debugPrint(
        '[MandiHome] 100kg→40kg_conversion '
        'rawPrice=${price.toStringAsFixed(0)} '
        'displayPrice=${_effectivePrice.toStringAsFixed(0)} '
        'commodity=$commodityKey',
      );
    } else {
      _effectivePrice = price;
    }

    final normalizedPrice =
        _effectivePrice.isFinite && _effectivePrice > 0 ? _effectivePrice : 0.0;
    final priceDisplay = '${normalizedPrice.toStringAsFixed(0)} روپے';

    final full =
        '$commodityDisplay • $cityDisplay • $priceDisplay / $unitDisplay';
    if (hasMixedLatinInUrdu(full)) {
      debugPrint(
        '[MandiHome] home_reject_reason=mixed_language_blocked line=$full',
      );
      return _rejected('mixed_language_blocked', sourceSelected, confidence);
    }

    debugPrint('[MandiHome] home_allowlist_hit=$commodityKey');
    debugPrint('[MandiHome] pipeline_used=true render_path=${renderPath.name}');

    return HomeMandiDisplayRow(
      commodityDisplay: commodityDisplay,
      cityDisplay: cityDisplay,
      priceDisplay: priceDisplay,
      unitDisplay: unitDisplay,
      fullTickerLine: full,
      fullSnapshotLine: full,
      sourceSelected: sourceSelected,
      confidence: confidence,
      isFallback: false,
      rejectReason: null,
      isRenderable: true,
    );
  }

  static HomeMandiDisplayRow _rejected(
    String reason,
    String sourceSelected,
    double confidence,
  ) {
    return HomeMandiDisplayRow(
      commodityDisplay: '',
      cityDisplay: '',
      priceDisplay: '',
      unitDisplay: '',
      fullTickerLine: '',
      fullSnapshotLine: '',
      sourceSelected: sourceSelected,
      confidence: confidence,
      isFallback: false,
      rejectReason: reason,
      isRenderable: false,
    );
  }
}
