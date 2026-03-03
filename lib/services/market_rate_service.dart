import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

class MarketRate {
  final String cropName;
  final double currentPrice;
  final double change;
  final String trend;

  MarketRate({
    required this.cropName,
    required this.currentPrice,
    required this.change,
    required this.trend,
  });
}

class RealtimeRateService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const List<String> _defaultCrops = [
    'Gandum',
    'Kapas',
    'Chawal',
    'Makai',
    'Dal Chana',
  ];

  List<MarketRate> _currentRatesList = [];

  RealtimeRateService._internal();
  static final RealtimeRateService _instance = RealtimeRateService._internal();
  factory RealtimeRateService() => _instance;

  String _normalizeCategory(String category) {
    return category.trim().toLowerCase();
  }

  String _normalizeCrop(String cropName) {
    return cropName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  double? calculateMovingAverage(List<double> prices) {
    final valid = prices.where((price) => price > 0).toList();
    if (valid.isEmpty) return null;
    final sum = valid.fold<double>(0, (acc, value) => acc + value);
    return sum / valid.length;
  }

  bool _isSuccessfulEscrow(Map<String, dynamic> map) {
    final state = (map['state'] ?? '').toString().toUpperCase();
    final status = (map['status'] ?? '').toString().toLowerCase();
    final paymentStatus = (map['paymentStatus'] ?? '').toString().toLowerCase();

    return state == 'FUNDS_RELEASED' ||
        status == 'success' ||
        status == 'completed' ||
        paymentStatus == 'completed';
  }

  bool _categoryMatches(Map<String, dynamic> map, String normalizedCategory) {
    final candidates = <String>[
      (map['category'] ?? '').toString(),
      (map['mandiType'] ?? '').toString(),
      (map['cropName'] ?? '').toString(),
      (map['itemName'] ?? '').toString(),
      (map['product'] ?? '').toString(),
    ];

    return candidates.any((candidate) {
      final raw = candidate.trim().toLowerCase();
      if (raw.isEmpty) return false;
      return raw == normalizedCategory || raw.contains(normalizedCategory);
    });
  }

  double? _extractEscrowAmount(Map<String, dynamic> map) {
    final candidates = <dynamic>[
      map['baseAmount'],
      map['totalPaidByBuyer'],
      map['dealAmount'],
      map['finalPayoutToSeller'],
      map['price'],
      map['amount'],
    ];

    for (final candidate in candidates) {
      if (candidate is num && candidate > 0) return candidate.toDouble();
      final parsed = double.tryParse(candidate?.toString() ?? '');
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  Future<List<double>> _fetchVerifiedEscrowTransactionAmounts(
    String category, {
    int maxTransactions = 10,
  }) async {
    final normalizedCategory = _normalizeCategory(category);
    if (normalizedCategory.isEmpty) return const <double>[];

    final snapshot = await _db
        .collection('escrow_transactions')
        .orderBy('updatedAt', descending: true)
        .limit(120)
        .get();

    final amounts = <double>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();

      if (!_isSuccessfulEscrow(data)) continue;
      if (!_categoryMatches(data, normalizedCategory)) continue;

      final amount = _extractEscrowAmount(data);
      if (amount != null && amount > 0) {
        amounts.add(amount);
      }

      if (amounts.length >= maxTransactions) break;
    }

    return amounts;
  }

  Future<double?> getVerifiedMovingAverage(String category) async {
    final amounts = await _fetchVerifiedEscrowTransactionAmounts(category);
    if (amounts.isEmpty) return null;
    return calculateMovingAverage(amounts);
  }

  Future<Map<String, double>?> fetchRuleBasedRateSnapshot(
    String cropName,
  ) async {
    final amounts = await _fetchVerifiedEscrowTransactionAmounts(cropName);
    if (amounts.isEmpty) return null;

    final avg = calculateMovingAverage(amounts);
    if (avg == null || avg <= 0) return null;

    return {
      'average': avg,
      'min': amounts.reduce((a, b) => a < b ? a : b),
      'max': amounts.reduce((a, b) => a > b ? a : b),
      'sampleSize': amounts.length.toDouble(),
    };
  }

  Future<double?> fetchRuleBasedRate(String cropName) async {
    return getVerifiedMovingAverage(cropName);
  }

  Future<double?> fetchMandiRate(String cropName) async {
    return fetchRuleBasedRate(cropName);
  }

  Future<List<String>> fetchRecentNewsHeadlines(
    String cropName, {
    int limit = 3,
  }) async {
    final normalized = cropName.trim().toLowerCase();
    if (normalized.isEmpty) return const <String>[];

    try {
      final snapshot = await _db
          .collection('market_news')
          .orderBy('publishedAt', descending: true)
          .limit(30)
          .get();

      final headlines = <String>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final title = (data['title'] ?? data['headline'] ?? '')
            .toString()
            .trim();
        if (title.isEmpty) continue;

        final cropTag = (data['cropName'] ?? data['itemName'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (cropTag.isNotEmpty && cropTag != normalized) continue;

        headlines.add(title);
        if (headlines.length >= limit) break;
      }

      if (headlines.isNotEmpty) return headlines;
    } catch (_) {}

    return <String>['Local supply and transport updates are under review.'];
  }

  Future<void> refreshAndPersistTrendForCrop(String cropName) async {
    final snapshot = await fetchRuleBasedRateSnapshot(cropName);
    final currentRate = snapshot?['average'];
    if (currentRate == null || currentRate <= 0) return;

    final docId = _normalizeCrop(cropName);
    await _db.collection('market_trends').doc(docId).set({
      'cropName': cropName,
      'cropNameLower': docId,
      'currentRate': currentRate,
      'predictedHigh': snapshot?['max'] ?? currentRate,
      'predictedLow': snapshot?['min'] ?? currentRate,
      'predictedAverage': currentRate,
      'ruleBasedAverage': currentRate,
      'sampleSize': snapshot?['sampleSize']?.toInt() ?? 0,
      'source': 'ESCROW_VERIFIED_MOVING_AVERAGE',
      'generatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> refreshAndPersistAllTrends({
    List<String> crops = _defaultCrops,
  }) async {
    for (final crop in crops) {
      await refreshAndPersistTrendForCrop(crop);
    }
  }

  Stream<double?> getAIVerifiedRateStream(String cropName) {
    final docId = _normalizeCrop(cropName);
    return _db.collection('market_trends').doc(docId).snapshots().map((doc) {
      final data = doc.data();
      if (data == null) return null;
      final dynamic average =
          data['ruleBasedAverage'] ??
          data['predictedAverage'] ??
          data['currentRate'];
      if (average is num) return average.toDouble();
      return double.tryParse(average?.toString() ?? '');
    });
  }

  Future<List<MarketRate>> fetchRealTimeRatesFromAI() async {
    await refreshAndPersistAllTrends();

    final rates = <MarketRate>[];
    for (final crop in _defaultCrops) {
      final avg = await getAIVerifiedRateStream(crop).first;
      if (avg != null && avg > 0) {
        rates.add(
          MarketRate(
            cropName: crop,
            currentPrice: avg,
            change: 0,
            trend: 'stable',
          ),
        );
      }
    }

    _currentRatesList = rates;
    return _currentRatesList;
  }

  List<MarketRate> getLatestRates() {
    return List<MarketRate>.from(_currentRatesList);
  }

  Stream<List<MarketRate>> getLiveRateStream() async* {
    try {
      yield await fetchRealTimeRatesFromAI();
    } catch (_) {
      yield getLatestRates();
    }

    while (true) {
      await Future.delayed(const Duration(minutes: 5));
      try {
        yield await fetchRealTimeRatesFromAI();
      } catch (_) {
        yield getLatestRates();
      }
    }
  }
}

class MarketRateService {
  final RealtimeRateService _realtimeRateService = RealtimeRateService();

  MarketRateService._internal();
  static final MarketRateService _instance = MarketRateService._internal();
  factory MarketRateService() => _instance;

  Future<double?> fetchMandiRate(String cropName) =>
      _realtimeRateService.fetchMandiRate(cropName);

  double? calculateMovingAverage(List<double> prices) =>
      _realtimeRateService.calculateMovingAverage(prices);

  Future<double?> getVerifiedMovingAverage(String category) =>
      _realtimeRateService.getVerifiedMovingAverage(category);

  Future<double?> fetchRuleBasedRate(String cropName) =>
      _realtimeRateService.fetchRuleBasedRate(cropName);

  Future<Map<String, double>?> fetchRuleBasedRateSnapshot(String cropName) =>
      _realtimeRateService.fetchRuleBasedRateSnapshot(cropName);

  Future<List<String>> fetchRecentNewsHeadlines(
    String cropName, {
    int limit = 3,
  }) => _realtimeRateService.fetchRecentNewsHeadlines(cropName, limit: limit);

  Future<void> refreshAndPersistAllTrends({
    List<String> crops = const [
      'Gandum',
      'Kapas',
      'Chawal',
      'Makai',
      'Dal Chana',
    ],
  }) => _realtimeRateService.refreshAndPersistAllTrends(crops: crops);

  Stream<double?> getAIVerifiedRateStream(String cropName) =>
      _realtimeRateService.getAIVerifiedRateStream(cropName);

  Future<List<MarketRate>> fetchRealTimeRatesFromAI() =>
      _realtimeRateService.fetchRealTimeRatesFromAI();

  List<MarketRate> getLatestRates() => _realtimeRateService.getLatestRates();

  Stream<List<MarketRate>> getLiveRateStream() =>
      _realtimeRateService.getLiveRateStream();
}

