import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'ai_generative_service.dart';
import 'market_rate_service.dart';

class SellerPriceSuggestion {
  const SellerPriceSuggestion({
    required this.marketAverage,
    required this.recommendedPrice,
    required this.priceDeviationPercent,
    required this.message,
  });

  final double marketAverage;
  final double recommendedPrice;
  final double priceDeviationPercent;
  final String message;
}

class BuyerBidSuggestion {
  const BuyerBidSuggestion({
    required this.suggestedBid,
    required this.marketRangeLow,
    required this.marketRangeHigh,
    required this.bidInsight,
  });

  final double suggestedBid;
  final double marketRangeLow;
  final double marketRangeHigh;
  final String bidInsight;
}

class MandiTrendPoint {
  const MandiTrendPoint({
    required this.crop,
    required this.province,
    required this.district,
    required this.trendDirection,
    required this.priceChangePercent,
    required this.marketAverage,
    required this.trendSummary,
  });

  final String crop;
  final String province;
  final String district;
  final String trendDirection;
  final double priceChangePercent;
  final double marketAverage;
  final String trendSummary;

  factory MandiTrendPoint.fromJson(Map<String, dynamic> json) {
    double readNum(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse((value ?? '').toString()) ?? 0;
    }

    return MandiTrendPoint(
      crop: (json['crop'] ?? '').toString().trim(),
      province: (json['province'] ?? '').toString().trim(),
      district: (json['district'] ?? '').toString().trim(),
      trendDirection: (json['trendDirection'] ?? 'stable').toString().trim(),
      priceChangePercent: readNum(json['priceChangePercent']),
      marketAverage: readNum(json['marketAverage']),
      trendSummary: (json['trendSummary'] ?? '').toString().trim(),
    );
  }
}

class AdminMarketInsightsResult {
  const AdminMarketInsightsResult({
    required this.topRisingCrops,
    required this.topFallingCrops,
    required this.highDemandCategories,
  });

  final List<String> topRisingCrops;
  final List<String> topFallingCrops;
  final List<String> highDemandCategories;
}

class Layer2MarketIntelligenceService {
  Layer2MarketIntelligenceService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    MandiIntelligenceService? mandiService,
    MarketRateService? rateService,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _mandiService = mandiService ?? MandiIntelligenceService(),
       _rateService = rateService ?? MarketRateService();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final MandiIntelligenceService _mandiService;
  final MarketRateService _rateService;

  String get _projectId {
    try {
      return DefaultFirebaseOptions.currentPlatform.projectId;
    } catch (_) {
      return DefaultFirebaseOptions.android.projectId;
    }
  }

  String get _functionsBaseUrl =>
      'https://asia-south1-$_projectId.cloudfunctions.net';

  Future<List<MandiTrendPoint>> fetchMandiTrends({
    String? crop,
    String? province,
    String? district,
    int top = 12,
  }) async {
    final payload = <String, dynamic>{
      if ((crop ?? '').trim().isNotEmpty) 'crop': crop,
      if ((province ?? '').trim().isNotEmpty) 'province': province,
      if ((district ?? '').trim().isNotEmpty) 'district': district,
      'top': top,
    };

    try {
      final response = await _postJson(
        functionName: 'getMandiTrendHttp',
        payload: payload,
      );
      final raw = response['trends'];
      if (raw is! List) return const <MandiTrendPoint>[];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(MandiTrendPoint.fromJson)
          .where((e) => e.crop.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const <MandiTrendPoint>[];
    }
  }

  Future<SellerPriceSuggestion> buildSellerPriceSuggestion({
    required String itemName,
    required double enteredPrice,
    String? listingId,
    String? province,
    String? district,
    double? quantity,
    String? unit,
  }) async {
    final normalizedItem = itemName.trim();
    if (normalizedItem.isEmpty || enteredPrice <= 0) {
      return const SellerPriceSuggestion(
        marketAverage: 0,
        recommendedPrice: 0,
        priceDeviationPercent: 0,
        message: 'Price insight unavailable.',
      );
    }

    final mandiAvgMeta = await _mandiService.fetchMandiAverageRateWithMeta(
      normalizedItem,
      province: province,
      district: district,
    );

    final marketRateResponse = await _mandiService.suggestMarketRate(
      listingId: listingId,
      itemName: normalizedItem,
      province: province,
      district: district,
      quantity: quantity,
      unit: unit,
    );

    final rangeLow = _toDouble(marketRateResponse?['suggestedMin']);
    final rangeHigh = _toDouble(marketRateResponse?['suggestedMax']);

    var marketAverage = mandiAvgMeta.rate ?? 0;
    if (marketAverage <= 0 && rangeLow > 0 && rangeHigh > 0) {
      marketAverage = (rangeLow + rangeHigh) / 2;
    }

    if (marketAverage <= 0) {
      marketAverage =
          await _rateService.fetchRuleBasedRate(normalizedItem) ?? 0;
    }

    if (marketAverage <= 0) {
      return const SellerPriceSuggestion(
        marketAverage: 0,
        recommendedPrice: 0,
        priceDeviationPercent: 0,
        message: 'Price insight unavailable.',
      );
    }

    final recommendedPrice = (rangeLow > 0 && rangeHigh > 0)
        ? ((rangeLow + rangeHigh) / 2)
        : marketAverage;
    final deviationPercent =
        ((enteredPrice - marketAverage) / marketAverage) * 100;
    final direction = deviationPercent >= 0 ? 'above' : 'below';

    return SellerPriceSuggestion(
      marketAverage: marketAverage,
      recommendedPrice: recommendedPrice,
      priceDeviationPercent: deviationPercent,
      message:
          'Your price is ${deviationPercent.abs().toStringAsFixed(1)}% $direction mandi average.',
    );
  }

  Future<BuyerBidSuggestion?> buildBuyerBidSuggestion({
    required Map<String, dynamic> listingData,
    required List<double> bidSamples,
    required double highestBid,
    String? district,
    String? province,
  }) async {
    final item =
        (listingData['itemName'] ??
                listingData['cropName'] ??
                listingData['product'] ??
                '')
            .toString()
            .trim();
    if (item.isEmpty) return null;

    final response = await _mandiService.suggestMarketRate(
      listingId: (listingData['id'] ?? '').toString().trim().isEmpty
          ? null
          : (listingData['id'] ?? '').toString(),
      itemName: item,
      province: province ?? (listingData['province'] ?? '').toString(),
      district: district ?? (listingData['district'] ?? '').toString(),
      quantity: _toDouble(listingData['quantity']) > 0
          ? _toDouble(listingData['quantity'])
          : null,
      unit: (listingData['unit'] ?? '').toString(),
    );

    final marketRangeLow = _toDouble(response?['suggestedMin']);
    final marketRangeHigh = _toDouble(response?['suggestedMax']);
    final listingPrice = _toDouble(listingData['price']);

    final baseline = [
      highestBid,
      listingPrice,
      marketRangeLow,
      marketRangeHigh,
    ].where((v) => v > 0).fold<double>(0, (a, b) => a > b ? a : b);

    final aiSuggested = await _mandiService.suggestBidRate(
      item: item,
      location: [
        if ((district ?? '').trim().isNotEmpty) district!.trim(),
        if ((province ?? '').trim().isNotEmpty) province!.trim(),
      ].join(', '),
      bidSamples: bidSamples,
      baseline: baseline,
    );

    final minIncrement = highestBid > 0
        ? (highestBid * 0.01).clamp(1, 5000).toDouble()
        : 1.0;
    final fallbackSuggested = highestBid > 0
        ? (highestBid + minIncrement)
        : (baseline > 0 ? baseline : 1.0);

    final suggestedBid = (aiSuggested != null && aiSuggested > 0)
        ? (aiSuggested > fallbackSuggested ? aiSuggested : fallbackSuggested)
        : fallbackSuggested;

    final effectiveLow = marketRangeLow > 0
        ? marketRangeLow
        : (baseline > 0 ? baseline * 0.95 : 0.0);
    final effectiveHigh = marketRangeHigh > 0
        ? marketRangeHigh
        : (baseline > 0 ? baseline * 1.05 : 0.0);

    final insight =
        'Current highest bid: Rs. ${highestBid.toStringAsFixed(0)} | Suggested bid: Rs. ${suggestedBid.toStringAsFixed(0)} | Market range: Rs. ${effectiveLow.toStringAsFixed(0)}-${effectiveHigh.toStringAsFixed(0)}.';

    return BuyerBidSuggestion(
      suggestedBid: suggestedBid,
      marketRangeLow: effectiveLow,
      marketRangeHigh: effectiveHigh,
      bidInsight: insight,
    );
  }

  Future<AdminMarketInsightsResult> buildAdminMarketInsights() async {
    final trends = await fetchMandiTrends(top: 18);

    final rising = trends
      ..sort((a, b) => b.priceChangePercent.compareTo(a.priceChangePercent));

    final topRising = rising
        .where((e) => e.priceChangePercent > 0)
        .take(3)
        .map(
          (e) =>
              '${e.crop} demand rising in ${e.province.isEmpty ? 'Pakistan' : e.province}',
        )
        .toList(growable: false);

    final falling = List<MandiTrendPoint>.from(trends)
      ..sort((a, b) => a.priceChangePercent.compareTo(b.priceChangePercent));
    final topFalling = falling
        .where((e) => e.priceChangePercent < 0)
        .take(3)
        .map(
          (e) =>
              '${e.crop} supply increasing in ${e.district.isEmpty ? (e.province.isEmpty ? 'Pakistan' : e.province) : e.district}',
        )
        .toList(growable: false);

    final demand = await _computeHighDemandCategories();

    return AdminMarketInsightsResult(
      topRisingCrops: topRising,
      topFallingCrops: topFalling,
      highDemandCategories: demand,
    );
  }

  Future<List<String>> _computeHighDemandCategories() async {
    final since = DateTime.now().toUtc().subtract(const Duration(hours: 24));

    final listingSnap = await _db
        .collection('listings')
        .orderBy('createdAt', descending: true)
        .limit(320)
        .get();

    final listingCategoryById = <String, String>{};
    for (final doc in listingSnap.docs) {
      final data = doc.data();
      final createdAt = _toDateTime(data['createdAt']);
      if (createdAt != null && createdAt.isBefore(since)) continue;

      final category =
          (data['subcategoryLabel'] ??
                  data['product'] ??
                  data['categoryLabel'] ??
                  data['category'] ??
                  '')
              .toString()
              .trim();
      if (category.isEmpty) continue;
      listingCategoryById[doc.id] = category;
    }

    final bidsSnap = await _db.collectionGroup('bids').limit(500).get();
    final demandByCategory = <String, int>{};

    for (final doc in bidsSnap.docs) {
      final data = doc.data();
      final ts =
          _toDateTime(data['createdAt']) ?? _toDateTime(data['timestamp']);
      if (ts != null && ts.isBefore(since)) continue;

      final listingId = (data['listingId'] ?? '').toString().trim();
      if (listingId.isEmpty) continue;
      final category = listingCategoryById[listingId];
      if (category == null || category.isEmpty) continue;
      demandByCategory[category] = (demandByCategory[category] ?? 0) + 1;
    }

    final sorted = demandByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted
        .take(3)
        .map((e) => '${e.key}: high bid activity (+${e.value} bids/24h)')
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> _postJson({
    required String functionName,
    required Map<String, dynamic> payload,
  }) async {
    final token = await _auth.currentUser?.getIdToken();
    final response = await http
        .post(
          Uri.parse('$_functionsBaseUrl/$functionName'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            if ((token ?? '').trim().isNotEmpty)
              'Authorization': 'Bearer $token',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 18));

    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        (body['error'] ?? 'FUNCTION_HTTP_${response.statusCode}').toString(),
      );
    }

    return body;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }
}
