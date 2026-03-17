import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';
import '../services/gemini_rate_enhancement_service.dart';
import '../services/mandi_rate_location_service.dart';
import '../services/mandi_rate_prioritization_service.dart';

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
  final GeminiRateEnhancementService _enhancement =
      GeminiRateEnhancementService();
  final MandiRateLocationService _locationService =
      const MandiRateLocationService();
  final MandiRatePrioritizationService _ranker =
      const MandiRatePrioritizationService();

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

  MandiType? _category;
  String? _subcategory;
  String? _mandi;
  String? _city;
  String? _source;
  String? _freshness;
  String? _confidence;
  String? _reviewStatus;
  bool _nearestOnly = false;
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
      _visible = const <LiveMandiRate>[];
      _cursor = null;
      _hasMore = true;
    });

    try {
      await _repository.refreshFromUpstream();
      final location = await _locationService.resolve(
        fallbackCity: widget.accountCity,
        fallbackDistrict: widget.accountDistrict,
        fallbackProvince: widget.accountProvince,
      );

      final scoped = await _repository.fetchLocationAwareCandidates(
        location: location,
        targetCount: 160,
      );

      final source = scoped.isNotEmpty
          ? scoped
          : (await _repository.fetchRatesPage(pageSize: 60)).items;

      _raw
        ..clear()
        ..addAll(await _enhancement.enhanceBatch(source, maxItems: source.length));
      _cursor = null;
      _hasMore = true;
      _lastSyncedAt = _deriveLastSyncedAt(_raw);
      _isOfflineFallback = false;
      await _recomputeVisible();
    } catch (e) {
      final fallback = await _repository.loadOfflineFallback();
      _raw
        ..clear()
        ..addAll(fallback);
      _lastSyncedAt = _deriveLastSyncedAt(_raw);
      _isOfflineFallback = true;
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
    final location = await _locationService.resolve(
      fallbackCity: widget.accountCity,
      fallbackDistrict: widget.accountDistrict,
      fallbackProvince: widget.accountProvince,
    );

    var list = List<LiveMandiRate>.from(_raw);

    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      list = list
          .where((item) {
            final haystack = [
              item.commodityName,
              item.categoryName,
              item.subCategoryName,
              item.mandiName,
              item.city,
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
          .where((item) => item.city.toLowerCase().contains(city))
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

    final freshness = (_freshness ?? '').trim().toLowerCase();
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

    final confidence = (_confidence ?? '').trim().toLowerCase();
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

    final review = (_reviewStatus ?? '').trim().toLowerCase();
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
        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    } else if (_sortBy == 'confidence') {
      list.sort((a, b) {
        final confidenceCompare = b.confidenceScore.compareTo(a.confidenceScore);
        if (confidenceCompare != 0) return confidenceCompare;

        final freshnessRankA = _freshnessRank(a);
        final freshnessRankB = _freshnessRank(b);
        final freshnessCompare = freshnessRankB.compareTo(freshnessRankA);
        if (freshnessCompare != 0) return freshnessCompare;

        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    } else if (_sortBy == 'nearby') {
      list.sort((a, b) {
        final tierA = _locationTier(a, location, nearestDistricts);
        final tierB = _locationTier(b, location, nearestDistricts);
        final tierCompare = tierA.compareTo(tierB);
        if (tierCompare != 0) return tierCompare;

        final confidenceCompare = b.confidenceScore.compareTo(a.confidenceScore);
        if (confidenceCompare != 0) return confidenceCompare;

        return b.lastUpdated.compareTo(a.lastUpdated);
      });
    } else {
      list = <LiveMandiRate>[...live, ...recent, ...aging, ...stale];
      list.sort((a, b) {
        final tierA = _locationTier(a, location, nearestDistricts);
        final tierB = _locationTier(b, location, nearestDistricts);
        final tierCompare = tierA.compareTo(tierB);
        if (tierCompare != 0) return tierCompare;

        final freshnessRankA = _freshnessRank(a);
        final freshnessRankB = _freshnessRank(b);
        final freshnessCompare = freshnessRankB.compareTo(freshnessRankA);
        if (freshnessCompare != 0) return freshnessCompare;

        final catCompare = a.categoryName.toLowerCase().compareTo(
          b.categoryName.toLowerCase(),
        );
        if (catCompare != 0) return catCompare;

        final subCompare = a.subCategoryName.toLowerCase().compareTo(
          b.subCategoryName.toLowerCase(),
        );
        if (subCompare != 0) return subCompare;

        final commodityCompare = a.commodityName.toLowerCase().compareTo(
          b.commodityName.toLowerCase(),
        );
        if (commodityCompare != 0) return commodityCompare;

        return b.lastUpdated.compareTo(a.lastUpdated);
      });
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
                              child: Text('Needs Review'),
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
                              child: Text('Needs Review'),
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
                        FilterChip(
                          selected: _nearestOnly,
                          label: const Text('Nearest / قریب ترین'),
                          onSelected: (value) {
                            setState(() => _nearestOnly = value);
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
                if (_loading) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentGold,
                    ),
                  );
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
                    final trustedPrice = getTrustedDisplayPrice(rate);
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
                                  rate.commodityName,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${rate.mandiName} • ${rate.locationLine}',
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
                                '${rate.currency} ${trustedPrice.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Color(0xFFEFD88A),
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (rate.displayPriceLabel.isNotEmpty)
                                Text(
                                  rate.displayPriceLabel,
                                  style: const TextStyle(
                                    color: AppColors.secondaryText,
                                    fontSize: 10.1,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              if (rate.isSuspiciousRate)
                                const Text(
                                  'Needs Review',
                                  style: TextStyle(
                                    color: AppColors.urgencyRed,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              Text(
                                '${rate.trendSymbol} ${rate.unit}',
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
}
