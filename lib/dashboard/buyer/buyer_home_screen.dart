import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../core/constants.dart';
import '../../core/market_hierarchy.dart';
import '../../core/seasonal_bakra_mandi_config.dart';
import '../../core/widgets/app_logo.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../routes.dart';
import '../../services/analytics_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/notification_service.dart';
import '../../services/trust_safety_service.dart';
import '../../services/weather_services.dart';
import '../../theme/app_colors.dart';
import '../../marketplace/screens/all_mandi_rates_screen.dart';
import '../../marketplace/services/pakistan_mandi_priority_registry.dart';
import 'bid_bottom_sheet.dart';
import 'watchlist_screen.dart';

const List<MandiType?> _homeCategoryOrder = <MandiType?>[
  MandiType.crops,
  MandiType.seeds,
  MandiType.fruit,
  MandiType.dryFruits,
  MandiType.vegetables,
  MandiType.spices,
  MandiType.livestock,
  MandiType.milk,
  MandiType.fertilizer,
  MandiType.machinery,
  null,
  MandiType.tools,
];

const Map<MandiType, String> _homeCategoryLabels = <MandiType, String>{
  MandiType.crops: 'Crops / فصلیں',
  MandiType.seeds: 'Seeds / بیج',
  MandiType.fruit: 'Fruits / پھل',
  MandiType.dryFruits: 'Dry Fruits / خشک میوہ',
  MandiType.vegetables: 'Vegetables / سبزیاں',
  MandiType.spices: 'Spices / مصالحے',
  MandiType.livestock: 'Livestock / مویشی',
  MandiType.milk: 'Milk & Dairy / دودھ اور ڈیری',
  MandiType.fertilizer: 'Fertilizer / کھاد',
  MandiType.machinery: 'Machinery / مشینری',
  MandiType.tools: 'Tools / اوزار',
};

class BuyerHomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const BuyerHomeScreen({super.key, required this.userData});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  static const bool _mandiDebugLogs = true;
  final MarketplaceService _marketplaceService = MarketplaceService();
  final AnalyticsService _analyticsService = AnalyticsService();
  final WeatherService _weatherService = WeatherService();
  final ScrollController _tickerScrollController = ScrollController();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeListingsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _winnerListingsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _recentlyViewedStream;

  String _searchQuery = '';
  MandiType? _selectedCategory;
  String? _selectedSubcategoryId;
  String? _selectedProvinceFilter;
  String? _selectedDistrictFilter;
  String? _selectedTehsilFilter;
  String? _selectedCityFilter;
  String _selectedSaleType = 'all';
  String _selectedSort = 'newest';
  double? _minPriceFilter;
  double? _maxPriceFilter;
  double? _minQuantityFilter;
  double? _maxQuantityFilter;
  bool _qurbaniOnly = false;
  bool _verifiedOnly = false;
  String _listingDerivedCropContext = 'عمومی فصل';
  List<_MandiTickerItem> _liveMandiTickerItems = const <_MandiTickerItem>[];
  String? _mandiTickerInfoText;
  String _mandiSnapshotContextLabelUr = 'پنجاب';
  String? _mandiSnapshotFallbackNote;

  void _logMandiLine(String prefix, String message) {
    if (!_mandiDebugLogs) return;
    debugPrint('[$prefix] $message');
  }

  void _logMandiDebug(String message) => _logMandiLine('MANDI_DEBUG', message);

  void _logMandiQuery(String message) => _logMandiLine('MANDI_QUERY', message);

  void _logMandiParse(String message) => _logMandiLine('MANDI_PARSE', message);

  void _logMandiReject(String message) => _logMandiLine('MANDI_REJECT', message);

  void _logMandiRender(String message) => _logMandiLine('MANDI_RENDER', message);

  Map<String, dynamic>? _weatherData;
  String _advisory = 'موسم کی معلومات تازہ کی جا رہی ہیں۔';
  String _weatherLocationLabelUr = 'پنجاب';
  bool _isWeatherLoading = true;
  bool _weatherFailed = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _approvedWinnerSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _activeListingsContextSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _mandiRatesSubscription;
  Timer? _tickerAutoScrollTimer;
  Timer? _mandiRatesRefreshTimer;
  final Set<String> _shownWinnerNotifications = <String>{};
  bool _isFilterLocationAssetReady = false;
  List<String> _filterAssetProvinces = const <String>[];
  final Map<String, List<String>> _filterDistrictsByProvince =
      <String, List<String>>{};
  final Map<String, List<String>> _filterTehsilsByDistrict =
      <String, List<String>>{};
  final Map<String, List<String>> _filterCitiesByDistrictTehsil =
      <String, List<String>>{};
  final Map<String, String> _provinceUrduByEn = <String, String>{};
  final Map<String, String> _districtUrduByEn = <String, String>{};
  final Map<String, String> _tehsilUrduByEn = <String, String>{};

  @override
  void initState() {
    super.initState();
    _selectedCategory = null;
    _setupCachedStreams();
    _setupLiveMandiTicker();
    _startTickerAutoScroll();
    unawaited(_loadFilterLocationAsset());
    _loadWeather();
    _listenApprovedWinnerStatus();
  }

  void _setupCachedStreams() {
    debugPrint(
      '[BuyerHome] listings query where isApproved == true; winner stream merged for accepted winners',
    );
    _activeListingsStream = FirebaseFirestore.instance
        .collection('listings')
        .where('isApproved', isEqualTo: true)
        .snapshots();

    _activeListingsContextSubscription?.cancel();
    _activeListingsContextSubscription = _activeListingsStream?.listen((
      snapshot,
    ) {
      _captureListingBasedCropContext(snapshot.docs);
    });

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      _winnerListingsStream = null;
      _recentlyViewedStream = null;
      return;
    }

    _winnerListingsStream = FirebaseFirestore.instance
        .collection('listings')
        .where('winnerId', isEqualTo: currentUserId)
        .snapshots();

    _recentlyViewedStream = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('recentlyViewed')
        .orderBy('viewedAt', descending: true)
        .limit(20)
        .snapshots();
  }

  @override
  void dispose() {
    _approvedWinnerSubscription?.cancel();
    _activeListingsContextSubscription?.cancel();
    _mandiRatesSubscription?.cancel();
    _tickerAutoScrollTimer?.cancel();
    _mandiRatesRefreshTimer?.cancel();
    _tickerScrollController.dispose();
    super.dispose();
  }

  void _setupLiveMandiTicker() {
    _mandiRatesSubscription?.cancel();
    _mandiRatesSubscription = null;

    _refreshMandiTickerFromServer();
    _mandiRatesRefreshTimer?.cancel();
    _mandiRatesRefreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _refreshMandiTickerFromServer();
    });
  }

  Future<void> _refreshMandiTickerFromServer() async {
    try {
      final strategy = await _fetchMandiDocsByStrictLocationStages();
      final parseResult = _parseMandiTickerItemsDetailed(strategy.docs);
      final parsed = parseResult.items;
      final snapshotPreview = _buildNearbyMandiSnapshotItemsForDebug(parsed);
      parseResult.stats.finalSnapshotItems = snapshotPreview.length;
        final tickerCityMix = parsed
          .map((item) => _normalizeLocationToken(item.location))
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
        final tickerSubcategoryMix = parsed
          .map((item) => item.subcategoryKey.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
        final snapshotCityMix = snapshotPreview
          .map((item) => _normalizeLocationToken(item.location))
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
        final snapshotSubcategoryMix = snapshotPreview
          .map((item) => item.subcategoryKey.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList(growable: false);
      _logMandiParse(
        'fetchedDocs=${parseResult.stats.fetchedDocs} parsedValidItems=${parseResult.stats.parsedValidItems} '
        'postQualityFilterItems=${parseResult.stats.postQualityFilterItems} postDedupItems=${parseResult.stats.postDedupItems} '
        'postCityFirstItems=${parseResult.stats.postCityFirstItems} '
        'postSubcategoryDiversificationItems=${parseResult.stats.postSubcategoryDiversificationItems} '
        'finalTickerItems=${parseResult.stats.finalTickerItems} finalSnapshotItems=${parseResult.stats.finalSnapshotItems} '
        'rejectedRecords=${parseResult.stats.rejectedItems}',
      );
      _logMandiReject(
        'invalidPrice=${parseResult.stats.invalidPriceReject} missingCity=${parseResult.stats.missingCityReject} '
        'missingCommodity=${parseResult.stats.missingCommodityReject} untrustedSource=${parseResult.stats.trustedSourceReject} '
        'staleReject=${parseResult.stats.freshnessReject} cityMismatchReject=${parseResult.stats.cityMismatchReject} '
        'outlierReject=${parseResult.stats.outlierReject} '
        'comparabilityReject=${parseResult.stats.comparabilityReject} duplicateReject=${parseResult.stats.duplicateReject} '
        'missingSubcategory=${parseResult.stats.emptySubcategoryReject} nonRenderable=${parseResult.stats.nonRenderableReject}',
      );
      if (parseResult.stats.finalTickerItems <= 1 && parseResult.stats.postDedupItems > 1) {
        _logMandiDebug(
          '[MANDI_COLLAPSE_REASON] collapseAt=postSubcategoryDiversification '
          'postDedupItems=${parseResult.stats.postDedupItems} '
          'postCityFirstItems=${parseResult.stats.postCityFirstItems} '
          'postSubcategoryDiversificationItems=${parseResult.stats.postSubcategoryDiversificationItems} '
          'duplicateReject=${parseResult.stats.duplicateReject} '
          'trustedSourceReject=${parseResult.stats.trustedSourceReject} '
          'freshnessReject=${parseResult.stats.freshnessReject}',
        );
      }
      if (!mounted) return;
      setState(() {
        _mandiSnapshotContextLabelUr = strategy.contextLabelUr;
        _mandiSnapshotFallbackNote = strategy.fallbackNoteUr;
        if (parsed.isNotEmpty) {
          _liveMandiTickerItems = parsed;
          _mandiTickerInfoText = null;
        } else if (_liveMandiTickerItems.isEmpty) {
          _mandiTickerInfoText = 'فی الحال تازہ منڈی ریٹ دستیاب نہیں۔';
        }
      });
      _logMandiRender(
        'stageUsed=${strategy.stageUsed.name} finalTickerRendered=${parsed.length} '
        'finalSnapshotRendered=${snapshotPreview.length} '
        'tickerCityMix=${tickerCityMix.join('|')} tickerSubcategoryMix=${tickerSubcategoryMix.join('|')} '
        'snapshotCityMix=${snapshotCityMix.join('|')} snapshotSubcategoryMix=${snapshotSubcategoryMix.join('|')} '
        'tickerEmptyState=${parsed.isEmpty && (_mandiTickerInfoText ?? '').isNotEmpty}',
      );
      if (_mandiDebugLogs) {
        unawaited(_runForcedLahoreMandiVerification());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mandiSnapshotFallbackNote = 'مقامی منڈی کے ریٹس عارضی طور پر دستیاب نہیں۔';
        if (_liveMandiTickerItems.isEmpty) {
          _mandiTickerInfoText = 'منڈی ریٹ لوڈ نہیں ہو سکے۔';
        }
      });
    }
  }

  Future<_MandiStageFetchResult> _fetchMandiDocsByStrictLocationStages() async {
    final context = await _resolveMandiFetchContext();
    const int stageLimit = 28;
    final exactCityValues = <String>{if (context.cityEn.trim().isNotEmpty) context.cityEn.trim()};
    final cityAliasValues = _expandLocationAliases(<String>{context.cityEn, context.cityUr})
      ..removeWhere((value) => exactCityValues.contains(value.trim()));

    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    var stageBNearestDocsCount = 0;

    void mergeDocs(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      for (final doc in docs) {
        merged[doc.id] = doc;
      }
    }

    bool hasEnough(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
      final parsed = _parseMandiTickerItems(docs);
      return parsed.length >= 6;
    }

    _logMandiDebug(
      'location lat=${context.latitude?.toStringAsFixed(6) ?? 'n/a'} lng=${context.longitude?.toStringAsFixed(6) ?? 'n/a'} '
      'city=${context.cityEn}/${context.cityUr} district=${context.districtEn}/${context.districtUr} '
      'province=${context.provinceEn}/${context.provinceUr} normalizedCity=${_normalizeLocationToken(context.cityEn)} '
      'cityTokens=${exactCityValues.join('|')} cityAliases=${cityAliasValues.join('|')} '
      'nearestCandidates=${context.nearestCityCandidatesEn.join('|')}',
    );

    final stageAExactCityDocs = await _queryMandiRatesByFields(
      fields: const <String>['city'],
      values: exactCityValues,
      limit: stageLimit,
      stageLabel: 'StageA-exactCity',
    );
    mergeDocs(stageAExactCityDocs);

    final stageACityAliasDocs = await _queryMandiRatesByFields(
      fields: const <String>['city', 'mandiName', 'marketName', 'market'],
      values: cityAliasValues,
      limit: stageLimit,
      stageLabel: 'StageA-cityAlias',
    );
    mergeDocs(stageACityAliasDocs);

    _logMandiQuery(
      'stageCounts exactCity=${stageAExactCityDocs.length} cityAlias=${stageACityAliasDocs.length} '
      'nearestCity=0 district=0 province=0 merged=${merged.length}',
    );
    if (hasEnough(merged.values.toList(growable: false))) {
      return _MandiStageFetchResult(
        docs: merged.values.toList(growable: false),
        stageUsed: _MandiFetchStage.exactCity,
        contextLabelUr: context.cityUr,
        fallbackNoteUr: null,
      );
    }

    var hasStageBCity = false;
    for (final nearestCity in context.nearestCityCandidatesEn) {
      final normalizedCandidate = _normalizeLocationToken(nearestCity);
      final normalizedCity = _normalizeLocationToken(context.cityEn);
      if (normalizedCandidate.isEmpty || normalizedCandidate == normalizedCity) {
        continue;
      }
      final docs = await _queryMandiRatesByFields(
        fields: const <String>['city', 'mandiName', 'marketName', 'market'],
        values: _expandLocationAliases(<String>{
          nearestCity,
          _toUrduLocationLabel(nearestCity),
        }),
        limit: stageLimit,
        stageLabel: 'StageB-nearestCity:$nearestCity',
      );
      if (docs.isEmpty) continue;
      hasStageBCity = true;
      stageBNearestDocsCount += docs.length;
      mergeDocs(docs);
      _logMandiQuery(
        'stageCounts exactCity=${stageAExactCityDocs.length} cityAlias=${stageACityAliasDocs.length} '
        'nearestCity=$stageBNearestDocsCount district=0 province=0 merged=${merged.length}',
      );
      if (hasEnough(merged.values.toList(growable: false))) {
        return _MandiStageFetchResult(
          docs: merged.values.toList(growable: false),
          stageUsed: _MandiFetchStage.nearestCity,
          contextLabelUr: _toUrduLocationLabel(nearestCity),
          fallbackNoteUr:
              '${context.cityUr} کے تازہ ریٹس دستیاب نہیں، قریبی منڈی کے ریٹس دکھائے جا رہے ہیں۔',
        );
      }
    }

    final stageCDistrictDocs = await _queryMandiRatesByFields(
      fields: const <String>['district', 'city', 'mandiName'],
      values: _expandLocationAliases(<String>{context.districtEn, context.districtUr}),
      limit: stageLimit,
      stageLabel: 'StageC-district',
    );
    mergeDocs(stageCDistrictDocs);
    _logMandiQuery(
      'stageCounts exactCity=${stageAExactCityDocs.length} cityAlias=${stageACityAliasDocs.length} '
      'nearestCity=$stageBNearestDocsCount district=${stageCDistrictDocs.length} province=0 merged=${merged.length}',
    );
    if (hasEnough(merged.values.toList(growable: false))) {
      return _MandiStageFetchResult(
        docs: merged.values.toList(growable: false),
        stageUsed: _MandiFetchStage.district,
        contextLabelUr: context.districtUr,
        fallbackNoteUr: hasStageBCity
            ? '${context.cityUr} کے تازہ ریٹس دستیاب نہیں، قریبی منڈی کے ریٹس دکھائے جا رہے ہیں۔'
            : '${context.cityUr} کے تازہ ریٹس دستیاب نہیں، ${context.districtUr} منڈی کے ریٹس دکھائے جا رہے ہیں۔',
      );
    }

    final stageDProvinceDocs = await _queryMandiRatesByFields(
      fields: const <String>['province', 'district'],
      values: _expandLocationAliases(<String>{context.provinceEn, context.provinceUr}),
      limit: stageLimit,
      stageLabel: 'StageD-province',
    );
    mergeDocs(stageDProvinceDocs);
    _logMandiQuery(
      'stageCounts exactCity=${stageAExactCityDocs.length} cityAlias=${stageACityAliasDocs.length} '
      'nearestCity=$stageBNearestDocsCount district=${stageCDistrictDocs.length} province=${stageDProvinceDocs.length} '
      'merged=${merged.length}',
    );

    if (merged.isEmpty) {
      final broad = await FirebaseFirestore.instance
          .collection('mandi_rates')
          .orderBy('rateDate', descending: true)
          .limit(stageLimit)
          .get();
      mergeDocs(broad.docs);
      _logMandiQuery('broadFallback docs=${broad.docs.length} merged=${merged.length}');
    }

    return _MandiStageFetchResult(
      docs: merged.values.toList(growable: false),
      stageUsed: _MandiFetchStage.province,
      contextLabelUr: context.provinceUr,
      fallbackNoteUr:
          '${context.cityUr} کے تازہ ریٹس دستیاب نہیں، ${context.provinceUr} کی قریبی منڈی کے ریٹس دکھائے جا رہے ہیں۔',
    );
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryMandiRatesByFields({
    required List<String> fields,
    required Set<String> values,
    required int limit,
    required String stageLabel,
  }) async {
    final out = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    final attemptedValues = values
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList(growable: false);
    _logMandiQuery(
      '$stageLabel querying fields=${fields.join(',')} values=${attemptedValues.join('|')}',
    );

    for (final field in fields) {
      for (final value in attemptedValues) {
        try {
          final snapshot = await FirebaseFirestore.instance
              .collection('mandi_rates')
              .where(field, isEqualTo: value)
              .limit(limit)
              .get();
          final matchedCityValues = snapshot.docs
              .map((doc) {
                final data = doc.data();
                return _firstNonEmpty(<String?>[
                  (data['city'] ?? '').toString(),
                  (data['mandiName'] ?? '').toString(),
                  (data['marketName'] ?? '').toString(),
                  (data['market'] ?? '').toString(),
                ]);
              })
              .where((entry) => entry.trim().isNotEmpty)
              .take(5)
              .toList(growable: false);
          final targetToken = _normalizeLocationToken(value);
          final sameCity = matchedCityValues.isNotEmpty &&
              matchedCityValues.every((entry) {
                final entryToken = _normalizeLocationToken(entry);
                if (entryToken.isEmpty || targetToken.isEmpty) return false;
                return entryToken == targetToken ||
                    entryToken.contains(targetToken) ||
                    targetToken.contains(entryToken);
              });
          _logMandiQuery(
            '$stageLabel field=$field value=$value docs=${snapshot.docs.length} '
            'matchedCities=${matchedCityValues.join('|')} sameCity=$sameCity',
          );
          for (final doc in snapshot.docs) {
            out[doc.id] = doc;
          }
        } catch (error) {
          _logMandiQuery('$stageLabel field=$field value=$value error=$error');
          continue;
        }
      }
    }
    return out.values.toList(growable: false);
  }

  Set<String> _expandLocationAliases(Set<String> base) {
    final out = <String>{};
    for (final raw in base) {
      final value = raw.trim();
      if (value.isEmpty) continue;

      out.add(value);
      out.add(_toCanonicalWeatherDistrict(value));
      out.add(_toUrduLocationLabel(value));

      final lower = value.toLowerCase();
      out.add(lower.replaceAll(' district', '').trim());
      out.add(lower.replaceAll(' city', '').trim());
      out.add(lower.replaceAll(' tehsil', '').trim());

      final urdu = _toUrduLocationLabel(value);
      if (urdu.isNotEmpty) {
        out.add(urdu.replaceAll(' ضلع', '').replaceAll(' شہر', '').trim());
      }
    }
    out.removeWhere((v) => v.trim().isEmpty || v.trim() == 'null');
    return out;
  }

  Future<_MandiFetchContext> _resolveMandiFetchContext() async {
    final live = await _tryDetectLiveWeatherLocation();
    final nearestProbe = await _resolveNearestCityCandidates();
    final citySeed = live?.$1 ??
        _firstNonEmpty(<String?>[
          _selectedCityFilter,
          (widget.userData['city'] ?? '').toString(),
          (widget.userData['cityVillage'] ?? '').toString(),
          _selectedDistrictFilter,
          (widget.userData['district'] ?? '').toString(),
          _selectedProvinceFilter,
          (widget.userData['province'] ?? '').toString(),
        ]);
    final cityEn = _toCanonicalWeatherDistrict(citySeed);
    final cityUr = _toUrduLocationLabel(citySeed.isEmpty ? cityEn : citySeed);

    final districtSeed = _firstNonEmpty(<String?>[
      _selectedDistrictFilter,
      (widget.userData['district'] ?? '').toString(),
      cityEn,
    ]);
    final districtEn = _toCanonicalWeatherDistrict(districtSeed);
    final districtUr = _toUrduLocationLabel(districtSeed.isEmpty ? districtEn : districtSeed);

    final provinceSeed = _firstNonEmpty(<String?>[
      _selectedProvinceFilter,
      (widget.userData['province'] ?? '').toString(),
      'Punjab',
    ]);
    final provinceEn = _toCanonicalWeatherDistrict(provinceSeed);
    final provinceUr = _toUrduLocationLabel(provinceSeed.isEmpty ? provinceEn : provinceSeed);

    _logMandiDebug(
      'resolveContext liveDistrict=${live?.$1 ?? ''} citySeed=$citySeed districtSeed=$districtSeed '
      'provinceSeed=$provinceSeed lat=${nearestProbe.$2?.toStringAsFixed(6) ?? 'n/a'} '
      'lng=${nearestProbe.$3?.toStringAsFixed(6) ?? 'n/a'}',
    );

    return _MandiFetchContext(
      cityEn: cityEn,
      cityUr: cityUr.isEmpty ? _toUrduLocationLabel(cityEn) : cityUr,
      districtEn: districtEn,
      districtUr: districtUr.isEmpty ? _toUrduLocationLabel(districtEn) : districtUr,
      provinceEn: provinceEn,
      provinceUr: provinceUr.isEmpty ? _toUrduLocationLabel(provinceEn) : provinceUr,
      nearestCityCandidatesEn: nearestProbe.$1,
      latitude: nearestProbe.$2,
      longitude: nearestProbe.$3,
    );
  }

  Future<(List<String>, double?, double?)> _resolveNearestCityCandidates() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return (const <String>[], null, null);

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return (const <String>[], null, null);
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return (const <String>[], null, null);

      _logMandiDebug(
        'gps lat=${position.latitude.toStringAsFixed(6)} lng=${position.longitude.toStringAsFixed(6)}',
      );

      final topPriority = PakistanMandiPriorityRegistry.nearestCityCandidates(
        latitude: position.latitude,
        longitude: position.longitude,
        limit: 6,
      );

      final ranked = _knownDistricts
          .map(
            (item) => (
              item.englishDistrict,
              Geolocator.distanceBetween(
                    position!.latitude,
                    position.longitude,
                    item.lat,
                    item.lng,
                  ) /
                  1000,
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => a.$2.compareTo(b.$2));

      final nearestDistance = ranked.map((entry) => entry.$1).take(6).toList(growable: false);
      final merged = <String>[...topPriority, ...nearestDistance];
      final seen = <String>{};
      final nearest = <String>[];
      for (final city in merged) {
        final key = city.trim().toLowerCase();
        if (key.isEmpty) continue;
        if (seen.add(key)) nearest.add(city.trim());
        if (nearest.length >= 6) break;
      }

      _logMandiDebug('nearest mandi candidates=${nearest.join(',')}');
      return (nearest, position.latitude, position.longitude);
    } catch (_) {
      return (const <String>[], null, null);
    }
  }

  void _startTickerAutoScroll() {
    _tickerAutoScrollTimer?.cancel();
    _tickerAutoScrollTimer = Timer.periodic(const Duration(milliseconds: 90), (
      _,
    ) {
      if (!mounted || !_tickerScrollController.hasClients) return;
      final maxExtent = _tickerScrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      final next = _tickerScrollController.offset + 1.4;
      if (next >= maxExtent - 2) {
        _tickerScrollController.jumpTo(0);
      } else {
        _tickerScrollController.jumpTo(next);
      }
    });
  }

  List<_MandiTickerItem> _parseMandiTickerItems(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final result = _parseMandiTickerItemsDetailed(docs);
    _logMandiParse(
      'rawDocs=${result.stats.fetchedDocs} parsedRecords=${result.stats.parsedItems} '
      'rejectedRecords=${result.stats.rejectedItems} finalTickerCandidates=${result.stats.finalTickerCandidates} '
      'finalTickerRendered=${result.items.length}',
    );
    _logMandiReject(
      'invalidPrice=${result.stats.invalidPriceReject} missingCity=${result.stats.missingCityReject} '
      'missingCommodity=${result.stats.missingCommodityReject} untrustedSource=${result.stats.trustedSourceReject} '
      'staleReject=${result.stats.freshnessReject} outlierReject=${result.stats.outlierReject} '
      'comparabilityReject=${result.stats.comparabilityReject} duplicateReject=${result.stats.duplicateReject} '
      'missingSubcategory=${result.stats.emptySubcategoryReject} nonRenderable=${result.stats.nonRenderableReject}',
    );
    return result.items;
  }

  _MandiParseResult _parseMandiTickerItemsDetailed(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final stats = _MandiParseStats(fetchedDocs: docs.length);

    String text(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final value = (map[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    double number(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is num) return value.toDouble();
        final parsed = double.tryParse((value ?? '').toString().trim());
        if (parsed != null && parsed > 0) return parsed;
      }
      return 0;
    }

    DateTime? date(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final value = map[key];
        if (value is Timestamp) return value.toDate().toUtc();
        if (value is DateTime) return value.toUtc();
        if (value is String && value.trim().isNotEmpty) {
          final raw = value.trim();
          final parsed = DateTime.tryParse(raw);
          if (parsed != null) return parsed.toUtc();

          final slash = RegExp(r'^(\d{1,2})[\/-](\d{1,2})[\/-](\d{2,4})$')
              .firstMatch(raw);
          if (slash != null) {
            final day = int.tryParse(slash.group(1) ?? '');
            final month = int.tryParse(slash.group(2) ?? '');
            final yearRaw = int.tryParse(slash.group(3) ?? '');
            if (day != null && month != null && yearRaw != null) {
              final year = yearRaw < 100 ? 2000 + yearRaw : yearRaw;
              try {
                return DateTime.utc(year, month, day);
              } catch (_) {
                // ignore invalid calendar values
              }
            }
          }
        }
      }
      return null;
    }

    String trendFrom(Map<String, dynamic> map) {
      final direction = text(map, const <String>['trendDirection']);
      final lower = direction.toLowerCase();
      if (lower.contains('up') || lower.contains('rise')) return '▲';
      if (lower.contains('down') || lower.contains('fall')) return '▼';

      final change = number(map, const <String>[
        'priceChangePercent',
        'changePercent',
      ]);
      if (change > 0.8) return '▲';
      if (change < -0.8) return '▼';
      return '•';
    }

    int locationTier(Map<String, dynamic> map) {
      final cityTarget = _firstNonEmpty(<String?>[
        _selectedCityFilter,
        (widget.userData['city'] ?? '').toString(),
        (widget.userData['cityVillage'] ?? '').toString(),
      ]);
      final liveDistrict = _weatherLocationLabelUr.trim();
      final districtTarget = _firstNonEmpty(<String?>[
        _selectedDistrictFilter,
        _selectedTehsilFilter,
        liveDistrict,
        (widget.userData['district'] ?? '').toString(),
      ]);
      final provinceTarget = _firstNonEmpty(<String?>[
        _selectedProvinceFilter,
        (widget.userData['province'] ?? '').toString(),
      ]);

      final city = text(map, const <String>['city', 'mandiName', 'marketName']);
      final district = text(map, const <String>['district', 'tehsil']);
      final province = text(map, const <String>['province']);

      bool locationMatches(String source, String target) {
        final s = _normalizeLocationToken(source);
        final t = _normalizeLocationToken(target);
        if (s.isEmpty || t.isEmpty) return false;
        return s == t || s.contains(t) || t.contains(s);
      }

      if (locationMatches(city, cityTarget) || locationMatches(district, cityTarget)) {
        return 1;
      }
      if (locationMatches(city, liveDistrict) || locationMatches(district, liveDistrict)) {
        return 2;
      }
      if (locationMatches(district, districtTarget) || locationMatches(city, districtTarget)) {
        return 3;
      }
      if (locationMatches(province, provinceTarget)) {
        return 4;
      }
      return 8;
    }

    int freshnessScore(Map<String, dynamic> map) {
      final updated = date(map, const <String>[
        'rateDate',
        'rate_date',
        'updatedAt',
        'updated_at',
        'timestamp',
        'scrapedAt',
        'scraped_at',
        'createdAt',
      ]);
      if (updated == null) return 0;
      final hours = DateTime.now().toUtc().difference(updated).inHours;
      if (hours <= 12) return 90;
      if (hours <= 24) return 70;
      if (hours <= 72) return 45;
      if (hours <= 168) return 20;
      return 0;
    }

    double confidenceScoreFrom(Map<String, dynamic> map) {
      final value = number(map, const <String>['confidenceScore', 'confidence']);
      if (value.isFinite && value >= 0 && value <= 1) return value;
      return 0;
    }

    String reviewStatusFrom(Map<String, dynamic> map) {
      return text(map, const <String>['reviewStatus']).toLowerCase();
    }

    String verificationStatusFrom(Map<String, dynamic> map) {
      return text(map, const <String>['verificationStatus']).toLowerCase();
    }

    String contributorTypeFrom(Map<String, dynamic> map) {
      return text(map, const <String>['contributorType']).toLowerCase();
    }

    bool acceptedBySystemFrom(Map<String, dynamic> map) {
      return map['acceptedBySystem'] == true || map['acceptedByAdmin'] == true;
    }

    bool isOfficialRecord(Map<String, dynamic> map) {
      final contributorType = contributorTypeFrom(map);
      final sourceType = text(map, const <String>['sourceType', 'ingestionSource']).toLowerCase();
      if (contributorType.isEmpty || contributorType == 'official') return true;
      return sourceType == 'official_aggregator' ||
          sourceType == 'official_market_committee' ||
          sourceType == 'official_commissioner';
    }

    bool hasStrongOfficialEquivalent({
      required String commodityKey,
      required String locationKey,
      required List<QueryDocumentSnapshot<Map<String, dynamic>>> allDocs,
    }) {
      for (final doc in allDocs) {
        final map = doc.data();
        if (!isOfficialRecord(map)) continue;
        final verification = verificationStatusFrom(map);
        if (verification != 'official verified' && verification != 'cross-checked') {
          continue;
        }
        final conf = confidenceScoreFrom(map);
        if (conf < 0.7) continue;

        final crop = _toUrduCommodityLabel(text(map, const <String>[
          'commodityName',
          'commodityNameUr',
          'cropType',
          'cropName',
          'itemName',
          'product',
        ]));
        final candidateCommodityKey = _normalizeCommodityKey(crop);
        final location = _cleanTickerLocation(_toUrduLocationLabel(text(map, const <String>[
          'mandiName',
          'marketName',
          'market',
          'district',
          'city',
          'tehsil',
          'province',
        ])));
        final candidateLocationKey = _normalizeLocationToken(location);
        if (candidateCommodityKey == commodityKey &&
            candidateLocationKey.isNotEmpty &&
            candidateLocationKey == locationKey) {
          return true;
        }
      }
      return false;
    }

    final candidates = <_TickerCandidate>[];
    final candidateAuditLines = <String>[];
    for (final doc in docs) {
      final data = doc.data();
      final source = text(data, const <String>[
        'source',
        'sourceType',
        'ingestionSource',
      ]).toLowerCase();
      if (source.contains('warmup_seed')) {
        stats.trustedSourceReject++;
        stats.rejectedItems++;
        continue;
      }

      final subcategoryRaw = text(data, const <String>[
        'subCategoryName',
        'subCategoryId',
        'subcategoryLabel',
        'subcategory',
        'categoryName',
        'categoryId',
        'category',
        'mandiType',
        'cropType',
      ]);
      final cropRaw = text(data, const <String>[
        'commodityName',
        'commodityNameUr',
        'cropType',
        'cropName',
        'itemName',
        'product',
      ]);
      final crop = _toUrduCommodityLabel(cropRaw);
      final categoryRaw = text(data, const <String>[
        'categoryName',
        'categoryId',
        'category',
        'mandiType',
      ]);
      if (crop.trim().isEmpty) {
        stats.missingCommodityReject++;
        stats.rejectedItems++;
        continue;
      }

      final district = text(data, const <String>['district', 'city', 'tehsil']);
      final mandiName = text(data, const <String>[
        'mandiName',
        'marketName',
        'market',
      ]);
      final province = text(data, const <String>['province']);
      if (district.trim().isEmpty && mandiName.trim().isEmpty && province.trim().isEmpty) {
        stats.missingCityReject++;
        stats.rejectedItems++;
        continue;
      }

      final price = number(data, const <String>[
        'averagePrice',
        'average',
        'rate',
        'price',
      ]);
      if (price <= 0) {
        stats.invalidPriceReject++;
        stats.rejectedItems++;
        continue;
      }
      if (price < 5 || price > 5000000) {
        stats.outlierReject++;
        stats.rejectedItems++;
        continue;
      }
      stats.parsedValidItems++;

      final mandiLabel = _cleanTickerLocation(_toUrduLocationLabel(mandiName));
      final districtLabel = _cleanTickerLocation(_toUrduLocationLabel(district));
      final provinceLabel = _cleanTickerLocation(_toUrduLocationLabel(province));
      final location = mandiLabel.isNotEmpty
          ? mandiLabel
          : (districtLabel.isNotEmpty
                ? districtLabel
                : (provinceLabel.isNotEmpty ? provinceLabel : 'مقامی ریٹ'));

      final tier = locationTier(data);
      final freshness = freshnessScore(data);
      if (freshness <= 0) {
        stats.freshnessReject++;
        stats.rejectedItems++;
        continue;
      }

      final commodityKey = _normalizeCommodityKey(crop);
      final normalizedCategoryKey = _normalizeSubcategoryKey(
        subcategoryRaw: categoryRaw,
        commodityRaw: cropRaw,
      );
      final subcategoryKey = _normalizeSubcategoryKey(
        subcategoryRaw: subcategoryRaw,
        commodityRaw: cropRaw,
      );
      if (subcategoryKey.isEmpty) {
        stats.emptySubcategoryReject++;
        stats.rejectedItems++;
        continue;
      }

      final contributorType = contributorTypeFrom(data);
      final isOfficial = isOfficialRecord(data);
      if (!isOfficial) {
        final verification = verificationStatusFrom(data);
        final review = reviewStatusFrom(data);
        final confidence = confidenceScoreFrom(data);
        final acceptedBySystem = acceptedBySystemFrom(data);
        final locationKey = _normalizeLocationToken(location);
        final hasStrongOfficial = hasStrongOfficialEquivalent(
          commodityKey: commodityKey,
          locationKey: locationKey,
          allDocs: docs,
        );

        final passesBase = acceptedBySystem &&
            review != 'rejected' &&
            review != 'needs_review' &&
            verification != 'needs review' &&
            confidence >= 0.72;
        final passesWithOfficialPresent = !hasStrongOfficial || confidence >= 0.82;
        final trustedContributor = contributorType == 'verified_mandi_reporter' ||
            contributorType == 'verified_commission_agent' ||
            contributorType == 'verified_dealer' ||
            contributorType == 'trusted_local_contributor';

        if (!trustedContributor || !passesBase || !passesWithOfficialPresent) {
          stats.trustedSourceReject++;
          stats.rejectedItems++;
          continue;
        }
      }

      final score = (10 - tier) * 100 + freshness;
      if (candidateAuditLines.length < 20) {
        final sourceId = text(data, const <String>['sourceId']);
        final sourceType = text(data, const <String>[
          'sourceType',
          'ingestionSource',
        ]);
        final cityRaw = text(data, const <String>['city']);
        candidateAuditLines.add(
          'idx=${candidateAuditLines.length + 1} '
          'categoryRaw=${categoryRaw.isEmpty ? '-' : categoryRaw} '
          'subCategoryRaw=${subcategoryRaw.isEmpty ? '-' : subcategoryRaw} '
          'commodityRaw=${cropRaw.isEmpty ? '-' : cropRaw} '
          'sourceId=${sourceId.isEmpty ? '-' : sourceId} '
          'sourceType=${sourceType.isEmpty ? '-' : sourceType} '
          'city=${cityRaw.isEmpty ? '-' : cityRaw} '
          'normalizedCategoryKey=${normalizedCategoryKey.isEmpty ? '-' : normalizedCategoryKey} '
          'normalizedSubcategoryKey=${subcategoryKey.isEmpty ? '-' : subcategoryKey}',
        );
      }
      candidates.add(
        _TickerCandidate(
          item: _MandiTickerItem(
            crop: crop,
            location: location,
            price: price,
            trendSymbol: trendFrom(data),
            subcategoryKey: subcategoryKey,
            subcategoryLabel: subcategoryRaw,
          ),
          score: score,
          commodityKey: commodityKey,
          subcategoryKey: subcategoryKey,
          tier: tier,
        ),
      );
    }

    stats.postQualityFilterItems = candidates.length;
    if (candidateAuditLines.isNotEmpty) {
      _logMandiDebug('[MANDI_SUBCATEGORY_AUDIT_BEGIN] total=${candidateAuditLines.length}');
      for (final line in candidateAuditLines) {
        _logMandiDebug('[MANDI_SUBCATEGORY_AUDIT] $line');
      }
      _logMandiDebug('[MANDI_SUBCATEGORY_AUDIT_END]');
    }
    candidates.sort((a, b) => b.score.compareTo(a.score));
    stats.finalTickerCandidates = candidates.length;

    final deduped = <_TickerCandidate>[];
    final dedupeKeySet = <String>{};
    for (final candidate in candidates) {
      final key =
          '${candidate.commodityKey}|${candidate.subcategoryKey}|${_normalizeLocationToken(candidate.item.location)}';
      if (!dedupeKeySet.add(key)) {
        stats.duplicateReject++;
        continue;
      }
      deduped.add(candidate);
    }
    stats.postDedupItems = deduped.length;

    final nearby = deduped.where((candidate) => candidate.tier <= 2).toList(growable: false);
    final broader = deduped.where((candidate) => candidate.tier > 2).toList(growable: false);
    stats.postCityFirstItems = nearby.length;

    final picked = <_MandiTickerItem>[];
    final usedSubcategories = <String>{};
    final usedKeys = <String>{};

    void pickDiversified(List<_TickerCandidate> list) {
      for (final candidate in list) {
        if (picked.length >= 12) break;
        if (candidate.subcategoryKey.isEmpty ||
            usedSubcategories.contains(candidate.subcategoryKey)) {
          continue;
        }
        final key =
          '${candidate.commodityKey}|${candidate.subcategoryKey}|${_normalizeLocationToken(candidate.item.location)}';
        if (usedKeys.contains(key)) continue;

        usedSubcategories.add(candidate.subcategoryKey);
        usedKeys.add(key);
        picked.add(candidate.item);
      }
    }

    // Preserve city-first preference, then broaden only to fill the utility gap.
    pickDiversified(nearby);
    pickDiversified(broader);
    stats.postSubcategoryDiversificationItems = picked.length;

    void fillRemaining(List<_TickerCandidate> list) {
      for (final candidate in list) {
        if (picked.length >= 12) break;
        if (candidate.subcategoryKey.isEmpty) {
          stats.emptySubcategoryReject++;
          continue;
        }
        final key =
            '${candidate.commodityKey}|${candidate.subcategoryKey}|${_normalizeLocationToken(candidate.item.location)}';
        if (usedKeys.contains(key)) continue;

        usedKeys.add(key);
        picked.add(candidate.item);
      }
    }

    fillRemaining(nearby);
    fillRemaining(broader);

    if (picked.length <= 1 && deduped.length > 1) {
      for (final candidate in deduped) {
        if (picked.length >= 4) break;
        final key =
            '${candidate.commodityKey}|${candidate.subcategoryKey}|${_normalizeLocationToken(candidate.item.location)}';
        if (usedKeys.add(key)) {
          picked.add(candidate.item);
        }
      }
    }

    stats.parsedItems = candidates.length;
    stats.finalTickerItems = picked.length;
    return _MandiParseResult(items: picked, stats: stats);
  }

  String _normalizeSubcategoryKey({
    required String subcategoryRaw,
    required String commodityRaw,
  }) {
    final source = '${subcategoryRaw.trim()} ${commodityRaw.trim()}'.toLowerCase();
    if (source.trim().isEmpty) return '';

    if (source.contains('vegetable') || source.contains('سبزی') ||
        source.contains('onion') || source.contains('tomato') ||
        source.contains('potato') || source.contains('brinjal') ||
        source.contains('okra') || source.contains('cabbage') ||
        source.contains('carrot') || source.contains('cauliflower')) {
      return 'vegetables';
    }
    if (source.contains('fruit') || source.contains('پھل') ||
        source.contains('apple') || source.contains('banana') ||
        source.contains('mango') || source.contains('orange') ||
        source.contains('guava') || source.contains('dates')) {
      return 'fruits';
    }
    if (source.contains('pulse') || source.contains('dal') || source.contains('دال') ||
        source.contains('lentil') || source.contains('gram') || source.contains('moong') ||
        source.contains('masoor') || source.contains('mash') || source.contains('chana')) {
      return 'pulses';
    }
    if (source.contains('seed') || source.contains('بیج')) {
      return 'seeds';
    }
    if (source.contains('spice') || source.contains('مصالح') || source.contains('chilli') ||
        source.contains('pepper') || source.contains('turmeric') || source.contains('haldi')) {
      return 'spices';
    }
    if (source.contains('milk') || source.contains('dairy') || source.contains('دودھ') ||
        source.contains('ghee') || source.contains('butter') || source.contains('cream')) {
      return 'dairy';
    }
    if (source.contains('livestock') || source.contains('مویشی') || source.contains('animal') ||
        source.contains('cattle') || source.contains('goat') || source.contains('sheep') ||
        source.contains('bakra') || source.contains('cow') || source.contains('buffalo')) {
      return 'livestock';
    }
    if (source.contains('crop') || source.contains('grain') ||
        source.contains('wheat') || source.contains('گندم') ||
        source.contains('rice') || source.contains('paddy') || source.contains('چاول') ||
        source.contains('corn') || source.contains('maize') || source.contains('مکئی') ||
        source.contains('cotton') || source.contains('sugarcane') ||
        source.contains('barley') || source.contains('jowar') || source.contains('bajra')) {
      return 'crops';
    }

    return source
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  void _captureListingBasedCropContext(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final frequency = <String, int>{};
    for (final doc in docs.take(60)) {
      final data = doc.data();
      final candidate =
          (data['subcategoryLabel'] ??
                  data['subcategory'] ??
                  data['categoryLabel'] ??
                  data['category'] ??
                  data['cropName'] ??
                  data['itemName'] ??
                  '')
              .toString()
              .trim();
      if (candidate.isEmpty) continue;
      frequency[candidate] = (frequency[candidate] ?? 0) + 1;
    }

    if (frequency.isEmpty) return;
    final sorted = frequency.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.first.key.trim();
    if (top.isEmpty || !mounted) return;

    if (_listingDerivedCropContext != top) {
      setState(() {
        _listingDerivedCropContext = top;
      });
    }
  }

  String _resolveWeatherCropContext() {
    final selectedSub = selectedSubcategoryLabel.trim();
    if (selectedSub.isNotEmpty) return selectedSub;

    if (_selectedCategory != null) {
      final label = MarketHierarchy.categoryLabelForMandiType(
        _selectedCategory!,
      );
      if (label.trim().isNotEmpty) return label;
    }

    final derived = _listingDerivedCropContext.trim();
    if (derived.isNotEmpty) return derived;
    return 'عمومی فصل';
  }

  Future<void> _refreshWeatherAdvisoryOnly() async {
    if (_weatherData == null) {
      if (!mounted) return;
      setState(() {
        _advisory = 'عام زرعی مشورہ: آبپاشی اور ذخیرہ احتیاط سے جاری رکھیں۔';
      });
      return;
    }

    final condition =
        ((_weatherData?['condition'] ?? _weatherData?['description'] ?? '')
                .toString())
            .trim();
    final temp = _weatherData?['temp'] ?? _weatherData?['temperature'] ?? 0;

    final advisory = await _weatherService.getAIAdvisory(
      condition,
      temp,
      _resolveWeatherCropContext(),
      district: _weatherLocationLabelUr,
      category: _selectedCategory?.label,
      subcategory: _selectedSubcategoryId,
    );

    if (!mounted) return;
    setState(() {
      _advisory = advisory.trim().isEmpty
          ? 'عام زرعی مشورہ: آبپاشی اور ذخیرہ احتیاط سے جاری رکھیں۔'
          : advisory.trim();
    });
  }

  void _listenApprovedWinnerStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _approvedWinnerSubscription = FirebaseFirestore.instance
        .collection('listings')
        .where('buyerId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final map = doc.data();
            final listingStatus =
                (map['listingStatus'] ??
                        map['auctionStatus'] ??
                        map['status'] ??
                        '')
                    .toString()
                    .toLowerCase();
            final acceptedBuyerUid =
                (map['acceptedBuyerUid'] ??
                        map['winnerId'] ??
                        map['buyerId'] ??
                        '')
                    .toString()
                    .trim();
            final hasAcceptedMarker =
                acceptedBuyerUid.isNotEmpty && acceptedBuyerUid == uid;
            final hasAcceptedStatus =
                listingStatus == 'approved_winner' ||
                listingStatus == 'bid_accepted';
            final hasUnlockedContact = _isTruthy(map['contactUnlocked']);

            if (!hasAcceptedStatus &&
                !hasAcceptedMarker &&
                !hasUnlockedContact) {
              continue;
            }
            if (acceptedBuyerUid.isNotEmpty && acceptedBuyerUid != uid) {
              continue;
            }
            if (_shownWinnerNotifications.contains(doc.id)) continue;

            _shownWinnerNotifications.add(doc.id);
            if (!mounted) return;

            await NotificationService.showApprovedWinnerNotification();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                backgroundColor: AppColors.background,
                content: const Text(
                  'مبارک ہو! آپ کی بولی منظور ہو گئی ہے۔ اب براہِ راست رابطہ کریں۔',
                  style: TextStyle(color: AppColors.primaryText),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                    },
                    child: const Text('Theek Hai'),
                  ),
                ],
              ),
            );
          }
        });
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    return value?.toString().trim().toLowerCase() == 'true';
  }

  Future<void> _loadWeather() async {
    try {
      if (mounted) {
        setState(() {
          _isWeatherLoading = true;
          _weatherFailed = false;
        });
      }

      final locationContext = await _resolveWeatherLocationContext();
      final district = locationContext.$1;
      final districtUr = locationContext.$2;

      final data = await _weatherService.getWeatherData(district);
      String advisory = 'موسمی معلومات فی الحال دستیاب نہیں۔';

      if (data['success'] == true) {
        advisory = await _weatherService.getAIAdvisory(
          data['condition'] ?? '',
          data['temp'] ?? 0,
          _resolveWeatherCropContext(),
          district: districtUr,
          category: _selectedCategory?.label,
          subcategory: _selectedSubcategoryId,
        );
      }

      if (!mounted) return;
      setState(() {
        _weatherLocationLabelUr = districtUr;
        _weatherData = <String, dynamic>{
          ...data,
          'requestedDistrict': district,
          'displayDistrictUr': districtUr,
        };
        _advisory = advisory.trim().isEmpty
            ? 'عام زرعی مشورہ: آبپاشی اور ذخیرہ احتیاط سے جاری رکھیں۔'
            : advisory;
        _isWeatherLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherData = null;
        _advisory = 'موسم کی معلومات عارضی طور پر دستیاب نہیں۔';
        _isWeatherLoading = false;
        _weatherFailed = true;
      });
    }
  }

  Future<(String, String)> _resolveWeatherLocationContext() async {
    final live = await _tryDetectLiveWeatherLocation();
    if (live != null) return live;

    final filterCandidate = _firstNonEmpty(<String?>[
      _selectedDistrictFilter,
      _selectedCityFilter,
      _selectedTehsilFilter,
      _selectedProvinceFilter,
    ]);
    if (filterCandidate.isNotEmpty) {
      final apiDistrict = _toCanonicalWeatherDistrict(filterCandidate);
      return (apiDistrict, _toUrduLocationLabel(filterCandidate));
    }

    final accountCandidate = _firstNonEmpty(<String?>[
      (widget.userData['district'] ?? '').toString(),
      (widget.userData['city'] ?? '').toString(),
      (widget.userData['tehsil'] ?? '').toString(),
      (widget.userData['province'] ?? '').toString(),
    ]);
    if (accountCandidate.isNotEmpty) {
      final apiDistrict = _toCanonicalWeatherDistrict(accountCandidate);
      return (apiDistrict, _toUrduLocationLabel(accountCandidate));
    }

    return ('Punjab', 'پنجاب');
  }

  Future<(String, String)?> _tryDetectLiveWeatherLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.low,
            timeLimit: Duration(seconds: 5),
          ),
        );
      } catch (_) {
        position = await Geolocator.getLastKnownPosition();
      }
      if (position == null) return null;

      final nearest = _resolveNearestKnownDistrict(
        lat: position.latitude,
        lng: position.longitude,
      );
      if (nearest == null) return null;
      return (nearest.englishDistrict, nearest.urduLabel);
    } catch (_) {
      return null;
    }
  }

  _KnownDistrict? _resolveNearestKnownDistrict({
    required double lat,
    required double lng,
  }) {
    _KnownDistrict? best;
    double bestKm = double.infinity;
    for (final item in _knownDistricts) {
      final km =
          Geolocator.distanceBetween(lat, lng, item.lat, item.lng) / 1000;
      if (km < bestKm) {
        bestKm = km;
        best = item;
      }
    }
    if (best == null || bestKm > 140) return null;
    return best;
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final v = (value ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  String _toCanonicalWeatherDistrict(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return 'Punjab';
    final lower = value.toLowerCase();
    if (_urduToEnglishLocation.containsKey(value)) {
      return _urduToEnglishLocation[value]!;
    }
    if (_englishToUrduLocation.containsKey(lower)) {
      final mapped = _urduToEnglishLocation[_englishToUrduLocation[lower]!];
      return mapped ?? _toTitleCaseAscii(value);
    }
    return _toTitleCaseAscii(value);
  }

  String _toUrduLocationLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (_isLikelyUrdu(value)) return value;

    final lower = value.toLowerCase();
    if (_englishToUrduLocation.containsKey(lower)) {
      return _englishToUrduLocation[lower]!;
    }
    return value;
  }

  String _cleanTickerLocation(String raw) {
    final value = _toUrduLocationLabel(raw).trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower == 'pakistan' || lower == 'all pakistan' || lower == 'pk') {
      return '';
    }
    if (value == 'پاکستان' || value == 'پورا پاکستان') return '';
    return value;
  }

  String _normalizeLocationToken(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';
    if (_urduToEnglishLocation.containsKey(value)) {
      return _urduToEnglishLocation[value]!.toLowerCase();
    }
    final lower = value.toLowerCase();
    if (_englishToUrduLocation.containsKey(lower)) return lower;

    return lower
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _toUrduCommodityLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (_isLikelyUrdu(value)) return value;

    final lower = value.toLowerCase();
    if (_englishToUrduCommodity.containsKey(lower)) {
      return _englishToUrduCommodity[lower]!;
    }
    if (lower.contains('wheat')) return 'گندم';
    if (lower.contains('rice') || lower.contains('paddy')) return 'چاول';
    if (lower.contains('corn') || lower.contains('maize')) return 'مکئی';
    if (lower.contains('mango')) return 'آم';
    if (lower.contains('cotton')) return 'کپاس';
    if (lower == 'dap') return 'ڈی اے پی';
    return value;
  }

  String _normalizeCommodityKey(String input) {
    return _toUrduCommodityLabel(input)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _isLikelyUrdu(String input) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(input);
  }

  String _toTitleCaseAscii(String value) {
    final parts = value
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
        .toList(growable: false);
    return parts.isEmpty ? value : parts.join(' ');
  }

  Future<void> _refreshAiRatesNow() async {
    try {
      await _marketplaceService.syncPakistanMandiRates(
        forcedType: _selectedCategory,
      );
    } catch (_) {
      if (!mounted) return;
    }
  }

  @override
  Widget build(BuildContext context) {
    const darkGreen = AppColors.background;

    return Scaffold(
      backgroundColor: darkGreen,
      floatingActionButton: CustomerSupportFab(
        userName: (widget.userData['name'] ?? '').toString(),
        mini: true,
      ),
      appBar: CustomAppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        titleWidget: const AppLogo(height: 30),
        actions: [
          IconButton(
            tooltip: 'Watchlist',
            onPressed: () async {
              final bool canContinue = await _promptAuthRequired(
                title: 'Watchlist Locked / واچ لسٹ لاک ہے',
                message:
                    'Watchlist access ke liye login zaroori hai.\nواچ لسٹ دیکھنے کے لیے لاگ اِن ضروری ہے۔',
              );
              if (!canContinue || !context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => WatchlistScreen()),
              );
            },
            icon: const Icon(
              Icons.favorite_border_rounded,
              color: AppColors.accentGold,
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () async {
              final bool canContinue = await _promptAuthRequired(
                title: 'Alerts Locked / الرٹس لاک ہیں',
                message:
                    'Personal alerts pane ke liye login zaroori hai.\nذاتی الرٹس حاصل کرنے کے لیے لاگ اِن ضروری ہے۔',
              );
              if (!canContinue || !context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  duration: Duration(seconds: 3),
                  content: Text('Live bid and listing notifications enabled.'),
                ),
              );
            },
            icon: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.accentGold,
            ),
          ),
          CustomerSupportIconAction(
            userName: (widget.userData['name'] ?? '').toString(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.softGlassTintedSurface,
              border: Border(
                bottom: BorderSide(color: AppColors.softGlassBorder),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'فوری تلاش کریں، بہترین آفر دیکھیں',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                _buildSearchBar(),
                const SizedBox(height: 6),
                _buildTopMandiTicker(),
                if (SeasonalBakraMandiConfig.isEnabled) ...[
                  const SizedBox(height: 8),
                  _buildBakraMandiEntryCard(),
                ],
              ],
            ),
          ),
          Expanded(
            child: _BuyerListingsSection(
              stream: _activeListingsStream,
              winnerStream: _winnerListingsStream,
              searchQuery: _searchQuery,
              selectedCategory: _selectedCategory,
              selectedSubcategoryId: _selectedSubcategoryId,
              selectedProvince: _selectedProvinceFilter,
              selectedDistrict: _selectedDistrictFilter,
              selectedTehsil: _selectedTehsilFilter,
              selectedCity: _selectedCityFilter,
              selectedSaleType: _selectedSaleType,
              selectedSort: _selectedSort,
              minPrice: _minPriceFilter,
              maxPrice: _maxPriceFilter,
              minQuantity: _minQuantityFilter,
              maxQuantity: _maxQuantityFilter,
              qurbaniOnly: _qurbaniOnly,
              verifiedOnly: _verifiedOnly,
              buyerProvince: (widget.userData['province'] ?? '').toString(),
              buyerDistrict: (widget.userData['district'] ?? 'Punjab')
                  .toString(),
              buyerVillage:
                  (widget.userData['village'] ??
                          widget.userData['cityVillage'] ??
                          '')
                      .toString(),
              buyerCity:
                  (widget.userData['city'] ??
                          widget.userData['cityVillage'] ??
                          '')
                      .toString(),
              recentlyViewedStream: _recentlyViewedStream,
              weatherData: _weatherData,
              isWeatherLoading: _isWeatherLoading,
              weatherFailed: _weatherFailed,
              advisoryText: _advisory,
              mandiTickerItems: _liveMandiTickerItems,
              mandiTickerInfoText: _mandiTickerInfoText,
              mandiSnapshotContextLabelUr: _mandiSnapshotContextLabelUr,
              mandiSnapshotFallbackNote: _mandiSnapshotFallbackNote,
              onBid: _openBidSheet,
              onRefreshAiRates: _refreshAiRatesNow,
              onSeeAllAuctions: () {
                setState(() {
                  _selectedSaleType = 'auction';
                  _selectedSort = 'ending_soon';
                });
              },
              onSeeAllNearby: () {
                setState(() {
                  _selectedSort = 'nearest';
                });
              },
              onSelectCategory: (MandiType type) {
                setState(() {
                  _selectedCategory = type;
                });
                unawaited(_refreshWeatherAdvisoryOnly());
              },
              isSeller:
                  (widget.userData['role'] ??
                          widget.userData['userRole'] ??
                          widget.userData['userType'] ??
                          '')
                      .toString()
                      .toLowerCase()
                      .contains('seller'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBakraMandiEntryCard() {
    Future<void> openEntry([String? animalType]) async {
      await _analyticsService.logEvent(
        event: 'bakra_home_card_tap',
        data: <String, dynamic>{
          'surface': 'buyer_home',
          'animalType': animalType ?? 'all',
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushNamed(
        Routes.bakraMandiEntry,
        arguments: <String, dynamic>{'animalType': animalType},
      );
    }

    Widget animalChip(String type, String label) {
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
          onPressed: () => openEntry(type),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Container(
      height: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF194B30), Color(0xFF24563A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: AppColors.softGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'عید بکرا منڈی',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const Text(
            'Eid Bakra Mandi',
            style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 6),
          const Text(
            'قربانی کے جانور خریدیں یا فروخت کریں',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              animalChip('bakray', 'بکرے / Bakray'),
              const SizedBox(width: 6),
              animalChip('gaye', 'گائے / Gaye'),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              animalChip('dumba', 'دنبہ / Dumba'),
              const SizedBox(width: 6),
              animalChip('oont', 'اونٹ / Oont'),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGold,
                foregroundColor: AppColors.ctaTextDark,
              ),
              onPressed: () => openEntry(),
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: const Text('جانور دیکھیں / Explore Animals'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.softGlassTintedSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.softGlassBorder),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: AppColors.accentGold,
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              onChanged: (value) =>
                  setState(() => _searchQuery = value.trim().toLowerCase()),
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                hintText:
                    'Search crops, district, or mandi / فصل، ضلع یا منڈی تلاش کریں',
                hintStyle: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11.8,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: _openAdvancedFilters,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.softGlassSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.softGlassBorder),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.tune_rounded,
                    color: AppColors.accentGold,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Filters / فلٹرز',
                    style: TextStyle(
                      color: AppColors.accentGold,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildTopMandiTicker() {
    final String tickerText = _liveMandiTickerItems.isEmpty
        ? (_mandiTickerInfoText ?? 'تازہ منڈی ریٹ لوڈ ہو رہے ہیں۔')
        : _liveMandiTickerItems
              .map((item) => _formatTickerItemText(item))
              .join('   •   ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFD4AF37).withValues(alpha: 0.14),
            AppColors.primaryText.withValues(alpha: 0.03),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE8C766).withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.graphic_eq_rounded,
            size: 13,
            color: Color(0xFFE8C766),
          ),
          const SizedBox(width: 5),
          const Text(
            'لائیو منڈی ٹکر',
            style: TextStyle(
              color: Color(0xFFEFD88A),
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: SingleChildScrollView(
              controller: _tickerScrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Text(
                tickerText,
                maxLines: 1,
                textDirection: TextDirection.ltr,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 10.9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTickerItemText(_MandiTickerItem item) {
    final crop = _toUrduCommodityLabel(item.crop).trim().isEmpty
        ? 'اجناس'
        : _toUrduCommodityLabel(item.crop).trim();
    final location = _cleanTickerLocation(item.location).isEmpty
        ? _tickerFallbackLocalityLabel()
        : _cleanTickerLocation(item.location);
    final trend = item.trendSymbol.trim().isEmpty ? '•' : item.trendSymbol;
      return '$crop | $location | ${item.price.toStringAsFixed(0)} روپے $trend';
  }

  String _tickerFallbackLocalityLabel() {
    final selected = _firstNonEmpty(<String?>[
      _selectedDistrictFilter,
      _selectedCityFilter,
      _selectedTehsilFilter,
      _selectedProvinceFilter,
    ]);
    if (selected.isNotEmpty) {
      return 'منتخب مقام: ${_toUrduLocationLabel(selected)}';
    }

    final buyerDistrict = _toUrduLocationLabel(
      (widget.userData['district'] ?? '').toString(),
    ).trim();
    if (buyerDistrict.isNotEmpty) {
      return 'موجودہ ضلع: $buyerDistrict';
    }
    return 'مقامی ریٹ';
  }

  static const Map<String, String> _englishToUrduCommodity = <String, String>{
    'wheat': 'گندم',
    'rice': 'چاول',
    'paddy': 'چاول',
    'corn': 'مکئی',
    'maize': 'مکئی',
    'mango': 'آم',
    'cotton': 'کپاس',
    'dap': 'ڈی اے پی',
  };

  static const Map<String, String> _englishToUrduLocation = <String, String>{
    'lahore': 'لاہور',
    'kasur': 'قصور',
    'multan': 'ملتان',
    'faisalabad': 'فیصل آباد',
    'islamabad': 'اسلام آباد',
    'karachi': 'کراچی',
    'peshawar': 'پشاور',
    'quetta': 'کوئٹہ',
    'punjab': 'پنجاب',
    'sindh': 'سندھ',
  };

  static const Map<String, String> _urduToEnglishLocation = <String, String>{
    'لاہور': 'Lahore',
    'قصور': 'Kasur',
    'ملتان': 'Multan',
    'فیصل آباد': 'Faisalabad',
    'اسلام آباد': 'Islamabad',
    'کراچی': 'Karachi',
    'پشاور': 'Peshawar',
    'کوئٹہ': 'Quetta',
    'پنجاب': 'Punjab',
    'سندھ': 'Sindh',
  };

  static const List<_KnownDistrict> _knownDistricts = <_KnownDistrict>[
    _KnownDistrict(
      englishDistrict: 'Lahore',
      urduLabel: 'لاہور',
      lat: 31.5204,
      lng: 74.3587,
    ),
    _KnownDistrict(
      englishDistrict: 'Kasur',
      urduLabel: 'قصور',
      lat: 31.1165,
      lng: 74.4498,
    ),
    _KnownDistrict(
      englishDistrict: 'Multan',
      urduLabel: 'ملتان',
      lat: 30.1575,
      lng: 71.5249,
    ),
    _KnownDistrict(
      englishDistrict: 'Faisalabad',
      urduLabel: 'فیصل آباد',
      lat: 31.4504,
      lng: 73.135,
    ),
    _KnownDistrict(
      englishDistrict: 'Islamabad',
      urduLabel: 'اسلام آباد',
      lat: 33.6844,
      lng: 73.0479,
    ),
    _KnownDistrict(
      englishDistrict: 'Karachi',
      urduLabel: 'کراچی',
      lat: 24.8607,
      lng: 67.0011,
    ),
    _KnownDistrict(
      englishDistrict: 'Peshawar',
      urduLabel: 'پشاور',
      lat: 34.0151,
      lng: 71.5249,
    ),
    _KnownDistrict(
      englishDistrict: 'Quetta',
      urduLabel: 'کوئٹہ',
      lat: 30.1798,
      lng: 66.975,
    ),
  ];

  Future<void> _loadFilterLocationAsset() async {
    try {
      final raw = await rootBundle.loadString(
        'assets/data/pakistan_locations.json',
      );
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final provincesRaw = decoded['provinces'];
      if (provincesRaw is! List) return;

      final provinces = <String>[];
      final districtsByProvince = <String, List<String>>{};
      final tehsilsByDistrict = <String, List<String>>{};
      final citiesByDistrictTehsil = <String, List<String>>{};
      final provinceUrduByEn = <String, String>{};
      final districtUrduByEn = <String, String>{};
      final tehsilUrduByEn = <String, String>{};

      for (final provinceItem in provincesRaw) {
        if (provinceItem is! Map) continue;
        final province = provinceItem.cast<String, dynamic>();
        final provinceEn = (province['name_en'] ?? '').toString().trim();
        if (provinceEn.isEmpty) continue;
        final provinceUr = (province['name_ur'] ?? '').toString().trim();
        provinces.add(provinceEn);
        provinceUrduByEn[provinceEn] = provinceUr;

        final districts = <String>[];
        final districtsRaw = province['districts'];
        if (districtsRaw is List) {
          for (final districtItem in districtsRaw) {
            if (districtItem is! Map) continue;
            final district = districtItem.cast<String, dynamic>();
            final districtEn = (district['name_en'] ?? '').toString().trim();
            if (districtEn.isEmpty) continue;
            final districtUr = (district['name_ur'] ?? '').toString().trim();
            districts.add(districtEn);
            districtUrduByEn[districtEn] = districtUr;

            final tehsils = <String>[];
            final tehsilsRaw = district['tehsils'];
            if (tehsilsRaw is List) {
              for (final tehsilItem in tehsilsRaw) {
                if (tehsilItem is! Map) continue;
                final tehsil = tehsilItem.cast<String, dynamic>();
                final tehsilEn = (tehsil['name_en'] ?? '').toString().trim();
                if (tehsilEn.isEmpty) continue;
                final tehsilUr = (tehsil['name_ur'] ?? '').toString().trim();
                tehsils.add(tehsilEn);
                tehsilUrduByEn[tehsilEn] = tehsilUr;
                // Keep city behavior aligned with Add Listing fallback: city list mirrors selected tehsil.
                citiesByDistrictTehsil['$districtEn|$tehsilEn'] = <String>[
                  tehsilEn,
                ];
              }
            }
            tehsils.sort();
            tehsilsByDistrict[districtEn] = tehsils;
          }
        }
        districts.sort();
        districtsByProvince[provinceEn] = districts;
      }

      provinces.sort();
      if (!mounted) return;
      setState(() {
        _filterAssetProvinces = provinces;
        _filterDistrictsByProvince
          ..clear()
          ..addAll(districtsByProvince);
        _filterTehsilsByDistrict
          ..clear()
          ..addAll(tehsilsByDistrict);
        _filterCitiesByDistrictTehsil
          ..clear()
          ..addAll(citiesByDistrictTehsil);
        _provinceUrduByEn
          ..clear()
          ..addAll(provinceUrduByEn);
        _districtUrduByEn
          ..clear()
          ..addAll(districtUrduByEn);
        _tehsilUrduByEn
          ..clear()
          ..addAll(tehsilUrduByEn);
        _isFilterLocationAssetReady = true;
      });
    } catch (_) {
      // Keep existing hierarchy fallback when asset is unavailable.
    }
  }

  String _bilingualLocationLabel(String english, Map<String, String> urduMap) {
    final en = english.trim();
    if (en.isEmpty) return '';
    final ur = (urduMap[en] ?? _toUrduLocationLabel(en)).trim();
    if (ur.isEmpty || ur.toLowerCase() == en.toLowerCase()) return en;
    return '$en / $ur';
  }

  List<String> _provinceOptionsForFilters() {
    if (_isFilterLocationAssetReady && _filterAssetProvinces.isNotEmpty) {
      return List<String>.from(_filterAssetProvinces);
    }
    return PakistanLocationHierarchy.provinces;
  }

  List<String> _districtOptionsForFilters(String province) {
    if (province.trim().isEmpty) return const <String>[];
    if (_isFilterLocationAssetReady && _filterDistrictsByProvince.isNotEmpty) {
      return List<String>.from(
        _filterDistrictsByProvince[province] ?? const <String>[],
      );
    }
    return PakistanLocationHierarchy.districtsForProvince(province);
  }

  List<String> _tehsilOptionsForFilters(String district) {
    if (district.trim().isEmpty) return const <String>[];
    if (_isFilterLocationAssetReady && _filterTehsilsByDistrict.isNotEmpty) {
      return List<String>.from(
        _filterTehsilsByDistrict[district] ?? const <String>[],
      );
    }
    return PakistanLocationHierarchy.tehsilsForDistrict(district);
  }

  List<String> _cityOptionsForFilters({
    required String district,
    required String tehsil,
  }) {
    if (district.trim().isEmpty || tehsil.trim().isEmpty) {
      return const <String>[];
    }
    if (_isFilterLocationAssetReady &&
        _filterCitiesByDistrictTehsil.isNotEmpty) {
      final key = '${district.trim()}|${tehsil.trim()}';
      return List<String>.from(
        _filterCitiesByDistrictTehsil[key] ?? <String>[tehsil.trim()],
      );
    }
    return PakistanLocationHierarchy.citiesForTehsil(
      district: district,
      tehsil: tehsil,
    );
  }

  List<MarketSubcategoryOption> _subcategoryOptionsForCategory(
    MandiType? category,
  ) {
    final sourceTypes = category == null
        ? MandiType.values
        : <MandiType>[category];

    final byId = <String, MarketSubcategoryOption>{};
    for (final type in sourceTypes) {
      for (final option in MarketHierarchy.subcategoriesForMandiType(type)) {
        if (option.id.trim().isNotEmpty) {
          byId[option.id.toLowerCase()] = option;
        }
      }
    }

    final items = byId.values.toList(growable: false)
      ..sort(
        (a, b) => a.labelEn.toLowerCase().compareTo(b.labelEn.toLowerCase()),
      );
    return items;
  }

  String _humanizeSubcategoryId(String id) {
    final compact = id.trim().toLowerCase();
    if (compact.isEmpty) return '';
    return compact
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
  }

  String _subcategoryLabelById(String? id) {
    final normalized = (id ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return '';
    for (final type in MandiType.values) {
      for (final option in MarketHierarchy.subcategoriesForMandiType(type)) {
        if (option.id.toLowerCase() == normalized) {
          return option.bilingualLabel;
        }
      }
    }
    final readable = _humanizeSubcategoryId(normalized);
    return readable.isEmpty
        ? normalized
        : MarketHierarchy.subcategoryDisplayFromProduct(readable);
  }

  void _clearAllFilters() {
    setState(() {
      _selectedSubcategoryId = null;
      _selectedProvinceFilter = null;
      _selectedDistrictFilter = null;
      _selectedTehsilFilter = null;
      _selectedCityFilter = null;
      _selectedSaleType = 'all';
      _selectedSort = 'newest';
      _minPriceFilter = null;
      _maxPriceFilter = null;
      _minQuantityFilter = null;
      _maxQuantityFilter = null;
      _qurbaniOnly = false;
      _verifiedOnly = false;
    });
    unawaited(_refreshWeatherAdvisoryOnly());
  }

  String _homeCategoryLabel(MandiType type) {
    return _homeCategoryLabels[type] ?? type.label;
  }

  String get selectedCategoryLabel {
    if (_selectedCategory == null) return '';
    return _homeCategoryLabel(_selectedCategory!);
  }

  String get selectedSubcategoryLabel =>
      _subcategoryLabelById(_selectedSubcategoryId);

  Future<void> _openAdvancedFilters() async {
    final minController = TextEditingController(
      text: _minPriceFilter?.toStringAsFixed(0) ?? '',
    );
    final maxController = TextEditingController(
      text: _maxPriceFilter?.toStringAsFixed(0) ?? '',
    );
    final minQtyController = TextEditingController(
      text: _minQuantityFilter?.toStringAsFixed(0) ?? '',
    );
    final maxQtyController = TextEditingController(
      text: _maxQuantityFilter?.toStringAsFixed(0) ?? '',
    );

    MandiType? tempCategory = _selectedCategory;
    String? tempSubcategory = _selectedSubcategoryId;
    String? tempProvince = _selectedProvinceFilter;
    String? tempDistrict = _selectedDistrictFilter;
    String? tempTehsil = _selectedTehsilFilter;
    String? tempCity = _selectedCityFilter;
    String tempSaleType = _selectedSaleType;
    String tempSort = _selectedSort;
    bool tempVerifiedOnly = _verifiedOnly;
    bool tempQurbaniOnly = _qurbaniOnly;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Widget sectionHeader(String title) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryText.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.primaryText.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFE8C766),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            InputDecoration fieldDecoration(String label) {
              return InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: AppColors.secondaryText),
                filled: true,
                fillColor: AppColors.primaryText.withValues(alpha: 0.06),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.primaryText.withValues(alpha: 0.18),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.primaryText.withValues(alpha: 0.18),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFFE8C766),
                    width: 1.2,
                  ),
                ),
              );
            }

            List<DropdownMenuItem<String?>> locationMenuItems(
              List<String> values,
              Map<String, String> urduMap,
            ) {
              return <DropdownMenuItem<String?>>[
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All / سب'),
                ),
                ...values.map(
                  (value) => DropdownMenuItem<String?>(
                    value: value,
                    child: Text(_bilingualLocationLabel(value, urduMap)),
                  ),
                ),
              ];
            }

            final districtOptions = (tempProvince ?? '').trim().isEmpty
                ? const <String>[]
                : _districtOptionsForFilters(tempProvince!);
            final tehsilOptions = (tempDistrict ?? '').trim().isEmpty
                ? const <String>[]
                : _tehsilOptionsForFilters(tempDistrict!);
            final cityOptions =
                ((tempDistrict ?? '').trim().isEmpty ||
                    (tempTehsil ?? '').trim().isEmpty)
                ? const <String>[]
                : _cityOptionsForFilters(
                    district: tempDistrict!,
                    tehsil: tempTehsil!,
                  );

            final allSubcategories = _subcategoryOptionsForCategory(
              tempCategory,
            );

            return SafeArea(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 14,
                    right: 14,
                    top: 14,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 14,
                  ),
                  child: SizedBox(
                    height: MediaQuery.of(context).size.height * 0.85,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Advanced Filters / اعلی فلٹرز',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                sectionHeader('Sort / ترتیب'),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: tempSort,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration('Sort / ترتیب'),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: const <DropdownMenuItem<String>>[
                                    DropdownMenuItem(
                                      value: 'newest',
                                      child: Text('Newest / تازہ ترین'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'nearest',
                                      child: Text('Nearest / قریب ترین'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'lowest_price',
                                      child: Text('Lowest Price / کم قیمت'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'highest_price',
                                      child: Text('Highest Price / زیادہ قیمت'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'ending_soon',
                                      child: Text(
                                        'Ending Soon / جلد ختم ہونے والی بولی',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: 'highest_bid',
                                      child: Text(
                                        'Highest Bid / سب سے بڑی بولی',
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setSheetState(() => tempSort = value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                sectionHeader('Sale Type / فروخت کی قسم'),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String>(
                                  initialValue: tempSaleType,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration(
                                    'Sale Type / فروخت کی قسم',
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: const <DropdownMenuItem<String>>[
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All / سب'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'auction',
                                      child: Text('Auction / بولی'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'fixed',
                                      child: Text('Fixed Price / مقرر قیمت'),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setSheetState(() => tempSaleType = value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                sectionHeader('Category / زمرہ'),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<MandiType?>(
                                  initialValue: tempCategory,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration(
                                    'Category / زمرہ',
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: <DropdownMenuItem<MandiType?>>[
                                    const DropdownMenuItem<MandiType?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...MarketHierarchy.categories.map(
                                      (cat) => DropdownMenuItem<MandiType?>(
                                        value: cat.mandiType,
                                        child: Text(
                                          _homeCategoryLabel(cat.mandiType),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setSheetState(() {
                                      tempCategory = value;
                                      tempSubcategory = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String?>(
                                  initialValue: tempSubcategory,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration(
                                    'Subcategory / ذیلی زمرہ',
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...allSubcategories.map(
                                      (option) => DropdownMenuItem<String?>(
                                        value: option.id,
                                        child: Text(option.bilingualLabel),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setSheetState(
                                      () => tempSubcategory = value,
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                sectionHeader(
                                  'Location Filters / مقام کے فلٹرز',
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String?>(
                                  initialValue: tempProvince,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration(
                                    'Province / صوبہ',
                                  ),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: locationMenuItems(
                                    _provinceOptionsForFilters(),
                                    _provinceUrduByEn,
                                  ),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      tempProvince = value;
                                      tempDistrict = null;
                                      tempTehsil = null;
                                      tempCity = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String?>(
                                  initialValue: tempDistrict,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration('District / ضلع'),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: locationMenuItems(
                                    districtOptions,
                                    _districtUrduByEn,
                                  ),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      tempDistrict = value;
                                      tempTehsil = null;
                                      tempCity = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String?>(
                                  initialValue: tempTehsil,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration('Tehsil / تحصیل'),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: locationMenuItems(
                                    tehsilOptions,
                                    _tehsilUrduByEn,
                                  ),
                                  onChanged: (value) {
                                    setSheetState(() {
                                      tempTehsil = value;
                                      tempCity = null;
                                    });
                                  },
                                ),
                                const SizedBox(height: 10),
                                DropdownButtonFormField<String?>(
                                  initialValue: tempCity,
                                  dropdownColor: AppColors.background,
                                  decoration: fieldDecoration('City / شہر'),
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...cityOptions.map(
                                      (value) => DropdownMenuItem<String?>(
                                        value: value,
                                        child: Text(
                                          _bilingualLocationLabel(
                                            value,
                                            _tehsilUrduByEn,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setSheetState(() => tempCity = value);
                                  },
                                ),
                                const SizedBox(height: 12),
                                sectionHeader('Price Range / قیمت کی حد'),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: minController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  decoration: fieldDecoration(
                                    'Min Price / کم از کم قیمت',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: maxController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  decoration: fieldDecoration(
                                    'Max Price / زیادہ سے زیادہ قیمت',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                sectionHeader('Quantity / مقدار'),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: minQtyController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  decoration: fieldDecoration(
                                    'Min Quantity / کم مقدار',
                                  ),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: maxQtyController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    color: AppColors.primaryText,
                                  ),
                                  decoration: fieldDecoration(
                                    'Max Quantity / زیادہ مقدار',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                sectionHeader(
                                  'Seller Filters / بیچنے والے کے فلٹرز',
                                ),
                                const SizedBox(height: 8),
                                SwitchListTile(
                                  value: tempVerifiedOnly,
                                  activeThumbColor: AppColors.accentGold,
                                  title: const Text(
                                    'Verified Sellers Only / صرف تصدیق شدہ فروخت کنندہ',
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                    ),
                                  ),
                                  onChanged: (value) {
                                    setSheetState(
                                      () => tempVerifiedOnly = value,
                                    );
                                  },
                                ),
                                if (SeasonalMarketRules.isQurbaniSeason)
                                  SwitchListTile(
                                    value: tempQurbaniOnly,
                                    activeThumbColor: AppColors.accentGold,
                                    title: const Text(
                                      'Qurbani Only / صرف قربانی',
                                      style: TextStyle(
                                        color: AppColors.primaryText,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      setSheetState(
                                        () => tempQurbaniOnly = value,
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.only(top: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(
                                color: AppColors.primaryText.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    Navigator.of(context).pop();
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primaryText,
                                    side: BorderSide(
                                      color: AppColors.primaryText.withValues(
                                        alpha: 0.35,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Cancel / منسوخ کریں'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    FocusScope.of(context).unfocus();
                                    setState(() {
                                      _selectedCategory = tempCategory;
                                      _selectedSubcategoryId = tempSubcategory;
                                      _selectedProvinceFilter = tempProvince;
                                      _selectedDistrictFilter = tempDistrict;
                                      _selectedTehsilFilter = tempTehsil;
                                      _selectedCityFilter = tempCity;
                                      _selectedSaleType = tempSaleType;
                                      _selectedSort = tempSort;
                                      _minPriceFilter = double.tryParse(
                                        minController.text.trim(),
                                      );
                                      _maxPriceFilter = double.tryParse(
                                        maxController.text.trim(),
                                      );
                                      _minQuantityFilter = double.tryParse(
                                        minQtyController.text.trim(),
                                      );
                                      _maxQuantityFilter = double.tryParse(
                                        maxQtyController.text.trim(),
                                      );
                                      _verifiedOnly = tempVerifiedOnly;
                                      _qurbaniOnly = tempQurbaniOnly;
                                    });
                                    unawaited(_refreshWeatherAdvisoryOnly());
                                    Navigator.of(context).pop();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentGold,
                                    foregroundColor: AppColors.ctaTextDark,
                                  ),
                                  child: const Text(
                                    'Apply Filters / فلٹر لاگو کریں',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    minController.dispose();
    maxController.dispose();
    minQtyController.dispose();
    maxQtyController.dispose();
  }

  Future<void> _openBidSheet(
    Map<String, dynamic> data,
    String listingId,
  ) async {
    final bool canContinue = await _promptAuthRequired(
      title: 'Bidding Locked / بولی لاک ہے',
      message:
          'Bid lagane ke liye login zaroori hai.\nبولی لگانے کے لیے لاگ اِن ضروری ہے۔',
    );
    if (!canContinue) {
      return;
    }

    Map<String, dynamic> latest = data;
    try {
      latest = await _marketplaceService.getListingBidContext(listingId);
    } catch (_) {
      latest = data;
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          BidBottomSheet(listingData: latest, listingId: listingId),
    );

    if (!mounted) return;
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Boli Lagaen: kamyabi se lag gayi hai!'),
          backgroundColor: AppColors.divider,
        ),
      );
    }
  }

  Future<bool> _promptAuthRequired({
    required String title,
    required String message,
  }) async {
    if (FirebaseAuth.instance.currentUser != null) return true;
    if (!mounted) return false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.softGlassBorder),
          ),
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: Text(
            message,
            style: const TextStyle(color: AppColors.secondaryText, height: 1.25),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continue Browsing / براؤز جاری رکھیں'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamed(Routes.createAccount);
              },
              child: const Text('Create Account / اکاؤنٹ بنائیں'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamed(Routes.login);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGold,
                foregroundColor: AppColors.ctaTextDark,
              ),
              child: const Text('Login / لاگ اِن'),
            ),
          ],
        );
      },
    );

    return false;
  }

  List<_MandiTickerItem> _buildNearbyMandiSnapshotItemsForDebug(
    List<_MandiTickerItem> source,
  ) {
    if (source.isEmpty) return const <_MandiTickerItem>[];

    final chosen = <_MandiTickerItem>[];
    final subcategoryKeys = <String>{};
    final dedupeKeys = <String>{};

    for (final item in source) {
      if (chosen.length >= 4) break;
      final subcategory = item.subcategoryKey.trim().toLowerCase();
      if (subcategory.isEmpty || subcategoryKeys.contains(subcategory)) continue;
      final commodity = _normalizeCommodityKey(item.crop);
      if (commodity.isEmpty) continue;
      final dedupe =
          '$commodity|$subcategory|${_normalizeLocationToken(item.location)}';
      if (dedupeKeys.contains(dedupe)) continue;

      subcategoryKeys.add(subcategory);
      dedupeKeys.add(dedupe);
      chosen.add(item);
    }

    for (final item in source) {
      if (chosen.length >= 4) break;
      final commodity = _normalizeCommodityKey(item.crop);
      if (commodity.isEmpty) continue;
      final dedupe =
          '$commodity|${item.subcategoryKey.trim().toLowerCase()}|${_normalizeLocationToken(item.location)}';
      if (dedupeKeys.contains(dedupe)) continue;
      dedupeKeys.add(dedupe);
      chosen.add(item);
    }

    return chosen;
  }

  Future<void> _runForcedLahoreMandiVerification() async {
    final values = _expandLocationAliases(<String>{'Lahore', 'لاہور'});
    final docs = await _queryMandiRatesByFields(
      fields: const <String>['city', 'mandiName', 'marketName', 'market'],
      values: values,
      limit: 28,
      stageLabel: 'LahoreProbe',
    );
    final parseResult = _parseMandiTickerItemsDetailed(docs);
    final snapshotItems = _buildNearbyMandiSnapshotItemsForDebug(
      parseResult.items,
    );
    _logMandiQuery('LahoreProbe totalDocs=${docs.length} aliasValues=${values.join('|')}');
    _logMandiParse(
      'LahoreProbe parsedRecords=${parseResult.stats.parsedItems} rejectedRecords=${parseResult.stats.rejectedItems} '
      'finalTickerRendered=${parseResult.items.length}',
    );
    _logMandiRender(
      'LahoreProbe finalTickerRendered=${parseResult.items.length} '
      'finalSnapshotRendered=${snapshotItems.length}',
    );
  }
}

class _HomeIntelligenceHub extends StatelessWidget {
  const _HomeIntelligenceHub({
    required this.listings,
    required this.buyerProvince,
    required this.buyerDistrict,
    required this.buyerVillage,
    required this.buyerCity,
    required this.recentlyViewedEntries,
    required this.selectedProvince,
    required this.selectedDistrict,
    required this.selectedTehsil,
    required this.selectedCity,
    required this.weatherData,
    required this.isWeatherLoading,
    required this.weatherFailed,
    required this.advisoryText,
    required this.mandiTickerItems,
    required this.mandiTickerInfoText,
    required this.mandiSnapshotContextLabelUr,
    required this.mandiSnapshotFallbackNote,
    required this.onBid,
    required this.onSeeAllAuctions,
    required this.onSeeAllNearby,
    required this.selectedCategory,
    required this.onSelectCategory,
    this.isSeller = false,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> listings;
  final String buyerProvince;
  final String buyerDistrict;
  final String buyerVillage;
  final String buyerCity;
  final List<Map<String, dynamic>> recentlyViewedEntries;
  final String? selectedProvince;
  final String? selectedDistrict;
  final String? selectedTehsil;
  final String? selectedCity;
  final Map<String, dynamic>? weatherData;
  final bool isWeatherLoading;
  final bool weatherFailed;
  final String advisoryText;
  final List<_MandiTickerItem> mandiTickerItems;
  final String? mandiTickerInfoText;
  final String mandiSnapshotContextLabelUr;
  final String? mandiSnapshotFallbackNote;
  final void Function(Map<String, dynamic> data, String listingId) onBid;
  final VoidCallback onSeeAllAuctions;
  final VoidCallback onSeeAllNearby;
  final MandiType? selectedCategory;
  final ValueChanged<MandiType> onSelectCategory;
  final bool isSeller;

  @override
  Widget build(BuildContext context) {
    final listingMaps = listings
        .map((doc) => <String, dynamic>{...doc.data(), '_id': doc.id})
        .toList(growable: false);

    final liveAuctions = _buildLiveAuctions(
      listingMaps,
    ).take(6).toList(growable: false);
    final featuredListings = _buildFeaturedListings(listingMaps);
    final preferredCategories = _preferredCategoryTokens(recentlyViewedEntries);
    final nearby = _buildNearbyListings(
      listingMaps,
      buyerProvince: buyerProvince,
      buyerDistrict: buyerDistrict,
      buyerVillage: buyerVillage,
      buyerCity: buyerCity,
      preferredCategories: preferredCategories,
    );
    final nearbyUnique = nearby.take(4).toList(growable: false);
    final nearbyMandiSnapshot = _buildNearbyMandiSnapshotItems(
      mandiTickerItems,
    );
    final trending = _buildTrending(listingMaps);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1E3F2A).withValues(alpha: 0.52),
                      const Color(0xFF0F2F1E).withValues(alpha: 0.46),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFE8C766).withValues(alpha: 0.26),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(
                      title: 'Live Auctions / لائیو بولیاں',
                      subtitle:
                          'Active auctions for instant bidding\nفوری بولی کے لیے فعال آکشنز',
                      onSeeAll: onSeeAllAuctions,
                    ),
                    const SizedBox(height: 6),
                    if (liveAuctions.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryText.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primaryText24),
                        ),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No live auctions available right now.\nفی الحال کوئی لائیو بولی دستیاب نہیں۔',
                              style: TextStyle(
                                color: AppColors.secondaryText,
                                fontWeight: FontWeight.w600,
                                fontSize: 11.8,
                                height: 1.25,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Live auction activity will appear here.\nلائیو بولی کی سرگرمی یہاں ظاہر ہوگی۔',
                              style: TextStyle(
                                color: AppColors.primaryText60,
                                fontSize: 11.2,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      SizedBox(
                        height: MediaQuery.sizeOf(context).width < 360
                            ? 296
                            : 284,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          physics: const BouncingScrollPhysics(),
                          padding: const EdgeInsets.only(left: 2, right: 2),
                          itemCount: liveAuctions.length,
                          itemBuilder: (context, index) {
                            final item = liveAuctions[index];
                            final isFeaturedAuction = _isFeaturedAuction(item);
                            return _intelligenceListingCard(
                              key: ValueKey('hero_live_${item['_id']}'),
                              context: context,
                              data: item,
                              badge: isFeaturedAuction
                                  ? 'Featured'
                                  : 'Auction / بولی',
                              accent: isFeaturedAuction
                                  ? const Color(0xFFFF7043)
                                  : AppColors.accentGold,
                              showUrgency: true,
                              primaryValue:
                                  'Current Bid / موجودہ بولی: Rs. ${(_toDouble(item['highestBid']) ?? _toDouble(item['basePrice']) ?? _toDouble(item['price']) ?? 0).toStringAsFixed(0)}',
                              secondaryValue: _auctionTimeLabel(item),
                              tertiaryValue: _auctionEngagementLabel(item),
                              actionLabel: 'Place Bid / بولی لگائیں',
                              onPressed: () {
                                final id = (item['_id'] ?? '').toString();
                                if (id.trim().isEmpty) return;
                                onBid(item, id);
                              },
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF3D2E00).withValues(alpha: 0.55),
                  const Color(0xFF1E1A00).withValues(alpha: 0.50),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(
                  title: 'Featured Listings / نمایاں لسٹنگز',
                  subtitle:
                      'Featured and promoted listings from verified sellers\nتصدیق شدہ فروخت کنندگان کی نمایاں اور پروموٹڈ لسٹنگز',
                ),
                const SizedBox(height: 6),
                if (featuredListings.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: AppColors.accentGold.withValues(alpha: 0.30),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'No featured listings right now.\nفی الحال کوئی نمایاں لسٹنگ موجود نہیں۔',
                          style: TextStyle(
                            color: AppColors.primaryText,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            height: 1.25,
                          ),
                        ),
                        if (isSeller) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Promote your listing to appear here.\nاپنی لسٹنگ پروموٹ کریں تاکہ یہاں نظر آئے۔',
                            style: TextStyle(
                              color: AppColors.accentGold,
                              fontSize: 12,
                              height: 1.25,
                            ),
                          ),
                        ],
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 246,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      itemCount: featuredListings.length,
                      itemBuilder: (context, index) {
                        final item = featuredListings[index];
                        final trustBadges =
                            TrustSafetyService.resolveBuyerTrustBadges(
                              listingData: item,
                            );
                        final bool verified = trustBadges.any(
                          (badge) =>
                              badge.key == 'verified' || badge.key == 'trusted',
                        );
                        return _latestListingPreviewCard(
                          key: ValueKey('featured_${item['_id']}'),
                          data: item,
                          verified: verified,
                          showFeaturedBadge: true,
                          onTap: () {
                            final id = (item['_id'] ?? '').toString();
                            if (id.trim().isEmpty) return;
                            onBid(item, id);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: _buildNearbyMandiSnapshotSection(
            context,
            snapshotItems: nearbyMandiSnapshot,
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                title: 'Nearby Listings / آپ کے قریب',
                subtitle:
                    'Available offers near your location\nآپ کے مقام کے قریب دستیاب آفرز',
                onSeeAll: onSeeAllNearby,
              ),
              const SizedBox(height: 6),
              if (nearbyUnique.isEmpty)
                const Text(
                  'No nearby offers available right now.\nفی الحال قریب کی کوئی آفر دستیاب نہیں۔',
                  style: TextStyle(
                    color: AppColors.primaryText60,
                    height: 1.25,
                  ),
                )
              else
                SizedBox(
                  height: 248,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: nearbyUnique.length,
                    itemBuilder: (context, index) {
                      final item = nearbyUnique[index];
                      final saleType = (item['saleType'] ?? 'auction')
                          .toString()
                          .toLowerCase();
                      final isAuction = saleType == 'auction';
                      return _intelligenceListingCard(
                        key: ValueKey(item['_id'].toString()),
                        context: context,
                        data: item,
                        badge: isAuction
                            ? 'Auction / بولی'
                            : 'Fixed Price / فکسڈ قیمت',
                        accent: isAuction
                            ? Colors.deepOrangeAccent
                            : AppColors.dividerAccent,
                        primaryValue: isAuction
                            ? 'Current Bid / موجودہ بولی: Rs. ${(_toDouble(item['highestBid']) ?? _toDouble(item['basePrice']) ?? _toDouble(item['price']) ?? 0).toStringAsFixed(0)}'
                            : 'Price / قیمت: Rs. ${(_toDouble(item['price']) ?? _toDouble(item['basePrice']) ?? 0).toStringAsFixed(0)}',
                        secondaryValue: _locationLine(item),
                        actionLabel: isAuction
                            ? 'Place Bid / بولی لگائیں'
                            : 'Contact Seller / فروخت کنندہ سے رابطہ',
                        onPressed: () {
                          final id = (item['_id'] ?? '').toString();
                          if (id.trim().isEmpty) return;
                          if (!isAuction) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Contact unlocks after seller accepts your bid.',
                                ),
                              ),
                            );
                          }
                          onBid(item, id);
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                title: 'Categories / زمرہ جات',
                subtitle: 'Browse by mandi type / منڈی کی زمرہ بندی',
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _homeCategoryOrder.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.96,
                ),
                itemBuilder: (context, index) {
                  final type = _homeCategoryOrder[index];
                  if (type == null) {
                    return const SizedBox.shrink();
                  }
                  return _categoryGridTile(
                    icon: _categoryIcon(type),
                    label: _homeCategoryLabels[type] ?? type.label,
                    selected: selectedCategory == type,
                    onTap: () => onSelectCategory(type),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(
                title: 'Trending Today / آج کا ٹرینڈ',
                subtitle: 'Fast moving commodities\nتیزی سے چلنے والی اجناس',
              ),
              const SizedBox(height: 6),
              if (trending.isEmpty)
                const Text(
                  'Trending commodities will show as trading grows.\nٹریڈنگ بڑھنے پر ٹرینڈنگ اشیاء یہاں آئیں گی۔',
                  style: TextStyle(
                    color: AppColors.primaryText60,
                    height: 1.25,
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: trending
                      .map(
                        (item) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryText.withValues(
                              alpha: 0.10,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: AppColors.accentGold.withValues(
                                alpha: 0.32,
                              ),
                            ),
                          ),
                          child: Text(
                            '${item.name} (${item.count})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sectionHeader({
    required String title,
    String? subtitle,
    VoidCallback? onSeeAll,
    Widget? trailing,
  }) {
    final Widget actionWidget =
        trailing ??
        (onSeeAll != null
            ? TextButton(
                onPressed: onSeeAll,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
                child: const Text(
                  'See All / سب دیکھیں',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : const SizedBox.shrink());

    final Widget textBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 3,
              height: 16,
              decoration: BoxDecoration(
                color: AppColors.accentGold.withValues(alpha: 0.80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ],
        ),
        if ((subtitle ?? '').trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: Text(
              subtitle!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
                height: 1.25,
              ),
            ),
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool stackAction =
            constraints.maxWidth < 360 &&
            (trailing != null || onSeeAll != null);
        if (stackAction) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              textBlock,
              const SizedBox(height: 6),
              Align(alignment: Alignment.centerLeft, child: actionWidget),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: textBlock),
            if (trailing != null || onSeeAll != null)
              Flexible(fit: FlexFit.loose, child: actionWidget),
          ],
        );
      },
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondarySurface),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.18),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  List<_MandiTickerItem> _buildNearbyMandiSnapshotItems(
    List<_MandiTickerItem> source,
  ) {
    if (source.isEmpty) return const <_MandiTickerItem>[];

    final chosen = <_MandiTickerItem>[];
    final subcategoryKeys = <String>{};
    final dedupeKeys = <String>{};

    for (final item in source) {
      if (chosen.length >= 4) break;
      final subcategory = item.subcategoryKey.trim().toLowerCase();
      if (subcategory.isEmpty || subcategoryKeys.contains(subcategory)) continue;
      final commodity = _normalizeCommodityKey(item.crop);
      if (commodity.isEmpty) continue;
      final dedupe = '$commodity|${_normalizeLocationToken(item.location)}';
      if (dedupeKeys.contains(dedupe)) continue;

      subcategoryKeys.add(subcategory);
      dedupeKeys.add(dedupe);
      chosen.add(item);
    }

    for (final item in source) {
      if (chosen.length >= 4) break;
      final commodity = _normalizeCommodityKey(item.crop);
      if (commodity.isEmpty) continue;
      final dedupe = '$commodity|${_normalizeLocationToken(item.location)}';
      if (dedupeKeys.contains(dedupe)) continue;
      dedupeKeys.add(dedupe);
      chosen.add(item);
    }

    debugPrint(
      '[MANDI_RENDER] finalSnapshotCandidates=${source.length} finalSnapshotRendered=${chosen.length}',
    );
    return chosen;
  }

  Widget _buildNearbyMandiSnapshotSection(
    BuildContext context, {
    required List<_MandiTickerItem> snapshotItems,
  }) {
    final locationLabel = mandiSnapshotContextLabelUr.trim().isNotEmpty
        ? mandiSnapshotContextLabelUr.trim()
        : _snapshotContextLabel();
    final guidance = _buildSnapshotGuidanceLine(
      locationLabel: locationLabel,
      items: snapshotItems,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Nearby Mandi Snapshot / آپ کی قریبی منڈی',
          subtitle: 'مختصر مقامی ریٹس اور رہنمائی',
          trailing: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AllMandiRatesScreen(
                    initialCategory: selectedCategory,
                    accountCity: selectedCity ?? buyerCity,
                    accountDistrict: selectedDistrict ?? buyerDistrict,
                    accountProvince: selectedProvince ?? buyerProvince,
                  ),
                ),
              );
            },
            child: const Text('See All / سب دیکھیں'),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'قریبی سیاق: $locationLabel',
          style: const TextStyle(
            color: AppColors.primaryText,
            fontSize: 11.6,
            fontWeight: FontWeight.w700,
          ),
        ),
        if ((mandiSnapshotFallbackNote ?? '').trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 3),
            child: Text(
              mandiSnapshotFallbackNote!.trim(),
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.6,
                height: 1.2,
              ),
            ),
          ),
        const SizedBox(height: 7),
        if (snapshotItems.isEmpty)
          Text(
            mandiTickerInfoText ?? 'اس وقت قریبی منڈی کا خلاصہ دستیاب نہیں۔',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 11,
              height: 1.25,
            ),
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: snapshotItems
                .map(
                  (item) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.softGlassSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.softGlassBorder,
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      '${_toUrduCommodityLabel(item.crop)} • ${_cleanTickerLocation(item.location)} • ${item.price.toStringAsFixed(0)} روپے ${item.trendSymbol}',
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
        const SizedBox(height: 7),
        Text(
          guidance,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 11,
            height: 1.25,
          ),
        ),
      ],
    );
  }

  String _snapshotContextLabel() {
    final city = _firstNonEmpty(<String?>[selectedCity, buyerCity]);
    if (city.isNotEmpty) return _toUrduLocationLabel(city);

    final district = _firstNonEmpty(<String?>[
      selectedDistrict,
      selectedTehsil,
      buyerDistrict,
    ]);
    if (district.isNotEmpty) return _toUrduLocationLabel(district);

    final province = _firstNonEmpty(<String?>[selectedProvince, buyerProvince]);
    if (province.isNotEmpty) return _toUrduLocationLabel(province);
    return 'پنجاب';
  }

  String _buildSnapshotGuidanceLine({
    required String locationLabel,
    required List<_MandiTickerItem> items,
  }) {
    if (items.isEmpty) {
      return '$locationLabel میں اس وقت مکمل مقامی ریٹس محدود ہیں۔ مزید تفصیل کے لیے سب دیکھیں کھولیں۔';
    }

    final topCrops = items
        .take(2)
        .map((item) => _toUrduCommodityLabel(item.crop).trim())
        .where((label) => label.isNotEmpty)
        .toList(growable: false);
    final cropText = topCrops.join(' اور ');
    if (cropText.isEmpty) {
      return '$locationLabel میں آج مختلف اجناس کے ریٹس نمایاں ہیں۔ مکمل تفصیل کے لیے سب دیکھیں کھولیں۔';
    }
    return '$locationLabel میں آج $cropText کے ریٹس نمایاں ہیں۔ خرید و فروخت سے پہلے مکمل ریٹس دیکھیں۔';
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final v = (value ?? '').trim();
      if (v.isNotEmpty && v.toLowerCase() != 'null') return v;
    }
    return '';
  }

  String _normalizeLocationToken(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';
    if (_urduToEnglishLocation.containsKey(value)) {
      return _urduToEnglishLocation[value]!.toLowerCase();
    }
    final lower = value.toLowerCase();
    if (_englishToUrduLocation.containsKey(lower)) return lower;

    return lower
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ignore: unused_element
  Widget _buildHighDemandPulseBlock(List<_PulseRow> pulseRows) {
    final scoreByName = <String, int>{};
    final labelByKey = <String, String>{};

    for (final row in pulseRows) {
      final key = _normalizeCommodityKey(row.name);
      if (key.isEmpty) continue;
      var score = 1;
      if (row.trendLabel.contains('↑')) score += 2;
      if (row.trendLabel.contains('↓')) score -= 1;
      scoreByName[key] = (scoreByName[key] ?? 0) + score;
      labelByKey[key] = _mergeCommodityLabel(labelByKey[key], row.name);
    }

    for (final item in mandiTickerItems) {
      final key = _normalizeCommodityKey(item.crop);
      if (key.isEmpty) continue;
      var score = 1;
      if (item.trendSymbol == '▲') score += 2;
      if (item.trendSymbol == '▼') score -= 1;
      scoreByName[key] = (scoreByName[key] ?? 0) + score;
      labelByKey[key] = _mergeCommodityLabel(labelByKey[key], item.crop);
    }

    final top = scoreByName.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    if (top.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'آج کی سب سے زیادہ مانگ',
            style: TextStyle(
              color: AppColors.primaryText,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'مانگ کے واضح اشارے دستیاب نہیں، نئی سرگرمی کے ساتھ اپڈیٹ ہوگا۔',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 11.2),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'آج کی سب سے زیادہ مانگ',
          style: TextStyle(
            color: AppColors.primaryText,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: top
              .take(5)
              .map((entry) {
                final label = _toUrduCommodityLabel(
                  labelByKey[entry.key] ?? entry.key,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFEFBA6E).withValues(alpha: 0.22),
                        AppColors.primaryText.withValues(alpha: 0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFF6D6A4).withValues(alpha: 0.38),
                    ),
                  ),
                  child: Text(
                    '$label ↑',
                    style: const TextStyle(
                      color: AppColors.primaryText,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              })
              .toList(growable: false),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildWeatherStrip() {
    final String location =
        _safeText(
          weatherData ?? const <String, dynamic>{},
          'displayDistrictUr',
          fallback: '',
        ).trim().isNotEmpty
        ? _safeText(
            weatherData ?? const <String, dynamic>{},
            'displayDistrictUr',
          )
        : (buyerDistrict.trim().isEmpty
              ? 'پنجاب'
              : _toUrduLocationLabel(buyerDistrict));
    final String condition = _safeText(
      weatherData ?? const <String, dynamic>{},
      'conditionUr',
      fallback: _safeText(
        weatherData ?? const <String, dynamic>{},
        'condition',
        fallback: _safeText(
          weatherData ?? const <String, dynamic>{},
          'description',
          fallback: 'صاف موسم',
        ),
      ),
    );
    final String tip = advisoryText.trim().isNotEmpty
        ? advisoryText.trim()
        : _farmerSuggestions(
            temp:
                _toDouble(weatherData?['temp']) ??
                _toDouble(weatherData?['temperature']) ??
                32,
            humidity: _toDouble(weatherData?['humidity']) ?? 50,
            rainChance:
                _toDouble(weatherData?['rainChance']) ??
                _toDouble(weatherData?['precipChance']) ??
                (_toDouble(weatherData?['isRainLikely']) == 1 ? 60 : 10),
          ).first;

    String headline;
    if (isWeatherLoading) {
      headline = 'موسم کی معلومات تازہ کی جا رہی ہیں';
    } else if (weatherFailed) {
      headline = 'موسم کی معلومات عارضی طور پر دستیاب نہیں';
    } else {
      headline = '$location • ${_tempLabel(weatherData)} • $condition';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE8C766).withValues(alpha: 0.2),
            AppColors.primaryText.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFE8C766).withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.wb_cloudy_rounded,
            color: Color(0xFFE8C766),
            size: 16,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _normalizeUrduAdvisory(tip, location),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 10.8,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _pulseSignalChip(_PulseRow row) {
    final bool isUp = row.trendLabel.contains('↑');
    final bool isDown = row.trendLabel.contains('↓');
    final Color accent = isUp
        ? Colors.lightGreenAccent
        : isDown
        ? AppColors.accentGoldAccent
        : const Color(0xFFE8E8E8);

    return Container(
      constraints: const BoxConstraints(minWidth: 120, maxWidth: 176),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryText24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 11.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${row.trendLabel} • Rs ${row.avgPrice.toStringAsFixed(0)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 10.8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _categoryIcon(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return Icons.grass_rounded;
      case MandiType.fruit:
        return Icons.apple_rounded;
      case MandiType.vegetables:
        return Icons.eco_rounded;
      case MandiType.flowers:
        return Icons.local_florist_rounded;
      case MandiType.livestock:
        return Icons.pets_rounded;
      case MandiType.milk:
        return Icons.water_drop_rounded;
      case MandiType.seeds:
        return Icons.grain_rounded;
      case MandiType.fertilizer:
        return Icons.science_rounded;
      case MandiType.machinery:
        return Icons.agriculture_rounded;
      case MandiType.tools:
        return Icons.build_rounded;
      case MandiType.dryFruits:
        return Icons.nature_rounded;
      case MandiType.spices:
        return Icons.spa_rounded;
    }
  }

  Widget _categoryGridTile({
    required IconData icon,
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    // Split bilingual 'English / اردو' label into two lines
    final slashIdx = label.indexOf(' / ');
    final englishPart = slashIdx > -1 ? label.substring(0, slashIdx) : label;
    final urduPart = slashIdx > -1 ? label.substring(slashIdx + 3) : '';

    final tile = Container(
      padding: const EdgeInsets.fromLTRB(5, 9, 5, 7),
      decoration: BoxDecoration(
        gradient: selected
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.accentGold.withValues(alpha: 0.22),
                  AppColors.accentGold.withValues(alpha: 0.09),
                ],
              )
            : null,
        color: selected ? null : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected
              ? AppColors.accentGold.withValues(alpha: 0.55)
              : AppColors.secondarySurface.withValues(alpha: 0.75),
          width: selected ? 1.2 : 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.14 : 0.07),
            blurRadius: selected ? 5 : 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(
                alpha: selected ? 0.22 : 0.11,
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 19,
              color: selected
                  ? AppColors.accentGold
                  : AppColors.accentGold.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            englishPart,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? AppColors.accentGold : AppColors.primaryText,
              fontSize: 9.8,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (urduPart.isNotEmpty)
            Text(
              urduPart,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected
                    ? AppColors.accentGold.withValues(alpha: 0.85)
                    : AppColors.secondaryText,
                fontSize: 9.2,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
        ],
      ),
    );

    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: tile,
      ),
    );
  }

  Widget _intelligenceListingCard({
    required Key key,
    required BuildContext context,
    required Map<String, dynamic> data,
    required String badge,
    required Color accent,
    required String primaryValue,
    required String secondaryValue,
    String? tertiaryValue,
    bool showUrgency = false,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    final product = _commodityName(data);
    final subcategory = _safeText(
      data,
      'subcategoryLabel',
      fallback: _safeText(data, 'subcategory', fallback: '--'),
    );
    final quantity =
        (_toDouble(data['quantity']) ?? _toDouble(data['qty']) ?? 0)
            .toStringAsFixed(0);
    final unit = _safeText(data, 'unit', fallback: '--');
    final imageUrl = _firstImageUrl(data);
    final progress = _auctionProgress(data);
    final saleType = (data['saleType'] ?? 'auction').toString().toLowerCase();
    final bool isAuction = saleType == 'auction';
    final double viewportWidth = MediaQuery.sizeOf(context).width;
    final double cardWidth = (viewportWidth - 56)
        .clamp(188.0, 236.0)
        .toDouble();
    final remaining = _toDate(
      data['endTime'],
    )?.difference(DateTime.now().toUtc());
    final endingSoon =
        remaining != null && !remaining.isNegative && remaining.inMinutes <= 20;
    final endingCritical =
        remaining != null && !remaining.isNegative && remaining.inSeconds <= 60;
    final highestBid = _toDouble(data['highestBid']) ?? 0;
    final base = _toDouble(data['basePrice']) ?? _toDouble(data['price']) ?? 0;
    final hasBidActivity = highestBid > base;

    return Card(
      key: key,
      margin: const EdgeInsets.only(right: 10),
      color: isAuction
          ? const Color(0xFF4A2313).withValues(alpha: 0.30)
          : AppColors.primaryText.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: endingSoon && showUrgency
              ? AppColors.urgencyRed.withValues(alpha: 0.78)
              : isAuction
              ? AppColors.accentGold.withValues(alpha: 0.48)
              : AppColors.primaryText.withValues(alpha: 0.22),
        ),
      ),
      elevation: endingSoon && showUrgency ? 2.5 : (showUrgency ? 2 : 0.8),
      shadowColor: AppColors.ctaTextDark.withValues(alpha: 0.10),
      child: SizedBox(
        width: cardWidth,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  height: showUrgency ? 70 : 64,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: imageUrl.isEmpty
                            ? Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF1B4A34),
                                      Color(0xFF0E2F21),
                                    ],
                                  ),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.inventory_2_rounded,
                                        color: AppColors.secondaryText,
                                        size: 22,
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Mandi Listing',
                                        style: TextStyle(
                                          color: AppColors.secondaryText,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Image.network(
                                imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      decoration: const BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                          colors: [
                                            Color(0xFF1B4A34),
                                            Color(0xFF0E2F21),
                                          ],
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported_rounded,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                              ),
                      ),
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: AppColors.primaryText,
                              fontSize: 9.8,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      if (showUrgency && endingSoon)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.urgencyRed.withValues(
                                alpha: 0.9,
                              ),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: AppColors.primaryText.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: Text(
                              endingCritical ? 'ENDING NOW' : 'ENDING SOON',
                              style: const TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                product,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subcategory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 10.5,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'Location / مقام: ${_locationLine(data)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Qty / مقدار: $quantity $unit',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                primaryValue,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: showUrgency && hasBidActivity
                      ? const Color(0xFFF1DE99)
                      : AppColors.primaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (showUrgency && endingCritical)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7B1010).withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: const Color(0xFFFF8F8F).withValues(alpha: 0.85),
                    ),
                  ),
                  child: Text(
                    secondaryValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFFB0B0),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              if (!(showUrgency && endingCritical))
                Text(
                  secondaryValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: endingSoon && showUrgency
                        ? const Color(0xFFFF8F8F)
                        : AppColors.primaryText60,
                    fontSize: 11,
                    fontWeight: endingSoon && showUrgency
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              if ((tertiaryValue ?? '').trim().isNotEmpty)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        tertiaryValue!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEFD88A),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              if (showUrgency && progress != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: AppColors.primaryText.withValues(
                        alpha: 0.18,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        endingSoon
                            ? const Color(0xFFFF7A7A)
                            : const Color(0xFFE8C766),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 34,
                child: ElevatedButton(
                  onPressed: onPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: endingSoon && showUrgency
                        ? AppColors.urgencyRed
                        : const Color(0xFFE8C766),
                    foregroundColor: endingSoon && showUrgency
                        ? AppColors.primaryText
                        : const Color(0xFF052A17),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    textStyle: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _latestListingPreviewCard({
    required Key key,
    required Map<String, dynamic> data,
    required bool verified,
    required VoidCallback onTap,
    bool showFeaturedBadge = false,
  }) {
    final product = _commodityName(data);
    final imageUrl = _firstImageUrl(data);
    final location = _locationLine(data);
    final saleType = (data['saleType'] ?? 'auction').toString().toLowerCase();
    final value = saleType == 'auction'
        ? (_toDouble(data['highestBid']) ??
              _toDouble(data['basePrice']) ??
              _toDouble(data['price']) ??
              0)
        : (_toDouble(data['price']) ?? _toDouble(data['basePrice']) ?? 0);
    final sellerBadge = (data['sellerBadge'] ?? '').toString().trim();
    final bool isFeaturedItem =
        showFeaturedBadge &&
        ((data['promotionStatus'] ?? '').toString().toLowerCase() == 'active' ||
            data['featured'] == true ||
            data['featuredAuction'] == true);
    final bool isFeaturedAuctionItem =
        isFeaturedItem &&
        (data['featuredAuction'] == true ||
            (saleType == 'auction' &&
                (data['promotionStatus'] ?? '').toString().toLowerCase() ==
                    'active'));
    final bool isAdminApproved = data['isApproved'] == true;

    return Card(
      key: key,
      margin: const EdgeInsets.only(right: 10),
      color: AppColors.primaryText.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFeaturedItem
              ? AppColors.accentGold.withValues(alpha: 0.65)
              : AppColors.primaryText.withValues(alpha: 0.22),
          width: isFeaturedItem ? 1.4 : 1.0,
        ),
      ),
      elevation: isFeaturedItem ? 3.5 : 1.5,
      shadowColor: isFeaturedItem
          ? AppColors.accentGold.withValues(alpha: 0.30)
          : AppColors.ctaTextDark.withValues(alpha: 0.18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 190,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 64,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: imageUrl.isEmpty
                              ? Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF1B4A34),
                                        Color(0xFF0E2F21),
                                      ],
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.inventory_2_rounded,
                                      color: AppColors.secondaryText,
                                      size: 22,
                                    ),
                                  ),
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [
                                              Color(0xFF1B4A34),
                                              Color(0xFF0E2F21),
                                            ],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.image_not_supported_rounded,
                                          color: AppColors.secondaryText,
                                        ),
                                      ),
                                ),
                        ),
                        if (isFeaturedItem)
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.68),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: AppColors.accentGold.withValues(
                                    alpha: 0.85,
                                  ),
                                ),
                              ),
                              child: Text(
                                isFeaturedAuctionItem
                                    ? '⭐ Featured Auction'
                                    : '⭐ Featured',
                                style: const TextStyle(
                                  color: AppColors.accentGold,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  product,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  location,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${saleType == 'auction' ? 'Current Bid / موجودہ بولی' : 'Price / قیمت'}: Rs. ${value.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEFD88A),
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (saleType == 'auction'
                                    ? const Color(0xFFFF7043)
                                    : const Color(0xFF4CAF50))
                                .withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color:
                              (saleType == 'auction'
                                      ? const Color(0xFFFF8A65)
                                      : const Color(0xFF66BB6A))
                                  .withValues(alpha: 0.72),
                        ),
                      ),
                      child: Text(
                        saleType == 'auction'
                            ? 'Auction / بولی'
                            : 'Fixed / مقررہ',
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (sellerBadge.isNotEmpty)
                      Expanded(
                        child: Text(
                          sellerBadge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryText60,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                if (verified || isAdminApproved)
                  Wrap(
                    spacing: 5,
                    runSpacing: 3,
                    children: [
                      if (verified)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.lightGreenAccent.withValues(
                              alpha: 0.16,
                            ),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.lightGreenAccent.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                          child: const Text(
                            'Verified Seller',
                            style: TextStyle(
                              color: Colors.lightGreenAccent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (isAdminApproved)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF64B5F6,
                            ).withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: const Color(
                                0xFF90CAF9,
                              ).withValues(alpha: 0.75),
                            ),
                          ),
                          child: const Text(
                            'Admin Approved',
                            style: TextStyle(
                              color: Color(0xFFBBDEFB),
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 4),
                SizedBox(
                  width: double.infinity,
                  height: 26,
                  child: OutlinedButton(
                    onPressed: onTap,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: const Color(0xFFE8C766).withValues(alpha: 0.65),
                      ),
                      foregroundColor: const Color(0xFFEFD88A),
                      padding: EdgeInsets.zero,
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: Text(
                      saleType == 'auction' ? 'Bid / بولی' : 'View / دیکھیں',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ignore: unused_element
  List<_PulseRow> _buildPulseRows(List<Map<String, dynamic>> listings) {
    final map = <String, _PulseAgg>{};
    for (final listing in listings) {
      final name = _commodityName(listing);
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      final price =
          _toDouble(listing['price']) ?? _toDouble(listing['basePrice']) ?? 0;
      final bid = _toDouble(listing['highestBid']) ?? price;
      final agg = map[key] ?? _PulseAgg(name: name);
      agg.count += 1;
      agg.priceSum += price;
      agg.bidSum += bid;
      map[key] = agg;
    }

    final rows = map.values.toList(growable: false)
      ..sort((a, b) => b.count.compareTo(a.count));

    return rows
        .take(4)
        .map((agg) {
          final avgPrice = agg.count == 0 ? 0.0 : agg.priceSum / agg.count;
          final avgBid = agg.count == 0 ? 0.0 : agg.bidSum / agg.count;
          String trend = 'stable';
          if (agg.count >= 3 && avgBid >= avgPrice) {
            trend = '↑ demand';
          } else if (avgBid < (avgPrice * 0.9)) {
            trend = '↓ price';
          } else if (agg.count <= 1) {
            trend = '↑ supply';
          }
          return _PulseRow(
            name: agg.name,
            avgPrice: avgPrice,
            trendLabel: trend,
          );
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _buildLiveAuctions(
    List<Map<String, dynamic>> listings,
  ) {
    final now = DateTime.now().toUtc();
    final auctions =
        listings
            .where((listing) {
              final saleType = (listing['saleType'] ?? 'auction')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (saleType != 'auction') return false;

              if (!_isLiveAuctionStatus(listing)) {
                return false;
              }

              final endTime = _toDate(listing['endTime']);
              if (endTime == null) return true;
              return endTime.isAfter(now);
            })
            .toList(growable: false)
          ..sort((a, b) {
            final priorityCompare = _auctionPriorityRank(
              b,
            ).compareTo(_auctionPriorityRank(a));
            if (priorityCompare != 0) return priorityCompare;

            final bidCountCompare = _bidCountValue(
              b,
            ).compareTo(_bidCountValue(a));
            if (bidCountCompare != 0) return bidCountCompare;

            final aTime = _toDate(a['endTime']);
            final bTime = _toDate(b['endTime']);
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            return aTime.compareTo(bTime);
          });

    return auctions.take(6).toList(growable: false);
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _takeUniqueListings(
    List<Map<String, dynamic>> listings,
    Set<String> seenIds, {
    required int limit,
  }) {
    final results = <Map<String, dynamic>>[];
    for (final listing in listings) {
      final id = (listing['_id'] ?? '').toString().trim();
      if (id.isEmpty || seenIds.contains(id)) continue;
      results.add(listing);
      seenIds.add(id);
      if (results.length >= limit) break;
    }
    return results;
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildRecentlyViewedListings(
    List<Map<String, dynamic>> listings,
    List<Map<String, dynamic>> recentEntries,
  ) {
    if (recentEntries.isEmpty) return const <Map<String, dynamic>>[];
    final byId = <String, Map<String, dynamic>>{};
    for (final listing in listings) {
      final id = (listing['_id'] ?? '').toString().trim();
      if (id.isNotEmpty) byId[id] = listing;
    }

    final rows = <Map<String, dynamic>>[];
    for (final entry in recentEntries) {
      final listingId = (entry['listingId'] ?? entry['id'] ?? '')
          .toString()
          .trim();
      if (listingId.isEmpty) continue;
      final listing = byId[listingId];
      if (listing != null) {
        rows.add(listing);
      }
    }
    return rows;
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildEndingSoonAuctions(
    List<Map<String, dynamic>> listings, {
    Set<String> excludeIds = const <String>{},
  }) {
    final now = DateTime.now().toUtc();
    final candidates =
        listings
            .where((listing) {
              final id = (listing['_id'] ?? '').toString().trim();
              if (id.isNotEmpty && excludeIds.contains(id)) return false;

              final saleType = (listing['saleType'] ?? 'auction')
                  .toString()
                  .toLowerCase();
              if (saleType != 'auction') return false;

              if (!_isLiveAuctionStatus(listing)) {
                return false;
              }

              final end = _toDate(listing['endTime']);
              if (end == null || !end.isAfter(now)) return false;
              return end.difference(now).inMinutes <= 120;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final priorityCompare = _auctionPriorityRank(
              b,
            ).compareTo(_auctionPriorityRank(a));
            if (priorityCompare != 0) return priorityCompare;

            final aEnd = _toDate(a['endTime']);
            final bEnd = _toDate(b['endTime']);
            if (aEnd == null && bEnd == null) return 0;
            if (aEnd == null) return 1;
            if (bEnd == null) return -1;
            return aEnd.compareTo(bEnd);
          });

    return candidates;
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildTrendingAuctions(
    List<Map<String, dynamic>> listings, {
    Set<String> excludeIds = const <String>{},
  }) {
    final now = DateTime.now().toUtc();
    final rows =
        listings
            .where((listing) {
              final id = (listing['_id'] ?? '').toString().trim();
              if (id.isNotEmpty && excludeIds.contains(id)) return false;

              final saleType = (listing['saleType'] ?? 'auction')
                  .toString()
                  .trim()
                  .toLowerCase();
              if (saleType != 'auction') return false;

              if (!_isLiveAuctionStatus(listing)) return false;

              final end = _toDate(listing['endTime']);
              if (end != null && !end.isAfter(now)) return false;
              return true;
            })
            .toList(growable: false)
          ..sort((a, b) {
            final priorityCompare = _auctionPriorityRank(
              b,
            ).compareTo(_auctionPriorityRank(a));
            if (priorityCompare != 0) return priorityCompare;

            final bidsCompare = _bidCountValue(b).compareTo(_bidCountValue(a));
            if (bidsCompare != 0) return bidsCompare;

            final bRecent =
                _toDate(b['highestBidAt']) ?? _toDate(b['updatedAt']);
            final aRecent =
                _toDate(a['highestBidAt']) ?? _toDate(a['updatedAt']);
            if (aRecent == null && bRecent == null) return 0;
            if (aRecent == null) return 1;
            if (bRecent == null) return -1;
            return bRecent.compareTo(aRecent);
          });

    return rows;
  }

  Set<String> _preferredCategoryTokens(
    List<Map<String, dynamic>> recentEntries,
  ) {
    final tokens = <String>{};
    for (final entry in recentEntries) {
      final category = (entry['category'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final subcategory = (entry['subcategory'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (category.isNotEmpty) tokens.add(category);
      if (subcategory.isNotEmpty) tokens.add(subcategory);
    }
    return tokens;
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildRecommendedListings(
    List<Map<String, dynamic>> listings, {
    required List<Map<String, dynamic>> recentlyViewedEntries,
    required String buyerProvince,
    required String buyerDistrict,
    required String buyerCity,
  }) {
    final preferred = _preferredCategoryTokens(recentlyViewedEntries);
    final recentIds = recentlyViewedEntries
        .map((entry) => (entry['listingId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final city = buyerCity.trim().toLowerCase();
    final district = buyerDistrict.trim().toLowerCase();
    final province = buyerProvince.trim().toLowerCase();

    final scored = <_ScoredListing>[];
    for (final listing in listings) {
      final id = (listing['_id'] ?? '').toString().trim();
      if (id.isEmpty || recentIds.contains(id)) continue;

      var score = 0;
      final category = _safeText(listing, 'category').toLowerCase();
      final subcategory = _safeText(listing, 'subcategory').toLowerCase();
      if (preferred.contains(subcategory)) score += 40;
      if (preferred.contains(category)) score += 28;

      final listingCity = _locationPart(listing, 'city');
      final listingDistrict = _locationPart(listing, 'district');
      final listingProvince = _locationPart(listing, 'province');
      if (city.isNotEmpty && listingCity == city) {
        score += 26;
      } else if (district.isNotEmpty && listingDistrict == district) {
        score += 20;
      } else if (province.isNotEmpty && listingProvince == province) {
        score += 14;
      }

      final bidderCount =
          ((_toDouble(listing['bidderCount']) ?? 0) +
                  (_toDouble(listing['bidsCount']) ?? 0) +
                  (_toDouble(listing['totalBidders']) ?? 0))
              .toInt();
      score += bidderCount.clamp(0, 8);
      score += _featuredRank(listing) * 12;

      final saleType = (listing['saleType'] ?? 'auction')
          .toString()
          .toLowerCase();
      if (saleType == 'auction') score += 4;

      if (score > 0) {
        scored.add(_ScoredListing(listing: listing, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final aTime = _toDate(a.listing['createdAt']);
      final bTime = _toDate(b.listing['createdAt']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return scored.map((entry) => entry.listing).toList(growable: false);
  }

  bool _isFeaturedListing(Map<String, dynamic> listing) {
    final status = (listing['promotionStatus'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      final expires = listing['promotionExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) {
        return false;
      }
      return true;
    }
    if (status.isNotEmpty && status != 'none') {
      return false;
    }
    final priority = (listing['priorityScore'] ?? '').toString().toLowerCase();
    return listing['featured'] == true ||
        listing['featuredAuction'] == true ||
        priority == 'high';
  }

  bool _isFeaturedAuction(Map<String, dynamic> listing) {
    final saleType = (listing['saleType'] ?? 'auction')
        .toString()
        .toLowerCase();
    return saleType == 'auction' && _isFeaturedListing(listing);
  }

  int _featuredRank(Map<String, dynamic> listing) {
    return _isFeaturedListing(listing) ? 1 : 0;
  }

  int _auctionPriorityRank(Map<String, dynamic> listing) {
    final saleType = (listing['saleType'] ?? 'auction')
        .toString()
        .trim()
        .toLowerCase();
    if (saleType != 'auction') return 0;

    final promotionStatus = (listing['promotionStatus'] ?? '')
        .toString()
        .toLowerCase();
    final promotionType = (listing['promotionType'] ?? '')
        .toString()
        .toLowerCase();
    final priorityScore = (listing['priorityScore'] ?? '')
        .toString()
        .toLowerCase();

    final isPromotedPremium =
        promotionStatus == 'active' &&
        (promotionType.contains('premium') ||
            promotionType.contains('promoted') ||
            priorityScore == 'premium');
    if (isPromotedPremium) return 3;
    if (_isFeaturedAuction(listing)) return 2;
    return 1;
  }

  bool _isLiveAuctionStatus(Map<String, dynamic> listing) {
    final auctionStatus = _canonicalAuctionState(
      (listing['auctionStatus'] ?? '').toString().toLowerCase(),
    );
    final listingStatus = _canonicalAuctionState(
      (listing['status'] ?? listing['listingStatus'] ?? '')
          .toString()
          .toLowerCase(),
    );
    return auctionStatus == 'live' || listingStatus == 'live';
  }

  String _canonicalAuctionState(String value) {
    switch (value.trim().toLowerCase()) {
      case 'approved':
      case 'active':
      case 'open':
      case 'running':
      case 'auction_live':
      case 'live':
        return 'live';
      case 'paused':
        return 'paused';
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return 'cancelled';
      case 'ended':
      case 'closed':
      case 'completed':
      case 'ended_waiting_seller':
        return 'ended_waiting_seller';
      case 'expired':
      case 'expired_unsold':
        return 'expired_unsold';
      case 'bid_accepted':
      case 'approved_winner':
        return 'bid_accepted';
      default:
        return value.trim().toLowerCase();
    }
  }

  int _bidCountValue(Map<String, dynamic> listing) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final counts = <int>[
      parseInt(listing['totalBids']),
      parseInt(listing['bidsCount']),
      parseInt(listing['bidCount']),
      parseInt(listing['bid_count']),
    ];
    return counts.reduce((a, b) => a > b ? a : b);
  }

  List<Map<String, dynamic>> _buildFeaturedListings(
    List<Map<String, dynamic>> listings,
  ) {
    final featured = listings.where(_isFeaturedListing).toList(growable: false)
      ..sort((a, b) {
        final featuredAuctionCompare = _featuredRank(
          b,
        ).compareTo(_featuredRank(a));
        if (featuredAuctionCompare != 0) return featuredAuctionCompare;

        final bAuction = _isFeaturedAuction(b) ? 1 : 0;
        final aAuction = _isFeaturedAuction(a) ? 1 : 0;
        final auctionCompare = bAuction.compareTo(aAuction);
        if (auctionCompare != 0) return auctionCompare;

        final aTime = _toDate(a['createdAt']);
        final bTime = _toDate(b['createdAt']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

    return featured.take(4).toList(growable: false);
  }

  // ignore: unused_element
  List<Map<String, dynamic>> _buildLatestApprovedListings(
    List<Map<String, dynamic>> listings,
  ) {
    final sorted = List<Map<String, dynamic>>.from(listings)
      ..sort((a, b) {
        final aTime = _toDate(a['createdAt']);
        final bTime = _toDate(b['createdAt']);
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    return sorted.take(4).toList(growable: false);
  }

  String? _bidsLabel(Map<String, dynamic> listing) {
    final resolved = _bidCountValue(listing);
    if (resolved <= 0) return null;
    return '$resolved bids';
  }

  String? _watchersLabel(Map<String, dynamic> listing) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final resolved = parseInt(listing['watchersCount']);
    if (resolved <= 0) return null;
    return '👁️ $resolved watching';
  }

  String? _auctionEngagementLabel(Map<String, dynamic> listing) {
    final parts = <String>[];
    final bids = _bidsLabel(listing);
    final watchers = _watchersLabel(listing);
    if (bids != null && bids.trim().isNotEmpty) {
      parts.add('🔥 $bids');
    }
    if (watchers != null && watchers.trim().isNotEmpty) {
      parts.add(watchers);
    }
    if (parts.isEmpty) return null;
    return parts.join('   ');
  }

  double? _auctionProgress(Map<String, dynamic> listing) {
    final start = _toDate(listing['createdAt']);
    final end = _toDate(listing['endTime']);
    if (start == null || end == null) return null;
    final total = end.difference(start).inSeconds;
    if (total <= 0) return null;
    final elapsed = DateTime.now().toUtc().difference(start).inSeconds;
    final ratio = elapsed / total;
    return ratio.clamp(0.0, 1.0);
  }

  List<Map<String, dynamic>> _buildNearbyListings(
    List<Map<String, dynamic>> listings, {
    required String buyerProvince,
    required String buyerDistrict,
    required String buyerVillage,
    required String buyerCity,
    required Set<String> preferredCategories,
  }) {
    final province = buyerProvince.trim().toLowerCase();
    final district = buyerDistrict.trim().toLowerCase();
    final village = buyerVillage.trim().toLowerCase();
    final city = buyerCity.trim().toLowerCase();

    final scored = <_ScoredListing>[];
    for (final listing in listings) {
      final listingVillage = _locationPart(listing, 'village').isEmpty
          ? _locationPart(listing, 'cityVillage')
          : _locationPart(listing, 'village');
      final listingProvince = _locationPart(listing, 'province');
      final listingDistrict = _locationPart(listing, 'district');
      final listingCity = _locationPart(listing, 'city');
      final listingCountry = _locationPart(listing, 'country');
      final listingCategory = _safeText(listing, 'category').toLowerCase();
      final listingSubcategory = _safeText(
        listing,
        'subcategory',
      ).toLowerCase();

      var score = 0;
      if (village.isNotEmpty && village == listingVillage) {
        score = 60;
      } else if (district.isNotEmpty && district == listingDistrict) {
        score = 50;
      } else if (city.isNotEmpty && city == listingCity) {
        score = 40;
      } else if (province.isNotEmpty && province == listingProvince) {
        score = 30;
      } else if (listingCountry == 'pakistan') {
        score = 20;
      } else if (preferredCategories.contains(listingCategory) ||
          preferredCategories.contains(listingSubcategory)) {
        score = 10;
      }

      if (score > 0) {
        scored.add(_ScoredListing(listing: listing, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;
      final aTime = _toDate(a.listing['createdAt']);
      final bTime = _toDate(b.listing['createdAt']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });

    return scored.take(4).map((e) => e.listing).toList(growable: false);
  }

  List<_TrendingCommodity> _buildTrending(List<Map<String, dynamic>> listings) {
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final listing in listings) {
      final key = _subcategoryId(listing);
      final name = _commodityName(listing);
      if (key.isEmpty || name.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      names[key] = name;
    }

    final rows =
        counts.entries
            .map(
              (entry) => _TrendingCommodity(
                name: names[entry.key] ?? entry.key,
                count: entry.value,
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.count.compareTo(a.count));

    return rows.take(5).toList(growable: false);
  }

  String _auctionTimeLabel(Map<String, dynamic> listing) {
    final end = _toDate(listing['endTime']);
    if (end == null) return 'Live now';
    final now = DateTime.now().toUtc();
    final remaining = end.difference(now);
    if (remaining.isNegative) return 'Closed';
    if (remaining.inSeconds < 60) {
      return '${remaining.inSeconds}s left';
    }
    if (remaining.inMinutes < 60) {
      final mins = remaining.inMinutes;
      final secs = remaining.inSeconds.remainder(60);
      return '${mins}m ${secs.toString().padLeft(2, '0')}s left';
    }
    final hours = remaining.inHours;
    final mins = remaining.inMinutes.remainder(60);
    return '${hours}h ${mins}m left';
  }

  String _locationLine(Map<String, dynamic> listing) {
    final city = _locationPart(listing, 'city');
    final district = _locationPart(listing, 'district');
    final province = _locationPart(listing, 'province');
    if (city.isNotEmpty) return city;
    if (district.isNotEmpty) return district;
    if (province.isNotEmpty) return province;
    return 'Pakistan';
  }

  String _commodityName(Map<String, dynamic> listing) {
    final product = _safeText(listing, 'product');
    if (product.isNotEmpty) return product;
    final subLabel = _safeText(listing, 'subcategoryLabel');
    if (subLabel.isNotEmpty) return subLabel;
    final sub = _safeText(listing, 'subcategory');
    if (sub.isNotEmpty) return sub;
    return 'Commodity';
  }

  String _normalizeCommodityKey(String input) {
    final normalized = _toUrduCommodityLabel(input)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    return normalized;
  }

  String _mergeCommodityLabel(String? existing, String incoming) {
    final incomingLabel = _toUrduCommodityLabel(incoming).trim();
    if (incomingLabel.isEmpty) return existing ?? '';
    if (existing == null || existing.trim().isEmpty) return incomingLabel;
    final current = _toUrduCommodityLabel(existing).trim();
    if (current.toLowerCase() == incomingLabel.toLowerCase()) return current;
    return incomingLabel.length <= current.length ? incomingLabel : current;
  }

  // ignore: unused_element
  String _buildTodayImportantChange({required List<_PulseRow> pulseRows}) {
    final demandTop = _topDemandCommodity(pulseRows);
    if (demandTop != null) {
      return 'آج کی اہم تبدیلی: ${_toUrduCommodityLabel(demandTop)} کی مانگ میں واضح حرکت دیکھی گئی ہے۔';
    }

    final mandiTop = mandiTickerItems.isNotEmpty
        ? mandiTickerItems.first
        : null;
    if (mandiTop != null) {
      final symbol = mandiTop.trendSymbol;
      if (symbol == '▲') {
        return 'آج کی اہم تبدیلی: ${_toUrduCommodityLabel(mandiTop.crop)} کی قیمت میں اضافہ دیکھا گیا ہے۔';
      }
      if (symbol == '▼') {
        return 'آج کی اہم تبدیلی: ${_toUrduCommodityLabel(mandiTop.crop)} کی قیمت میں کمی ریکارڈ ہوئی ہے۔';
      }
      return 'آج کی اہم تبدیلی: ${_toUrduCommodityLabel(mandiTop.crop)} کی بولی آج نسبتاً مستحکم رہی۔';
    }

    return 'آج کی اہم تبدیلی: منڈی سرگرمی کے تازہ اشارے جلد نمایاں ہوں گے۔';
  }

  String? _topDemandCommodity(List<_PulseRow> pulseRows) {
    if (pulseRows.isEmpty) return null;
    final sorted = List<_PulseRow>.from(pulseRows)
      ..sort((a, b) => b.avgPrice.compareTo(a.avgPrice));
    final name = sorted.first.name.trim();
    return name.isEmpty ? null : name;
  }

  String _normalizeUrduAdvisory(String tip, String location) {
    var cleaned = tip.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.isEmpty) {
      return 'آج $location میں موسم نسبتاً سازگار ہے۔ عمومی فصلوں کی آبپاشی اور ذخیرہ کاری جاری رکھیں۔';
    }
    if (RegExp(r'[A-Za-z]').hasMatch(cleaned)) {
      cleaned =
          'آج $location میں موسم نسبتاً سازگار ہے۔ عمومی فصلوں کی آبپاشی اور ذخیرہ کاری جاری رکھیں۔';
    }
    return cleaned;
  }

  String _toUrduCommodityLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(value)) return value;

    final lower = value.toLowerCase();
    if (_englishToUrduCommodity.containsKey(lower)) {
      return _englishToUrduCommodity[lower]!;
    }
    if (lower.contains('wheat')) return 'گندم';
    if (lower.contains('rice') || lower.contains('paddy')) return 'چاول';
    if (lower.contains('corn') || lower.contains('maize')) return 'مکئی';
    if (lower.contains('mango')) return 'آم';
    if (lower.contains('cotton')) return 'کپاس';
    if (lower == 'dap') return 'ڈی اے پی';
    return value;
  }

  String _toUrduLocationLabel(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(value)) return value;
    final lower = value.toLowerCase();
    return _englishToUrduLocation[lower] ?? value;
  }

  String _cleanTickerLocation(String raw) {
    final value = _toUrduLocationLabel(raw).trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower == 'pakistan' || lower == 'all pakistan' || lower == 'pk') {
      return '';
    }
    if (value == 'پاکستان' || value == 'پورا پاکستان') return '';
    return value;
  }

  static const Map<String, String> _englishToUrduCommodity = <String, String>{
    'wheat': 'گندم',
    'rice': 'چاول',
    'paddy': 'چاول',
    'corn': 'مکئی',
    'maize': 'مکئی',
    'mango': 'آم',
    'cotton': 'کپاس',
    'dap': 'ڈی اے پی',
  };

  static const Map<String, String> _englishToUrduLocation = <String, String>{
    'lahore': 'لاہور',
    'kasur': 'قصور',
    'multan': 'ملتان',
    'faisalabad': 'فیصل آباد',
    'islamabad': 'اسلام آباد',
    'karachi': 'کراچی',
    'peshawar': 'پشاور',
    'quetta': 'کوئٹہ',
    'punjab': 'پنجاب',
    'sindh': 'سندھ',
  };

  static const Map<String, String> _urduToEnglishLocation = <String, String>{
    'لاہور': 'Lahore',
    'قصور': 'Kasur',
    'ملتان': 'Multan',
    'فیصل آباد': 'Faisalabad',
    'اسلام آباد': 'Islamabad',
    'کراچی': 'Karachi',
    'پشاور': 'Peshawar',
    'کوئٹہ': 'Quetta',
    'پنجاب': 'Punjab',
    'سندھ': 'Sindh',
  };

  String _subcategoryId(Map<String, dynamic> listing) {
    final sub = _safeText(listing, 'subcategory').toLowerCase();
    if (sub.isNotEmpty) return sub;
    final product = _safeText(listing, 'product').toLowerCase();
    if (product.isEmpty) return '';
    return product
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _locationPart(Map<String, dynamic> listing, String key) {
    final direct = _safeText(listing, key).toLowerCase();
    if (direct.isNotEmpty && direct != 'null') return direct;
    final locationData = listing['locationData'];
    if (locationData is Map) {
      final nested = (locationData[key] ?? '').toString().trim().toLowerCase();
      if (nested.isNotEmpty && nested != 'null') return nested;
    }
    return '';
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  double? _toDouble(dynamic value) {
    if (value is bool) return value ? 1 : 0;
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  String _firstImageUrl(Map<String, dynamic> listing) {
    final direct = [
      _safeText(listing, 'thumbnailUrl'),
      _safeText(listing, 'imageUrl'),
      _safeText(listing, 'photoUrl'),
      _safeText(listing, 'trustPhotoUrl'),
      _safeText(listing, 'verificationTrustPhotoUrl'),
      _safeText(listing, 'videoThumbnailUrl'),
    ].firstWhere((e) => e.trim().isNotEmpty, orElse: () => '');
    if (direct.isNotEmpty) return direct;

    final images = listing['imageUrls'];
    if (images is List && images.isNotEmpty) {
      final first = images.first.toString().trim();
      if (first.isNotEmpty) return first;
    }

    final media = listing['mediaMetadata'];
    if (media is Map) {
      final mediaImages = media['imageUrls'];
      if (mediaImages is List && mediaImages.isNotEmpty) {
        final first = mediaImages.first.toString().trim();
        if (first.isNotEmpty && first.toLowerCase() != 'null') return first;
      }
      final trust = media['verificationTrustPhoto'];
      if (trust is Map) {
        final trustUrl = (trust['url'] ?? '').toString().trim();
        if (trustUrl.isNotEmpty && trustUrl.toLowerCase() != 'null') {
          return trustUrl;
        }
      }
    }
    return '';
  }

  // ignore: unused_element
  bool _isQurbaniListing(Map<String, dynamic> data) {
    if (data['isSeasonalQurbani'] == true) return true;

    final tagsRaw = data['seasonalTags'];
    if (tagsRaw is List) {
      final tags = tagsRaw
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (tags.contains('qurbani')) return true;
    }

    final product = (data['product'] ?? '').toString();
    return SeasonalMarketRules.isQurbaniEligibleProduct(product);
  }

  String _tempLabel(Map<String, dynamic>? weather) {
    final temp =
        _toDouble(weather?['temp']) ?? _toDouble(weather?['temperature']);
    if (temp == null) return '--°C';
    return '${temp.round()}°C';
  }

  List<String> _farmerSuggestions({
    required double temp,
    required double humidity,
    required double rainChance,
  }) {
    final tips = <String>[];
    if (temp >= 35) {
      tips.add('گرمی زیادہ ہے، دودھ اور سبزی کی کولڈ اسٹوریج احتیاط سے رکھیں۔');
    }
    if (rainChance >= 40) {
      tips.add('بارش کا امکان ہے، فصل اور چارہ محفوظ جگہ منتقل کریں۔');
    }
    if (humidity >= 65) {
      tips.add('نمی زیادہ ہے، پیاز اور خشک اجناس ہوادار جگہ میں رکھیں۔');
    }
    if (tips.isEmpty) {
      tips.add('موسم معتدل ہے، آبپاشی اور اسٹوریج معمول کے مطابق جاری رکھیں۔');
    }
    return tips;
  }

  static String _safeText(
    Map<String, dynamic> map,
    String key, {
    String fallback = '',
  }) {
    final text = (map[key] ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }
}

class _PulseAgg {
  _PulseAgg({required this.name});

  final String name;
  int count = 0;
  double priceSum = 0;
  double bidSum = 0;
}

enum _MandiFetchStage { exactCity, nearestCity, district, province }

class _MandiFetchContext {
  const _MandiFetchContext({
    required this.cityEn,
    required this.cityUr,
    required this.districtEn,
    required this.districtUr,
    required this.provinceEn,
    required this.provinceUr,
    required this.nearestCityCandidatesEn,
    required this.latitude,
    required this.longitude,
  });

  final String cityEn;
  final String cityUr;
  final String districtEn;
  final String districtUr;
  final String provinceEn;
  final String provinceUr;
  final List<String> nearestCityCandidatesEn;
  final double? latitude;
  final double? longitude;
}

class _MandiStageFetchResult {
  const _MandiStageFetchResult({
    required this.docs,
    required this.stageUsed,
    required this.contextLabelUr,
    required this.fallbackNoteUr,
  });

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  final _MandiFetchStage stageUsed;
  final String contextLabelUr;
  final String? fallbackNoteUr;
}

class _MandiParseStats {
  _MandiParseStats({required this.fetchedDocs});

  final int fetchedDocs;
  int parsedItems = 0;
  int parsedValidItems = 0;
  int postQualityFilterItems = 0;
  int postDedupItems = 0;
  int postCityFirstItems = 0;
  int postSubcategoryDiversificationItems = 0;
  int rejectedItems = 0;
  int cityMismatchReject = 0;
  int missingCityReject = 0;
  int missingCommodityReject = 0;
  int freshnessReject = 0;
  int trustedSourceReject = 0;
  int invalidPriceReject = 0;
  int outlierReject = 0;
  int comparabilityReject = 0;
  int duplicateReject = 0;
  int emptySubcategoryReject = 0;
  int nonRenderableReject = 0;
  int finalTickerCandidates = 0;
  int finalTickerItems = 0;
  int finalSnapshotItems = 0;
}

class _MandiParseResult {
  const _MandiParseResult({required this.items, required this.stats});

  final List<_MandiTickerItem> items;
  final _MandiParseStats stats;
}

class _MandiTickerItem {
  const _MandiTickerItem({
    required this.crop,
    required this.location,
    required this.price,
    required this.trendSymbol,
    required this.subcategoryKey,
    required this.subcategoryLabel,
  });

  final String crop;
  final String location;
  final double price;
  final String trendSymbol;
  final String subcategoryKey;
  final String subcategoryLabel;
}

class _TickerCandidate {
  const _TickerCandidate({
    required this.item,
    required this.score,
    required this.commodityKey,
    required this.subcategoryKey,
    required this.tier,
  });

  final _MandiTickerItem item;
  final int score;
  final String commodityKey;
  final String subcategoryKey;
  final int tier;
}

class _PulseRow {
  const _PulseRow({
    required this.name,
    required this.avgPrice,
    required this.trendLabel,
  });

  final String name;
  final double avgPrice;
  final String trendLabel;
}

class _ScoredListing {
  const _ScoredListing({required this.listing, required this.score});

  final Map<String, dynamic> listing;
  final int score;
}

class _TrendingCommodity {
  const _TrendingCommodity({required this.name, required this.count});

  final String name;
  final int count;
}

class _KnownDistrict {
  const _KnownDistrict({
    required this.englishDistrict,
    required this.urduLabel,
    required this.lat,
    required this.lng,
  });

  final String englishDistrict;
  final String urduLabel;
  final double lat;
  final double lng;
}

class _BuyerListingsSection extends StatelessWidget {
  const _BuyerListingsSection({
    required this.stream,
    required this.winnerStream,
    required this.searchQuery,
    required this.selectedCategory,
    required this.selectedSubcategoryId,
    required this.selectedProvince,
    required this.selectedDistrict,
    required this.selectedTehsil,
    required this.selectedCity,
    required this.selectedSaleType,
    required this.selectedSort,
    required this.minPrice,
    required this.maxPrice,
    required this.minQuantity,
    required this.maxQuantity,
    required this.qurbaniOnly,
    required this.verifiedOnly,
    required this.buyerProvince,
    required this.buyerDistrict,
    required this.buyerVillage,
    required this.buyerCity,
    required this.recentlyViewedStream,
    required this.weatherData,
    required this.isWeatherLoading,
    required this.weatherFailed,
    required this.advisoryText,
    required this.mandiTickerItems,
    required this.mandiTickerInfoText,
    required this.mandiSnapshotContextLabelUr,
    required this.mandiSnapshotFallbackNote,
    required this.onBid,
    required this.onRefreshAiRates,
    required this.onSeeAllAuctions,
    required this.onSeeAllNearby,
    required this.onSelectCategory,
    this.isSeller = false,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>>? stream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? winnerStream;
  final String searchQuery;
  final MandiType? selectedCategory;
  final String? selectedSubcategoryId;
  final String? selectedProvince;
  final String? selectedDistrict;
  final String? selectedTehsil;
  final String? selectedCity;
  final String selectedSaleType;
  final String selectedSort;
  final double? minPrice;
  final double? maxPrice;
  final double? minQuantity;
  final double? maxQuantity;
  final bool qurbaniOnly;
  final bool verifiedOnly;
  final String buyerProvince;
  final String buyerDistrict;
  final String buyerVillage;
  final String buyerCity;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? recentlyViewedStream;
  final Map<String, dynamic>? weatherData;
  final bool isWeatherLoading;
  final bool weatherFailed;
  final String advisoryText;
  final List<_MandiTickerItem> mandiTickerItems;
  final String? mandiTickerInfoText;
  final String mandiSnapshotContextLabelUr;
  final String? mandiSnapshotFallbackNote;
  final void Function(Map<String, dynamic> data, String listingId) onBid;
  final Future<void> Function() onRefreshAiRates;
  final VoidCallback onSeeAllAuctions;
  final VoidCallback onSeeAllNearby;
  final ValueChanged<MandiType> onSelectCategory;
  final bool isSeller;
  static const double _bottomContentInset = 110;

  @override
  Widget build(BuildContext context) {
    const goldColor = AppColors.accentGold;
    final listingStream = stream;
    if (listingStream == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, _bottomContentInset),
        children: [
          _HomeIntelligenceHub(
            listings: const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            buyerProvince: buyerProvince,
            buyerDistrict: buyerDistrict,
            buyerVillage: buyerVillage,
            buyerCity: buyerCity,
            recentlyViewedEntries: const <Map<String, dynamic>>[],
            selectedProvince: selectedProvince,
            selectedDistrict: selectedDistrict,
            selectedTehsil: selectedTehsil,
            selectedCity: selectedCity,
            weatherData: weatherData,
            isWeatherLoading: isWeatherLoading,
            weatherFailed: weatherFailed,
            advisoryText: advisoryText,
            mandiTickerItems: mandiTickerItems,
            mandiTickerInfoText: mandiTickerInfoText,
            mandiSnapshotContextLabelUr: mandiSnapshotContextLabelUr,
            mandiSnapshotFallbackNote: mandiSnapshotFallbackNote,
            onBid: onBid,
            onSeeAllAuctions: onSeeAllAuctions,
            onSeeAllNearby: onSeeAllNearby,
            selectedCategory: selectedCategory,
            onSelectCategory: onSelectCategory,
            isSeller: isSeller,
          ),
          const SizedBox(height: 24),
          const Center(
            child: Text(
              'Listings are not available right now / اس وقت لسٹنگ دستیاب نہیں',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.secondaryText),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text(
              'Please check again shortly for fresh mandi offers / تازہ آفرز کے لیے تھوڑی دیر بعد دوبارہ دیکھیں',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.primaryText54),
            ),
          ),
        ],
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: listingStream,
      builder: (context, activeSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: winnerStream,
          builder: (context, winnerSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: recentlyViewedStream,
              builder: (context, recentSnapshot) {
                final recentEntries =
                    (recentSnapshot.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[])
                        .map(
                          (doc) => <String, dynamic>{
                            ...doc.data(),
                            'listingId': doc.id,
                          },
                        )
                        .toList(growable: false);

                final bool hasActiveError = activeSnapshot.hasError;
                final bool hasWinnerError = winnerSnapshot.hasError;
                if (activeSnapshot.connectionState == ConnectionState.waiting &&
                    winnerSnapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 140),
                      Center(
                        child: CircularProgressIndicator(color: goldColor),
                      ),
                    ],
                  );
                }

                final activeDocs = hasActiveError
                    ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                    : (activeSnapshot.data?.docs ??
                          const <
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >[]);
                final winnerDocs = hasWinnerError
                    ? const <QueryDocumentSnapshot<Map<String, dynamic>>>[]
                    : (winnerSnapshot.data?.docs ??
                          const <
                            QueryDocumentSnapshot<Map<String, dynamic>>
                          >[]);

                final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
                merged =
                    <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

                for (final doc in activeDocs) {
                  merged[doc.id] = doc;
                }

                for (final doc in winnerDocs) {
                  final status =
                      (doc.data()['listingStatus'] ??
                              doc.data()['status'] ??
                              '')
                          .toString()
                          .toLowerCase();
                  if (status == 'bid_accepted' || status == 'approved_winner') {
                    merged[doc.id] = doc;
                  }
                }

                final docs = merged.values.toList(growable: false);
                final filteredDocs = docs
                    .where((doc) {
                      final raw = doc.data();
                      final bool isApproved = raw['isApproved'] == true;
                      final String listingStatus =
                          (raw['listingStatus'] ?? raw['status'] ?? '')
                              .toString()
                              .toLowerCase();
                      final bool isAcceptedWinner =
                          listingStatus == 'bid_accepted' ||
                          listingStatus == 'approved_winner';
                      final MandiType listingType = _resolveListingType(raw);
                      final double price =
                          _toDouble(raw['price'] ?? raw['basePrice']) ?? 0;
                      final double quantity =
                          _toDouble(raw['quantity'] ?? raw['qty']) ?? 0;

                      final String normalizedSubcategory =
                          _resolveSubcategoryId(raw);
                      final String normalizedProvince = _resolveLocationPart(
                        raw,
                        'province',
                      );
                      final String normalizedDistrict = _resolveLocationPart(
                        raw,
                        'district',
                      );
                      final String normalizedTehsil = _resolveLocationPart(
                        raw,
                        'tehsil',
                      );
                      final String normalizedCity = _resolveLocationPart(
                        raw,
                        'city',
                      );
                      final String saleType = (raw['saleType'] ?? 'auction')
                          .toString()
                          .toLowerCase();

                      final bool priceMatch =
                          (minPrice == null || price >= minPrice!) &&
                          (maxPrice == null || price <= maxPrice!);
                      final bool subcategoryMatch =
                          (selectedSubcategoryId ?? '').trim().isEmpty ||
                          normalizedSubcategory ==
                              (selectedSubcategoryId ?? '')
                                  .trim()
                                  .toLowerCase();
                      final bool provinceMatch =
                          (selectedProvince ?? '').trim().isEmpty ||
                          normalizedProvince ==
                              (selectedProvince ?? '').trim().toLowerCase();
                      final bool districtMatch =
                          (selectedDistrict ?? '').trim().isEmpty ||
                          normalizedDistrict ==
                              (selectedDistrict ?? '').trim().toLowerCase();
                      final bool tehsilMatch =
                          (selectedTehsil ?? '').trim().isEmpty ||
                          normalizedTehsil ==
                              (selectedTehsil ?? '').trim().toLowerCase();
                      final bool cityMatch =
                          (selectedCity ?? '').trim().isEmpty ||
                          normalizedCity ==
                              (selectedCity ?? '').trim().toLowerCase();
                      final bool saleTypeMatch =
                          selectedSaleType == 'all' ||
                          saleType == selectedSaleType;
                      final bool qurbaniMatch =
                          !qurbaniOnly || _isQurbaniListing(raw);
                      final bool quantityMatch =
                          (minQuantity == null || quantity >= minQuantity!) &&
                          (maxQuantity == null || quantity <= maxQuantity!);
                      final bool verifiedMatch =
                          !verifiedOnly || _isVerifiedSeller(raw);
                      final bool searchMatch = _matchesSearch(raw, searchQuery);

                      return (isApproved || isAcceptedWinner) &&
                          searchMatch &&
                          (selectedCategory == null ||
                              listingType == selectedCategory) &&
                          subcategoryMatch &&
                          provinceMatch &&
                          districtMatch &&
                          tehsilMatch &&
                          cityMatch &&
                          saleTypeMatch &&
                          priceMatch &&
                          quantityMatch &&
                          qurbaniMatch &&
                          verifiedMatch;
                    })
                    .toList(growable: false);

                final sortedDocs = _sortListings(
                  filteredDocs,
                  sortBy: selectedSort,
                  buyerProvince: buyerProvince,
                  buyerDistrict: buyerDistrict,
                  buyerCity: buyerCity,
                );

                if (sortedDocs.isEmpty) {
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      _bottomContentInset,
                    ),
                    children: [
                      _HomeIntelligenceHub(
                        listings: docs,
                        buyerProvince: buyerProvince,
                        buyerDistrict: buyerDistrict,
                        buyerVillage: buyerVillage,
                        buyerCity: buyerCity,
                        recentlyViewedEntries: recentEntries,
                        selectedProvince: selectedProvince,
                        selectedDistrict: selectedDistrict,
                        selectedTehsil: selectedTehsil,
                        selectedCity: selectedCity,
                        weatherData: weatherData,
                        isWeatherLoading: isWeatherLoading,
                        weatherFailed: weatherFailed,
                        advisoryText: advisoryText,
                        mandiTickerItems: mandiTickerItems,
                        mandiTickerInfoText: mandiTickerInfoText,
                        mandiSnapshotContextLabelUr:
                          mandiSnapshotContextLabelUr,
                        mandiSnapshotFallbackNote: mandiSnapshotFallbackNote,
                        onBid: onBid,
                        onSeeAllAuctions: onSeeAllAuctions,
                        onSeeAllNearby: onSeeAllNearby,
                        selectedCategory: selectedCategory,
                        onSelectCategory: onSelectCategory,
                        isSeller: isSeller,
                      ),
                      const SizedBox(height: 24),
                      const Center(
                        child: Text(
                          'No listings match your search and filters / تلاش اور فلٹر کے مطابق لسٹنگ موجود نہیں',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.secondaryText),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Center(
                        child: Text(
                          'Try adjusting filters or check local market updates / فلٹر تبدیل کریں یا مقامی مارکیٹ اپڈیٹس دیکھیں',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.primaryText54),
                        ),
                      ),
                    ],
                  );
                }

                return RefreshIndicator(
                  color: goldColor,
                  onRefresh: onRefreshAiRates,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    cacheExtent: 650,
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      _bottomContentInset,
                    ),
                    itemCount: 1,
                    itemBuilder: (context, index) {
                      return _HomeIntelligenceHub(
                        listings: docs,
                        buyerProvince: buyerProvince,
                        buyerDistrict: buyerDistrict,
                        buyerVillage: buyerVillage,
                        buyerCity: buyerCity,
                        recentlyViewedEntries: recentEntries,
                        selectedProvince: selectedProvince,
                        selectedDistrict: selectedDistrict,
                        selectedTehsil: selectedTehsil,
                        selectedCity: selectedCity,
                        weatherData: weatherData,
                        isWeatherLoading: isWeatherLoading,
                        weatherFailed: weatherFailed,
                        advisoryText: advisoryText,
                        mandiTickerItems: mandiTickerItems,
                        mandiTickerInfoText: mandiTickerInfoText,
                        mandiSnapshotContextLabelUr:
                          mandiSnapshotContextLabelUr,
                        mandiSnapshotFallbackNote: mandiSnapshotFallbackNote,
                        onBid: onBid,
                        onSeeAllAuctions: onSeeAllAuctions,
                        onSeeAllNearby: onSeeAllNearby,
                        selectedCategory: selectedCategory,
                        onSelectCategory: onSelectCategory,
                        isSeller: isSeller,
                      );
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  bool _matchesSearch(Map<String, dynamic> raw, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;

    final fields = <String>[
      (raw['product'] ?? '').toString(),
      (raw['itemName'] ?? '').toString(),
      (raw['title'] ?? '').toString(),
      (raw['category'] ?? '').toString(),
      (raw['categoryLabel'] ?? '').toString(),
      (raw['subcategory'] ?? '').toString(),
      (raw['subcategoryLabel'] ?? '').toString(),
      (raw['mandiType'] ?? '').toString(),
      (raw['city'] ?? '').toString(),
      (raw['district'] ?? '').toString(),
      (raw['province'] ?? '').toString(),
      (raw['sellerName'] ?? '').toString(),
      (raw['ownerName'] ?? '').toString(),
      (raw['farmerName'] ?? '').toString(),
    ];

    final locationData = raw['locationData'];
    if (locationData is Map) {
      fields.add((locationData['city'] ?? '').toString());
      fields.add((locationData['district'] ?? '').toString());
      fields.add((locationData['province'] ?? '').toString());
      fields.add((locationData['tehsil'] ?? '').toString());
    }

    final haystack = fields.join(' ').toLowerCase();
    return haystack.contains(normalized);
  }

  bool _isVerifiedSeller(Map<String, dynamic> raw) {
    bool truthy(dynamic value) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text == 'true' || text == '1' || text == 'yes';
    }

    return truthy(raw['isAiVerifiedSeller']) ||
        truthy(raw['phoneVerified']) ||
        truthy(raw['isPhoneVerified']) ||
        truthy(raw['cnicVerified']) ||
        truthy(raw['isCnicVerified']) ||
        truthy(raw['adminVerified']) ||
        truthy(raw['isAdminVerified']) ||
        truthy(raw['isVerified']);
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _sortListings(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs, {
    required String sortBy,
    required String buyerProvince,
    required String buyerDistrict,
    required String buyerCity,
  }) {
    final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(docs);
    final now = DateTime.now().toUtc();

    int newestCompare(
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) {
      final featuredCompare = _featuredSortRank(
        b.data(),
      ).compareTo(_featuredSortRank(a.data()));
      if (featuredCompare != 0) return featuredCompare;

      final aTime =
          _toDate(a.data()['bumpedAt']) ??
          _toDate(a.data()['updatedAt']) ??
          _toDate(a.data()['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bTime =
          _toDate(b.data()['bumpedAt']) ??
          _toDate(b.data()['updatedAt']) ??
          _toDate(b.data()['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    }

    int priorityCompare(
      QueryDocumentSnapshot<Map<String, dynamic>> a,
      QueryDocumentSnapshot<Map<String, dynamic>> b,
    ) {
      return _featuredSortRank(b.data()).compareTo(_featuredSortRank(a.data()));
    }

    switch (sortBy) {
      case 'nearest':
        sorted.sort((a, b) {
          final p = priorityCompare(a, b);
          if (p != 0) return p;
          final aScore = _locationMatchScore(
            a.data(),
            buyerProvince,
            buyerDistrict,
            buyerCity,
          );
          final bScore = _locationMatchScore(
            b.data(),
            buyerProvince,
            buyerDistrict,
            buyerCity,
          );
          final scoreCompare = bScore.compareTo(aScore);
          if (scoreCompare != 0) return scoreCompare;
          return newestCompare(a, b);
        });
        break;
      case 'lowest_price':
        sorted.sort((a, b) {
          final p = priorityCompare(a, b);
          if (p != 0) return p;
          final aPrice =
              _toDouble(a.data()['price'] ?? a.data()['basePrice']) ?? 0;
          final bPrice =
              _toDouble(b.data()['price'] ?? b.data()['basePrice']) ?? 0;
          final priceCompare = aPrice.compareTo(bPrice);
          if (priceCompare != 0) return priceCompare;
          return newestCompare(a, b);
        });
        break;
      case 'highest_price':
        sorted.sort((a, b) {
          final p = priorityCompare(a, b);
          if (p != 0) return p;
          final aPrice =
              _toDouble(a.data()['price'] ?? a.data()['basePrice']) ?? 0;
          final bPrice =
              _toDouble(b.data()['price'] ?? b.data()['basePrice']) ?? 0;
          final priceCompare = bPrice.compareTo(aPrice);
          if (priceCompare != 0) return priceCompare;
          return newestCompare(a, b);
        });
        break;
      case 'ending_soon':
        sorted.sort((a, b) {
          final p = priorityCompare(a, b);
          if (p != 0) return p;
          final aEnd =
              _toDate(a.data()['endTime']) ??
              now.add(const Duration(days: 3650));
          final bEnd =
              _toDate(b.data()['endTime']) ??
              now.add(const Duration(days: 3650));
          final aLive = aEnd.isAfter(now);
          final bLive = bEnd.isAfter(now);
          if (aLive != bLive) return aLive ? -1 : 1;
          final endCompare = aEnd.compareTo(bEnd);
          if (endCompare != 0) return endCompare;
          return newestCompare(a, b);
        });
        break;
      case 'highest_bid':
        sorted.sort((a, b) {
          final p = priorityCompare(a, b);
          if (p != 0) return p;
          final aBid =
              _toDouble(a.data()['highestBid'] ?? a.data()['basePrice']) ?? 0;
          final bBid =
              _toDouble(b.data()['highestBid'] ?? b.data()['basePrice']) ?? 0;
          final bidCompare = bBid.compareTo(aBid);
          if (bidCompare != 0) return bidCompare;
          return newestCompare(a, b);
        });
        break;
      case 'newest':
      default:
        sorted.sort(newestCompare);
        break;
    }

    return sorted;
  }

  int _featuredSortRank(Map<String, dynamic> data) {
    final status = (data['promotionStatus'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      final expires = data['promotionExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) {
        return 0;
      }
      return 1;
    }
    if (status.isNotEmpty && status != 'none') return 0;
    final priority = (data['priorityScore'] ?? '').toString().toLowerCase();
    if (data['featured'] == true ||
        data['featuredAuction'] == true ||
        priority == 'high') {
      return 1;
    }
    return 0;
  }

  int _locationMatchScore(
    Map<String, dynamic> listing,
    String buyerProvince,
    String buyerDistrict,
    String buyerCity,
  ) {
    final city = _resolveLocationPart(listing, 'city');
    final district = _resolveLocationPart(listing, 'district');
    final province = _resolveLocationPart(listing, 'province');

    if (buyerCity.trim().isNotEmpty && city == buyerCity.trim().toLowerCase()) {
      return 3;
    }
    if (buyerDistrict.trim().isNotEmpty &&
        district == buyerDistrict.trim().toLowerCase()) {
      return 2;
    }
    if (buyerProvince.trim().isNotEmpty &&
        province == buyerProvince.trim().toLowerCase()) {
      return 1;
    }
    return 0;
  }

  MandiType _resolveListingType(Map<String, dynamic> data) {
    try {
      final rawType = (data['mandiType'] ?? '').toString().trim().toUpperCase();
      for (final type in MandiType.values) {
        if (type.wireValue == rawType) return type;
      }

      final product = (data['product'] ?? '').toString().toLowerCase();
      if (product.contains('milk') || product.contains('doodh')) {
        return MandiType.milk;
      }
      if (product.contains('goat') ||
          product.contains('bakra') ||
          product.contains('bhains') ||
          product.contains('bail')) {
        return MandiType.livestock;
      }
      if (product.contains('aam') ||
          product.contains('mango') ||
          product.contains('apple') ||
          product.contains('banana')) {
        return MandiType.fruit;
      }
      if (product.contains('aloo') ||
          product.contains('pyaz') ||
          product.contains('tamatar') ||
          product.contains('potato')) {
        return MandiType.vegetables;
      }
    } catch (e) {
      debugPrint('MANDI_TYPE_PARSE_ERROR|error=$e');
    }
    return MandiType.crops;
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  String _resolveSubcategoryId(Map<String, dynamic> data) {
    final direct = (data['subcategory'] ?? '').toString().trim().toLowerCase();
    if (direct.isNotEmpty && direct != 'null') return direct;

    final product = (data['product'] ?? '').toString().trim().toLowerCase();
    if (product.isEmpty || product == 'null') return '';

    final collapsed = product.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return collapsed
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  String _resolveLocationPart(Map<String, dynamic> data, String key) {
    final direct = (data[key] ?? '').toString().trim().toLowerCase();
    if (direct.isNotEmpty && direct != 'null') return direct;

    final locationDataRaw = data['locationData'];
    if (locationDataRaw is Map) {
      final nested = (locationDataRaw[key] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (nested.isNotEmpty && nested != 'null') return nested;
    }
    return '';
  }

  bool _isQurbaniListing(Map<String, dynamic> data) {
    if (data['isSeasonalQurbani'] == true) return true;

    final tagsRaw = data['seasonalTags'];
    if (tagsRaw is List) {
      final tags = tagsRaw
          .map((e) => e.toString().trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (tags.contains('qurbani')) return true;
    }

    final listingType = _resolveListingType(data);
    if (listingType != MandiType.livestock) return false;
    final product = (data['product'] ?? '').toString();
    return SeasonalMarketRules.isQurbaniEligibleProduct(product);
  }
}
