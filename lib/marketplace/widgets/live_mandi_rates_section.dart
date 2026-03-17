import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';
import '../screens/all_mandi_rates_screen.dart';
import '../services/gemini_rate_enhancement_service.dart';
import '../services/mandi_rate_location_service.dart';
import '../services/mandi_rate_prioritization_service.dart';
import '../services/mandi_rate_sync_manager.dart';
import 'mandi_rate_horizontal_card_list.dart';
import 'mandi_rates_ticker.dart';

class LiveMandiRatesSection extends StatefulWidget {
  const LiveMandiRatesSection({
    super.key,
    this.selectedCategory,
    this.accountCity,
    this.accountDistrict,
    this.accountProvince,
  });

  final MandiType? selectedCategory;
  final String? accountCity;
  final String? accountDistrict;
  final String? accountProvince;

  @override
  State<LiveMandiRatesSection> createState() => _LiveMandiRatesSectionState();
}

class _LiveMandiRatesSectionState extends State<LiveMandiRatesSection> {
  final MandiRateSyncManager _syncManager = MandiRateSyncManager();
  final MandiRatesRepository _repository = MandiRatesRepository();
  final MandiRateLocationService _locationService =
      const MandiRateLocationService();
  final MandiRatePrioritizationService _ranker =
      const MandiRatePrioritizationService();
  final GeminiRateEnhancementService _enhancer = GeminiRateEnhancementService();

  MandiRatesSyncState _state = MandiRatesSyncState.initial;
  StreamSubscription<MandiRatesSyncState>? _sub;
  MandiLocationContext _location = MandiLocationContext.empty;
  List<LiveMandiRate> _tickerRates = const <LiveMandiRate>[];
  List<LiveMandiRate> _cardRates = const <LiveMandiRate>[];
  bool _hasSuppressedNonLiveData = false;
  bool _isNationalFallbackActive = false;

  @override
  void initState() {
    super.initState();
    _sub = _syncManager.stream.listen((state) async {
      final loc = await _locationService.resolve(
        fallbackCity: widget.accountCity,
        fallbackDistrict: widget.accountDistrict,
        fallbackProvince: widget.accountProvince,
      );

      var sourceRates = state.rates;
      final locationScoped = await _repository.fetchLocationAwareCandidates(
        location: loc,
        targetCount: 140,
      );
      if (locationScoped.isNotEmpty) {
        sourceRates = locationScoped;
      }

      debugPrint(
        '[MANDI_QUERY] LiveSection: stateRates=${state.rates.length} '
        'locationScoped=${locationScoped.length} sourceRatesUsed=${sourceRates.length} '
        'location city=${loc.city} district=${loc.district} province=${loc.province} '
        'lat=${loc.latitude?.toStringAsFixed(5) ?? 'n/a'} lng=${loc.longitude?.toStringAsFixed(5) ?? 'n/a'}',
      );

      final fetchTrace = _repository.lastFetchTrace;
      final fetchedDocs = fetchTrace?.fetchedDocs ?? sourceRates.length;
      final parsedValidItems = fetchTrace?.parsedValidItems ?? sourceRates.length;
      final fetchPostDedup = fetchTrace?.postDedupItems ?? sourceRates.length;

      var ranked = sourceRates.where(_isRenderableForHome).toList(growable: false);
      final postQualityFilter = ranked.length;

      debugPrint(
        '[MANDI_REJECT] LiveSection: rawCandidates=${sourceRates.length} '
        'afterRenderableFilter=${ranked.length} '
        'rejected=${sourceRates.length - ranked.length} '
        'rejectionBreakdown: notTrusted=${sourceRates.where((r) => !r.isTrustedSource).length} '
        'isStale=${sourceRates.where((r) => r.isStale).length} '
        'missingName=${sourceRates.where((r) => r.commodityName.trim().isEmpty || r.mandiName.trim().isEmpty).length} '
        'zeroPrice=${sourceRates.where((r) => getTrustedDisplayPrice(r) <= 0).length}',
      );

      ranked = _ranker.rank(rates: ranked, location: loc);
      ranked = _applyCategoryFilter(ranked);

      for (var i = 0; i < ranked.length; i++) {
        final item = ranked[i];
        final isNearby = _isNearbyByFallback(item, loc);
        ranked[i] = item.copyWith(isNearby: isNearby || item.isNearby);
      }

      ranked = _prioritizeFreshness(ranked);
      final preDedupe = ranked.length;
      ranked = _dedupeRates(ranked);
      final postDedupe = ranked.length;

      final homeSafe = _buildTrustworthyHomeRates(ranked);
      final hasNearby = _hasNearbyLocationMatch(homeSafe, loc);
      final homeOrdered = _applyLocationDrivenHomeOrdering(homeSafe, loc);
      final postCityFirst = homeOrdered.length;
      final diversifiedHome = _diversifyHomePool(
        homeOrdered,
        location: loc,
        targetCount: 16,
      );
      final postSubcategoryDiversification = diversifiedHome.length;
      final enhanced = await _enhancer.enhanceBatch(diversifiedHome, maxItems: 8);
      final split = _splitTickerAndCards(enhanced);

      final tierStats = _tierStats(homeOrdered, loc);
      final distinctSubcategories = homeOrdered
          .map(_subcategoryKey)
          .where((key) => key.isNotEmpty)
          .toSet()
          .length;
      final unknownPriceSource = homeOrdered
          .where((item) => item.displayPriceSource == 'unknown')
          .length;
      final suspiciousRates = homeOrdered
          .where((item) => item.isSuspiciousRate)
          .length;

      debugPrint(
        '[MANDI_STAGE_COUNTS] fetchedDocs=$fetchedDocs '
        'parsedValidItems=$parsedValidItems '
        'postQualityFilterItems=$postQualityFilter '
        'postDedupItems=$postDedupe '
        'postCityFirstItems=$postCityFirst '
        'postSubcategoryDiversificationItems=$postSubcategoryDiversification '
        'finalTickerItems=${split.ticker.length} '
        'finalSnapshotItems=${split.cards.length} '
        'fetchPostDedupItems=$fetchPostDedup',
      );

      if (split.ticker.length <= 1) {
        debugPrint(
          '[MANDI_COLLAPSE_REASON] '
          'cityTierItems=${tierStats.cityTier} '
          'nearestFallbackItems=${tierStats.nearestTier} '
          'provinceTierItems=${tierStats.provinceTier} '
          'otherTierItems=${tierStats.otherTier} '
          'distinctSubcategories=$distinctSubcategories '
          'dedupRemoved=${preDedupe - postDedupe} '
          'unknownDisplayPriceSource=$unknownPriceSource '
          'suspiciousRates=$suspiciousRates '
          'enhancedItems=${enhanced.length}',
        );
      }

      debugPrint(
        '[MANDI_PARSE] LiveSection: afterRanking=${ranked.length} '
        'afterTrustworthyFilter=${homeSafe.length} '
        'afterLocationOrdering=${homeOrdered.length} '
        'afterEnhancement=${enhanced.length} '
        'hasNearbyLocationMatch=$hasNearby',
      );
      debugPrint(
        '[MANDI_RENDER] LiveSection: finalTickerRendered=${split.ticker.length} '
        'finalSnapshotCards=${split.cards.length} '
        'hasSuppressedNonLive=${sourceRates.isNotEmpty && homeOrdered.isEmpty} '
        'isNationalFallback=${_hasLocationContext(loc) && !hasNearby && homeOrdered.isNotEmpty}',
      );

      if (!mounted) return;
      setState(() {
        _location = loc;
        _tickerRates = split.ticker;
        _cardRates = split.cards;
        _hasSuppressedNonLiveData = sourceRates.isNotEmpty && homeOrdered.isEmpty;
        _isNationalFallbackActive =
          _hasLocationContext(loc) && !hasNearby && homeOrdered.isNotEmpty;
        _state = MandiRatesSyncState(
          rates: enhanced,
          isLoading: state.isLoading,
          isOfflineFallback: state.isOfflineFallback,
          lastSyncedAt: state.lastSyncedAt,
          error: state.error,
        );
      });
    });

    unawaited(_syncManager.start());
  }

  List<LiveMandiRate> _applyCategoryFilter(List<LiveMandiRate> items) {
    if (widget.selectedCategory == null) return items;
    final key = widget.selectedCategory!.wireValue.toLowerCase();
    return items
        .where((item) {
          final categoryData = '${item.categoryName} ${item.categoryId}'
              .toLowerCase();
          return categoryData.contains(key);
        })
        .toList(growable: false);
  }

  bool _isNearbyByFallback(LiveMandiRate item, MandiLocationContext loc) {
    final city = loc.city.trim().toLowerCase();
    final district = loc.district.trim().toLowerCase();
    final province = loc.province.trim().toLowerCase();
    if (city.isNotEmpty && item.city.trim().toLowerCase() == city) return true;
    if (district.isNotEmpty && item.district.trim().toLowerCase() == district) {
      return true;
    }
    if (province.isNotEmpty && item.province.trim().toLowerCase() == province) {
      return true;
    }
    return false;
  }

  bool _isRenderableForHome(LiveMandiRate item) {
    final hasRequiredFields =
        item.commodityName.trim().isNotEmpty &&
        item.mandiName.trim().isNotEmpty &&
        getTrustedDisplayPrice(item) > 0;

    if (!hasRequiredFields) return false;
    if (!item.isTrustedSource) return false;
    if (item.isStale) return false;

    return item.freshnessStatus == MandiFreshnessStatus.live ||
        item.freshnessStatus == MandiFreshnessStatus.recent ||
        item.freshnessStatus == MandiFreshnessStatus.aging;
  }

  List<LiveMandiRate> _prioritizeFreshness(List<LiveMandiRate> items) {
    final live = items
        .where((item) => item.isLiveFresh)
        .toList(growable: false);
    final recent = items
        .where((item) => item.isRecentFresh)
        .toList(growable: false);
    final aging = items
        .where((item) => item.freshnessStatus == MandiFreshnessStatus.aging)
        .toList(growable: false);
    return <LiveMandiRate>[...live, ...recent, ...aging];
  }

  List<LiveMandiRate> _buildTrustworthyHomeRates(List<LiveMandiRate> rates) {
    if (rates.isEmpty) return rates;

    final candidates = rates
        .where(_isRenderableForHome)
        .toList(growable: false);
    if (candidates.isEmpty) return const <LiveMandiRate>[];

    final baseBuckets = <String, List<LiveMandiRate>>{};
    for (final item in candidates) {
      final baseKey = _comparabilityBaseKey(item);
      if (baseKey.isEmpty) continue;
      baseBuckets.putIfAbsent(baseKey, () => <LiveMandiRate>[]).add(item);
    }

    final comparableBuckets = <String, List<LiveMandiRate>>{};
    for (final entry in baseBuckets.entries) {
      final qualityKeys = entry.value
          .map(_qualityOrRefKey)
          .where((key) => key.isNotEmpty && key != 'generic')
          .toSet();

      for (final item in entry.value) {
        final qualityKey = _qualityOrRefKey(item);
        final hasSpecificQualities = qualityKeys.isNotEmpty;
        final missingQualityInMixedBucket =
            hasSpecificQualities &&
            (qualityKey.isEmpty || qualityKey == 'generic');
        if (missingQualityInMixedBucket) {
          continue;
        }

        final finalQuality = qualityKey.isNotEmpty ? qualityKey : 'generic';
        final key = '${entry.key}|$finalQuality';
        comparableBuckets.putIfAbsent(key, () => <LiveMandiRate>[]).add(item);
      }
    }

    final outlierIds = _computeOutlierIds(comparableBuckets);
    final nonOutlier = candidates
        .where((item) => !outlierIds.contains(item.id))
        .toList(growable: false);
    if (nonOutlier.isEmpty) return const <LiveMandiRate>[];

    final reliableComparable = nonOutlier
        .where((item) => _isComparableForHome(item) && !item.isSuspiciousRate)
        .toList(growable: false);
    final suspicious = nonOutlier
        .where((item) => item.isSuspiciousRate)
        .toList(growable: false);

    final picked = <LiveMandiRate>[];
    final preferredComparable = reliableComparable.isNotEmpty
        ? reliableComparable
        : nonOutlier.where(_isComparableForHome).toList(growable: false);

    picked.addAll(preferredComparable);

    if (suspicious.isNotEmpty) {
      final cap = picked.isEmpty
          ? suspicious.length
          : math.max(2, (picked.length / 3).ceil());
      picked.addAll(suspicious.take(cap));
    }

    if (picked.isEmpty) {
      picked.addAll(nonOutlier);
    }

    return _dedupeRates(picked);
  }

  List<LiveMandiRate> _applyLocationDrivenHomeOrdering(
    List<LiveMandiRate> rates,
    MandiLocationContext location,
  ) {
    if (rates.isEmpty) return rates;
    if (!_hasLocationContext(location)) {
      return rates;
    }

    final nearestDistricts = _nearestDistricts(location);
    final scored = rates
        .map(
          (rate) => _LocationRankedRate(
            rate: rate,
            tier: _locationTier(rate, location, nearestDistricts),
          ),
        )
        .toList(growable: false);

    final hasNearbyMandi = scored.any((item) => item.tier <= 2);
    if (!hasNearbyMandi) {
      // No city/district/province match: fallback to national market view.
      return rates;
    }

    final byMandi = <String, List<_LocationRankedRate>>{};
    for (final item in scored) {
      byMandi
          .putIfAbsent(_mandiKey(item.rate), () => <_LocationRankedRate>[])
          .add(item);
    }

    final mandiKeys = byMandi.keys.toList(growable: false)
      ..sort((a, b) {
        final aItems = byMandi[a]!;
        final bItems = byMandi[b]!;
        final aTier = aItems
            .map((item) => item.tier)
            .fold<int>(9, (min, tier) => tier < min ? tier : min);
        final bTier = bItems
            .map((item) => item.tier)
            .fold<int>(9, (min, tier) => tier < min ? tier : min);
        if (aTier != bTier) return aTier.compareTo(bTier);

        final aLatest = aItems
            .map((item) => item.rate.lastUpdated)
            .fold<DateTime>(
              DateTime.fromMillisecondsSinceEpoch(0),
              (latest, value) => value.isAfter(latest) ? value : latest,
            );
        final bLatest = bItems
            .map((item) => item.rate.lastUpdated)
            .fold<DateTime>(
              DateTime.fromMillisecondsSinceEpoch(0),
              (latest, value) => value.isAfter(latest) ? value : latest,
            );
        return bLatest.compareTo(aLatest);
      });

    final ordered = <LiveMandiRate>[];
    final seen = <String>{};
    for (final mandiKey in mandiKeys) {
      final mandiItems = byMandi[mandiKey] ?? const <_LocationRankedRate>[];
      final bySubcategory = <String, List<_LocationRankedRate>>{};
      for (final item in mandiItems) {
        bySubcategory
            .putIfAbsent(
              _subcategoryKey(item.rate),
              () => <_LocationRankedRate>[],
            )
            .add(item);
      }

      final subKeys = bySubcategory.keys.toList(growable: false)
        ..sort((a, b) {
          final aItems = bySubcategory[a]!;
          final bItems = bySubcategory[b]!;
          final aTier = aItems
              .map((item) => item.tier)
              .fold<int>(9, (min, tier) => tier < min ? tier : min);
          final bTier = bItems
              .map((item) => item.tier)
              .fold<int>(9, (min, tier) => tier < min ? tier : min);
          if (aTier != bTier) return aTier.compareTo(bTier);
          final aFresh = aItems
              .map((item) => _freshnessWeight(item.rate))
              .fold<int>(0, (max, value) => value > max ? value : max);
          final bFresh = bItems
              .map((item) => _freshnessWeight(item.rate))
              .fold<int>(0, (max, value) => value > max ? value : max);
          return bFresh.compareTo(aFresh);
        });

      for (final subKey in subKeys) {
        final items = bySubcategory[subKey] ?? const <_LocationRankedRate>[];
        items.sort((a, b) {
          if (a.tier != b.tier) return a.tier.compareTo(b.tier);
          final fresh = _freshnessWeight(
            b.rate,
          ).compareTo(_freshnessWeight(a.rate));
          if (fresh != 0) return fresh;
          return b.rate.lastUpdated.compareTo(a.rate.lastUpdated);
        });

        for (final item in items) {
          if (seen.add(item.rate.id)) {
            ordered.add(item.rate);
          }
        }
      }
    }

    return ordered.isEmpty ? rates : ordered;
  }

  bool _hasLocationContext(MandiLocationContext location) {
    return location.city.trim().isNotEmpty ||
        location.district.trim().isNotEmpty ||
        location.province.trim().isNotEmpty ||
        (location.latitude != null && location.longitude != null);
  }

  Set<String> _nearestDistricts(MandiLocationContext location) {
    final districts = <String>{};
    final current = _norm(location.district);
    if (current.isEmpty) return districts;
    districts.add(current);

    for (final entry in AppConstants.districtDistancePairsKm.entries) {
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final a = _norm(parts[0]);
      final b = _norm(parts[1]);
      if (entry.value > 220) continue;

      if (a == current) districts.add(b);
      if (b == current) districts.add(a);
    }

    return districts;
  }

  bool _hasNearbyLocationMatch(
    List<LiveMandiRate> rates,
    MandiLocationContext location,
  ) {
    if (rates.isEmpty) return false;
    final nearestDistricts = _nearestDistricts(location);
    return rates.any(
      (rate) => _locationTier(rate, location, nearestDistricts) <= 2,
    );
  }

  int _locationTier(
    LiveMandiRate rate,
    MandiLocationContext location,
    Set<String> nearestDistricts,
  ) {
    final city = _norm(location.city);
    final district = _norm(location.district);
    final province = _norm(location.province);

    final rateCity = _norm(rate.city);
    final rateDistrict = _norm(
      rate.district.trim().isNotEmpty ? rate.district : rate.city,
    );
    final rateProvince = _norm(rate.province);

    if (city.isNotEmpty && rateCity == city) return 0;
    if (district.isNotEmpty && (rateDistrict == district)) return 1;
    if (rateDistrict.isNotEmpty && nearestDistricts.contains(rateDistrict)) {
      return 1;
    }
    if (province.isNotEmpty && rateProvince == province) return 2;

    final hasCoords =
        location.latitude != null &&
        location.longitude != null &&
        rate.latitude != null &&
        rate.longitude != null;
    if (hasCoords) {
      final distanceKm = _distanceInKm(
        location.latitude!,
        location.longitude!,
        rate.latitude!,
        rate.longitude!,
      );
      if (distanceKm <= 30) return 0;
      if (distanceKm <= 140) return 1;
      if (distanceKm <= 280) return 2;
    }

    return 3;
  }

  double _distanceInKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.pow(math.sin(dLon / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a.toDouble()), math.sqrt(1 - a));
    return r * c;
  }

  double _toRadians(double degree) => degree * (math.pi / 180.0);

  String _mandiKey(LiveMandiRate rate) {
    return [
      _norm(rate.mandiName),
      _norm(rate.city),
      _norm(rate.district),
      _norm(rate.province),
    ].join('|');
  }

  String _subcategoryKey(LiveMandiRate rate) {
    return [
      _norm(rate.categoryName.isNotEmpty ? rate.categoryName : rate.categoryId),
      _norm(
        rate.subCategoryName.isNotEmpty
            ? rate.subCategoryName
            : rate.subCategoryId,
      ),
    ].join('|');
  }

  bool _isComparableForHome(LiveMandiRate item) {
    if (item.hasWeakComparability) return false;
    if (item.displayPriceSource == 'unknown') return false;

    final commodity = _norm(item.commodityName);
    final category = _norm(
      item.categoryName.isNotEmpty ? item.categoryName : item.categoryId,
    );
    final subCategory = _norm(
      item.subCategoryName.isNotEmpty
          ? item.subCategoryName
          : item.subCategoryId,
    );
    final unit = _normalizedUnitKey(item.unit);

    if (commodity.isEmpty ||
        category.isEmpty ||
        subCategory.isEmpty ||
        unit.isEmpty) {
      return false;
    }
    return getTrustedDisplayPrice(item) > 0;
  }

  String _comparabilityBaseKey(LiveMandiRate item) {
    final commodity = _norm(item.commodityName);
    final category = _norm(
      item.categoryName.isNotEmpty ? item.categoryName : item.categoryId,
    );
    final subCategory = _norm(
      item.subCategoryName.isNotEmpty
          ? item.subCategoryName
          : item.subCategoryId,
    );
    final unit = _normalizedUnitKey(item.unit);

    if (commodity.isEmpty ||
        category.isEmpty ||
        subCategory.isEmpty ||
        unit.isEmpty) {
      return '';
    }
    return '$category|$subCategory|$commodity|$unit';
  }

  String _qualityOrRefKey(LiveMandiRate item) {
    final ref = _norm(item.commodityRefId);
    if (ref.isNotEmpty) return 'ref:$ref';

    final metadata = item.metadata;
    final grade = _norm('${metadata['grade'] ?? ''}');
    final variety = _norm('${metadata['variety'] ?? ''}');
    final quality = _norm('${metadata['quality'] ?? ''}');
    final label = _norm('${metadata['rawLabel'] ?? ''}');

    final parts = <String>[
      grade,
      variety,
      quality,
    ].where((part) => part.isNotEmpty).toList(growable: false);

    if (parts.isNotEmpty) return parts.join('_');
    if (label.contains('seed') ||
        label.contains('certified') ||
        label.contains('hybrid')) {
      return 'seed_like';
    }
    if (label.contains('basmati') || label.contains('irri')) {
      return 'specific_rice';
    }
    return 'generic';
  }

  Set<String> _computeOutlierIds(Map<String, List<LiveMandiRate>> buckets) {
    final outliers = <String>{};

    for (final entry in buckets.entries) {
      final items = entry.value;
      if (items.length < 4) continue;

      final prices = items
          .map((item) => getTrustedDisplayPrice(item))
          .where((price) => price > 0)
          .toList(growable: false);
      if (prices.length < 4) continue;

      final median = _median(prices);
      if (median <= 0) continue;

      final deviations = prices
          .map((value) => (value - median).abs())
          .toList(growable: false);
      final mad = _median(deviations);

      for (final item in items) {
        final price = getTrustedDisplayPrice(item);
        if (price <= 0) continue;

        final ratio = price / median;
        final isRatioOutlier = ratio < 0.55 || ratio > 1.85;

        var isMadOutlier = false;
        if (mad > 0) {
          final robustZ = (price - median).abs() / mad;
          isMadOutlier = robustZ > 4.0;
        }

        if (isRatioOutlier || isMadOutlier) {
          outliers.add(item.id);
        }
      }
    }

    return outliers;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
  }

  List<LiveMandiRate> _dedupeRates(List<LiveMandiRate> rates) {
    final map = <String, LiveMandiRate>{};
    for (final item in rates) {
      final key = [
        _norm(
          item.categoryName.isNotEmpty ? item.categoryName : item.categoryId,
        ),
        _norm(
          item.subCategoryName.isNotEmpty
              ? item.subCategoryName
              : item.subCategoryId,
        ),
        _norm(item.commodityName),
        _normalizedUnitKey(item.unit),
        _norm(item.city),
        _qualityOrRefKey(item),
      ].join('|');

      final existing = map[key];
      if (existing == null || _preferOverExisting(item, existing)) {
        map[key] = item;
      }
    }

    return map.values.toList(growable: false);
  }

  bool _preferOverExisting(LiveMandiRate a, LiveMandiRate b) {
    final ap = _displaySourcePriority(a.displayPriceSource);
    final bp = _displaySourcePriority(b.displayPriceSource);
    if (ap != bp) return ap > bp;

    if (a.isNearby != b.isNearby) return a.isNearby;

    final aSync = a.syncedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bSync = b.syncedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return aSync.isAfter(bSync);
  }

  int _displaySourcePriority(String source) {
    switch (source) {
      case 'average':
        return 4;
      case 'fqp':
        return 3;
      case 'midpoint':
        return 2;
      case 'rawMin':
        return 1;
      default:
        return 0;
    }
  }

  _TickerCardsSplit _splitTickerAndCards(List<LiveMandiRate> rates) {
    final desiredSnapshot = rates.length >= 5
        ? 3
        : (rates.length >= 4 ? 2 : (rates.length >= 2 ? 1 : 0));
    final tickerCap = math.max(1, math.min(12, rates.length - desiredSnapshot));
    final ticker = _diversifyForTicker(rates, maxItems: tickerCap);
    final tickerIds = ticker.map((item) => item.id).toSet();

    final cards = rates
        .where((item) => !tickerIds.contains(item.id))
        .toList(growable: false);

    if (cards.isEmpty) {
      final start = math.min(ticker.length, rates.length);
      final fallbackCards = rates.skip(start).take(8).toList(growable: false);
      return _TickerCardsSplit(ticker: ticker, cards: fallbackCards);
    }

    return _TickerCardsSplit(
      ticker: ticker,
      cards: cards.take(8).toList(growable: false),
    );
  }

  List<LiveMandiRate> _diversifyForTicker(
    List<LiveMandiRate> rates, {
    int maxItems = 12,
  }) {
    if (rates.isEmpty) return const <LiveMandiRate>[];

    final grouped = <String, List<LiveMandiRate>>{};
    for (final rate in rates) {
      final key = [
        _norm(
          rate.categoryName.isNotEmpty ? rate.categoryName : rate.categoryId,
        ),
        _norm(
          rate.subCategoryName.isNotEmpty
              ? rate.subCategoryName
              : rate.subCategoryId,
        ),
      ].join('|');
      grouped.putIfAbsent(key, () => <LiveMandiRate>[]).add(rate);
    }

    for (final entry in grouped.entries) {
      entry.value.sort((a, b) {
        if (a.isNearby != b.isNearby) return a.isNearby ? -1 : 1;
        final freshness = _freshnessWeight(b).compareTo(_freshnessWeight(a));
        if (freshness != 0) return freshness;
        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    }

    final result = <LiveMandiRate>[];
    final usedCommodityCitySubcategory = <String>{};
    final usedBucketCommodity = <String>{};

    // Pass 1: one strong representative per category/subcategory bucket.
    for (final entry in grouped.entries) {
      if (result.length >= maxItems) break;
      for (final item in entry.value) {
        final commodityCitySubcategory =
            '${_norm(item.commodityName)}|${_norm(item.city)}|${_subcategoryKey(item)}';
        final bucketCommodity = '${entry.key}|${_norm(item.commodityName)}';
        if (usedCommodityCitySubcategory.contains(commodityCitySubcategory) ||
            usedBucketCommodity.contains(bucketCommodity)) {
          continue;
        }
        result.add(item);
        usedCommodityCitySubcategory.add(commodityCitySubcategory);
        usedBucketCommodity.add(bucketCommodity);
        break;
      }
    }

    if (result.length >= maxItems) {
      return result.take(maxItems).toList(growable: false);
    }

    // Pass 2: round-robin fill while keeping diversity and no duplicate commodity-city pairs.
    final queues = grouped.values
        .map((items) => List<LiveMandiRate>.from(items))
        .toList();
    var progressed = true;
    while (result.length < maxItems && progressed) {
      progressed = false;
      for (final queue in queues) {
        if (result.length >= maxItems) break;
        while (queue.isNotEmpty) {
          final candidate = queue.removeAt(0);
          final commodityCitySubcategory =
              '${_norm(candidate.commodityName)}|${_norm(candidate.city)}|${_subcategoryKey(candidate)}';
          if (usedCommodityCitySubcategory.contains(commodityCitySubcategory)) {
            continue;
          }
          result.add(candidate);
          usedCommodityCitySubcategory.add(commodityCitySubcategory);
          progressed = true;
          break;
        }
      }
    }

    return result.take(maxItems).toList(growable: false);
  }

  List<LiveMandiRate> _diversifyHomePool(
    List<LiveMandiRate> rates, {
    required MandiLocationContext location,
    int targetCount = 16,
  }) {
    if (rates.isEmpty) return rates;

    final nearestDistricts = _nearestDistricts(location);
    final scored = rates
        .map(
          (rate) => _LocationRankedRate(
            rate: rate,
            tier: _locationTier(rate, location, nearestDistricts),
          ),
        )
        .toList(growable: false);

    final cityTier = scored.where((item) => item.tier == 0).toList(growable: false);
    final nearestTier = scored
        .where((item) => item.tier > 0 && item.tier <= 2)
        .toList(growable: false);
    final broadTier = scored.where((item) => item.tier > 2).toList(growable: false);

    final result = <LiveMandiRate>[];
    final seenIds = <String>{};
    final seenSubcategories = <String>{};

    void addDistinctSubcategory(List<_LocationRankedRate> pool, {int? cap}) {
      var added = 0;
      for (final item in pool) {
        if (result.length >= targetCount) return;
        final subcategory = _subcategoryKey(item.rate);
        if (seenIds.contains(item.rate.id) || seenSubcategories.contains(subcategory)) {
          continue;
        }
        result.add(item.rate);
        seenIds.add(item.rate.id);
        seenSubcategories.add(subcategory);
        added += 1;
        if (cap != null && added >= cap) return;
      }
    }

    void addAny(List<_LocationRankedRate> pool) {
      for (final item in pool) {
        if (result.length >= targetCount) return;
        if (seenIds.add(item.rate.id)) {
          result.add(item.rate);
        }
      }
    }

    // Keep exact-city first, but if city has limited depth then force nearest fallback mix.
    addDistinctSubcategory(cityTier);
    final minFallbackDistinct = cityTier.length <= 1 ? 3 : 1;
    addDistinctSubcategory(nearestTier, cap: minFallbackDistinct);
    addDistinctSubcategory(nearestTier);
    addDistinctSubcategory(broadTier);

    if (result.length < targetCount) addAny(cityTier);
    if (result.length < targetCount) addAny(nearestTier);
    if (result.length < targetCount) addAny(broadTier);

    return result.take(targetCount).toList(growable: false);
  }

  _TierStats _tierStats(List<LiveMandiRate> rates, MandiLocationContext location) {
    if (rates.isEmpty) return const _TierStats();
    final nearestDistricts = _nearestDistricts(location);
    var cityTier = 0;
    var nearestTier = 0;
    var provinceTier = 0;
    var otherTier = 0;

    for (final rate in rates) {
      final tier = _locationTier(rate, location, nearestDistricts);
      if (tier == 0) {
        cityTier += 1;
      } else if (tier == 1) {
        nearestTier += 1;
      } else if (tier == 2) {
        provinceTier += 1;
      } else {
        otherTier += 1;
      }
    }

    return _TierStats(
      cityTier: cityTier,
      nearestTier: nearestTier,
      provinceTier: provinceTier,
      otherTier: otherTier,
    );
  }

  int _freshnessWeight(LiveMandiRate item) {
    if (item.isLiveFresh) return 4;
    if (item.isRecentFresh) return 3;
    if (item.freshnessStatus == MandiFreshnessStatus.aging) return 2;
    if (item.isStale) return 1;
    return 0;
  }

  String _normalizedUnitKey(String value) {
    final unit = _norm(value);
    if (unit.isEmpty) return '';
    if (unit.contains('100') && unit.contains('kg')) return 'per_100kg';
    if (unit.contains('40') && unit.contains('kg')) return 'per_40kg';
    if (unit.contains('maund') || unit.contains('mond')) return 'per_40kg';
    if (unit.contains('50') && unit.contains('kg')) return 'per_50kg';
    if (unit.contains('kg')) return 'per_kg';
    if (unit.contains('dozen') || unit.contains('doz')) return 'per_dozen';
    return unit;
  }

  String _norm(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _syncManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rates = _state.rates;
    final tickerRates = _tickerRates;
    final cardRates = _cardRates;
    final stale = rates.isNotEmpty && _state.isStale;
    final hasLiveOrRecent = rates.any(
      (item) => item.isLiveFresh || item.isRecentFresh,
    );
    final hasAgingOnly = rates.isNotEmpty && !hasLiveOrRecent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nearby Mandi Rates / آپ کے قریب منڈی ریٹس',
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Live market prices and trends\nلائیو مارکیٹ قیمتیں اور رجحانات',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.primaryText60,
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AllMandiRatesScreen(
                      initialCategory: widget.selectedCategory,
                      accountCity: widget.accountCity,
                      accountDistrict: widget.accountDistrict,
                      accountProvince: widget.accountProvince,
                    ),
                  ),
                );
              },
              child: const Text('See All / سب دیکھیں'),
            ),
          ],
        ),
        if (_state.isOfflineFallback)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Offline fallback is active.\nآف لائن بیک اپ ڈیٹا دکھایا جا رہا ہے۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ),
        if (stale)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Data may be stale. Pull to refresh in See All screen.\nڈیٹا پرانا ہو سکتا ہے۔ سب دیکھیں اسکرین میں ریفریش کریں۔',
              style: TextStyle(
                color: AppColors.urgencyRed,
                fontSize: 10.8,
                height: 1.25,
              ),
            ),
          ),
        if (hasAgingOnly)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Latest verified mandi rates are shown below.\nتازہ تصدیق شدہ منڈی ریٹس نیچے دکھائے گئے ہیں۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.8,
                height: 1.25,
              ),
            ),
          ),
        if (_state.lastSyncedAt != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'Last sync: ${_relative(_state.lastSyncedAt!)} / آخری سنک: ${_relative(_state.lastSyncedAt!)}',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.4,
                height: 1.2,
              ),
            ),
          ),
        if (_location.permissionDenied || _location.permissionPermanentlyDenied)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Location permission denied. Prioritizing account or filter location.\nلوکیشن اجازت نہ ملنے پر اکاؤنٹ یا فلٹر مقام کو ترجیح دی جا رہی ہے۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.8,
                height: 1.25,
              ),
            ),
          ),
        if (_location.locationServiceDisabled)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Location service is off. Showing fallback mandi context.\nلوکیشن سروس بند ہے۔ بیک اپ منڈی سیاق دکھایا جا رہا ہے۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.8,
                height: 1.25,
              ),
            ),
          ),
        if (_isNationalFallbackActive)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'No nearby mandi rates found. Showing broader market.\nقریب کی منڈی ریٹس دستیاب نہیں، وسیع مارکیٹ دکھائی جا رہی ہے۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.8,
                height: 1.25,
              ),
            ),
          ),
        if (!_state.isLoading && rates.isEmpty && _hasSuppressedNonLiveData)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Latest verified mandi rates are not available yet.\nتازہ تصدیق شدہ منڈی ریٹس ابھی دستیاب نہیں۔',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ),
        MandiRatesTicker(rates: tickerRates),
        const SizedBox(height: 8),
        if (_state.isLoading && rates.isEmpty)
          const SizedBox(
            height: 120,
            child: Center(
              child: CircularProgressIndicator(color: AppColors.accentGold),
            ),
          )
        else
          MandiRateHorizontalCardList(rates: cardRates),
      ],
    );
  }

  String _relative(DateTime dateTime) {
    final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _TickerCardsSplit {
  const _TickerCardsSplit({required this.ticker, required this.cards});

  final List<LiveMandiRate> ticker;
  final List<LiveMandiRate> cards;
}

class _LocationRankedRate {
  const _LocationRankedRate({required this.rate, required this.tier});

  final LiveMandiRate rate;
  final int tier;
}

class _TierStats {
  const _TierStats({
    this.cityTier = 0,
    this.nearestTier = 0,
    this.provinceTier = 0,
    this.otherTier = 0,
  });

  final int cityTier;
  final int nearestTier;
  final int provinceTier;
  final int otherTier;
}
