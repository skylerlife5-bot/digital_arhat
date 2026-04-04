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
import '../services/mandi_home_presenter.dart';
import '../utils/mandi_display_utils.dart';
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

  static const Set<String> _homeCommodityAllowlist =
      MandiHomePresenter.homeCommodityAllowlist;

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

      // Display layer guard: show only user-city commodities.
      sourceRates = MandiHomePresenter.filterRatesByUserCity(
        rates: sourceRates,
        userCity: loc.city,
      );

      debugPrint(
        '[MANDI_QUERY] LiveSection: stateRates=${state.rates.length} '
        'locationScoped=${locationScoped.length} sourceRatesUsed=${sourceRates.length} '
        'location city=${loc.city} district=${loc.district} province=${loc.province} '
        'lat=${loc.latitude?.toStringAsFixed(5) ?? 'n/a'} lng=${loc.longitude?.toStringAsFixed(5) ?? 'n/a'}',
      );

      final fetchTrace = _repository.lastFetchTrace;
      final fetchedDocs = fetchTrace?.fetchedDocs ?? sourceRates.length;
      final parsedValidItems =
          fetchTrace?.parsedValidItems ?? sourceRates.length;
      final fetchPostDedup = fetchTrace?.postDedupItems ?? sourceRates.length;

      var ranked = _buildControlledHomeRates(sourceRates);
      final postQualityFilter = ranked.length;

      debugPrint(
        '[MANDI_REJECT] LiveSection: rawCandidates=${sourceRates.length} '
        'afterRenderableFilter=${ranked.length} '
        'rejected=${sourceRates.length - ranked.length}',
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
      var enhanced = await _enhancer.enhanceBatch(diversifiedHome, maxItems: 8);
      final split = _ensureRequiredWheatVisibility(
        _splitTickerAndCards(enhanced),
        pool: enhanced,
        location: loc,
      );

      if (split.ticker.isNotEmpty) {
        final probe = split.ticker.first;
        final cityRaw = [
          probe.city,
          probe.district,
          probe.province,
        ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' | ');
        final commodityRaw = probe.commodityNameUr.trim().isNotEmpty
            ? probe.commodityNameUr
            : probe.commodityName;
        final unitRaw = probe.unit;
        final probeRow = MandiHomePresenter.buildDisplayRow(
          commodityRaw: probe.commodityName,
          urduName: '${probe.metadata['urduName'] ?? ''}'.trim().isNotEmpty
              ? '${probe.metadata['urduName']}'.trim()
              : null,
          commodityNameUr: probe.commodityNameUr.trim().isNotEmpty
              ? probe.commodityNameUr
              : null,
          city: probe.city,
          district: probe.district,
          province: probe.province,
          unitRaw: unitRaw,
          price: getTrustedDisplayPrice(probe),
          sourceSelected:
              '${probe.sourceId}|${probe.sourceType}|${probe.source}',
          confidence: probe.confidenceScore,
          renderPath: MandiHomeRenderPath.ticker,
        );
        debugPrint('[MandiPulseUI] ticker_city_raw=$cityRaw');
        debugPrint(
          '[MandiPulseUI] ticker_city_localized=${probeRow.cityDisplay}',
        );
        debugPrint('[MandiPulseUI] ticker_commodity_raw=$commodityRaw');
        debugPrint(
          '[MandiPulseUI] ticker_commodity_localized=${probeRow.commodityDisplay}',
        );
        debugPrint('[MandiPulseUI] ticker_unit_raw=$unitRaw');
        debugPrint(
          '[MandiPulseUI] ticker_unit_localized=${probeRow.unitDisplay}',
        );
        debugPrint('[MandiPulseUI] probe_renderable=${probeRow.isRenderable}');
        debugPrint('[MandiHome] legacy_render_path_hit=false');
      }

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
      debugPrint('[MandiPulse] final_home_ticker_count=${split.ticker.length}');
      debugPrint(
        '[MandiPulse] final_home_snapshot_count=${split.cards.length}',
      );
      _logFinalHomeSurfaceProof(split);

      if (!mounted) return;
      setState(() {
        _location = loc;
        _tickerRates = split.ticker;
        _cardRates = split.cards;
        _hasSuppressedNonLiveData =
            sourceRates.isNotEmpty && homeOrdered.isEmpty;
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
    // Hard-reject rows with unit violations or critical data quality issues.
    if (item.rowConfidence == MandiRowConfidence.rejected) return false;

    final commodity = _normalizeHomeCommodity(item);
    if (commodity.isEmpty) return false;
    if (!MandiHomePresenter.isAllowlistedCommodity(commodity)) return false;

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

  List<LiveMandiRate> _buildControlledHomeRates(List<LiveMandiRate> rates) {
    if (rates.isEmpty) return const <LiveMandiRate>[];

    final commodityById = <String, String>{};
    final unitById = <String, String>{};
    final locById = <String, String>{};
    final groupedUnits = <String, Set<String>>{};

    for (final rate in rates) {
      final commodity = _normalizeHomeCommodity(rate);
      final unit = _normalizedHomeUnitKey(rate.unit);
      final loc = _homeLocationKey(rate);
      commodityById[rate.id] = commodity;
      unitById[rate.id] = unit;
      locById[rate.id] = loc;

      if (commodity.isEmpty || unit.isEmpty || loc.isEmpty) {
        continue;
      }

      final key = '$commodity|$loc';
      groupedUnits.putIfAbsent(key, () => <String>{}).add(unit);
    }

    final mixedUnitConflicts = <String>{};
    for (final entry in groupedUnits.entries) {
      if (entry.value.length > 1) {
        mixedUnitConflicts.add(entry.key);
      }
    }

    final accepted = <LiveMandiRate>[];
    for (final rate in rates) {
      final commodity = commodityById[rate.id] ?? '';
      final localizedCommodity = _homeLocalizedCommodity(rate);
      final allowlistHit = _homeCommodityAllowlist.contains(commodity);

      debugPrint('[MandiPulse] commodity_normalized=$commodity');
      debugPrint('[MandiPulse] commodity_localized=$localizedCommodity');
      debugPrint('[MandiPulse] home_allowlist_hit=$allowlistHit');

      final reason = _homeRejectReason(
        rate,
        commodity: commodity,
        localizedCommodity: localizedCommodity,
        normalizedUnit: unitById[rate.id] ?? '',
        locationKey: locById[rate.id] ?? '',
        mixedUnitConflicts: mixedUnitConflicts,
      );

      if (reason != null) {
        debugPrint('[MandiPulse] home_reject_reason=$reason');
        continue;
      }

      accepted.add(rate);
    }

    return _selectHomePreferredSourceRows(accepted);
  }

  String? _homeRejectReason(
    LiveMandiRate item, {
    required String commodity,
    required String localizedCommodity,
    required String normalizedUnit,
    required String locationKey,
    required Set<String> mixedUnitConflicts,
  }) {
    if (commodity.isEmpty) return 'commodity_not_normalized';
    if (!_homeCommodityAllowlist.contains(commodity))
      return 'commodity_not_allowlisted';
    if (localizedCommodity.isEmpty || localizedCommodity == 'اجناس') {
      return 'missing_clean_localized_label';
    }

    final englishLabel = getLocalizedCommodityName(
      item.commodityName,
      MandiDisplayLanguage.english,
    );
    if (englishLabel == 'Commodity') return 'missing_clean_english_label';

    final sourcePriority = _homeSourcePriority(item);
    if (sourcePriority >= 90) return 'untrusted_source';
    if (sourcePriority == 5) return 'pbs_spi_trend_only';

    if (normalizedUnit.isEmpty) return 'invalid_unit';
    if (!_isAllowedUnitForHomeCommodity(commodity, normalizedUnit)) {
      return 'commodity_unit_mismatch';
    }

    final conflictKey = '$commodity|$locationKey';
    if (locationKey.isNotEmpty && mixedUnitConflicts.contains(conflictKey)) {
      return 'mixed_unit_conflict';
    }

    if (!_isRenderableForHome(item)) return 'not_renderable_for_home';
    if (item.isRejectedContribution) return 'rejected_row';
    if (item.rowConfidence == MandiRowConfidence.rejected)
      return 'rejected_row_confidence';
    if (item.confidenceScore < 0.72) return 'insufficient_confidence';
    if (!item.isTickerPriceEligible) return 'not_ticker_price_eligible';

    return null;
  }

  List<LiveMandiRate> _selectHomePreferredSourceRows(List<LiveMandiRate> rows) {
    final grouped = <String, LiveMandiRate>{};

    for (final row in rows) {
      final commodity = _normalizeHomeCommodity(row);
      final unit = _normalizedHomeUnitKey(row.unit);
      final location = _homeLocationKey(row);
      if (commodity.isEmpty || unit.isEmpty || location.isEmpty) {
        continue;
      }

      final key = '$commodity|$location|$unit';
      final existing = grouped[key];
      if (existing == null || _preferHomeSource(row, existing)) {
        grouped[key] = row;
      }
    }

    for (final selected in grouped.values) {
      debugPrint(
        '[MandiPulse] source_selected=${selected.sourceId}|${selected.sourceType}|${selected.source}',
      );
    }

    return grouped.values.toList(growable: false);
  }

  bool _preferHomeSource(LiveMandiRate incoming, LiveMandiRate existing) {
    final sourceCompare = _homeSourcePriority(
      incoming,
    ).compareTo(_homeSourcePriority(existing));
    if (sourceCompare != 0) return sourceCompare < 0;

    final incomingFresh = _freshnessWeight(incoming);
    final existingFresh = _freshnessWeight(existing);
    if (incomingFresh != existingFresh) return incomingFresh > existingFresh;

    if (incoming.confidenceScore != existing.confidenceScore) {
      return incoming.confidenceScore > existing.confidenceScore;
    }

    return incoming.lastUpdated.isAfter(existing.lastUpdated);
  }

  String _homeLocalizedCommodity(LiveMandiRate rate) {
    final commodity = _normalizeHomeCommodity(rate);
    if (commodity.isEmpty) return '';
    return MandiHomePresenter.commodityDisplayUrdu(commodity);
  }

  String _normalizeHomeCommodity(LiveMandiRate item) {
    final candidates = <String>[
      '${item.metadata['urduName'] ?? ''}',
      item.commodityName,
      item.commodityNameUr,
      item.subCategoryName,
      item.subCategoryId,
      item.commodityRefId,
    ];
    for (final candidate in candidates) {
      final key = MandiHomePresenter.normalizeCommodityKey(candidate);
      if (key.isNotEmpty && MandiHomePresenter.isAllowlistedCommodity(key)) {
        return key;
      }
    }
    return '';
  }

  String _homeLocationKey(LiveMandiRate item) {
    final city = _norm(item.city);
    final district = _norm(item.district);
    final province = _norm(item.province);
    if (city.isNotEmpty) return city;
    if (district.isNotEmpty) return district;
    return province;
  }

  int _homeSourcePriority(LiveMandiRate item) {
    return MandiHomePresenter.sourcePriorityFromRate(item);
  }

  String _normalizedHomeUnitKey(String value) {
    return MandiHomePresenter.normalizeHomeUnitKey(value);
  }

  bool _isAllowedUnitForHomeCommodity(String commodity, String unit) {
    return MandiHomePresenter.isAllowedUnitForCommodity(commodity, unit);
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

    final remaining = rates
        .where((item) => !tickerIds.contains(item.id))
        .toList(growable: false);

    // Apply snapshot commodity diversity: max snapshotCommodityCap per commodity.
    final snapshotCap = MandiHomePresenter.snapshotCommodityCap;
    final snapshotCommodityCount = <String, int>{};
    final snapshotCommodityLocalitySeen = <String>{};
    final cards = <LiveMandiRate>[];
    final pool = remaining.isNotEmpty
        ? remaining
        : rates
              .skip(math.min(ticker.length, rates.length))
              .toList(growable: false);

    // Sort snapshot candidates by priority, freshness.
    final sortedPool = List<LiveMandiRate>.from(pool)
      ..sort((a, b) {
        final aPri = _commodityPriorityScore(a);
        final bPri = _commodityPriorityScore(b);
        if (aPri != bPri) return aPri.compareTo(bPri);
        final freshCmp = _freshnessWeight(b).compareTo(_freshnessWeight(a));
        if (freshCmp != 0) return freshCmp;
        return b.lastUpdated.compareTo(a.lastUpdated);
      });

    for (final item in sortedPool) {
      if (cards.length >= 8) break;
      final commodity = _normalizeHomeCommodity(item);
      final locality = _homeLocationKey(item);
      final commodityLocalityKey = '$commodity|$locality';
      if (commodity.isNotEmpty &&
          locality.isNotEmpty &&
          snapshotCommodityLocalitySeen.contains(commodityLocalityKey)) {
        continue;
      }
      final count = snapshotCommodityCount[commodity] ?? 0;
      if (commodity.isNotEmpty && count >= snapshotCap) {
        debugPrint(
          '[MandiHome] diversity_skip_reason=snapshot_commodity_cap '
          'commodity=$commodity',
        );
        continue;
      }
      cards.add(item);
      if (commodity.isNotEmpty) {
        snapshotCommodityCount[commodity] = count + 1;
        if (locality.isNotEmpty) {
          snapshotCommodityLocalitySeen.add(commodityLocalityKey);
        }
      }
    }

    // If diversity filter left cards empty, fall back to first available.
    if (cards.isEmpty) {
      cards.addAll(sortedPool.take(8));
    }

    debugPrint(
      '[MandiHome] final_home_snapshot_diversity_count='
      '${snapshotCommodityCount.keys.length}',
    );

    final forcedTicker = MandiHomePresenter.forceWheatLeadInDisplayList(
      ticker,
      maxItems: 12,
      requireTickerEligibility: true,
    );
    final forcedCards = MandiHomePresenter.forceWheatLeadInDisplayList(
      cards.take(8).toList(growable: false),
      maxItems: 8,
    );

    return _TickerCardsSplit(ticker: forcedTicker, cards: forcedCards);
  }

  _TickerCardsSplit _ensureRequiredWheatVisibility(
    _TickerCardsSplit split, {
    required List<LiveMandiRate> pool,
    required MandiLocationContext location,
  }) {
    final wheatPool = pool.where(_isWheatCommodity).toList(growable: false);
    if (wheatPool.isEmpty) {
      return split;
    }

    final rankedWheat = _rankWheatForVisibility(wheatPool, location);
    var ticker = List<LiveMandiRate>.from(split.ticker);
    var cards = List<LiveMandiRate>.from(split.cards);

    final tickerHasWheat = ticker.any(_isVisibleTickerWheat);
    if (!tickerHasWheat) {
      LiveMandiRate? tickerCandidate;
      for (final item in rankedWheat) {
        if (_isVisibleTickerWheat(item)) {
          tickerCandidate = item;
          break;
        }
      }
      if (tickerCandidate != null) {
        final selected = tickerCandidate;
        final existing = ticker.indexWhere((row) => row.id == selected.id);
        if (existing >= 0) {
          final moved = ticker.removeAt(existing);
          ticker.insert(0, moved);
        } else {
          if (ticker.length >= 12) {
            final removable = ticker.lastIndexWhere(
              (row) => !_isWheatCommodity(row),
            );
            if (removable >= 0) {
              ticker.removeAt(removable);
            } else {
              ticker.removeLast();
            }
          }
          ticker.insert(0, selected);
        }
      }
    }

    // Hard-lock rule: if any renderable ticker wheat exists, it must lead.
    final visibleTickerWheat = rankedWheat
        .where(_isVisibleTickerWheat)
        .toList(growable: false);
    if (visibleTickerWheat.isNotEmpty) {
      final lead = MandiHomePresenter.pickBestWheatLeadCandidate(
        visibleTickerWheat,
        requireTickerEligibility: true,
      );
      if (lead != null) {
        final existing = ticker.indexWhere((row) => row.id == lead.id);
        if (existing >= 0) {
          final moved = ticker.removeAt(existing);
          ticker.insert(0, moved);
        } else {
          if (ticker.length >= 12) {
            final removable = ticker.lastIndexWhere(
              (row) => !_isWheatCommodity(row),
            );
            if (removable >= 0) {
              ticker.removeAt(removable);
            } else {
              ticker.removeLast();
            }
          }
          ticker.insert(0, lead);
        }
      }
    }

    final snapshotHasWheat = cards.any(_isVisibleSnapshotWheat);
    if (!snapshotHasWheat) {
      LiveMandiRate? snapshotCandidate;
      for (final item in rankedWheat) {
        if (_isVisibleSnapshotWheat(item)) {
          snapshotCandidate = item;
          break;
        }
      }
      if (snapshotCandidate != null) {
        final selected = snapshotCandidate;
        final existing = cards.indexWhere((row) => row.id == selected.id);
        if (existing >= 0) {
          final moved = cards.removeAt(existing);
          cards.insert(0, moved);
        } else {
          if (cards.length >= 8) {
            final removable = cards.lastIndexWhere(
              (row) => !_isWheatCommodity(row),
            );
            if (removable >= 0) {
              cards.removeAt(removable);
            } else {
              cards.removeLast();
            }
          }
          cards.insert(0, selected);
        }
      }
    }

    // Mirror the same lead guarantee for snapshot/cards surface.
    final visibleSnapshotWheat = rankedWheat
        .where(_isVisibleSnapshotWheat)
        .toList(growable: false);
    if (visibleSnapshotWheat.isNotEmpty) {
      final lead = MandiHomePresenter.pickBestWheatLeadCandidate(
        visibleSnapshotWheat,
      );
      if (lead != null) {
        final existing = cards.indexWhere((row) => row.id == lead.id);
        if (existing >= 0) {
          final moved = cards.removeAt(existing);
          cards.insert(0, moved);
        } else {
          if (cards.length >= 8) {
            final removable = cards.lastIndexWhere(
              (row) => !_isWheatCommodity(row),
            );
            if (removable >= 0) {
              cards.removeAt(removable);
            } else {
              cards.removeLast();
            }
          }
          cards.insert(0, lead);
        }
      }
    }

    return _TickerCardsSplit(
      ticker: ticker.take(12).toList(growable: false),
      cards: cards.take(8).toList(growable: false),
    );
  }

  List<LiveMandiRate> _rankWheatForVisibility(
    List<LiveMandiRate> wheat,
    MandiLocationContext location,
  ) {
    if (wheat.length <= 1) return wheat;
    final nearestDistricts = _nearestDistricts(location);
    final ranked = List<LiveMandiRate>.from(wheat)
      ..sort((a, b) {
        final tierA = _locationTier(a, location, nearestDistricts);
        final tierB = _locationTier(b, location, nearestDistricts);
        if (tierA != tierB) return tierA.compareTo(tierB);
        final freshCmp = _freshnessWeight(b).compareTo(_freshnessWeight(a));
        if (freshCmp != 0) return freshCmp;
        final confidenceCmp = b.confidenceScore.compareTo(a.confidenceScore);
        if (confidenceCmp != 0) return confidenceCmp;
        final sourceCmp = _homeSourcePriority(
          a,
        ).compareTo(_homeSourcePriority(b));
        if (sourceCmp != 0) return sourceCmp;
        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    return ranked;
  }

  bool _isWheatCommodity(LiveMandiRate rate) {
    return _normalizeHomeCommodity(rate) == 'wheat';
  }

  bool _isVisibleTickerWheat(LiveMandiRate rate) {
    if (!_isWheatCommodity(rate)) return false;
    if (!rate.isTickerPriceEligible) return false;
    return _isRenderableForPath(rate, MandiHomeRenderPath.ticker);
  }

  bool _isVisibleSnapshotWheat(LiveMandiRate rate) {
    if (!_isWheatCommodity(rate)) return false;
    return _isRenderableForPath(rate, MandiHomeRenderPath.card);
  }

  bool _isRenderableForPath(LiveMandiRate rate, MandiHomeRenderPath path) {
    final commodityKey = _normalizeHomeCommodity(rate);
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
      price: getTrustedDisplayPrice(rate),
      sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
      confidence: rate.confidenceScore,
      renderPath: path,
    );
    return row.isRenderable;
  }

  String _proofRowSummary(LiveMandiRate rate, MandiHomeRenderPath path) {
    final commodityKey = _normalizeHomeCommodity(rate);
    if (!MandiHomePresenter.isAllowlistedCommodity(commodityKey)) {
      return 'non_allowlisted_row';
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
      price: getTrustedDisplayPrice(rate),
      sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
      confidence: rate.confidenceScore,
      renderPath: path,
    );
    if (!row.isRenderable) {
      return 'non_renderable_row';
    }
    return path == MandiHomeRenderPath.ticker
        ? row.fullTickerLine
        : row.fullSnapshotLine;
  }

  void _logFinalHomeSurfaceProof(_TickerCardsSplit split) {
    final tickerPreview = split.ticker.take(6).toList(growable: false);
    for (var i = 0; i < tickerPreview.length; i++) {
      final row = tickerPreview[i];
      final summary = _proofRowSummary(row, MandiHomeRenderPath.ticker);
      debugPrint('[MandiProof] final_visible_home_ticker_row=$summary');
      if (_isVisibleTickerWheat(row)) {
        debugPrint(
          '[MandiProof] wheat_visible_rank=${i + 1} surface=home_ticker',
        );
      }
    }

    final snapshotPreview = split.cards.take(6).toList(growable: false);
    for (var i = 0; i < snapshotPreview.length; i++) {
      final row = snapshotPreview[i];
      final summary = _proofRowSummary(row, MandiHomeRenderPath.card);
      debugPrint('[MandiProof] final_visible_snapshot_row=$summary');
      if (_isVisibleSnapshotWheat(row)) {
        debugPrint('[MandiProof] wheat_visible_rank=${i + 1} surface=snapshot');
      }
    }
  }

  List<LiveMandiRate> _diversifyForTicker(
    List<LiveMandiRate> rates, {
    int maxItems = 12,
  }) {
    if (rates.isEmpty) return const <LiveMandiRate>[];

    // Sort by commodity priority, then nearby, freshness, recency.
    final sorted = List<LiveMandiRate>.from(rates)
      ..sort((a, b) {
        final aPri = _commodityPriorityScore(a);
        final bPri = _commodityPriorityScore(b);
        if (aPri != bPri) return aPri.compareTo(bPri);
        if (a.isNearby != b.isNearby) return a.isNearby ? -1 : 1;
        final freshness = _freshnessWeight(b).compareTo(_freshnessWeight(a));
        if (freshness != 0) return freshness;
        return b.lastUpdated.compareTo(a.lastUpdated);
      });

    final result = <LiveMandiRate>[];
    final commodityCount = <String, int>{};
    final seenCommodityCityPairs = <String>{};
    final tickerCap = MandiHomePresenter.tickerCommodityCap;

    // Pass 1: one row per unique commodity — maximize spread.
    final usedCommodities = <String>{};
    for (final item in sorted) {
      if (result.length >= maxItems) break;
      final commodity = _normalizeHomeCommodity(item);
      if (commodity.isEmpty || usedCommodities.contains(commodity)) continue;
      final pairKey = '$commodity|${_norm(item.city)}';
      result.add(item);
      usedCommodities.add(commodity);
      seenCommodityCityPairs.add(pairKey);
      commodityCount[commodity] = 1;
      debugPrint(
        '[MandiHome] diversity_candidate_commodity=$commodity '
        'diversity_selected=true pass=1',
      );
    }

    if (result.length >= maxItems) {
      debugPrint(
        '[MandiHome] final_home_ticker_diversity_count=${commodityCount.keys.length}',
      );
      return result.take(maxItems).toList(growable: false);
    }

    // Pass 2: fill remaining slots respecting per-commodity cap.
    for (final item in sorted) {
      if (result.length >= maxItems) break;
      final commodity = _normalizeHomeCommodity(item);
      if (commodity.isEmpty) continue;
      final pairKey = '$commodity|${_norm(item.city)}';
      if (seenCommodityCityPairs.contains(pairKey)) continue;
      final count = commodityCount[commodity] ?? 0;
      if (count >= tickerCap) {
        debugPrint(
          '[MandiHome] diversity_skip_reason=ticker_commodity_cap '
          'commodity=$commodity count=$count',
        );
        continue;
      }
      result.add(item);
      seenCommodityCityPairs.add(pairKey);
      commodityCount[commodity] = count + 1;
      debugPrint(
        '[MandiHome] diversity_candidate_commodity=$commodity '
        'diversity_selected=true pass=2',
      );
    }

    // Pass 3: if still short, allow overflow.
    if (result.length < maxItems) {
      for (final item in sorted) {
        if (result.length >= maxItems) break;
        final pairKey = '${_normalizeHomeCommodity(item)}|${_norm(item.city)}';
        if (seenCommodityCityPairs.add(pairKey)) {
          result.add(item);
        }
      }
    }

    debugPrint(
      '[MandiHome] final_home_ticker_diversity_count=${commodityCount.keys.length}',
    );
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

    // Sort candidates: high-priority commodities first, then by location tier,
    // freshness, and update recency.
    scored.sort((a, b) {
      final aPri = _commodityPriorityScore(a.rate);
      final bPri = _commodityPriorityScore(b.rate);
      if (aPri != bPri) return aPri.compareTo(bPri);
      if (a.tier != b.tier) return a.tier.compareTo(b.tier);
      final freshCmp = _freshnessWeight(
        b.rate,
      ).compareTo(_freshnessWeight(a.rate));
      if (freshCmp != 0) return freshCmp;
      return b.rate.lastUpdated.compareTo(a.rate.lastUpdated);
    });

    final result = <LiveMandiRate>[];
    final seenIds = <String>{};
    final commodityCount = <String, int>{};
    final seenCommodities = <String>{};

    // Pass 1: one row per unique commodity — diversity-first.
    for (final item in scored) {
      if (result.length >= targetCount) break;
      final commodity = _normalizeHomeCommodity(item.rate);
      if (commodity.isEmpty || seenCommodities.contains(commodity)) {
        continue;
      }
      if (seenIds.contains(item.rate.id)) continue;
      result.add(item.rate);
      seenIds.add(item.rate.id);
      seenCommodities.add(commodity);
      commodityCount[commodity] = 1;
      debugPrint(
        '[MandiHome] diversity_selected=true '
        'commodity=$commodity '
        'commodity_priority=${MandiHomePresenter.commodityPriority[commodity] ?? 99} '
        'tier=${item.tier}',
      );
    }

    // Pass 2: allow up to tickerCommodityCap per commodity with remaining slots.
    final tickerCap = MandiHomePresenter.tickerCommodityCap;
    for (final item in scored) {
      if (result.length >= targetCount) break;
      if (seenIds.contains(item.rate.id)) continue;
      final commodity = _normalizeHomeCommodity(item.rate);
      if (commodity.isEmpty) continue;
      final count = commodityCount[commodity] ?? 0;
      if (count >= tickerCap) {
        debugPrint(
          '[MandiHome] diversity_skip_reason=commodity_cap_reached '
          'commodity=$commodity count=$count',
        );
        continue;
      }
      result.add(item.rate);
      seenIds.add(item.rate.id);
      commodityCount[commodity] = count + 1;
    }

    // Pass 3: if still short, allow overflow — never leave Home empty.
    for (final item in scored) {
      if (result.length >= targetCount) break;
      if (seenIds.add(item.rate.id)) {
        result.add(item.rate);
      }
    }

    final distinctCommodities = commodityCount.keys.length;
    debugPrint(
      '[MandiHome] final_home_pool_diversity_count=$distinctCommodities '
      'pool_size=${result.length}',
    );

    return result.take(targetCount).toList(growable: false);
  }

  int _commodityPriorityScore(LiveMandiRate rate) {
    final commodity = _normalizeHomeCommodity(rate);
    return MandiHomePresenter.commodityPriority[commodity] ?? 3;
  }

  _TierStats _tierStats(
    List<LiveMandiRate> rates,
    MandiLocationContext location,
  ) {
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
    if (unit.contains('tray')) return 'per_tray';
    if (unit.contains('crate')) return 'per_crate';
    if (unit.contains('peti')) return 'per_peti';
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
                    'آپ کے قریب منڈی ریٹس',
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'صاف، تازہ اور تصدیق شدہ منڈی قیمتیں',
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
              child: const Text('سب دیکھیں'),
            ),
          ],
        ),
        if (_state.isOfflineFallback)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'آف لائن بیک اپ ڈیٹا دکھایا جا رہا ہے۔',
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
              'ڈیٹا پرانا ہو سکتا ہے۔ سب دیکھیں میں جا کر ریفریش کریں۔',
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
              'تازہ تصدیق شدہ منڈی ریٹس نیچے دکھائے گئے ہیں۔',
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
              'آخری ہم آہنگی: ${_relative(_state.lastSyncedAt!)}',
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
              'لوکیشن اجازت نہ ملنے پر اکاؤنٹ یا فلٹر مقام کو ترجیح دی جا رہی ہے۔',
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
              'لوکیشن سروس بند ہے۔ بیک اپ منڈی سیاق دکھایا جا رہا ہے۔',
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
              'قریب کی منڈی ریٹس دستیاب نہیں، وسیع مارکیٹ دکھائی جا رہی ہے۔',
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
              'تازہ تصدیق شدہ منڈی ریٹس ابھی دستیاب نہیں۔',
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
    return getLocalizedRelativeTime(dateTime, MandiDisplayLanguage.urdu);
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
