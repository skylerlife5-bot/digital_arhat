import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import '../firebase_options.dart';
import 'market_rate_service.dart';

class MandiIntelligenceService {
  MandiIntelligenceService._internal();
  static final MandiIntelligenceService _instance =
      MandiIntelligenceService._internal();
  factory MandiIntelligenceService() => _instance;

  final MarketRateService _marketRateService = MarketRateService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _initialized = false;

  List<String> getItemsForType(MandiType mandiType) {
    return CategoryConstants.itemsForMandiType(mandiType);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await warmupMandiRatesIfEmpty();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        return;
      }
      rethrow;
    }
    _initialized = true;
  }

  Future<double?> fetchMandiAverageRate(
    String itemName, {
    String? province,
    String? district,
  }) async {
    final result = await fetchMandiAverageRateWithMeta(
      itemName,
      province: province,
      district: district,
    );
    return result.rate;
  }

  Future<MandiRateResult> fetchMandiAverageRateWithMeta(
    String itemName, {
    String? province,
    String? district,
  }) async {
    final lookupTokens = _buildLookupTokens(itemName);
    final locationContext = _resolveNationalLocationContext(
      province: province,
      district: district,
    );
    final normalizedProvince = locationContext.normalizedProvince;
    final normalizedDistrict = locationContext.normalizedDistrict;

    final snapshot = await _db
        .collection(AppConstants.mandiRatesCollection)
        .orderBy('rateDate', descending: true)
        .limit(100)
        .get();

    double? bestLocationRate;
    var bestLocationScore = -1;
    double? fallbackRate;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final crop =
          (data['cropType'] ?? data['cropName'] ?? data['itemName'] ?? '')
              .toString();
      final cropTokens = _buildLookupTokens(crop);

      final matched =
          lookupTokens.any(cropTokens.contains) ||
          cropTokens.any(lookupTokens.contains);
      if (!matched) continue;

      final avg = _toDouble(data['averagePrice'] ?? data['average']);
      if (avg == null || avg <= 0) continue;

      fallbackRate ??= avg;

      final locationScore = _locationMatchScore(
        data: data,
        province: normalizedProvince,
        district: normalizedDistrict,
      );
      if (locationScore > bestLocationScore) {
        bestLocationScore = locationScore;
        bestLocationRate = avg;
      }
    }

    final liveRate = bestLocationRate ?? fallbackRate;
    if (liveRate != null && liveRate > 0) {
      return MandiRateResult(rate: liveRate, isEstimate: false);
    }

    final estimatedRate = CategoryConstants.lastKnownGovernmentRate(itemName);
    return MandiRateResult(
      rate: estimatedRate,
      isEstimate: estimatedRate != null && estimatedRate > 0,
    );
  }

  Future<String> resolveSellerVerificationBadge({
    required String itemName,
    required double price,
    required String? videoUrl,
    required bool isVerifiedSource,
    double allowedDeviationPercent = 20.0,
  }) async {
    final hasVideo = (videoUrl ?? '').trim().isNotEmpty;
    if (!hasVideo || !isVerifiedSource || price <= 0) {
      return '';
    }

    final avg = await fetchMandiAverageRate(itemName);
    if (avg == null || avg <= 0) {
      return '';
    }

    final deviationPercent = ((price - avg).abs() / avg) * 100;
    if (deviationPercent <= allowedDeviationPercent) {
      return 'AI Verified Seller';
    }

    return '';
  }

  Future<void> warmupMandiRatesIfEmpty() async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _db
          .collection(AppConstants.mandiRatesCollection)
          .limit(1)
          .get();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        return;
      }
      rethrow;
    }

    if (snapshot.docs.isNotEmpty) return;

    final today = DateTime.now().toUtc();
    final normalizedDate = DateTime(today.year, today.month, today.day);

    final seedRates = <Map<String, dynamic>>[];
    for (final mandiType in MandiType.values) {
      final items = CategoryConstants.itemsForMandiType(mandiType);
      for (final item in items) {
        seedRates.add(<String, dynamic>{
          'cropType': item,
          'averagePrice': _seedAverageForType(mandiType),
        });
      }
    }

    final batch = _db.batch();

    for (final seed in seedRates) {
      final cropType = (seed['cropType'] ?? '').toString();
      final docId = _buildMandiRateDocId(cropType, normalizedDate);

      batch.set(
        _db.collection(AppConstants.mandiRatesCollection).doc(docId),
        <String, dynamic>{
          'cropType': cropType,
          'rateDate': Timestamp.fromDate(normalizedDate),
          'averagePrice': seed['averagePrice'],
          'unit': 'PKR/40kg',
          'source': 'warmup_seed',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    try {
      await batch.commit();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        return;
      }
      rethrow;
    }
  }

  String _buildMandiRateDocId(String cropType, DateTime date) {
    final crop = cropType.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${crop}_${date.year}-$mm-$dd';
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await initialize();
  }

  String get _projectId {
    try {
      return DefaultFirebaseOptions.currentPlatform.projectId;
    } catch (_) {
      return DefaultFirebaseOptions.android.projectId;
    }
  }

  String get _functionsBaseUrl =>
      'https://asia-south1-$_projectId.cloudfunctions.net';

  Future<Map<String, dynamic>> _postFunctionJson({
    required String functionName,
    required Map<String, dynamic> payload,
    bool requireAuth = false,
  }) async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (requireAuth && (token == null || token.trim().isEmpty)) {
      throw Exception('AUTH_REQUIRED');
    }

    final response = await http.post(
      Uri.parse('$_functionsBaseUrl/$functionName'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (token != null && token.trim().isNotEmpty)
          'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    Map<String, dynamic> body = <String, dynamic>{};
    if (response.body.trim().isNotEmpty) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        body = decoded;
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = (body['error'] ?? body['errorMessage'] ?? 'FUNCTION_HTTP_${response.statusCode}')
          .toString();
      throw Exception(error);
    }

    return body;
  }

  Future<double?> suggestBidRate({
    required String item,
    required String location,
    required List<double> bidSamples,
    double baseline = 0,
  }) async {
    final response = await _postFunctionJson(
      functionName: 'aiSuggestBidRate',
      payload: <String, dynamic>{
        'item': item,
        'location': location,
        'baseline': baseline,
        'bidSamples': bidSamples,
      },
    );

    final rate = _toDouble(response['suggestedRate']);
    if (rate == null || rate <= 0) return null;
    return rate;
  }

  Future<Map<String, dynamic>?> suggestMarketRate({
    String? listingId,
    String? itemName,
    String? district,
    String? province,
    double? quantity,
    String? unit,
  }) async {
    try {
      final payload = <String, dynamic>{
        if ((listingId ?? '').trim().isNotEmpty) 'listingId': listingId,
        if ((itemName ?? '').trim().isNotEmpty) 'itemName': itemName,
        if ((district ?? '').trim().isNotEmpty) 'district': district,
        if ((province ?? '').trim().isNotEmpty) 'province': province,
        if ((quantity ?? 0) > 0) 'quantity': quantity,
        if ((unit ?? '').trim().isNotEmpty) 'unit': unit,
      };

      final response = await _postFunctionJson(
        functionName: 'suggestMarketRateHttp',
        payload: payload,
        requireAuth: true,
      );
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> evaluateBidRisk({
    required String listingId,
    required String buyerUid,
    required double bidRate,
    required double quantity,
    required String unit,
  }) async {
    try {
      final response = await _postFunctionJson(
        functionName: 'evaluateBidRiskHttp',
        payload: <String, dynamic>{
          'listingId': listingId,
          'buyerUid': buyerUid,
          'bidRate': bidRate,
          'quantity': quantity,
          'unit': unit,
        },
        requireAuth: true,
      );
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<String> getAIResponse(String prompt) async {
    final locationAwarePrice = await _tryResolveLocationAwarePricePrompt(
      prompt,
    );
    if (locationAwarePrice != null) {
      return locationAwarePrice;
    }

    final response = await _callProxy(
      action: 'general_text',
      payload: <String, dynamic>{'prompt': prompt},
    );
    return (response['text'] ?? '').toString().trim();
  }

  Future<String?> _tryResolveLocationAwarePricePrompt(String prompt) async {
    final parsed = _parsePriceInLocationPrompt(prompt);
    if (parsed == null) return null;

    final locationContext = _resolveNationalLocationContext(
      province: parsed.province,
      district: parsed.district,
    );

    final average = await fetchMandiAverageRate(
      parsed.item,
      province: locationContext.province,
      district: locationContext.district,
    );
    if (average == null || average <= 0) return null;

    final locationLabel = locationContext.district?.trim().isNotEmpty == true
        ? '${locationContext.district}, ${locationContext.province ?? 'Pakistan'}'
        : (locationContext.province?.trim().isNotEmpty == true
              ? locationContext.province!
              : 'Pakistan');
    return 'Latest mandi average for ${parsed.item} in $locationLabel is Rs. ${average.toStringAsFixed(0)}.';
  }

  _PricePromptContext? _parsePriceInLocationPrompt(String prompt) {
    final match = RegExp(
      r'^\s*([A-Za-z\s\-\(\)]+?)\s+(?:price|rate)\s+in\s+([A-Za-z&\-\s\(\)]+)\s*\??\s*$',
      caseSensitive: false,
    ).firstMatch(prompt.trim());
    if (match == null) return null;

    final item = (match.group(1) ?? '').trim();
    final locationRaw = (match.group(2) ?? '').trim();
    if (item.isEmpty || locationRaw.isEmpty) return null;

    final provinces = AppConstants.provinces;
    final locationLower = locationRaw.toLowerCase();

    for (final province in provinces) {
      if (province.toLowerCase() == locationLower ||
          province.toLowerCase().contains(locationLower)) {
        return _PricePromptContext(item: item, province: province);
      }
    }

    for (final province in provinces) {
      final districts = AppConstants.districtsForProvince(province);
      for (final district in districts) {
        if (district.toLowerCase() == locationLower ||
            district.toLowerCase().contains(locationLower)) {
          return _PricePromptContext(
            item: item,
            province: province,
            district: district,
          );
        }
      }
    }

    return _PricePromptContext(item: item, province: locationRaw);
  }

  Future<String> getWeatherAlert({
    required String condition,
    required double temperature,
    required String crop,
  }) async {
    final response = await _callProxy(
      action: 'weather_advisory',
      payload: <String, dynamic>{
        'condition': condition,
        'temperature': temperature,
        'crop': crop,
      },
    );
    final text = (response['advisory'] ?? response['text'] ?? '').toString();
    return text.trim().isEmpty
        ? 'Mausam update dastyab hai, ehtiyaat se fasal management karein.'
        : text.trim();
  }

  Future<String> getPricePredictions({
    String region = 'Pakistan',
    List<String> crops = CategoryConstants.defaultPredictionItems,
  }) async {
    final response = await _callProxy(
      action: 'market_sentiment',
      payload: <String, dynamic>{'region': region, 'crops': crops},
    );
    return jsonEncode(response);
  }

  Set<String> _buildLookupTokens(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) return <String>{};

    final noBrackets = normalized.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    final chunks = noBrackets
        .split(RegExp(r'\-|\/|,|\s{2,}'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    chunks.add(normalized.replaceAll(RegExp(r'\s+'), ' ').trim());
    return chunks;
  }

  String _normalizeLocationToken(String? raw) {
    return (raw ?? '').trim().toLowerCase();
  }

  _NationalLocationContext _resolveNationalLocationContext({
    String? province,
    String? district,
  }) {
    final provinceRaw = (province ?? '').trim();
    final districtRaw = (district ?? '').trim();

    String? matchedProvince;
    String? matchedDistrict;

    for (final entry in AppConstants.pakistanLocations.entries) {
      final provinceName = entry.key;
      final provinceLower = provinceName.toLowerCase();
      if (provinceRaw.isNotEmpty &&
          (provinceLower == provinceRaw.toLowerCase() ||
              provinceLower.contains(provinceRaw.toLowerCase()))) {
        matchedProvince = provinceName;
      }

      for (final districtName in entry.value) {
        final districtLower = districtName.toLowerCase();
        if (districtRaw.isNotEmpty &&
            (districtLower == districtRaw.toLowerCase() ||
                districtLower.contains(districtRaw.toLowerCase()))) {
          matchedDistrict = districtName;
          matchedProvince ??= provinceName;
          break;
        }
      }
    }

    if (matchedDistrict != null && matchedProvince != null) {
      final allowedDistricts = AppConstants.districtsForProvince(
        matchedProvince,
      );
      if (!allowedDistricts.contains(matchedDistrict)) {
        matchedDistrict = null;
      }
    }

    return _NationalLocationContext(
      province:
          matchedProvince ?? (provinceRaw.isNotEmpty ? provinceRaw : null),
      district:
          matchedDistrict ?? (districtRaw.isNotEmpty ? districtRaw : null),
      normalizedProvince: _normalizeLocationToken(
        matchedProvince ?? (provinceRaw.isNotEmpty ? provinceRaw : null),
      ),
      normalizedDistrict: _normalizeLocationToken(
        matchedDistrict ?? (districtRaw.isNotEmpty ? districtRaw : null),
      ),
    );
  }

  int _locationMatchScore({
    required Map<String, dynamic> data,
    required String province,
    required String district,
  }) {
    if (province.isEmpty && district.isEmpty) {
      return 0;
    }

    final candidates = <String>[
      (data['province'] ?? '').toString().toLowerCase(),
      (data['district'] ?? '').toString().toLowerCase(),
      (data['region'] ?? '').toString().toLowerCase(),
      (data['location'] ?? '').toString().toLowerCase(),
      (data['city'] ?? '').toString().toLowerCase(),
      (data['market'] ?? '').toString().toLowerCase(),
    ].where((value) => value.trim().isNotEmpty).toList(growable: false);

    if (candidates.isEmpty) {
      return -1;
    }

    var score = 0;
    if (district.isNotEmpty) {
      final districtMatch = candidates.any((value) => value.contains(district));
      score += districtMatch ? 3 : -2;
    }
    if (province.isNotEmpty) {
      final provinceMatch = candidates.any((value) => value.contains(province));
      score += provinceMatch ? 2 : -1;
    }

    return score < 0 ? -1 : score;
  }

  double? _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  double _seedAverageForType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return 4200.0;
      case MandiType.fruit:
        return 240.0;
      case MandiType.vegetables:
        return 110.0;
      case MandiType.flowers:
        return 180.0;
      case MandiType.livestock:
        return 125000.0;
      case MandiType.milk:
        return 210.0;
      case MandiType.seeds:
        return 5800.0;
      case MandiType.fertilizer:
        return 7200.0;
      case MandiType.machinery:
        return 150000.0;
      case MandiType.tools:
        return 18500.0;
      case MandiType.dryFruits:
        return 2900.0;
      case MandiType.spices:
        return 1300.0;
    }
  }

  Future<Map<String, double>> getPredictedMarketRate(String cropName) async {
    final snapshot = await _marketRateService.fetchRuleBasedRateSnapshot(
      cropName,
    );
    if (snapshot == null) {
      throw Exception('RULE_BASED_RATE_UNAVAILABLE|item=$cropName');
    }
    return snapshot;
  }

  Future<Map<String, double>> getPredictedMarketRateByType({
    required MandiType mandiType,
    required String itemName,
  }) async {
    final snapshot = await _marketRateService.fetchRuleBasedRateSnapshot(
      itemName,
    );
    if (snapshot == null) {
      throw Exception(
        'RULE_BASED_RATE_UNAVAILABLE|type=${mandiType.wireValue}|item=$itemName',
      );
    }
    return snapshot;
  }

  Future<String> explainMarketTrend({
    required String cropName,
    required double movingAverage,
    List<String> recentNews = const <String>[],
    String? province,
    String? district,
  }) async {
    return analyzeSentiment(
      cropName: cropName,
      movingAvg: movingAverage,
      recentTrends: recentNews,
      province: province,
      district: district,
    );
  }

  Future<String> analyzeSentiment({
    required String cropName,
    required double movingAvg,
    List<String> recentTrends = const <String>[],
    String? province,
    String? district,
  }) async {
    final locationContext = [
      if ((district ?? '').trim().isNotEmpty) 'District: ${district!.trim()}',
      if ((province ?? '').trim().isNotEmpty) 'Province: ${province!.trim()}',
    ].join(' | ');

    final prompt =
        'Based on a market average of $movingAvg and these recent trends, explain in Roman-Urdu if the market is Bullish, Bearish, or Stable. Do not provide new numbers.\n'
        'Category: $cropName\n'
        '${locationContext.isEmpty ? '' : 'Location: $locationContext\n'}'
        'Recent Trends: ${recentTrends.join(' | ')}';

    final response = await _callProxy(
      action: 'mandi_insight',
      payload: <String, dynamic>{
        'cropName': cropName,
        'movingAverage': movingAvg,
        'recentTrends': recentTrends,
        'province': province,
        'district': district,
        'prompt': prompt,
      },
    );

    final text =
        (response['insight'] ??
                response['explanation'] ??
                response['text'] ??
                '')
            .toString()
            .trim();
    if (text.isEmpty) {
      throw Exception('MANDI_INSIGHT_EMPTY|crop=$cropName|avg=$movingAvg');
    }
    return text;
  }

  Future<String> checkAiConnectivity() async {
    final response = await _callProxy(
      action: 'ping',
      payload: const <String, dynamic>{
        'message': 'Reply with exactly: Success',
      },
    );

    final text =
        (response['message'] ?? response['text'] ?? response['status'] ?? '')
            .toString()
            .trim();
    if (text.isEmpty) {
      throw Exception('AI_PROXY_EMPTY_RESPONSE|body=${jsonEncode(response)}');
    }
    return text;
  }

  Future<CnicExtractionResult> extractPakistaniCnicFieldsFromImage({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    debugPrint('[CNIC_AI] extract_start | payload={mimeType: $mimeType, imageBytesLength: ${imageBytes.length}}');
    if (imageBytes.isEmpty) {
      debugPrint('[CNIC_AI] extract_short_circuit_empty_image');
      return const CnicExtractionResult(
        success: false,
        errorMessage:
            'Could not read CNIC clearly. Please retake the image.\nشناختی کارڈ واضح نہیں پڑھا جا سکا۔ براہ کرم دوبارہ تصویر لیں۔',
      );
    }

    await _ensureInitialized();
    try {
      final response = await _postFunctionJson(
        functionName: 'aiExtractCnic',
        payload: <String, dynamic>{
          'imageBase64': base64Encode(imageBytes),
          'mimeType': mimeType,
        },
      );

      debugPrint('[CNIC_AI] extract_raw_response | ${response.toString()}');

      final success = response['success'] == true;
      if (!success) {
        final aiError = (response['errorMessage'] ?? '').toString().trim();
        debugPrint('[CNIC_AI] extract_failed_success_false | error=$aiError');
        return CnicExtractionResult(
          success: false,
          errorMessage: _mapCnicErrorToSafeMessage(aiError),
          rawResponse: (response['rawResponse'] ?? '').toString(),
        );
      }

      final name = (response['name'] ?? '').toString().trim();
      final fatherName = (response['fatherName'] ?? '').toString().trim();
      final normalizedCnic = _normalizeCnic(
        (response['cnicNumber'] ?? '').toString(),
      );
      final detectedSide = _normalizeDetectedSide(
        (response['detectedSide'] ?? '').toString(),
      );
      final isCnicDocument = response['isCnicDocument'] == true;
      final dateOfBirth = (response['dateOfBirth'] ?? '').toString().trim();
      final expiryDate = (response['expiryDate'] ?? '').toString().trim();
      final confidence = (response['confidence'] ?? 'medium')
          .toString()
          .toLowerCase()
          .trim();

      debugPrint('[CNIC_AI] extract_parsed_fields | name=$name | fatherName=$fatherName | cnicNumber=$normalizedCnic | detectedSide=$detectedSide | isCnicDocument=$isCnicDocument | dob=$dateOfBirth | expiry=$expiryDate | confidence=$confidence');

      if (!isCnicDocument || detectedSide == 'unknown') {
        debugPrint('[CNIC_AI] extract_rejected_document_or_side | isCnicDocument=$isCnicDocument | detectedSide=$detectedSide');
        return CnicExtractionResult(
          success: false,
          errorMessage:
              'Could not read CNIC clearly. Please retake the image.\nشناختی کارڈ واضح نہیں پڑھا جا سکا۔ براہ کرم دوبارہ تصویر لیں۔',
          rawResponse: (response['rawResponse'] ?? '').toString(),
        );
      }

      final bool needsReview =
          confidence == 'low' || name.isEmpty || normalizedCnic.isEmpty;

      return CnicExtractionResult(
        success: true,
        name: name,
        fatherName: fatherName,
        cnicNumber: normalizedCnic,
        detectedSide: detectedSide,
        isCnicDocument: isCnicDocument,
        dateOfBirth: dateOfBirth,
        expiryDate: expiryDate,
        confidence: confidence.isEmpty ? 'medium' : confidence,
        needsReview: needsReview,
        rawResponse: (response['rawResponse'] ?? '').toString(),
      );
    } catch (e) {
      debugPrint('[CNIC_AI] extract_exception | ${e.toString()}');
      return const CnicExtractionResult(
        success: false,
        errorMessage:
            'AI service is temporarily unavailable. Please try again.\nAI سروس عارضی طور پر دستیاب نہیں۔ براہ کرم دوبارہ کوشش کریں۔',
      );
    }
  }

  String _normalizeDetectedSide(String rawSide) {
    final side = rawSide.toLowerCase().trim();
    if (side == 'front') return 'front';
    if (side == 'back') return 'back';
    if (side.contains('front') || side.contains('frnt')) return 'front';
    if (side.contains('back') || side.contains('rear')) return 'back';
    return 'unknown';
  }

  String _mapCnicErrorToSafeMessage(String rawMessage) {
    final lower = rawMessage.toLowerCase();
    if (lower.contains('ai-unavailable') ||
        lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('quota') ||
        lower.contains('timeout')) {
      return 'AI service is temporarily unavailable. Please try again.\nAI سروس عارضی طور پر دستیاب نہیں۔ براہ کرم دوبارہ کوشش کریں۔';
    }
    return 'Could not read CNIC clearly. Please retake the image.\nشناختی کارڈ واضح نہیں پڑھا جا سکا۔ براہ کرم دوبارہ تصویر لیں۔';
  }

  String _normalizeCnic(String input) {
    final digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 13) return '';
    return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12)}';
  }

  Future<Map<String, dynamic>> _callProxy({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    await _ensureInitialized();

    try {
      if (action == 'weather_advisory') {
        final response = await _postFunctionJson(
          functionName: 'aiWeatherAdvisory',
          payload: <String, dynamic>{
            'condition': payload['condition'],
            'temperature': payload['temperature'],
            'crop': payload['crop'],
          },
        );
        return <String, dynamic>{
          'advisory': (response['advisory'] ?? '').toString().trim(),
          'ok': response['ok'] == true,
        };
      }

      final prompt = _buildPrompt(action: action, payload: payload);
      final response = await _postFunctionJson(
        functionName: 'aiGenerateText',
        payload: <String, dynamic>{'prompt': prompt},
      );
      final text = (response['text'] ?? '').toString().trim();
      if (text.isNotEmpty) {
        return _mapResponseByAction(action: action, text: text);
      }
    } catch (_) {
      throw Exception('MANDI_SERVER_BUSY_OFFLINE');
    }

    throw Exception('MANDI_SERVER_BUSY_OFFLINE');
  }

  String _buildPrompt({
    required String action,
    required Map<String, dynamic> payload,
  }) {
    switch (action) {
      case 'weather_advisory':
        return 'You are a mandi assistant. Give a short Roman-Urdu weather advisory for crop protection. Data: ${jsonEncode(payload)}';
      case 'market_sentiment':
        return 'Provide concise market sentiment for the supplied region and crops in Roman-Urdu. Data: ${jsonEncode(payload)}';
      case 'mandi_insight':
        return (payload['prompt'] ?? '').toString().trim().isEmpty
            ? 'Provide Roman-Urdu mandi insight based on: ${jsonEncode(payload)}'
            : (payload['prompt'] ?? '').toString();
      case 'ping':
        return (payload['message'] ?? 'Reply with exactly: Success').toString();
      case 'general_text':
      default:
        return (payload['prompt'] ?? '').toString();
    }
  }

  Map<String, dynamic> _mapResponseByAction({
    required String action,
    required String text,
  }) {
    switch (action) {
      case 'weather_advisory':
        return <String, dynamic>{'advisory': text, 'ok': true};
      case 'market_sentiment':
        return <String, dynamic>{'text': text, 'ok': true};
      case 'mandi_insight':
        return <String, dynamic>{'insight': text, 'ok': true};
      case 'ping':
        return <String, dynamic>{'message': text, 'ok': true};
      case 'general_text':
      default:
        return <String, dynamic>{'text': text, 'ok': true};
    }
  }
}

typedef AIGenerativeService = MandiIntelligenceService;

class MandiRateResult {
  const MandiRateResult({required this.rate, required this.isEstimate});

  final double? rate;
  final bool isEstimate;
}

class _NationalLocationContext {
  const _NationalLocationContext({
    required this.province,
    required this.district,
    required this.normalizedProvince,
    required this.normalizedDistrict,
  });

  final String? province;
  final String? district;
  final String normalizedProvince;
  final String normalizedDistrict;
}

class _PricePromptContext {
  const _PricePromptContext({required this.item, this.province, this.district});

  final String item;
  final String? province;
  final String? district;
}

class CnicExtractionResult {
  const CnicExtractionResult({
    required this.success,
    this.name = '',
    this.fatherName = '',
    this.cnicNumber = '',
    this.detectedSide = '',
    this.isCnicDocument = false,
    this.dateOfBirth = '',
    this.expiryDate = '',
    this.confidence = 'low',
    this.errorMessage = '',
    this.needsReview = false,
    this.rawResponse = '',
  });

  final bool success;
  final String name;
  final String fatherName;
  final String cnicNumber;
  final String detectedSide;
  final bool isCnicDocument;
  final String dateOfBirth;
  final String expiryDate;
  final String confidence;
  final String errorMessage;
  final bool needsReview;
  final String rawResponse;
}
