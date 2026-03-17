import '../../services/ai_generative_service.dart';
import '../models/live_mandi_rate.dart';

class GeminiRateEnhancementService {
  GeminiRateEnhancementService({MandiIntelligenceService? aiService})
      : _aiService = aiService ?? MandiIntelligenceService();

  final MandiIntelligenceService _aiService;

  Future<LiveMandiRate> enhanceOne(LiveMandiRate raw) async {
    final locallyCleaned = raw.copyWith(
      commodityName: _normalizeCommodity(raw.commodityName),
      commodityNameUr: _normalizeLabel(raw.commodityNameUr),
      subCategoryName: _normalizeCommodity(raw.subCategoryName),
      categoryName: _normalizeCommodity(raw.categoryName),
      mandiName: _normalizeLabel(raw.mandiName),
      city: _normalizeLabel(raw.city),
      district: _normalizeLabel(raw.district),
      province: _normalizeLabel(raw.province),
      isAiCleaned: true,
    );

    // Non-blocking AI enrichment with timeout/retry. Raw live price remains source of truth.
    try {
      final summary = await _withRetry(
        () => _aiService.explainMarketTrend(
          cropName: locallyCleaned.commodityName,
          movingAverage: locallyCleaned.price,
          province: locallyCleaned.province,
          district: locallyCleaned.district,
          recentNews: const <String>[],
        ).timeout(const Duration(seconds: 2)),
        retries: 1,
      );

      final meta = Map<String, dynamic>.from(locallyCleaned.metadata);
      if (summary.trim().isNotEmpty) {
        meta['aiTrendSummary'] = summary.trim();
      }
      meta['aiEnhancedAt'] = DateTime.now().toUtc().toIso8601String();
      return locallyCleaned.copyWith(metadata: meta);
    } catch (_) {
      return locallyCleaned;
    }
  }

  Future<List<LiveMandiRate>> enhanceBatch(
    List<LiveMandiRate> rates, {
    int maxItems = 10,
  }) async {
    if (rates.isEmpty) return rates;

    final output = <LiveMandiRate>[];
    final limit = rates.length < maxItems ? rates.length : maxItems;

    for (var i = 0; i < rates.length; i++) {
      if (i < limit) {
        output.add(await enhanceOne(rates[i]));
      } else {
        output.add(rates[i]);
      }
    }

    return output;
  }

  Future<T> _withRetry<T>(Future<T> Function() fn, {int retries = 1}) async {
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? Exception('AI enhancement failed');
  }

  String _normalizeCommodity(String input) {
    final value = input.trim();
    if (value.isEmpty) return value;

    const alias = <String, String>{
      'gandum': 'Wheat / گندم',
      'wheat': 'Wheat / گندم',
      'گندم': 'Wheat / گندم',
      'chawal': 'Rice / چاول',
      'rice': 'Rice / چاول',
      'دھان': 'Rice Crop (Paddy) / دھان',
      'cotton': 'Cotton / کپاس',
      'kapaas': 'Cotton / کپاس',
      'buffalo_milk': 'Buffalo Milk / بھینس کا دودھ',
      'black_pepper': 'Black Pepper / کالی مرچ',
    };

    final key = value.toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    if (alias.containsKey(key)) return alias[key]!;

    // Humanize snake_case while preserving bilingual-friendly label if already present.
    if (value.contains('/')) return value;
    final humanized = key
        .split('_')
        .where((part) => part.isNotEmpty)
        .map((part) => part[0].toUpperCase() + part.substring(1))
        .join(' ');
    return humanized;
  }

  String _normalizeLabel(String input) {
    final value = input.trim();
    if (value.isEmpty) return value;
    return value
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\s+,\s+'), ', ')
        .trim();
  }
}
