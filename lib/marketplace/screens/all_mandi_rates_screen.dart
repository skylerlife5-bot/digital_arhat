import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';
import '../services/mandi_all_presenter.dart';
import '../services/mandi_home_presenter.dart';
import '../services/mandi_rate_location_service.dart';
import '../services/mandi_rate_prioritization_service.dart';
import '../services/mandi_rate_trust_policy_service.dart';
import '../utils/mandi_display_utils.dart';

class AllMandiRatesScreen extends StatefulWidget {
  const AllMandiRatesScreen({
    super.key,
    this.initialCategory,
    this.accountCity,
    this.accountDistrict,
    this.accountProvince,
  });

  final MandiType? initialCategory;
  final String? accountCity;
  final String? accountDistrict;
  final String? accountProvince;

  @override
  State<AllMandiRatesScreen> createState() => _AllMandiRatesScreenState();
}

class _AllMandiRatesScreenState extends State<AllMandiRatesScreen> {
  final MandiRatesRepository _repository = MandiRatesRepository();
  final MandiRateLocationService _locationService =
      const MandiRateLocationService();
  final MandiRatePrioritizationService _ranker =
      const MandiRatePrioritizationService();
    final MandiRateTrustPolicyService _trustPolicy =
      const MandiRateTrustPolicyService();

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  final List<LiveMandiRate> _raw = <LiveMandiRate>[];
  List<LiveMandiRate> _visible = <LiveMandiRate>[];

  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _isOfflineFallback = false;
  String? _error;
  DateTime? _lastSyncedAt;

  // Location resolution cache to reduce redundant resolves during filtering
  MandiLocationContext? _cachedLocation;
  DateTime? _cachedLocationResolvedAt;

  MandiType? _category;
  String? _subcategory;
  String? _mandi;
  String? _city;
  String? _unit;
  String? _source;
  String? _freshness;
  String? _confidence;
  String? _reviewStatus;
  String? _province;
  bool _nearestOnly = false;
  bool _verifiedOnly = false;
  bool _freshToday = false;
  String _sortBy = 'latest';
  bool _broaderMarketFallback = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _scrollController.addListener(_onScroll);
    unawaited(_loadInitial());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 280) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loading = true;
      _error = null;
      _raw.clear();
      // Keep previous _visible results visible during reload instead of showing blank
      _cursor = null;
      _hasMore = true;
    });

    try {
      // Parallelize: refresh upstream and resolve location simultaneously
      final refreshFuture = _repository.refreshFromUpstream();
      final locationFuture = _locationService.resolve(
        fallbackCity: widget.accountCity,
        fallbackDistrict: widget.accountDistrict,
        fallbackProvince: widget.accountProvince,
      );

      await Future.wait([refreshFuture, locationFuture]);
      final location = await locationFuture;

      final scoped = await _repository.fetchLocationAwareCandidates(
        location: location,
        targetCount: 160,
      );

      final source = scoped.isNotEmpty
          ? scoped
          : (await _repository.fetchRatesPage(pageSize: 60)).items;

      _raw
        ..clear()
        // Load data directly – deterministic display-name mapping applied at
        // render time via displayCommodityName/displayUnit getters.
        ..addAll(source);
      _cursor = null;
      _hasMore = true;
      _lastSyncedAt = _deriveLastSyncedAt(_raw);
      _isOfflineFallback = false;
      _error = null;
      // Cache the resolved location for subsequent filters
      _cachedLocation = location;
      _cachedLocationResolvedAt = DateTime.now();
      await _recomputeVisible();
    } catch (e) {
      debugPrint('[MANDI_FIRESTORE_ERROR] Firestore load failed in AllMandiRatesScreen: $e');
      _raw.clear();
      _lastSyncedAt = null;
      _isOfflineFallback = false;
      _error = e.toString();
      await _recomputeVisible();
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.fetchRatesPage(
        pageSize: 60,
        startAfter: _cursor,
      );
      _raw.addAll(page.items);
      _cursor = page.cursor;
      _hasMore = page.hasMore;
      _lastSyncedAt = _deriveLastSyncedAt(_raw);
      await _recomputeVisible();
    } finally {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _recomputeVisible() async {
    // Use cached location if recent (< 5 min), otherwise resolve fresh
    final now = DateTime.now();
    final isCacheStale = _cachedLocation == null ||
        _cachedLocationResolvedAt == null ||
        now.difference(_cachedLocationResolvedAt!).inMinutes > 5;

    final location = isCacheStale
        ? (await _locationService.resolve(
              fallbackCity: widget.accountCity,
              fallbackDistrict: widget.accountDistrict,
              fallbackProvince: widget.accountProvince,
            ))
        : _cachedLocation!;

    // Cache the resolved location for subsequent filters
    _cachedLocation = location;
    _cachedLocationResolvedAt = now;

    var list = List<LiveMandiRate>.from(_raw);
    final freshness = (_freshness ?? '').trim().toLowerCase();
    final confidence = (_confidence ?? '').trim().toLowerCase();
    final review = (_reviewStatus ?? '').trim().toLowerCase();
    final allowLowTrust =
        confidence == 'limited' || confidence == 'review' || review == 'limited';
    final allowStale = freshness == 'stale';

    final preIntegrityCount = list.length;
    final integrityFiltered = list.where((item) {
      if (item.price <= 0) return false;
      if (item.isRejectedContribution) return false;
      if (item.rowConfidence == MandiRowConfidence.rejected) return false;
      if (item.flags.contains('unit_violation') ||
          item.flags.contains('critical_unit_violation') ||
          item.flags.contains('mixed_unit_violation')) {
        return false;
      }
      if (_hasMixedUnitSignals(item.unit, item.displayUnit)) return false;
      if (!allowStale && item.isStale) return false;

      final sourceRank = _trustPolicy.priorityRank(item);
      if (!allowLowTrust && sourceRank > 4) return false;
      if (!allowLowTrust && item.needsReview) return false;
      return true;
    }).toList(growable: false);

    // Safety fallback: avoid blanking the screen when strict gating has no rows.
    if (integrityFiltered.isNotEmpty) {
      list = integrityFiltered;
    }

    // --- Canonical normalization rejection ---
    final preCanonicalCount = list.length;
    list = list.where((item) {
      final normalizedUnit = MandiHomePresenter.normalizeHomeUnitKey(item.unit);
      debugPrint('[MandiAll] parsed_unit_raw=${item.unit}');
      debugPrint('[MandiAll] parsed_unit_normalized=$normalizedUnit');
      final reason = MandiAllPresenter.rejectReason(item);
      if (reason != null) {
        debugPrint(
          '[MandiAll] row_rejected_reason=$reason '
          'commodity=${item.commodityName} city=${item.city}',
        );
        return false;
      }
      return true;
    }).toList(growable: false);
    final postCanonicalCount = list.length;

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((item) {
            final canonicalCommodity = MandiAllPresenter.commodityEnglish(item);
            final canonicalCity = MandiAllPresenter.cityEnglish(item);
            final haystack = [
              item.commodityName,
              canonicalCommodity,
              item.categoryName,
              item.subCategoryName,
              item.mandiName,
              item.city,
              canonicalCity,
              item.district,
              item.province,
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          })
          .toList(growable: false);
    }

    if (_category != null) {
      final needle = _category!.wireValue.toLowerCase();
      list = list
          .where((item) {
            final cat = item.categoryName.toLowerCase();
            final catId = item.categoryId.toLowerCase();
            return cat.contains(needle) || catId.contains(needle);
          })
          .toList(growable: false);
    }

    final sub = (_subcategory ?? '').trim().toLowerCase();
    if (sub.isNotEmpty) {
      list = list
          .where((item) {
            return item.subCategoryId.toLowerCase() == sub ||
                item.subCategoryName.toLowerCase().contains(sub);
          })
          .toList(growable: false);
    }

    final mandi = (_mandi ?? '').trim().toLowerCase();
    if (mandi.isNotEmpty) {
      list = list
          .where((item) => item.mandiName.toLowerCase().contains(mandi))
          .toList(growable: false);
    }

    final city = (_city ?? '').trim().toLowerCase();
    if (city.isNotEmpty) {
      list = list
          .where((item) {
            final canonicalCity = MandiAllPresenter.cityEnglish(item).toLowerCase();
            return item.city.toLowerCase().contains(city) ||
                canonicalCity.contains(city);
          })
          .toList(growable: false);
    }

    final province = (_province ?? '').trim().toLowerCase();
    if (province.isNotEmpty) {
      list = list
          .where((item) => item.province.trim().toLowerCase().contains(province))
          .toList(growable: false);
    }

    final unit = (_unit ?? '').trim().toLowerCase();
    if (unit.isNotEmpty) {
      list = list
          .where((item) {
            final rawUnit = item.unit.toLowerCase();
            final displayUnit = item.displayUnit.toLowerCase();
            return rawUnit.contains(unit) || displayUnit.contains(unit);
          })
          .toList(growable: false);
    }

    final source = (_source ?? '').trim().toLowerCase();
    if (source.isNotEmpty) {
      list = list
          .where((item) {
            final sourceId = item.sourceId.toLowerCase();
            final sourceType = item.sourceType.toLowerCase();
            final sourceName = item.source.toLowerCase();
            return sourceId.contains(source) ||
                sourceType.contains(source) ||
                sourceName.contains(source);
          })
          .toList(growable: false);
    }

    if (freshness.isNotEmpty) {
      list = list.where((item) {
        if (freshness == 'live') return item.isLiveFresh;
        if (freshness == 'recent') return item.isRecentFresh;
        if (freshness == 'aging') {
          return item.freshnessStatus == MandiFreshnessStatus.aging;
        }
        if (freshness == 'stale') return item.isStale;
        return true;
      }).toList(growable: false);
    }

    if (confidence.isNotEmpty) {
      list = list.where((item) {
        final status = item.verificationStatus.trim().toLowerCase();
        if (confidence == 'official') {
          return status.contains('official') || status.contains('verified');
        }
        if (confidence == 'cross') {
          return status.contains('cross');
        }
        if (confidence == 'limited') {
          return status.contains('limited');
        }
        if (confidence == 'review') {
          return status.contains('review') || status.contains('needs');
        }
        return true;
      }).toList(growable: false);
    }

    if (review.isNotEmpty) {
      list = list.where((item) {
        final status = item.reviewStatus.trim().toLowerCase();
        if (review == 'accepted') return status == 'accepted';
        if (review == 'limited') return status == 'limited_confidence';
        if (review == 'needs_review') return status == 'needs_review';
        if (review == 'rejected') return status == 'rejected';
        return true;
      }).toList(growable: false);
    }

    if (_verifiedOnly) {
      list = list.where((item) {
        final status = item.verificationStatus.trim().toLowerCase();
        return status.contains('official') ||
            status.contains('verified') ||
            status.contains('cross');
      }).toList(growable: false);
    }

    if (_freshToday) {
      list = list
          .where((item) => item.isLiveFresh || item.isRecentFresh)
          .toList(growable: false);
    }

    list = _ranker.rank(rates: list, location: location);

    final nearestDistricts = _nearestDistricts(location);
    list = list
        .map((item) {
          final tier = _locationTier(item, location, nearestDistricts);
          return item.copyWith(isNearby: tier <= 2 || item.isNearby);
        })
        .toList(growable: false);

    final hasNearby = list.any((item) => item.isNearby);
    final hasLocation = _hasLocationContext(location);
    _broaderMarketFallback = hasLocation && !hasNearby && list.isNotEmpty;

    if (_nearestOnly) {
      list = list.where((item) => item.isNearby).toList(growable: false);
    }

    final live = list.where((item) => item.isLiveFresh).toList(growable: false);
    final recent = list
        .where((item) => item.isRecentFresh)
        .toList(growable: false);
    final aging = list
        .where((item) => item.freshnessStatus == MandiFreshnessStatus.aging)
        .toList(growable: false);
    final stale = list.where((item) => item.isStale).toList(growable: false);

    if (_sortBy == 'trend') {
      final trendScore = <String, int>{'up': 3, 'same': 2, 'down': 1};
      list.sort((a, b) {
        final aScore = trendScore[a.trend] ?? 0;
        final bScore = trendScore[b.trend] ?? 0;
        final byTrend = bScore.compareTo(aScore);
        if (byTrend != 0) return byTrend;
        return _compareTrustedDeterministic(a, b, location, nearestDistricts);
      });
    } else if (_sortBy == 'confidence') {
      list.sort((a, b) {
        final confidenceCompare = b.confidenceScore.compareTo(a.confidenceScore);
        if (confidenceCompare != 0) return confidenceCompare;
        return _compareTrustedDeterministic(a, b, location, nearestDistricts);
      });
    } else if (_sortBy == 'nearby') {
      list.sort((a, b) {
        final tierA = _locationTier(a, location, nearestDistricts);
        final tierB = _locationTier(b, location, nearestDistricts);
        final tierCompare = tierA.compareTo(tierB);
        if (tierCompare != 0) return tierCompare;
        return _compareTrustedDeterministic(a, b, location, nearestDistricts);
      });
    } else {
      list = <LiveMandiRate>[...live, ...recent, ...aging, ...stale];
      list.sort((a, b) {
        return _compareTrustedDeterministic(a, b, location, nearestDistricts);
      });
    }

    list = _ensureWheatNearTopVisible(
      list,
      location: location,
      nearestDistricts: nearestDistricts,
    );

    debugPrint(
      '[MandiAll] filter_applied=raw:$preIntegrityCount '
      'postIntegrity:${integrityFiltered.length} '
      'preCanonical:$preCanonicalCount postCanonical:$postCanonicalCount '
      'final:${list.length} sort:$_sortBy '
      'province:${province.isEmpty ? '-' : province} '
      'freshness:${freshness.isEmpty ? '-' : freshness} '
      'confidence:${confidence.isEmpty ? '-' : confidence} '
      'verifiedOnly:$_verifiedOnly freshToday:$_freshToday '
      'nearestOnly:$_nearestOnly broaderFallback:$_broaderMarketFallback',
    );
    if (list.isNotEmpty) {
      final preview = list.take(8).toList(growable: false);
      for (var i = 0; i < preview.length; i++) {
        final row = preview[i];
        final srcRank = MandiAllPresenter.sourceRank(row);
        final summaryRow =
            '${MandiAllPresenter.commodityEnglish(row)} '
            '${MandiAllPresenter.cityEnglish(row)} '
          '${row.price.toStringAsFixed(0)} '
            '${MandiAllPresenter.unitEnglish(row)}';
        debugPrint('[MandiProof] final_visible_all_mandi_row=$summaryRow');
        if (_isWheatRate(row)) {
          debugPrint('[MandiProof] wheat_visible_rank=${i + 1} surface=all_mandi');
        }
        // TEMP TRACE: all_mandi visible row
        debugPrint('[MandiProof] all_mandi_visible_row docId=${row.id} commodity=${MandiAllPresenter.commodityEnglish(row)} city=${MandiAllPresenter.cityEnglish(row)}');
        debugPrint(
          '[MandiAll] visible_row idx=${i + 1} '
          'commodity=${MandiAllPresenter.commodityEnglish(row)} '
          'city=${MandiAllPresenter.cityEnglish(row)} '
          'price=${row.price.toStringAsFixed(0)} '
          'unit=${MandiAllPresenter.unitEnglish(row)} '
          'freshness=${row.freshnessStatus.name}',
        );
        debugPrint(
          '[MandiAll] visible_row=${MandiAllPresenter.commodityEnglish(row)} '
          '${MandiAllPresenter.cityEnglish(row)} '
          '${row.price.toStringAsFixed(0)} '
          '${MandiAllPresenter.unitEnglish(row)}',
        );
        debugPrint(
          '[MandiAll] source_selected=${row.sourceId} '
          'rank=$srcRank confidence=${row.confidenceScore.toStringAsFixed(2)}',
        );
      }
    }

    if (!mounted) return;
    setState(() {
      _visible = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    final staleNotice =
        _lastSyncedAt != null &&
        DateTime.now().toUtc().difference(_lastSyncedAt!).inHours > 24;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('All Mandi Rates / تمام منڈی ریٹس'),
        backgroundColor: AppColors.accentGold,
        foregroundColor: AppColors.ctaTextDark,
      ),
      body: RefreshIndicator(
        color: AppColors.accentGold,
        onRefresh: _loadInitial,
        child: Column(
          children: [
            // Thin refresh-progress bar visible when reloading with existing data
            if (_loading && _visible.isNotEmpty)
              const LinearProgressIndicator(
                color: AppColors.accentGold,
                minHeight: 2,
              ),
            if (staleNotice)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: AppColors.urgencyRed.withValues(alpha: 0.2),
                child: const Text(
                  'Some rates are stale (>24h). Pull to refresh. / کچھ ریٹس پرانے ہیں (24 گھنٹے سے زائد)، ریفریش کریں۔',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 11.6,
                  ),
                ),
              ),
            if (_isOfflineFallback)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: AppColors.secondarySurface.withValues(alpha: 0.65),
                child: const Text(
                  'Offline fallback active. Showing last known rates. / آف لائن بیک اپ فعال ہے، آخری معلوم ریٹس دکھائے جا رہے ہیں۔',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 11.4,
                  ),
                ),
              ),
            if (_broaderMarketFallback)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                color: AppColors.secondarySurface.withValues(alpha: 0.45),
                child: const Text(
                  'No nearby mandi rates found. Showing broader market. / قریب کی منڈی ریٹس دستیاب نہیں، وسیع مارکیٹ دکھائی جا رہی ہے۔',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 11.2,
                  ),
                ),
              ),
            if (_lastSyncedAt != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Text(
                  'Last sync: ${_relative(_lastSyncedAt!)}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.8,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (_) => unawaited(_recomputeVisible()),
                    style: const TextStyle(color: AppColors.primaryText),
                    decoration: InputDecoration(
                      hintText: 'Search commodity or mandi / تلاش کریں',
                      hintStyle: const TextStyle(
                        color: AppColors.secondaryText,
                      ),
                      filled: true,
                      fillColor: AppColors.primaryText.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.primaryText.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 170,
                          child: TextField(
                            onChanged: (value) {
                              _subcategory = value.trim().isEmpty
                                  ? null
                                  : value.trim();
                              unawaited(_recomputeVisible());
                            },
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Subcategory / ذیلی زمرہ',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            onChanged: (value) {
                              _mandi = value.trim().isEmpty
                                  ? null
                                  : value.trim();
                              unawaited(_recomputeVisible());
                            },
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Mandi / منڈی',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 170,
                          child: TextField(
                            onChanged: (value) {
                              _city = value.trim().isEmpty ? null : value.trim();
                              unawaited(_recomputeVisible());
                            },
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'City / شہر',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 150,
                          child: TextField(
                            onChanged: (value) {
                              _unit = value.trim().isEmpty ? null : value.trim();
                              unawaited(_recomputeVisible());
                            },
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'Unit / اکائی',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<MandiType?>(
                          value: _category,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Category'),
                          items: <DropdownMenuItem<MandiType?>>[
                            const DropdownMenuItem<MandiType?>(
                              value: null,
                              child: Text('All Categories / سب'),
                            ),
                            ...MandiType.values.map(
                              (value) => DropdownMenuItem<MandiType?>(
                                value: value,
                                child: Text(value.label),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _category = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: _sortBy,
                          dropdownColor: AppColors.cardSurface,
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem(
                              value: 'latest',
                              child: Text('Latest / تازہ ترین'),
                            ),
                            DropdownMenuItem(
                              value: 'confidence',
                              child: Text('Confidence / اعتماد'),
                            ),
                            DropdownMenuItem(
                              value: 'nearby',
                              child: Text('Nearby Relevance / نزدیکی'),
                            ),
                            DropdownMenuItem(
                              value: 'trend',
                              child: Text('Trend / رجحان'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _sortBy = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _source,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Source'),
                          items: const <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Sources / سب ذرائع'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'amis_official',
                              child: Text('AMIS Official'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'lahore_official_market_rates',
                              child: Text('Lahore Official'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'karachi_official_price_lists',
                              child: Text('Karachi Official'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _source = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _freshness,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Freshness'),
                          items: const <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Freshness / سب'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'live',
                              child: Text('Live'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'recent',
                              child: Text('Recent'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'aging',
                              child: Text('Aging'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'stale',
                              child: Text('Stale'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _freshness = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _confidence,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Confidence'),
                          items: const <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Confidence / سب'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'official',
                              child: Text('Official Verified'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'cross',
                              child: Text('Cross-Checked'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'limited',
                              child: Text('Limited Confidence'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'review',
                              child: Text('مزید جانچ درکار'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _confidence = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _reviewStatus,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Review'),
                          items: const <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Review / سب'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'accepted',
                              child: Text('Accepted'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'limited',
                              child: Text('Limited Confidence'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'needs_review',
                              child: Text('مزید جانچ درکار'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'rejected',
                              child: Text('Rejected'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _reviewStatus = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        DropdownButton<String?>(
                          value: _province,
                          dropdownColor: AppColors.cardSurface,
                          hint: const Text('Province'),
                          items: const <DropdownMenuItem<String?>>[
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text('All Provinces'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Punjab',
                              child: Text('Punjab'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Sindh',
                              child: Text('Sindh'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'KPK',
                              child: Text('KPK'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Balochistan',
                              child: Text('Balochistan'),
                            ),
                            DropdownMenuItem<String?>(
                              value: 'Islamabad',
                              child: Text('ICT'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _province = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _nearestOnly,
                          label: const Text('Nearest / قریب ترین'),
                          onSelected: (value) {
                            setState(() => _nearestOnly = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _verifiedOnly,
                          label: const Text('Verified Only'),
                          onSelected: (value) {
                            setState(() => _verifiedOnly = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          selected: _freshToday,
                          label: const Text('Fresh Today'),
                          onSelected: (value) {
                            setState(() => _freshToday = value);
                            unawaited(_recomputeVisible());
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: () {
                if (_loading && _visible.isEmpty) {
                  return _buildLoadingSkeleton();
                }
                if (_error != null && _visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Unable to load mandi rates. / منڈی ریٹس لوڈ نہ ہو سکے۔',
                            style: TextStyle(color: AppColors.primaryText),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loadInitial,
                            child: const Text('Retry / دوبارہ کوشش کریں'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (_visible.isEmpty) {
                  return const Center(
                    child: Text(
                      'No mandi rates found for selected filters. / منتخب فلٹرز کے مطابق ڈیٹا نہیں ملا۔',
                      style: TextStyle(color: AppColors.secondaryText),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                  itemCount: _visible.length + (_loadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index >= _visible.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.accentGold,
                          ),
                        ),
                      );
                    }

                    final rate = _visible[index];
                    final commodityKey = MandiHomePresenter.normalizeCommodityKey(
                      '${rate.metadata['urduName'] ?? ''} ${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}',
                    );
                    if (!MandiHomePresenter.isAllowlistedCommodity(commodityKey)) {
                      return const SizedBox.shrink();
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
                      renderPath: MandiHomeRenderPath.card,
                    );
                    if (!row.isRenderable) {
                      return const SizedBox.shrink();
                    }
                    final formattedUnit = formatUnitDisplay(rate.unit);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.secondarySurface),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  row.commodityDisplay,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  row.cityDisplay,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 11.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                row.priceDisplay,
                                style: const TextStyle(
                                  color: Color(0xFFEFD88A),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (rate.isSuspiciousRate)
                                const Text(
                                  'مزید جانچ درکار',
                                  style: TextStyle(
                                    color: AppColors.urgencyRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              if (formattedUnit.trim().isNotEmpty)
                                Text(
                                  formattedUnit,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 10.5,
                                  ),
                                )
                              else
                                Text(
                                  rate.trendSymbol,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 10.5,
                                  ),
                                ),
                              Text(
                                rate.freshnessLabel,
                                style: TextStyle(
                                  color: rate.isStale
                                      ? AppColors.urgencyRed
                                      : AppColors.secondaryText,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              }(),
            ),
          ],
        ),
      ),
    );
  }

  /// Loading skeleton shown on first open when no cached data is available.
  Widget _buildLoadingSkeleton() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      itemCount: 10,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.secondarySurface),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonBar(width: 120, height: 13),
                    const SizedBox(height: 6),
                    _skeletonBar(width: 160, height: 10),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _skeletonBar(width: 70, height: 14),
                  const SizedBox(height: 4),
                  _skeletonBar(width: 50, height: 10),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _skeletonBar({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  int _freshnessRank(LiveMandiRate item) {
    if (item.isLiveFresh) return 4;
    if (item.isRecentFresh) return 3;
    if (item.freshnessStatus == MandiFreshnessStatus.aging) return 2;
    if (item.isStale) return 1;
    return 0;
  }

  DateTime? _deriveLastSyncedAt(List<LiveMandiRate> rates) {
    if (rates.isEmpty) return null;
    final candidates = rates
        .map((item) => item.syncedAt ?? item.lastUpdated)
        .whereType<DateTime>()
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates
        .map((item) => item.toUtc())
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  String _relative(DateTime dateTime) {
    final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  bool _hasLocationContext(MandiLocationContext location) {
    return location.city.trim().isNotEmpty ||
        location.district.trim().isNotEmpty ||
        location.province.trim().isNotEmpty ||
        location.locationAvailable;
  }

  Set<String> _nearestDistricts(MandiLocationContext location) {
    final current = location.district.trim().toLowerCase();
    if (current.isEmpty) return <String>{};

    final districts = <String>{current};
    for (final entry in AppConstants.districtDistancePairsKm.entries) {
      if (entry.value > 220) continue;
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final a = parts[0].trim().toLowerCase();
      final b = parts[1].trim().toLowerCase();
      if (a == current) districts.add(b);
      if (b == current) districts.add(a);
    }
    return districts;
  }

  int _locationTier(
    LiveMandiRate rate,
    MandiLocationContext location,
    Set<String> nearestDistricts,
  ) {
    final city = location.city.trim().toLowerCase();
    final district = location.district.trim().toLowerCase();
    final province = location.province.trim().toLowerCase();

    final rateCity = rate.city.trim().toLowerCase();
    final rateDistrict =
        (rate.district.trim().isNotEmpty ? rate.district : rate.city)
            .trim()
            .toLowerCase();
    final rateProvince = rate.province.trim().toLowerCase();

    if (city.isNotEmpty && rateCity == city) return 0;

    final hasCoords =
        location.locationAvailable && rate.latitude != null && rate.longitude != null;
    if (hasCoords) {
      final km = Geolocator.distanceBetween(
            location.latitude!,
            location.longitude!,
            rate.latitude!,
            rate.longitude!,
          ) /
          1000;
      if (km <= 30) return 1;
    }

    if (district.isNotEmpty && rateDistrict == district) return 2;
    if (rateDistrict.isNotEmpty && nearestDistricts.contains(rateDistrict)) {
      return 2;
    }
    if (province.isNotEmpty && rateProvince == province) return 3;
    return 4;
  }

  int _compareTrustedDeterministic(
    LiveMandiRate a,
    LiveMandiRate b,
    MandiLocationContext location,
    Set<String> nearestDistricts,
  ) {
    final sourceRankA = _trustPolicy.priorityRank(a);
    final sourceRankB = _trustPolicy.priorityRank(b);
    final sourceCompare = sourceRankA.compareTo(sourceRankB);
    if (sourceCompare != 0) return sourceCompare;

    final tierA = _locationTier(a, location, nearestDistricts);
    final tierB = _locationTier(b, location, nearestDistricts);
    final tierCompare = tierA.compareTo(tierB);
    if (tierCompare != 0) return tierCompare;

    final freshnessRankA = _freshnessRank(a);
    final freshnessRankB = _freshnessRank(b);
    final freshnessCompare = freshnessRankB.compareTo(freshnessRankA);
    if (freshnessCompare != 0) return freshnessCompare;

    final confidenceCompare = b.confidenceScore.compareTo(a.confidenceScore);
    if (confidenceCompare != 0) return confidenceCompare;

    final updatedCompare = b.lastUpdated.compareTo(a.lastUpdated);
    if (updatedCompare != 0) return updatedCompare;

    final categoryCompare = a.categoryName.toLowerCase().compareTo(
      b.categoryName.toLowerCase(),
    );
    if (categoryCompare != 0) return categoryCompare;

    final commodityCompare = a.commodityName.toLowerCase().compareTo(
      b.commodityName.toLowerCase(),
    );
    if (commodityCompare != 0) return commodityCompare;

    return a.id.compareTo(b.id);
  }

  bool _hasMixedUnitSignals(String rawUnit, String displayUnit) {
    final source = '$rawUnit $displayUnit'.toLowerCase();
    final hasKg = source.contains('kg') || source.contains('کلو');
    final hasDozen = source.contains('dozen') || source.contains('درجن');
    final hasPiece = source.contains('piece') || source.contains('عدد');
    final has40kg = source.contains('40kg') || source.contains('40 کلو');
    final has100kg = source.contains('100kg') || source.contains('100 کلو');
    if (hasKg && hasDozen) return true;
    if (hasPiece && hasKg) return true;
    if (has40kg && has100kg) return true;
    return false;
  }

  List<LiveMandiRate> _ensureWheatNearTopVisible(
    List<LiveMandiRate> list, {
    required MandiLocationContext location,
    required Set<String> nearestDistricts,
  }) {
    if (list.isEmpty) return list;

    final wheatCandidates = list.where(_isWheatRate).toList(growable: false);
    if (wheatCandidates.isEmpty) return list;

    final hasLahoreWheat = wheatCandidates.any(_isLahoreRate);
    final topWindow = list.take(8).toList(growable: false);
    final hasTopWheat = topWindow.any(_isWheatRate);
    final hasTopLahoreWheat = topWindow.any(
      (row) => _isWheatRate(row) && _isLahoreRate(row),
    );

    if (!hasLahoreWheat && hasTopWheat) return list;
    if (hasLahoreWheat && hasTopLahoreWheat) return list;

    final rankedWheat = List<LiveMandiRate>.from(wheatCandidates)
      ..sort((a, b) {
        final aLahore = _isLahoreRate(a);
        final bLahore = _isLahoreRate(b);
        if (aLahore != bLahore) return bLahore ? 1 : -1;
        return _compareTrustedDeterministic(a, b, location, nearestDistricts);
      });

    final target = rankedWheat.first;
    final existingIndex = list.indexWhere((row) => row.id == target.id);
    if (existingIndex < 0) return list;

    final mutable = List<LiveMandiRate>.from(list);
    final moved = mutable.removeAt(existingIndex);
    final insertIndex = 0;
    mutable.insert(insertIndex, moved);
    return mutable;
  }

  bool _isWheatRate(LiveMandiRate rate) {
    final commodity = MandiAllPresenter.commodityEnglish(rate)
        .trim()
        .toLowerCase();
    return commodity == 'wheat' || commodity.contains('wheat');
  }

  bool _isLahoreRate(LiveMandiRate rate) {
    final cityEnglish = MandiAllPresenter.cityEnglish(rate).trim().toLowerCase();
    final cityRaw = rate.city.trim().toLowerCase();
    final districtRaw = rate.district.trim().toLowerCase();
    final mandi = rate.mandiName.trim().toLowerCase();
    return cityEnglish.contains('lahore') ||
        cityRaw.contains('lahore') ||
        cityRaw.contains('لاہور') ||
        districtRaw.contains('lahore') ||
        districtRaw.contains('لاہور') ||
        mandi.contains('lahore') ||
        mandi.contains('لاہور');
  }

}
