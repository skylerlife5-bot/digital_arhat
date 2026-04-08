import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../models/live_mandi_rate.dart';
import '../services/mandi_rate_location_service.dart';
import '../services/pakistan_mandi_priority_registry.dart';

class MandiRatesPage {
  const MandiRatesPage({
    required this.items,
    required this.cursor,
    required this.hasMore,
  });

  final List<LiveMandiRate> items;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class MandiFetchTrace {
  const MandiFetchTrace({
    required this.fetchedDocs,
    required this.parsedValidItems,
    required this.postDedupItems,
  });

  final int fetchedDocs;
  final int parsedValidItems;
  final int postDedupItems;
}

class _QueryFetchResult {
  const _QueryFetchResult({
    required this.items,
    required this.fetchedDocs,
    required this.parsedValidItems,
  });

  final List<LiveMandiRate> items;
  final int fetchedDocs;
  final int parsedValidItems;
}

class _ParseDocsResult {
  const _ParseDocsResult({required this.items, required this.fetchedDocs});

  final List<LiveMandiRate> items;
  final int fetchedDocs;
}

class MandiRatesRepository {
  MandiRatesRepository({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  static const String _primaryCollection = AppConstants.mandiRatesCollection;
  static const String _legacyCollection =
      AppConstants.pakistanMandiRatesCollection;
  static const List<String> _punjabProvinceQueryValues = <String>[
    'Punjab',
    'punjab',
    'پنجاب',
  ];

  List<LiveMandiRate> _memoryCache = const <LiveMandiRate>[];
  MandiFetchTrace? _lastFetchTrace;

  MandiFetchTrace? get lastFetchTrace => _lastFetchTrace;

  Query<Map<String, dynamic>> _primaryPunjabScope() {
    return _db
        .collection(_primaryCollection)
        .where('province', whereIn: _punjabProvinceQueryValues);
  }

  bool _isPunjabRate(LiveMandiRate item) {
    final city = item.city.trim().toLowerCase();
    final province = item.province.trim().toLowerCase();
    if (city == 'karachi' || city == 'کراچی') {
      return false;
    }
    return province == 'punjab' || province == 'پنجاب';
  }

  Stream<List<LiveMandiRate>> watchLiveRates({int limit = 150}) {
    return _buildPrimaryQuery(limit: limit)
        .snapshots()
        .map((snapshot) {
          final parsed = snapshot.docs
              .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))
              .where((item) => item.price > 0)
              .where(_isPunjabRate)
              .toList(growable: false);

          final deduped = _dedupe(parsed);
          _memoryCache = deduped;
          return deduped;
        })
        .handleError((Object error, StackTrace stack) {
          debugPrint(
            '[MANDI_STREAM_ERROR] Firestore watchLiveRates error: $error',
          );
          throw error;
        });
  }

  Query<Map<String, dynamic>> _buildPrimaryQuery({required int limit}) {
    return _primaryPunjabScope()
        .orderBy('syncedAt', descending: true)
        .limit(limit);
  }

  Query<Map<String, dynamic>> _buildFallbackOrderQuery({required int limit}) {
    return _primaryPunjabScope()
        .orderBy('rateDate', descending: true)
        .limit(limit);
  }

  Future<MandiRatesPage> fetchRatesPage({
    int pageSize = 50,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    Query<Map<String, dynamic>> query = _buildPrimaryQuery(limit: pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await query.get();
    } catch (_) {
      query = _buildFallbackOrderQuery(limit: pageSize);
      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }
      snapshot = await query.get();
    }

    final items = snapshot.docs
        .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))
        .where((item) => item.price > 0)
        .where(_isPunjabRate)
        .toList(growable: false);

    final deduped = _dedupe(items);
    if (deduped.isNotEmpty) {
      _memoryCache = _dedupe(<LiveMandiRate>[..._memoryCache, ...deduped]);
    }

    return MandiRatesPage(
      items: deduped,
      cursor: snapshot.docs.isEmpty ? startAfter : snapshot.docs.last,
      hasMore: snapshot.docs.length >= pageSize,
    );
  }

  Future<void> refreshFromUpstream() async {
    // Reads from Firestore are the source of truth for app clients.
    // Ingestion runs on backend scheduler; do not generate rates on device.
  }

  Future<List<LiveMandiRate>> fetchLocationAwareCandidates({
    required MandiLocationContext location,
    int targetCount = 120,
  }) async {
    final merged = <String, LiveMandiRate>{};
    var fetchedDocs = 0;
    var parsedValidItems = 0;

    Future<void> addScope(Future<_QueryFetchResult> Function() loader) async {
      if (merged.length >= targetCount) return;
      final result = await loader();
      fetchedDocs += result.fetchedDocs;
      parsedValidItems += result.parsedValidItems;
      for (final item in result.items) {
        merged[item.id] = item;
      }
    }

    final city = location.city.trim();
    final district = location.district.trim();
    final province = location.province.trim();
    final cityAliases = _expandCityAliases(city);

    if (cityAliases.isNotEmpty) {
      for (final alias in cityAliases) {
        await addScope(
          () => _fetchByFieldValue(field: 'city', value: alias, limit: 60),
        );
      }
    }

    if (location.locationAvailable) {
      final nearestPriority =
          PakistanMandiPriorityRegistry.nearestCityCandidates(
            latitude: location.latitude!,
            longitude: location.longitude!,
            excludeCity: city,
            limit: 6,
          );
      for (final nearestCity in nearestPriority) {
        for (final alias in _expandCityAliases(nearestCity)) {
          await addScope(
            () => _fetchByFieldValue(field: 'city', value: alias, limit: 45),
          );
          if (merged.length >= targetCount) break;
        }
        if (merged.length >= targetCount) break;
      }
    }

    final nearestDistricts = _nearestDistricts(district);
    for (final nearest in nearestDistricts) {
      if (nearest.toLowerCase() == district.toLowerCase()) continue;
      await addScope(
        () => _fetchByFieldValue(field: 'district', value: nearest, limit: 40),
      );
      if (merged.length >= targetCount) break;
    }

    if (district.isNotEmpty) {
      await addScope(
        () => _fetchByFieldValue(field: 'district', value: district, limit: 60),
      );
    }

    if (province.isNotEmpty) {
      await addScope(
        () => _fetchByFieldValue(field: 'province', value: province, limit: 80),
      );
    }

    if (merged.length < targetCount) {
      await addScope(() => _fetchGlobalRecent(limit: targetCount));
    }

    final list = _dedupe(merged.values.toList(growable: false));
    final strictCityOnly = _filterByUserCityOrDistrict(
      rates: list,
      userCity: city,
      userDistrict: district,
      cityAliases: cityAliases,
    );
    final selected = strictCityOnly.isNotEmpty
        ? strictCityOnly
        : list.where(_isPunjabRate).toList(growable: false);
    _lastFetchTrace = MandiFetchTrace(
      fetchedDocs: fetchedDocs,
      parsedValidItems: parsedValidItems,
      postDedupItems: selected.length,
    );
    debugPrint(
      '[MANDI_FETCH_TRACE] fetchedDocs=$fetchedDocs '
      'parsedValidItems=$parsedValidItems '
      'postDedupItems=${selected.length} '
      'strictCity=${city.isEmpty ? 'none' : city}',
    );
    if (selected.isNotEmpty) {
      _memoryCache = _dedupe(<LiveMandiRate>[
        ...selected,
        ..._memoryCache,
      ]);
    }
    return selected.take(targetCount).toList(growable: false);
  }

  List<LiveMandiRate> _filterByUserCityOrDistrict({
    required List<LiveMandiRate> rates,
    required String userCity,
    required String userDistrict,
    required List<String> cityAliases,
  }) {
    final normalizedAliases = cityAliases
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final normalizedCity = userCity.trim().toLowerCase();
    final normalizedDistrict = userDistrict.trim().toLowerCase();
    if (normalizedCity.isNotEmpty) {
      normalizedAliases.add(normalizedCity);
    }
    if (normalizedAliases.isEmpty && normalizedDistrict.isEmpty) return rates;

    return rates
        .where((rate) {
          final rateCity = rate.city.trim().toLowerCase();
          final rateDistrict = rate.district.trim().toLowerCase();
          if (rateCity.isEmpty && rateDistrict.isEmpty) return false;
          if (!_isPunjabRate(rate)) return false;
          final cityMatch = rateCity.isNotEmpty &&
              normalizedAliases.contains(rateCity);
          final districtMatch = normalizedDistrict.isNotEmpty &&
              rateDistrict.isNotEmpty &&
              rateDistrict == normalizedDistrict;
          return cityMatch || districtMatch;
        })
        .toList(growable: false);
  }

  Future<_QueryFetchResult> _fetchByFieldValue({
    required String field,
    required String value,
    required int limit,
  }) async {
    try {
      final query = await _primaryPunjabScope()
          .where(field, isEqualTo: value)
          .orderBy('rateDate', descending: true)
          .limit(limit)
          .get();
      final parsed = _parseDocs(query.docs);
      return _QueryFetchResult(
        items: parsed.items,
        fetchedDocs: parsed.fetchedDocs,
        parsedValidItems: parsed.items.length,
      );
    } catch (_) {
      try {
        final query = await _primaryPunjabScope()
            .where(field, isEqualTo: value)
            .orderBy('syncedAt', descending: true)
            .limit(limit)
            .get();
        final parsed = _parseDocs(query.docs);
        return _QueryFetchResult(
          items: parsed.items,
          fetchedDocs: parsed.fetchedDocs,
          parsedValidItems: parsed.items.length,
        );
      } catch (_) {
        return const _QueryFetchResult(
          items: <LiveMandiRate>[],
          fetchedDocs: 0,
          parsedValidItems: 0,
        );
      }
    }
  }

  Future<_QueryFetchResult> _fetchGlobalRecent({required int limit}) async {
    try {
      final query = await _buildPrimaryQuery(limit: limit).get();
      final parsed = _parseDocs(query.docs);
      return _QueryFetchResult(
        items: parsed.items,
        fetchedDocs: parsed.fetchedDocs,
        parsedValidItems: parsed.items.length,
      );
    } catch (_) {
      try {
        final query = await _buildFallbackOrderQuery(limit: limit).get();
        final parsed = _parseDocs(query.docs);
        return _QueryFetchResult(
          items: parsed.items,
          fetchedDocs: parsed.fetchedDocs,
          parsedValidItems: parsed.items.length,
        );
      } catch (_) {
        return const _QueryFetchResult(
          items: <LiveMandiRate>[],
          fetchedDocs: 0,
          parsedValidItems: 0,
        );
      }
    }
  }

  _ParseDocsResult _parseDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = docs
        .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))
        .where((item) => item.price > 0)
        .where(_isPunjabRate)
        .toList(growable: false);
    return _ParseDocsResult(items: items, fetchedDocs: docs.length);
  }

  List<String> _nearestDistricts(String district) {
    final current = district.trim().toLowerCase();
    if (current.isEmpty) return const <String>[];

    final nearest = <String>[district.trim()];
    for (final entry in AppConstants.districtDistancePairsKm.entries) {
      if (entry.value > 220) continue;
      final parts = entry.key.split('|');
      if (parts.length != 2) continue;
      final a = parts[0].trim();
      final b = parts[1].trim();

      if (a.toLowerCase() == current) nearest.add(b);
      if (b.toLowerCase() == current) nearest.add(a);
    }

    final seen = <String>{};
    final result = <String>[];
    for (final value in nearest) {
      final key = value.toLowerCase();
      if (key.isEmpty) continue;
      if (seen.add(key)) result.add(value);
    }
    return result;
  }

  Future<List<LiveMandiRate>> loadOfflineFallback() async {
    if (_memoryCache.isNotEmpty) return _memoryCache;

    QuerySnapshot<Map<String, dynamic>>? fallbackPrimary;
    try {
      fallbackPrimary = await _buildPrimaryQuery(limit: 120).get();
    } catch (_) {
      try {
        fallbackPrimary = await _buildFallbackOrderQuery(limit: 120).get();
      } catch (_) {
        fallbackPrimary = null;
      }
    }
    var parsed = fallbackPrimary == null
        ? <LiveMandiRate>[]
        : fallbackPrimary.docs
              .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))
              .where((item) => item.price > 0)
              .where(_isPunjabRate)
              .toList(growable: false);

    if (parsed.isEmpty) {
      try {
        final fallbackLegacy = await _db
            .collection(_legacyCollection)
            .orderBy('rateDate', descending: true)
            .limit(120)
            .get();
        parsed = fallbackLegacy.docs
            .map((doc) => LiveMandiRate.fromMap(doc.id, doc.data()))
            .where((item) => item.price > 0)
            .where(_isPunjabRate)
            .toList(growable: false);
      } catch (_) {
        parsed = const <LiveMandiRate>[];
      }
    }

    _memoryCache = _dedupe(parsed);
    return _memoryCache;
  }

  List<LiveMandiRate> _dedupe(List<LiveMandiRate> items) {
    final map = <String, LiveMandiRate>{};
    for (final item in items) {
      final key = [
        item.commodityName.trim().toLowerCase(),
        item.categoryName.trim().toLowerCase(),
        item.subCategoryName.trim().toLowerCase(),
        item.unit.trim().toLowerCase(),
        item.mandiName.trim().toLowerCase(),
        item.city.trim().toLowerCase(),
        item.district.trim().toLowerCase(),
      ].join('|');
      final existing = map[key];
      if (existing == null) {
        map[key] = item;
      } else if (item.sourcePriorityRank < existing.sourcePriorityRank) {
        map[key] = item;
      } else if (item.sourcePriorityRank == existing.sourcePriorityRank &&
          item.lastUpdated.isAfter(existing.lastUpdated)) {
        map[key] = item;
      }
    }

    final deduped = map.values.toList(growable: false)
      ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return deduped;
  }

  List<String> _expandCityAliases(String city) {
    final value = city.trim();
    if (value.isEmpty) return const <String>[];
    final set = <String>{value};

    final normalized = PakistanMandiPriorityRegistry.normalizeCity(value);
    if (normalized.isNotEmpty) {
      final target = PakistanMandiPriorityRegistry.top25.firstWhere(
        (item) =>
            PakistanMandiPriorityRegistry.normalizeCity(item.city) ==
            normalized,
        orElse: () => PriorityMandiTarget(
          city: value,
          district: value,
          province: '',
          aliases: <String>[value],
          priorityRank: 999,
          expectedSourceFamily: 'future_city_committee_source',
          latitude: 0,
          longitude: 0,
          enabled: true,
          futureReady: true,
        ),
      );
      set.addAll(target.aliases);
    }

    set.add(value.toLowerCase());
    set.add(value.replaceAll(' District', '').replaceAll(' City', '').trim());
    return set.where((item) => item.trim().isNotEmpty).toList(growable: false);
  }
}
