import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../core/constants.dart';
import 'config_service.dart';
import 'market_rate_service.dart';

class MandiIntelligenceService {
  MandiIntelligenceService._internal();
  static final MandiIntelligenceService _instance =
      MandiIntelligenceService._internal();
  factory MandiIntelligenceService() => _instance;

  final MarketRateService _marketRateService = MarketRateService();
  final ConfigService _configService = ConfigService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  bool _keysInitialized = false;
  String _geminiApiKey = '';
  String _openAiApiKey = '';

  List<String> getItemsForType(MandiType mandiType) {
    return CategoryConstants.itemsForMandiType(mandiType);
  }

  Future<void> initialize() async {
    if (_keysInitialized) return;

    await _configService.warmup();
    try {
      await warmupMandiRatesIfEmpty();
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied') {
        return;
      }
      rethrow;
    }
    _geminiApiKey = await _configService.fetchGeminiApiKey();
    _openAiApiKey = await _configService.fetchOpenAiApiKey();
    _keysInitialized = true;
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
    if (_keysInitialized) return;
    await initialize();
  }

  Future<String> getAIResponse(String prompt) async {
    final locationAwarePrice = await _tryResolveLocationAwarePricePrompt(prompt);
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
      final allowedDistricts = AppConstants.districtsForProvince(matchedProvince);
      if (!allowedDistricts.contains(matchedDistrict)) {
        matchedDistrict = null;
      }
    }

    return _NationalLocationContext(
      province: matchedProvince ?? (provinceRaw.isNotEmpty ? provinceRaw : null),
      district: matchedDistrict ?? (districtRaw.isNotEmpty ? districtRaw : null),
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
      case MandiType.vegetables:
        return 110.0;
      case MandiType.fruit:
        return 240.0;
      case MandiType.livestock:
        return 125000.0;
      case MandiType.milk:
        return 210.0;
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
    if (imageBytes.isEmpty) {
      return const CnicExtractionResult(
        success: false,
        errorMessage: 'CNIC image read nahi ho saki. Dobara clear photo upload karein.',
      );
    }

    await _ensureInitialized();

    if (_geminiApiKey.trim().isEmpty) {
      return const CnicExtractionResult(
        success: false,
        errorMessage: 'AI service temporarily unavailable. Baad mein dobara koshish karein.',
      );
    }

    const prompt =
        'You are a strict Pakistani CNIC OCR parser.\n'
        'Carefully distinguish between Name, Father Name, and CNIC Number fields.\n'
        'Extract text from both Urdu and English labels on Pakistani CNIC.\n'
        'If image is blurry, low-resolution, cropped, reflective, or uncertain, DO NOT GUESS.\n'
        'Return status=error and ask for a clearer photo.\n'
        'Return ONLY valid JSON with this exact schema:\n'
        '{"status":"ok|error","error":"string","name":"string","fatherName":"string","cnicNumber":"xxxxx-xxxxxxx-x","confidence":"high|medium|low"}';

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _geminiApiKey,
      );

      final response = await model.generateContent([
        Content.multi([
          TextPart(prompt),
          DataPart(mimeType, imageBytes),
        ]),
      ]);

      final raw = (response.text ?? '').trim();
      if (raw.isEmpty) {
        return const CnicExtractionResult(
          success: false,
          errorMessage: 'AI se response nahi mila. Clear photo ke sath dobara try karein.',
        );
      }

      final jsonText = _extractJsonBlock(raw);
      final Map<String, dynamic> parsed =
          jsonDecode(jsonText) as Map<String, dynamic>;

      final status = (parsed['status'] ?? '').toString().toLowerCase().trim();
      final confidence =
          (parsed['confidence'] ?? '').toString().toLowerCase().trim();
      final aiError = (parsed['error'] ?? '').toString().trim();

      if (status == 'error' || confidence == 'low') {
        return CnicExtractionResult(
          success: false,
          errorMessage: aiError.isEmpty
              ? 'تص���Rر دھ� د��R ہ�� براہ کر�& ز�Rادہ ��اضح CNIC تص���Rر اپ����� کر�Rں�'
              : aiError,
          rawResponse: raw,
        );
      }

      final name = (parsed['name'] ?? '').toString().trim();
      final fatherName = (parsed['fatherName'] ?? '').toString().trim();
      final normalizedCnic = _normalizeCnic((parsed['cnicNumber'] ?? '').toString());

      if (name.isEmpty || normalizedCnic.isEmpty) {
        return CnicExtractionResult(
          success: false,
          errorMessage: 'CNIC fields clearly detect nahi hue. Clear, seedhi photo upload karein.',
          rawResponse: raw,
        );
      }

      return CnicExtractionResult(
        success: true,
        name: name,
        fatherName: fatherName,
        cnicNumber: normalizedCnic,
        confidence: confidence.isEmpty ? 'medium' : confidence,
        needsReview: true,
        rawResponse: raw,
      );
    } catch (_) {
      return const CnicExtractionResult(
        success: false,
        errorMessage: 'CNIC scan process mein masla aya. Clear image ke sath dobara scan karein.',
      );
    }
  }

  String _extractJsonBlock(String rawText) {
    final cleaned = rawText
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(cleaned);
    return (match?.group(0) ?? cleaned).trim();
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

    final prompt = _buildPrompt(action: action, payload: payload);
    try {
      final geminiText = await _generateWithGemini(prompt);
      if (geminiText.isNotEmpty) {
        return _mapResponseByAction(action: action, text: geminiText);
      }
    } catch (_) {}

    try {
      final openAiText = await _generateWithOpenAi(prompt);
      if (openAiText.isNotEmpty) {
        return _mapResponseByAction(action: action, text: openAiText);
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

  Future<String> _generateWithGemini(String prompt) async {
    if (_geminiApiKey.trim().isEmpty) {
      throw Exception('GEMINI_KEY_MISSING');
    }

    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _geminiApiKey,
    );
    final response = await model.generateContent([Content.text(prompt)]);
    final text = response.text?.trim() ?? '';
    if (text.isEmpty) {
      throw Exception('GEMINI_EMPTY_RESPONSE');
    }
    return text;
  }

  Future<String> _generateWithOpenAi(String prompt) async {
    if (_openAiApiKey.trim().isEmpty) {
      throw Exception('OPENAI_KEY_MISSING');
    }

    final uri = Uri.parse('https://api.openai.com/v1/chat/completions');
    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_openAiApiKey',
      },
      body: jsonEncode(<String, dynamic>{
        'model': 'gpt-4o-mini',
        'messages': <Map<String, String>>[
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'temperature': 0.2,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('OPENAI_HTTP_${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw Exception('OPENAI_INVALID_RESPONSE');
    }

    final first = choices.first;
    if (first is! Map) {
      throw Exception('OPENAI_INVALID_CHOICE');
    }

    final message = first['message'];
    if (message is! Map) {
      throw Exception('OPENAI_INVALID_MESSAGE');
    }

    final content = (message['content'] ?? '').toString().trim();
    if (content.isEmpty) {
      throw Exception('OPENAI_EMPTY_RESPONSE');
    }

    return content;
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
  const _PricePromptContext({
    required this.item,
    this.province,
    this.district,
  });

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
    this.confidence = 'low',
    this.errorMessage = '',
    this.needsReview = false,
    this.rawResponse = '',
  });

  final bool success;
  final String name;
  final String fatherName;
  final String cnicNumber;
  final String confidence;
  final String errorMessage;
  final bool needsReview;
  final String rawResponse;
}

