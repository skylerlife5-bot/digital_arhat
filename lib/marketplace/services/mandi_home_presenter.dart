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

  static const Set<String> _blockedCommodityFragments = <String>{
    'ajnas',
    'اجناس',
    'ganna',
    'گنا',
    'cotton',
    'کپاس',
    'haldi',
    'ہلدی',
    'shimla',
    'شملہ',
    'shimla mirch',
    'شملہ مرچ',
    'fodder',
    'chara',
    'charah',
    'چارہ',
    'bhusa',
    'بھوسہ',
    'silage',
    'animal feed',
    'feed',
  };

  static const Set<String> homeCommodityAllowlist = <String>{
    'wheat',
    'rice',
    'maize',
    'barley',
    'canola',
    'sugar',
    'flour',
    'milk',
    'eggs',
    'cooking_oil',
    'live_chicken',
    'chicken_meat',
    'beef',
    'mutton',
    'potato',
    'onion',
    'tomato',
    'garlic',
    'ginger',
    'peas',
    'cauliflower',
    'cabbage',
    'bitter_gourd',
    'cucumber',
    'banana',
    'apple',
    'orange',
    'guava',
    'daal_chana',
    'daal_moong',
    'daal_mash',
    'white_chana',
    'yogurt',
    'ghee',
  };

  /// Priority tiers for Home commodity ranking.
  /// Lower number = higher priority. Used by diversity layer.
  static const Map<String, int> commodityPriority = <String, int>{
    'wheat': 1,
    'rice': 2,
    'maize': 3,
    'barley': 4,
    'canola': 5,
    'sugar': 3,
    'flour': 6,
    'milk': 7,
    'eggs': 8,
    'cooking_oil': 9,
    'live_chicken': 10,
    'chicken_meat': 11,
    'beef': 12,
    'mutton': 13,
    'potato': 14,
    'onion': 15,
    'tomato': 16,
    'garlic': 17,
    'ginger': 18,
    'peas': 19,
    'cauliflower': 20,
    'cabbage': 21,
    'bitter_gourd': 22,
    'cucumber': 23,
    'banana': 24,
    'apple': 25,
    'orange': 26,
    'guava': 27,
    'daal_chana': 28,
    'daal_moong': 29,
    'daal_mash': 30,
    'white_chana': 31,
    'yogurt': 32,
    'ghee': 33,
  };

  /// Soft cap: max rows per commodity in ticker candidate pool.
  static const int tickerCommodityCap = 2;

  /// Soft cap: max rows per commodity in snapshot visible list.
  static const int snapshotCommodityCap = 1;

  static const Map<String, List<String>> _commoditySynonyms =
      <String, List<String>>{
        'live_chicken': <String>[
          'live chicken',
          'chicken live',
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
        'flour': <String>['flour', 'atta', 'wheat flour', 'آٹا'],
        'milk': <String>['milk', 'doodh', 'دودھ', 'cow milk', 'buffalo milk'],
        'rice': <String>['rice', 'chawal', 'دھان', 'چاول', 'paddy'],
        'maize': <String>['maize', 'corn', 'makai', 'مکئی'],
        'barley': <String>['barley', 'jau', 'جو'],
        'canola': <String>['canola', 'canola seed', 'کنولہ', 'کینولا'],
        'potato': <String>['potato', 'aloo', 'aalu', 'alu', 'آلو'],
        'onion': <String>['onion', 'pyaz', 'piaz', 'پیاز'],
        'tomato': <String>['tomato', 'tamatar', 'tomatar', 'ٹماٹر'],
        'eggs': <String>['egg', 'eggs', 'anda', 'anday', 'انڈا', 'انڈے'],
        'sugar': <String>['sugar', 'chini', 'cheeni', 'چینی'],
        'cooking_oil': <String>[
          'cooking oil',
          'edible oil',
          'vegetable oil',
          'canola oil',
          'sunflower oil',
          'soybean oil',
          'ککنگ آئل',
          'کوکنگ آئل',
          'آئل',
        ],
        'garlic': <String>['garlic', 'lehsan', 'lahsun', 'لہسن'],
        'ginger': <String>['ginger', 'adrak', 'ادرک'],
        'peas': <String>['peas', 'pea', 'matar', 'مٹر'],
        'cauliflower': <String>['cauliflower', 'phool gobhi', 'پھول گوبھی'],
        'cabbage': <String>['cabbage', 'band gobhi', 'بند گوبھی'],
        'bitter_gourd': <String>['bitter gourd', 'karela', 'کریلا'],
        'cucumber': <String>['cucumber', 'kheera', 'خیرا', 'کھیرا'],
        'banana': <String>['banana', 'kela', 'kaila', 'کیلا'],
        'apple': <String>['apple', 'seb', 'سیب'],
        'orange': <String>['orange', 'malta', 'santara', 'مالٹا', 'سنگترہ'],
        'guava': <String>['guava', 'amrood', 'امرود'],
        'daal_chana': <String>[
          'chana dal',
          'dal chana',
          'daal chana',
          'چنے کی دال',
          'چنا دال',
        ],
        'daal_moong': <String>[
          'moong dal',
          'dal moong',
          'daal moong',
          'مونگ دال',
          'دال مونگ',
          'moong',
        ],
        'daal_mash': <String>[
          'mash dal',
          'dal mash',
          'daal mash',
          'ماش دال',
          'دال ماش',
          'mash',
        ],
        'white_chana': <String>[
          'white chana',
          'safed chana',
          'kabuli chana',
          'gram',
          'chickpea',
          'chana',
          'سفید چنا',
          'کابلی چنا',
          'چنا',
        ],
        'yogurt': <String>['yogurt', 'yoghurt', 'curd', 'dahi', 'دہی'],
        'ghee': <String>['ghee', 'desi ghee', 'گھی', 'دیسی گھی'],
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
    for (final blocked in _blockedCommodityFragments) {
      final normalizedBlocked = normalizeCommodityText(blocked);
      if (normalizedBlocked.isEmpty) continue;
      if (candidate == normalizedBlocked || candidate.contains(normalizedBlocked)) {
        return '';
      }
    }

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
      case 'flour':
        return 'آٹا';
      case 'milk':
        return 'دودھ';
      case 'cooking_oil':
        return 'ککنگ آئل';
      case 'rice':
        return 'چاول';
      case 'maize':
        return 'Makai';
      case 'barley':
        return 'Jau';
      case 'canola':
        return 'Canola';
      case 'potato':
        return 'آلو';
      case 'onion':
        return 'پیاز';
      case 'tomato':
        return 'ٹماٹر';
      case 'eggs':
        return 'انڈے';
      case 'sugar':
        return 'Cheeni';
      case 'garlic':
        return 'لہسن';
      case 'ginger':
        return 'ادرک';
      case 'peas':
        return 'مٹر';
      case 'cauliflower':
        return 'پھول گوبھی';
      case 'cabbage':
        return 'بند گوبھی';
      case 'bitter_gourd':
        return 'کریلا';
      case 'cucumber':
        return 'کھیرا';
      case 'banana':
        return 'کیلا';
      case 'apple':
        return 'سیب';
      case 'orange':
        return 'سنگترہ';
      case 'guava':
        return 'امرود';
      case 'daal_chana':
        return 'چنے کی دال';
      case 'daal_moong':
        return 'دال مونگ';
      case 'daal_mash':
        return 'دال ماش';
      case 'white_chana':
        return 'سفید چنا';
      case 'yogurt':
        return 'دہی';
      case 'ghee':
        return 'گھی';
      default:
        return '';
    }
  }

  static String normalizeHomeUnitKey(String unitRaw) {
    final unit = _normalizeDigitsToAscii(unitRaw.trim().toLowerCase());
    if (unit.isEmpty) return '';

    final rawUnit = unit.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (rawUnit == 'per 40 kg' ||
        rawUnit == 'per 40kg' ||
        rawUnit == 'rs/40kg' ||
        rawUnit == 'pkr/40kg' ||
        rawUnit == '/40 kg') {
      return 'per_40kg';
    }
    if (rawUnit == 'per 100 kg' ||
        rawUnit == 'per 100kg' ||
        rawUnit == 'rs/100kg' ||
        rawUnit == '/100 kg') {
      return 'per_100kg';
    }
    if (rawUnit == 'per kg' ||
        rawUnit == 'pkr/kg' ||
        rawUnit == '/kg') {
      return 'per_kg';
    }

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
    final hasLitre =
      unit.contains('liter') ||
      unit.contains('litre') ||
      unit.contains('ltr') ||
      unit.contains('لیٹر') ||
      unit.contains('لٹر') ||
      compact.contains('l');
    if ((hasKg || compactHasKg) && compact.contains('20')) return 'per_20kg';
    if (hasLitre && compact.contains('5')) return 'per_5litre';
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
      case 'daal_chana':
      case 'daal_moong':
      case 'daal_mash':
      case 'maize':
      case 'barley':
      case 'canola':
      case 'maize':
      case 'barley':
      case 'canola':
      case 'white_chana':
      case 'potato':
      case 'onion':
      case 'tomato':
      case 'rice':
        return 'per_40kg';
      case 'sugar':
        return 'per_50kg';
      case 'flour':
        return 'per_20kg';
      case 'cooking_oil':
        return 'per_5litre';
      case 'live_chicken':
      case 'chicken_meat':
      case 'beef':
      case 'mutton':
      case 'garlic':
      case 'ginger':
      case 'peas':
      case 'cauliflower':
      case 'cabbage':
      case 'bitter_gourd':
      case 'cucumber':
      case 'apple':
      case 'orange':
      case 'guava':
      case 'ghee':
      case 'yogurt':
        return 'per_kg';
      case 'milk':
        return 'per_litre';
      case 'eggs':
        return 'per_dozen';
      case 'banana':
        return 'per_dozen';
      default:
        return '';
    }
  }

  static String resolveUnitKeyForCommodity({
    required String commodityKey,
    required String unitRaw,
  }) {
    final parsed = normalizeHomeUnitKey(unitRaw);
    if (parsed.isNotEmpty) {
      if (parsed == 'per_100kg') {
        if (commodityKey == 'sugar') {
          return 'per_50kg';
        }
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
      case 'banana':
        return unitKey == 'per_dozen' ||
            unitKey == 'per_crate' ||
            unitKey == 'per_peti';
      case 'live_chicken':
      case 'chicken_meat':
      case 'beef':
      case 'mutton':
        return unitKey == 'per_kg';
      case 'milk':
        return unitKey == 'per_litre';
      case 'cooking_oil':
        return unitKey == 'per_5litre' || unitKey == 'per_litre';
      case 'flour':
        return unitKey == 'per_20kg' ||
            unitKey == 'per_kg' ||
            unitKey == 'per_40kg';
      case 'daal_chana':
      case 'daal_moong':
      case 'daal_mash':
      case 'sugar':
      case 'white_chana':
      case 'potato':
      case 'onion':
      case 'tomato':
      case 'wheat':
      case 'rice':
      case 'garlic':
      case 'ginger':
      case 'peas':
      case 'cauliflower':
      case 'cabbage':
      case 'bitter_gourd':
      case 'cucumber':
      case 'apple':
      case 'orange':
      case 'guava':
      case 'ghee':
      case 'yogurt':
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
    if (raw.contains('officialmarketadministration')) return 2;
    if (raw.contains('local') && raw.contains('amis')) return 2;
    if (raw.contains('amis')) return 2;
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
    String sanitizeCityToken(String input) {
      final cleaned = _normalizeDigitsToAscii(input)
          .replaceAll(RegExp(r'^\s*\d+\s*[-.):]?\s*'), '')
          .trim();
      if (cleaned.isEmpty) return '';
      if (RegExp(r'^\d+$').hasMatch(cleaned)) return '';

      // Never leak source identifiers as city labels.
      final lower = cleaned.toLowerCase();
      if (lower.contains('|')) return '';
      if (lower.contains('sourceid') ||
          lower.contains('official') ||
          lower.contains('adapter') ||
          lower.contains('ingest')) {
        return '';
      }
      return cleaned;
    }

    final safeCity = sanitizeCityToken(city);
    final safeDistrict = sanitizeCityToken(district);
    final safeProvince = sanitizeCityToken(province);

    return enforceUrduOnlyText(
      getLocalizedPrimaryLocation(
        city: safeCity,
        district: safeDistrict,
        province: safeProvince,
        language: MandiDisplayLanguage.urdu,
      ),
      fallback: 'پاکستان',
    );
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

    final cityDisplay = _cleanCityUrdu(
      city: city,
      district: district,
      province: province,
    );

    final normalizedPrice = price.isFinite && price > 0 ? price : 0.0;
    final unitDisplay = unitRaw.trim();
    final priceDisplay = 'Rs. ${normalizedPrice.toStringAsFixed(0)}';

    debugPrint(
      '[MandiHome] raw_price_format '
      'commodity=$commodityKey '
      'rawPrice=${normalizedPrice.toStringAsFixed(0)} '
      'unit=$unitDisplay',
    );

    final full = unitDisplay.isEmpty
        ? '$commodityDisplay • $cityDisplay • $priceDisplay'
        : '$commodityDisplay • $cityDisplay • $priceDisplay • $unitDisplay';
    final validationText = '$commodityDisplay • $cityDisplay';
    if (hasMixedLatinInUrdu(validationText)) {
      debugPrint(
        '[MandiHome] home_reject_reason=mixed_language_blocked line=$validationText',
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
