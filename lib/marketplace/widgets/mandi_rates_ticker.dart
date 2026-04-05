import 'dart:async';

import 'package:flutter/material.dart';

import '../models/live_mandi_rate.dart';
import '../services/mandi_home_presenter.dart';
import '../utils/mandi_display_utils.dart';

// ---------------------------------------------------------------------------
// Pulse messages shown when no high-confidence price rows are available.
// Rotate every [_pulseIntervalSec] seconds.
// ---------------------------------------------------------------------------
const List<String> _pulseMessages = <String>[
  'مارکیٹ پلس کے ریٹس اپ ڈیٹ ہو رہے ہیں',
  'تازہ سرکاری ریٹ کی تصدیق جاری ہے',
  'آج کے منڈی ریٹس جلد دستیاب ہوں گے',
  'صاف اور تصدیق شدہ نرخ تیار کیے جا رہے ہیں',
];

/// A ticker item for the home screen.
///
/// Two kinds of items are rendered:
/// 1. **Price row** — only when [rate.isTickerPriceEligible] is true:
///    `گندم • گوجرانوالہ • Rs. 3800 • per_100kg`
/// 2. **Pulse message** — when confidence is too low to show a numeric price:
///    `مارکیٹ پلس: پاکستان کے سرکاری نرخ جاری ہیں`
sealed class _TickerItem {
  const _TickerItem();
}

final class _PriceTickerItem extends _TickerItem {
  const _PriceTickerItem({
    required this.rate,
    required this.displayLine,
    required this.displayPriority,
  });
  final LiveMandiRate rate;
  final String displayLine;
  final int displayPriority;
}

final class _PulseTickerItem extends _TickerItem {
  const _PulseTickerItem({required this.message});
  final String message;
}

final class _TickerDisplayCandidate {
  const _TickerDisplayCandidate({
    required this.rate,
    required this.displayLine,
    required this.displayPriority,
    required this.dedupeKey,
    required this.row,
    required this.hasNativeUrduCommodity,
  });

  final LiveMandiRate rate;
  final HomeMandiDisplayRow row;
  final String displayLine;
  final int displayPriority;
  final String dedupeKey;
  final bool hasNativeUrduCommodity;
}

// ---------------------------------------------------------------------------
// Frozen ticker presentation rules (display layer only).
// These mappings and priorities are deterministic and intentionally local.
// ---------------------------------------------------------------------------

const Map<String, String> _tickerUrduCommodityByNormalizedKey =
    <String, String>{
      'live_chicken': 'زندہ مرغی',
      'chicken_meat': 'مرغی کا گوشت',
      'beef': 'بڑا گوشت',
      'mutton': 'چھوٹا گوشت',
      'wheat': 'گندم',
      'milk': 'دودھ',
      'cow_milk': 'دودھ',
      'buffalo_milk': 'دودھ',
      'egg': 'انڈے',
      'eggs': 'انڈے',
      'potato': 'آلو',
      'tomato': 'ٹماٹر',
      'onion': 'پیاز',
      'rice': 'چاول',
      'lentils': 'دالیں',
      'lentil': 'دالیں',
      'daal': 'دالیں',
      'dal': 'دالیں',
      'sugar': 'چینی',
      'gram': 'چنا',
      'garlic': 'لہسن',
      'ginger': 'ادرک',
    };

const Map<String, String> _tickerUrduCommodityByEnglishToken = <String, String>{
  'live chicken': 'زندہ مرغی',
  'chicken meat': 'مرغی کا گوشت',
  'beef': 'بڑا گوشت',
  'mutton': 'چھوٹا گوشت',
  'wheat': 'گندم',
  'milk': 'دودھ',
  'cow milk': 'دودھ',
  'buffalo milk': 'دودھ',
  'eggs': 'انڈے',
  'egg': 'انڈے',
  'potato': 'آلو',
  'tomato': 'ٹماٹر',
  'onion': 'پیاز',
  'rice': 'چاول',
  'lentils': 'دالیں',
  'lentil': 'دالیں',
  'daal': 'دالیں',
  'dal': 'دالیں',
  'sugar': 'چینی',
  'gram': 'چنا',
  'chana': 'چنا',
  'garlic': 'لہسن',
  'ginger': 'ادرک',
};

const Map<String, String> _tickerForcedEnglishCommodityReplacement =
    <String, String>{
      'live chicken': 'زندہ مرغی',
      'chicken meat': 'مرغی کا گوشت',
      'beef': 'بڑا گوشت',
      'mutton': 'چھوٹا گوشت',
      'potato': 'آلو',
      'tomato': 'ٹماٹر',
      'wheat': 'گندم',
      'milk': 'دودھ',
      'eggs': 'انڈے',
      'egg': 'انڈے',
      'onion': 'پیاز',
      'rice': 'چاول',
      'lentils': 'دالیں',
      'lentil': 'دالیں',
      'daal': 'دالیں',
      'dal': 'دالیں',
      'sugar': 'چینی',
      'gram': 'چنا',
      'chana': 'چنا',
      'garlic': 'لہسن',
      'ginger': 'ادرک',
    };

String _extractUrduCommodityOnly(String raw) {
  final String input = raw.trim();
  if (input.isEmpty) return '';

  final Iterable<Match> matches = RegExp(
    r'[\u0600-\u06FF]+(?:\s+[\u0600-\u06FF]+)*',
  ).allMatches(input);
  if (matches.isEmpty) return '';

  String best = '';
  for (final Match m in matches) {
    final String candidate = (m.group(0) ?? '').trim();
    if (candidate.length > best.length) {
      best = candidate;
    }
  }
  return best;
}

String _forceReplaceEnglishCommoditySegments(String text) {
  String output = text;
  for (final entry in _tickerForcedEnglishCommodityReplacement.entries) {
    output = output.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
      entry.value,
    );
  }
  return output;
}

String normalizeLocalCommodityLabelForTicker({
  required LiveMandiRate rate,
  required HomeMandiDisplayRow row,
}) {
  final String normalizedKey = MandiHomePresenter.normalizeCommodityKey(
    '${rate.commodityNameUr} ${rate.commodityName} ${row.commodityDisplay}',
  );
  final String? mappedByKey =
      _tickerUrduCommodityByNormalizedKey[normalizedKey];
  if (mappedByKey != null && mappedByKey.isNotEmpty) {
    return mappedByKey;
  }

  final String combinedLower =
      '${rate.commodityNameUr} ${rate.commodityName} ${row.commodityDisplay}'
          .toLowerCase();
  for (final entry in _tickerUrduCommodityByEnglishToken.entries) {
    if (combinedLower.contains(entry.key)) {
      return entry.value;
    }
  }

  final String rowCommodity = row.commodityDisplay.trim();
  if (rowCommodity.isNotEmpty) {
    final String urduOnly = _extractUrduCommodityOnly(rowCommodity);
    if (urduOnly.isNotEmpty) {
      return urduOnly;
    }
  }

  final String urduCandidate = rate.commodityNameUr.trim();
  if (urduCandidate.isNotEmpty) {
    final String urduOnly = _extractUrduCommodityOnly(urduCandidate);
    if (urduOnly.isNotEmpty) {
      return urduOnly;
    }
  }

  final String forcedFromEnglish = _forceReplaceEnglishCommoditySegments(
    rate.commodityName.trim(),
  );
  final String forcedUrduOnly = _extractUrduCommodityOnly(forcedFromEnglish);
  if (forcedUrduOnly.isNotEmpty) {
    return forcedUrduOnly;
  }

  // Urdu-only hard lock for ticker commodity display.
  return 'اجناس';
}

bool _isWheat40kgForTicker(LiveMandiRate rate, HomeMandiDisplayRow row) {
  final String normalizedKey = MandiHomePresenter.normalizeCommodityKey(
    '${rate.commodityNameUr} ${rate.commodityName} ${row.commodityDisplay}',
  );
  if (normalizedKey != 'wheat') {
    return false;
  }

  final String context = '${rate.unit} ${row.unitDisplay} ${row.fullTickerLine}'
      .toLowerCase();
  final bool has40 = context.contains('40');
  final bool hasKiloContext =
      context.contains('kg') ||
      context.contains('kilo') ||
      row.fullTickerLine.contains('کلو');
  return has40 && hasKiloContext;
}

int getTickerDisplayPriority({
  required LiveMandiRate rate,
  required HomeMandiDisplayRow row,
  required String commodityUrdu,
}) {
  if (_isWheat40kgForTicker(rate, row)) return 0;
  if (commodityUrdu == 'گندم') return 1;
  if (commodityUrdu == 'زندہ مرغی') return 2;
  if (commodityUrdu == 'مرغی کا گوشت') return 3;
  if (commodityUrdu == 'بڑا گوشت') return 4;
  if (commodityUrdu == 'چھوٹا گوشت') return 5;
  if (commodityUrdu == 'دودھ') return 6;
  if (commodityUrdu == 'چاول') return 7;
  if (commodityUrdu == 'دالیں') return 8;
  if (commodityUrdu == 'چینی') return 9;
  if (commodityUrdu == 'چنا') return 10;
  if (commodityUrdu == 'انڈے') return 11;
  if (commodityUrdu == 'آلو') return 12;
  if (commodityUrdu == 'پیاز') return 13;
  if (commodityUrdu == 'ٹماٹر') return 14;
  if (commodityUrdu == 'لہسن') return 15;
  if (commodityUrdu == 'ادرک') return 16;
  return 99;
}

String buildTickerDisplayKeyForDedupe({
  required String commodityUrdu,
  required HomeMandiDisplayRow row,
  required LiveMandiRate rate,
}) {
  final String locality = row.cityDisplay.trim().isNotEmpty
      ? row.cityDisplay.trim().toLowerCase()
      : getLocalizedPrimaryLocation(
          city: rate.city,
          district: rate.district,
          province: rate.province,
          language: MandiDisplayLanguage.urdu,
        ).trim().toLowerCase();

  return '${commodityUrdu.trim().toLowerCase()}|$locality';
}

_TickerDisplayCandidate _pickBetterTickerCandidate(
  _TickerDisplayCandidate current,
  _TickerDisplayCandidate incoming,
) {
  if (incoming.displayPriority != current.displayPriority) {
    return incoming.displayPriority < current.displayPriority
        ? incoming
        : current;
  }

  if (incoming.hasNativeUrduCommodity != current.hasNativeUrduCommodity) {
    return incoming.hasNativeUrduCommodity ? incoming : current;
  }

  final bool incomingHasSpecificCity =
      incoming.row.cityDisplay.trim().isNotEmpty &&
      incoming.row.cityDisplay.trim() != 'پاکستان';
  final bool currentHasSpecificCity =
      current.row.cityDisplay.trim().isNotEmpty &&
      current.row.cityDisplay.trim() != 'پاکستان';
  if (incomingHasSpecificCity != currentHasSpecificCity) {
    return incomingHasSpecificCity ? incoming : current;
  }

  final int incomingSourceRank = _sourcePriorityRank(incoming.rate);
  final int currentSourceRank = _sourcePriorityRank(current.rate);
  if (incomingSourceRank != currentSourceRank) {
    return incomingSourceRank < currentSourceRank ? incoming : current;
  }

  if (incoming.rate.lastUpdated.isAfter(current.rate.lastUpdated)) {
    return incoming;
  }

  return incoming.displayLine.length < current.displayLine.length
      ? incoming
      : current;
}

String _cityFallbackMessage(LiveMandiRate rate) {
  final city = getLocalizedPrimaryLocation(
    city: rate.city,
    district: rate.district,
    province: rate.province,
    language: MandiDisplayLanguage.urdu,
  );
  if (city == 'پاکستان') return 'تازہ سرکاری ریٹ کی تصدیق جاری ہے';
  return '$city کے ریٹس اپڈیٹ ہو رہے ہیں';
}

String _normalizeTickerCityLabel(String cityDisplay) {
  final city = cityDisplay.trim();
  if (city.isEmpty || city == 'پاکستان') return 'پاکستان';
  if (city.contains('منڈی')) return city;
  return 'منڈی، $city';
}

bool _isWheatTickerLine(_TickerDisplayCandidate item) {
  return MandiHomePresenter.isWheatRate(item.rate) ||
      item.displayLine.trimLeft().startsWith('گندم');
}

int _wheatLeadScore(_TickerDisplayCandidate item) {
  var score = 0;
  if (MandiHomePresenter.isWheat40KgRate(item.rate)) score += 100;
  final isFresh =
      item.rate.freshnessStatus == MandiFreshnessStatus.live ||
      item.rate.freshnessStatus == MandiFreshnessStatus.recent;
  if (isFresh) score += 30;
  if (item.rate.isTickerPriceEligible) score += 20;
  score += item.rate.confidenceScore.round();
  return score;
}

_TickerDisplayCandidate? _bestWheatTickerCandidate(
  List<_TickerDisplayCandidate> items,
) {
  final wheat = items.where(_isWheatTickerLine).toList(growable: false);
  if (wheat.isEmpty) return null;

  final ranked = List<_TickerDisplayCandidate>.from(wheat)
    ..sort((a, b) {
      final scoreCmp = _wheatLeadScore(b).compareTo(_wheatLeadScore(a));
      if (scoreCmp != 0) return scoreCmp;
      final sourceCmp = _sourcePriorityRank(
        a.rate,
      ).compareTo(_sourcePriorityRank(b.rate));
      if (sourceCmp != 0) return sourceCmp;
      return b.rate.lastUpdated.compareTo(a.rate.lastUpdated);
    });
  return ranked.first;
}

// ---------------------------------------------------------------------------
// Build the ordered list of ticker items.
// High-confidence price rows are interleaved with pulse messages, so the
// ticker always has content even during update windows.
// ---------------------------------------------------------------------------
List<_TickerItem> _buildTickerItems(List<LiveMandiRate> rates) {
  final resolvedRates = _resolveBySourcePriority(
    rates,
  ).where(_isCleanTickerRow).toList(growable: false);
  final hasRenderableWheat = resolvedRates.any(_isWheatCommodity);
  final lowConfidenceItems = resolvedRates
      .where((r) => !r.isTickerPriceEligible)
      .map<_TickerItem>(
        (r) => _PulseTickerItem(message: _cityFallbackMessage(r)),
      )
      .toList(growable: false);
  final Map<String, _TickerDisplayCandidate> deduped =
      <String, _TickerDisplayCandidate>{};

  for (final rate in resolvedRates.where((r) => r.isTickerPriceEligible)) {
    final commodityKey = MandiHomePresenter.normalizeCommodityKey(
      '${rate.metadata['urduName'] ?? ''} ${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}',
    );
    if (!MandiHomePresenter.isAllowlistedCommodity(commodityKey)) {
      continue;
    }
    final HomeMandiDisplayRow row = MandiHomePresenter.buildDisplayRow(
      commodityRaw: rate.commodityName,
      urduName: '${rate.metadata['urduName'] ?? ''}'.trim().isNotEmpty
          ? '${rate.metadata['urduName']}'.trim()
          : null,
      commodityNameUr: rate.commodityNameUr.trim().isNotEmpty
          ? rate.commodityNameUr
          : null,
      city: rate.city,
      district: rate.district,
      province: rate.province,
      unitRaw: rate.unit,
      price: rate.price,
      sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
      confidence: rate.confidenceScore,
      renderPath: MandiHomeRenderPath.ticker,
    );
    if (!row.isRenderable) {
      continue;
    }

    final String commodityUrdu = normalizeLocalCommodityLabelForTicker(
      rate: rate,
      row: row,
    );
    final int priority = getTickerDisplayPriority(
      rate: rate,
      row: row,
      commodityUrdu: commodityUrdu,
    );
    final String normalizedCity = _normalizeTickerCityLabel(row.cityDisplay);
    final bool isWheat =
        MandiHomePresenter.isWheatRate(rate) || commodityUrdu == 'گندم';
    final String forcedCommodity = isWheat ? 'گندم' : commodityUrdu;
    final String forcedCity = normalizedCity == 'پاکستان'
        ? 'منڈی، پاکستان'
        : normalizedCity;
    final String line = _forceReplaceEnglishCommoditySegments(
      '$forcedCommodity • $forcedCity • ${row.priceDisplay}',
    );
    final String dedupeKey = buildTickerDisplayKeyForDedupe(
      commodityUrdu: commodityUrdu,
      row: row,
      rate: rate,
    );

    final _TickerDisplayCandidate incoming = _TickerDisplayCandidate(
      rate: rate,
      row: row,
      displayLine: line,
      displayPriority: priority,
      dedupeKey: dedupeKey,
      hasNativeUrduCommodity: rate.commodityNameUr.trim().isNotEmpty,
    );

    final _TickerDisplayCandidate? existing = deduped[dedupeKey];
    if (existing == null) {
      deduped[dedupeKey] = incoming;
    } else {
      deduped[dedupeKey] = _pickBetterTickerCandidate(existing, incoming);
    }
  }

  final List<_TickerDisplayCandidate> curated =
      deduped.values.toList(growable: true)..sort((a, b) {
        if (a.displayPriority != b.displayPriority) {
          return a.displayPriority.compareTo(b.displayPriority);
        }
        final int sourceOrder = _sourcePriorityRank(
          a.rate,
        ).compareTo(_sourcePriorityRank(b.rate));
        if (sourceOrder != 0) {
          return sourceOrder;
        }
        return b.rate.lastUpdated.compareTo(a.rate.lastUpdated);
      });

  final wheatIndex = curated.indexWhere((item) => _isWheatCommodity(item.rate));
  if (wheatIndex > 0) {
    final wheat = curated.removeAt(wheatIndex);
    curated.insert(0, wheat);
  }

  // Final guard before widget mapping: lead item must be wheat if present.
  final leadWheat = _bestWheatTickerCandidate(curated);
  if (leadWheat != null) {
    final existing = curated.indexWhere(
      (item) => item.rate.id == leadWheat.rate.id,
    );
    if (existing > 0) {
      debugPrint(
        '[MandiPulse] Wheat found at index: $existing -> Moving to index 0.',
      );
      final moved = curated.removeAt(existing);
      curated.insert(0, moved);
    }
  }

  final List<_TickerItem> priceItems = curated
      .map<_TickerItem>(
        (c) => _PriceTickerItem(
          rate: c.rate,
          displayLine: c.displayLine,
          displayPriority: c.displayPriority,
        ),
      )
      .toList(growable: false);

  if (priceItems.isEmpty) {
    debugPrint(
      '[MandiPulse] fallback_used=true reason=no_high_confidence_rows',
    );
    debugPrint(
      '[MandiProof] fallback_replaced_real_row=$hasRenderableWheat surface=home_ticker',
    );
    final fallback = lowConfidenceItems.isNotEmpty
        ? lowConfidenceItems
        : _pulseMessages
              .map<_TickerItem>((m) => _PulseTickerItem(message: m))
              .toList(growable: false);
    return fallback;
  }

  // Interleave: one pulse message every 4 price items, so the ticker always
  // looks alive even when data is sparse.
  final result = <_TickerItem>[];
  var fallbackIndex = 0;
  for (var i = 0; i < priceItems.length; i++) {
    result.add(priceItems[i]);
    if ((i + 1) % 4 == 0) {
      if (lowConfidenceItems.isNotEmpty) {
        result.add(
          lowConfidenceItems[fallbackIndex % lowConfidenceItems.length],
        );
        fallbackIndex += 1;
      } else {
        result.add(
          _PulseTickerItem(
            message: _pulseMessages[i ~/ 4 % _pulseMessages.length],
          ),
        );
      }
    }
  }
  return result;
}

bool _isWheatCommodity(LiveMandiRate rate) {
  final commodityRaw = rate.commodityNameUr.trim().isNotEmpty
      ? rate.commodityNameUr
      : rate.commodityName;
  return MandiHomePresenter.normalizeCommodityKey(commodityRaw) == 'wheat';
}

List<LiveMandiRate> _resolveBySourcePriority(List<LiveMandiRate> rates) {
  final buckets = <String, LiveMandiRate>{};
  for (final rate in rates) {
    final city = rate.city.trim().isNotEmpty
        ? rate.city.trim().toLowerCase()
        : rate.district.trim().toLowerCase();
    final commodity = rate.commodityName.trim().toLowerCase();
    final unit = rate.unit.trim().toLowerCase();
    final key = '$commodity|$city|$unit';
    final existing = buckets[key];
    if (existing == null) {
      buckets[key] = rate;
      continue;
    }

    final existingPriority = _sourcePriorityRank(existing);
    final incomingPriority = _sourcePriorityRank(rate);
    if (incomingPriority < existingPriority) {
      buckets[key] = rate;
      continue;
    }
    if (incomingPriority == existingPriority &&
        rate.lastUpdated.isAfter(existing.lastUpdated)) {
      buckets[key] = rate;
    }
  }
  return buckets.values.toList(growable: false);
}

bool _isCleanTickerRow(LiveMandiRate rate) {
  final commodityKey = MandiHomePresenter.normalizeCommodityKey(
    '${rate.metadata['urduName'] ?? ''} ${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}',
  );
  if (!MandiHomePresenter.isAllowlistedCommodity(commodityKey)) {
    return false;
  }
  final row = MandiHomePresenter.buildDisplayRow(
    commodityRaw: rate.commodityName,
    urduName: '${rate.metadata['urduName'] ?? ''}'.trim().isNotEmpty
        ? '${rate.metadata['urduName']}'.trim()
        : null,
    commodityNameUr: rate.commodityNameUr.trim().isNotEmpty
        ? rate.commodityNameUr
        : null,
    city: rate.city,
    district: rate.district,
    province: rate.province,
    unitRaw: rate.unit,
    price: rate.price,
    sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
    confidence: rate.confidenceScore,
    renderPath: MandiHomeRenderPath.ticker,
  );
  debugPrint('[MandiHome] legacy_render_path_hit=false');
  return row.isRenderable;
}

int _sourcePriorityRank(LiveMandiRate rate) {
  return MandiHomePresenter.sourcePriorityFromRate(rate);
}

// ---------------------------------------------------------------------------
// Widget
// ---------------------------------------------------------------------------

class MandiRatesTicker extends StatefulWidget {
  const MandiRatesTicker({super.key, required this.rates});

  final List<LiveMandiRate> rates;

  @override
  State<MandiRatesTicker> createState() => _MandiRatesTickerState();
}

class _MandiRatesTickerState extends State<MandiRatesTicker> {
  final ScrollController _controller = ScrollController();
  Timer? _scrollTimer;

  static const Color _tickerBase = Color(0xFF0E2B1D);
  static const Color _tickerBaseSoft = Color(0xFF113523);
  static const Color _accentGold = Color(0xFFD8B36A);

  @override
  void initState() {
    super.initState();
    _startScroll();
  }

  @override
  void didUpdateWidget(covariant MandiRatesTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rates != widget.rates) {
      _stopScroll();
      if (_controller.hasClients) _controller.jumpTo(0);
      _startScroll();
    }
  }

  void _startScroll() {
    _scrollTimer?.cancel();
    // UI-only tuning: calmer motion for a premium market-ribbon feel.
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 1) return;
      final next = _controller.offset + 0.7;
      _controller.jumpTo(next >= max ? 0 : next);
    });
  }

  void _stopScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  void dispose() {
    _stopScroll();
    _controller.dispose();
    super.dispose();
  }

  // ---- Build helpers -------------------------------------------------------

  Widget _buildPriceWidget({
    required LiveMandiRate rate,
    required String line,
    required int displayPriority,
  }) {
    final isUp = rate.trend == 'up';
    final isDown = rate.trend == 'down';
    final trendColor = isUp
        ? const Color(0xFF69EE8A) // soft green
        : isDown
        ? const Color(0xFFFF7575) // soft red
        : const Color(0xFFEFD88A); // default gold
    final bool highPriorityVegetable =
        displayPriority >= 5 && displayPriority <= 8;
    final FontWeight textWeight = displayPriority <= 4
        ? FontWeight.w700
        : (highPriorityVegetable ? FontWeight.w600 : FontWeight.w500);
    final double fontSize = displayPriority <= 1 ? 12.2 : 11.8;

    return Center(
      child: Text(
        line,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        textDirection: TextDirection.rtl,
        style: TextStyle(
          color: Color.lerp(trendColor, Colors.white, 0.18),
          fontSize: fontSize,
          fontWeight: textWeight,
          height: 1.18,
          letterSpacing: 0.08,
        ),
      ),
    );
  }

  Widget _buildPulseWidget(String message) {
    return Center(
      child: Text(
        message,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.72),
          fontSize: 11.2,
          fontWeight: FontWeight.w500,
          fontStyle: FontStyle.italic,
          height: 1.15,
        ),
      ),
    );
  }

  Widget _buildLiveIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _accentGold.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _accentGold.withValues(alpha: 0.35)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: Color(0xFFE6C888)),
          SizedBox(width: 4),
          Text(
            'لائیو منڈی',
            style: TextStyle(
              color: Color(0xFFE6C888),
              fontWeight: FontWeight.w600,
              fontSize: 10,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  // ---- Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final items = _buildTickerItems(widget.rates);

    if (items.isEmpty) return const SizedBox.shrink();

    // Mirror list so the scroll loop looks seamless.
    final mirrored = <_TickerItem>[...items, ...items];

    return Container(
      height: 44,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [_tickerBase, _tickerBaseSoft],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _accentGold.withValues(alpha: 0.24)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildLiveIndicator(),
          const SizedBox(width: 10),
          Expanded(
            child: ListView.separated(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: mirrored.length,
              separatorBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Center(
                  child: Text(
                    '|',
                    style: TextStyle(
                      color: _accentGold.withValues(alpha: 0.62),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              itemBuilder: (_, index) {
                final item = mirrored[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: switch (item) {
                  _PriceTickerItem(
                    :final rate,
                    :final displayLine,
                    :final displayPriority,
                  ) =>
                    _buildPriceWidget(
                      rate: rate,
                      line: displayLine,
                      displayPriority: displayPriority,
                    ),
                  _PulseTickerItem(:final message) => _buildPulseWidget(
                    message,
                  ),
                },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
