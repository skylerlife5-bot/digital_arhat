import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/constants.dart';
import '../../services/ai_generative_service.dart';

class GeminiVoiceDraft {
  const GeminiVoiceDraft({
    required this.rawResponse,
    required this.data,
    required this.usedFallback,
  });

  final String rawResponse;
  final Map<String, String> data;
  final bool usedFallback;

  String get category => data['category'] ?? '';
  String get subcategory => data['subcategory'] ?? '';
  String get quantity => data['quantity'] ?? '';
  String get unit => data['unit'] ?? '';
  String get price => data['price'] ?? '';
  String get province => data['province'] ?? '';
  String get district => data['district'] ?? '';
  String get tehsil => data['tehsil'] ?? '';
  String get localArea => data['localArea'] ?? '';
  String get description => data['description'] ?? '';
}

class GeminiVoiceHelper {
  static const String extractionPrompt =
      'You are an assistant for a Pakistan mandi app. '
      'Convert the user transcript into STRICT JSON only. '
      'No markdown, no code fences, no explanation, no extra keys. '
      'Use this exact schema with string values only: '
      '{"category":"","subcategory":"","quantity":"","unit":"","price":"","province":"","district":"","tehsil":"","localArea":"","description":""}. '
      'If a value is unknown, return empty string for that field. '
      'Keep Pakistani names as spoken. '
      'Quantity and price should be plain numeric text when possible.';

  static Future<GeminiVoiceDraft> extractDraft({
    required MandiIntelligenceService ai,
    required String transcript,
  }) async {
    if (transcript.trim().isEmpty) {
      throw const FormatException('Empty transcript');
    }

    String raw = '';
    try {
      debugPrint('[VOICE] gemini_started');
      final String prompt =
          '$extractionPrompt\n\nUser transcript:\n${transcript.trim()}';
      raw = await ai.getAIResponse(prompt);
      debugPrint('[VOICE] gemini_response=$raw');

      final Map<String, dynamic> jsonMap = _decodeBestEffortJson(raw);
      debugPrint('[VoiceListing] gemini_json_parse_success');

      String field(String key) {
        final value = (jsonMap[key] ?? '').toString().trim();
        return value;
      }

      return GeminiVoiceDraft(
        rawResponse: raw,
        usedFallback: false,
        data: <String, String>{
          'category': field('category'),
          'subcategory': field('subcategory'),
          'quantity': field('quantity'),
          'unit': field('unit'),
          'price': field('price'),
          'province': field('province'),
          'district': field('district'),
          'tehsil': field('tehsil'),
          'localArea': field('localArea'),
          'description': field('description'),
        },
      );
    } catch (geminiError) {
      debugPrint('[VOICE] gemini_failed=$geminiError');
      debugPrint('[VoiceListing] gemini_json_parse_failed error=$geminiError');
      debugPrint('[VOICE] fallback_started');
      debugPrint('[VoiceListing] local_fallback_parse_started');

      try {
        final fallbackData = _localFallbackParse(transcript);
        debugPrint('[VOICE] fallback_success');
        debugPrint('[VoiceListing] local_fallback_parse_success');
        return GeminiVoiceDraft(
          rawResponse: raw.isEmpty ? 'Failed to call Gemini' : raw,
          usedFallback: true,
          data: fallbackData,
        );
      } catch (fallbackError) {
        debugPrint('[VoiceListing] local_fallback_parse_failed error=$fallbackError');
        rethrow;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Keyword → category ID (matches MarketHierarchy.listingCategories ids)
  // Public so add_listing_screen can re-run the keyword scan on transcript.
  // -------------------------------------------------------------------------
  static const Map<String, String> categoryKeywords = {
    // vegetables
    'aalu': 'vegetables', 'aloo': 'vegetables', 'alu': 'vegetables',
    'potato': 'vegetables',
    'pyaz': 'vegetables', 'piaz': 'vegetables', 'onion': 'vegetables',
    'tamatar': 'vegetables', 'tomato': 'vegetables',
    'mirch': 'vegetables', 'chili': 'vegetables', 'chilli': 'vegetables',
    'shimla mirch': 'vegetables', 'capsicum': 'vegetables',
    'lehsan': 'vegetables', 'garlic': 'vegetables',
    'adrak': 'vegetables', 'ginger': 'vegetables',
    'bhindi': 'vegetables', 'bindi': 'vegetables', 'okra': 'vegetables',
    'baigan': 'vegetables', 'brinjal': 'vegetables',
    'gobi': 'vegetables', 'gobhi': 'vegetables', 'cauliflower': 'vegetables',
    'palak': 'vegetables', 'spinach': 'vegetables',
    'matar': 'vegetables', 'peas': 'vegetables',
    'gajar': 'vegetables', 'carrot': 'vegetables',
    'mooli': 'vegetables', 'radish': 'vegetables',
    'shalgam': 'vegetables', 'turnip': 'vegetables',
    // crops
    'gehun': 'crops', 'gandum': 'crops', 'wheat': 'crops',
    'chawal': 'crops', 'rice': 'crops',
    'dhan': 'crops', 'paddy': 'crops',
    'kapas': 'crops', 'cotton': 'crops',
    'ganna': 'crops', 'sugarcane': 'crops',
    'makki': 'crops', 'maize': 'crops', 'corn': 'crops',
    'chana': 'crops', 'gram': 'crops',
    'sarson': 'crops', 'mustard': 'crops',
    'barley': 'crops', 'jo': 'crops',
    'bajra': 'crops', 'millet': 'crops',
    'jawar': 'crops', 'jowar': 'crops', 'sorghum': 'crops',
    // fruits
    'aam': 'fruit', 'mango': 'fruit',
    'kinnow': 'fruit', 'kinnu': 'fruit',
    'orange': 'fruit', 'malta': 'fruit',
    'seb': 'fruit', 'apple': 'fruit',
    'kela': 'fruit', 'banana': 'fruit',
    'amrood': 'fruit', 'guava': 'fruit',
    'khajur': 'fruit', 'dates': 'fruit',
    'anaar': 'fruit', 'pomegranate': 'fruit',
    'angoor': 'fruit', 'grapes': 'fruit',
    'tarbuz': 'fruit', 'watermelon': 'fruit',
    'kharboza': 'fruit', 'melon': 'fruit',
    'aru': 'fruit', 'peach': 'fruit',
    'alucha': 'fruit', 'plum': 'fruit',
    'apricot': 'fruit',
    // livestock
    'gaye': 'livestock', 'gaay': 'livestock', 'cow': 'livestock',
    'bhains': 'livestock', 'buffalo': 'livestock',
    'bail': 'livestock', 'bull': 'livestock',
    'bakra': 'livestock', 'bakri': 'livestock', 'goat': 'livestock',
    'bhair': 'livestock', 'sheep': 'livestock',
    'oont': 'livestock', 'camel': 'livestock',
    'bachhra': 'livestock', 'calf': 'livestock',
    // poultry
    'murgi': 'poultry', 'chicken': 'poultry',
    'broiler': 'poultry',
    'anda': 'poultry', 'eggs': 'poultry',
    'choza': 'poultry', 'chicks': 'poultry',
    // milk & dairy
    'doodh': 'milk', 'milk': 'milk', 'dudh': 'milk',
    'dahi': 'milk', 'yogurt': 'milk',
    'ghee': 'milk', 'makhan': 'milk', 'butter': 'milk',
    // seeds
    'beej': 'seeds', 'seed': 'seeds', 'seeds': 'seeds',
    // fertilizer
    'khad': 'fertilizer', 'urea': 'fertilizer', 'dap': 'fertilizer',
    'fertilizer': 'fertilizer',
    // dry fruits
    'badam': 'dry_fruits', 'almond': 'dry_fruits',
    'akhrot': 'dry_fruits', 'walnut': 'dry_fruits',
    'pista': 'dry_fruits', 'pistachio': 'dry_fruits',
    'kishmish': 'dry_fruits', 'raisins': 'dry_fruits',
    // spices
    'haldi': 'spices', 'turmeric': 'spices',
    'dhania': 'spices', 'coriander': 'spices',
    'zeera': 'spices', 'cumin': 'spices',
    'kali mirch': 'spices', 'black pepper': 'spices',
  };

  // Maps same keywords → exact subcategory label from CategoryConstants
  // Public so add_listing_screen can re-run the keyword scan on transcript.
  static const Map<String, String> subcategoryKeywords = {
    'aalu': 'Potato / آلو', 'aloo': 'Potato / آلو', 'alu': 'Potato / آلو',
    'potato': 'Potato / آلو',
    'pyaz': 'Onion / پیاز', 'piaz': 'Onion / پیاز', 'onion': 'Onion / پیاز',
    'tamatar': 'Tomato / ٹماٹر', 'tomato': 'Tomato / ٹماٹر',
    'mirch': 'Chili / مرچ', 'chili': 'Chili / مرچ', 'chilli': 'Chili / مرچ',
    'shimla mirch': 'Capsicum / شملہ مرچ', 'capsicum': 'Capsicum / شملہ مرچ',
    'lehsan': 'Garlic / لہسن', 'garlic': 'Garlic / لہسن',
    'adrak': 'Ginger / ادرک', 'ginger': 'Ginger / ادرک',
    'bhindi': 'Okra / بھنڈی', 'bindi': 'Okra / بھنڈی', 'okra': 'Okra / بھنڈی',
    'baigan': 'Brinjal / بینگن', 'brinjal': 'Brinjal / بینگن',
    'gobi': 'Cauliflower / پھول گوبھی', 'gobhi': 'Cauliflower / پھول گوبھی',
    'cauliflower': 'Cauliflower / پھول گوبھی',
    'palak': 'Spinach / پالک', 'spinach': 'Spinach / پالک',
    'matar': 'Peas / مٹر', 'peas': 'Peas / مٹر',
    'gajar': 'Carrot / گاجر', 'carrot': 'Carrot / گاجر',
    'mooli': 'Radish / مولی', 'radish': 'Radish / مولی',
    'shalgam': 'Turnip / شلجم', 'turnip': 'Turnip / شلجم',
    'gehun': 'Wheat / گندم', 'gandum': 'Wheat / گندم', 'wheat': 'Wheat / گندم',
    'chawal': 'Processed Rice / چاول', 'rice': 'Processed Rice / چاول',
    'dhan': 'Rice Crop (Paddy) / دھان', 'paddy': 'Rice Crop (Paddy) / دھان',
    'kapas': 'Cotton / کپاس', 'cotton': 'Cotton / کپاس',
    'ganna': 'Sugarcane / گنا', 'sugarcane': 'Sugarcane / گنا',
    'makki': 'Maize / مکئی', 'maize': 'Maize / مکئی', 'corn': 'Maize / مکئی',
    'chana': 'Gram / چنا', 'gram': 'Gram / چنا',
    'sarson': 'Mustard / سرسوں', 'mustard': 'Mustard / سرسوں',
    'barley': 'Barley / جو', 'jo': 'Barley / جو',
    'bajra': 'Millet / باجرا', 'millet': 'Millet / باجرا',
    'jawar': 'Sorghum / جوار', 'jowar': 'Sorghum / جوار', 'sorghum': 'Sorghum / جوار',
    'aam': 'Mango / آم', 'mango': 'Mango / آم',
    'kinnow': 'Kinnow / کینو', 'kinnu': 'Kinnow / کینو',
    'orange': 'Orange / مالٹا', 'malta': 'Orange / مالٹا',
    'seb': 'Apple / سیب', 'apple': 'Apple / سیب',
    'kela': 'Banana / کیلا', 'banana': 'Banana / کیلا',
    'amrood': 'Guava / امرود', 'guava': 'Guava / امرود',
    'khajur': 'Dates / کھجور', 'dates': 'Dates / کھجور',
    'anaar': 'Pomegranate / انار', 'pomegranate': 'Pomegranate / انار',
    'angoor': 'Grapes / انگور', 'grapes': 'Grapes / انگور',
    'tarbuz': 'Watermelon / تربوز', 'watermelon': 'Watermelon / تربوز',
    'kharboza': 'Melon / خربوزہ', 'melon': 'Melon / خربوزہ',
    'gaye': 'Cow / گائے', 'gaay': 'Cow / گائے', 'cow': 'Cow / گائے',
    'bhains': 'Buffalo / بھینس', 'buffalo': 'Buffalo / بھینس',
    'bail': 'Bull / بیل', 'bull': 'Bull / بیل',
    'bakra': 'Goat / بکری', 'bakri': 'Goat / بکری', 'goat': 'Goat / بکری',
    'bhair': 'Sheep / بھیڑ', 'sheep': 'Sheep / بھیڑ',
    'oont': 'Camel / اونٹ', 'camel': 'Camel / اونٹ',
    'bachhra': 'Calf / بچھڑا', 'calf': 'Calf / بچھڑا',
    'murgi': 'Desi Chicken / دیسی مرغی', 'chicken': 'Desi Chicken / دیسی مرغی',
    'broiler': 'Broiler / برائلر',
    'anda': 'Eggs / انڈے', 'eggs': 'Eggs / انڈے',
    'doodh': 'Raw Milk / کچا دودھ', 'milk': 'Raw Milk / کچا دودھ', 'dudh': 'Raw Milk / کچا دودھ',
    'dahi': 'Yogurt / دہی', 'yogurt': 'Yogurt / دہی',
    'ghee': 'Desi Ghee / دیسی گھی',
    'badam': 'Almond / بادام', 'almond': 'Almond / بادام',
    'akhrot': 'Walnut / اخروٹ', 'walnut': 'Walnut / اخروٹ',
    'pista': 'Pistachio / پستہ', 'pistachio': 'Pistachio / پستہ',
    'kishmish': 'Raisins / کشمش', 'raisins': 'Raisins / کشمش',
    'haldi': 'Turmeric / ہلدی', 'turmeric': 'Turmeric / ہلدی',
    'dhania': 'Coriander / دھنیا', 'coriander': 'Coriander / دھنیا',
    'zeera': 'Cumin / زیرہ', 'cumin': 'Cumin / زیرہ',
  };

  static const Map<String, String> _provinceAliases = {
    'punjab': 'Punjab',
    'sindh': 'Sindh',
    'balochistan': 'Balochistan',
    'kpk': 'Khyber Pakhtunkhwa (KPK)',
    'kp': 'Khyber Pakhtunkhwa (KPK)',
    'khyber': 'Khyber Pakhtunkhwa (KPK)',
    'nwfp': 'Khyber Pakhtunkhwa (KPK)',
    'gilgit': 'Gilgit-Baltistan',
    'gb': 'Gilgit-Baltistan',
    'skardu': 'Gilgit-Baltistan',
    'ajk': 'Azad Jammu & Kashmir (AJK)',
    'kashmir': 'Azad Jammu & Kashmir (AJK)',
    'azad kashmir': 'Azad Jammu & Kashmir (AJK)',
  };

  static const Map<String, String> _urduDigitMap = {
    '۰': '0',
    '۱': '1',
    '۲': '2',
    '۳': '3',
    '۴': '4',
    '۵': '5',
    '۶': '6',
    '۷': '7',
    '۸': '8',
    '۹': '9',
    '٠': '0',
    '١': '1',
    '٢': '2',
    '٣': '3',
    '٤': '4',
    '٥': '5',
    '٦': '6',
    '٧': '7',
    '٨': '8',
    '٩': '9',
  };

  static String normalizeVoiceText(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_urduDigitMap[char] ?? char);
    }
    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'([a-z\u0600-\u06FF]+)(\d+)'), r'$1 $2')
        .replaceAll(RegExp(r'(\d+)([a-z\u0600-\u06FF]+)'), r'$1 $2')
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF.]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _isNumericToken(String token) {
    return RegExp(r'^\d+(?:[.,]\d+)?$').hasMatch(token.trim());
  }

  static bool _isCurrencyToken(String token) {
    final value = token.trim();
    return value == 'rupay' ||
        value == 'rupee' ||
        value == 'rupees' ||
        value == 'rs' ||
        value == 'pkr' ||
        value == 'روپے';
  }

  static String? extractMergedPriceTokens(String transcript) {
    final normalized = normalizeVoiceText(transcript);
    if (normalized.isEmpty) {
      debugPrint('[VoiceListing] merged_price_tokens=none');
      return null;
    }

    final tokens = normalized
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    String? bestMatch;

    for (var index = 0; index < tokens.length; index++) {
      if (!_isCurrencyToken(tokens[index])) {
        continue;
      }

      final leftDigits = <String>[];
      for (var cursor = index - 1; cursor >= 0; cursor--) {
        final token = tokens[cursor];
        if (_isNumericToken(token)) {
          leftDigits.insert(0, token.replaceAll(RegExp(r'[^0-9]'), ''));
          continue;
        }
        break;
      }

      final rightDigits = <String>[];
      if (leftDigits.isEmpty) {
        for (var cursor = index + 1; cursor < tokens.length; cursor++) {
          final token = tokens[cursor];
          if (_isNumericToken(token)) {
            rightDigits.add(token.replaceAll(RegExp(r'[^0-9]'), ''));
            continue;
          }
          break;
        }
      }

      final candidate = leftDigits.isNotEmpty
          ? leftDigits.join()
          : rightDigits.join();
      if (candidate.isEmpty) {
        continue;
      }
      if (bestMatch == null || candidate.length > bestMatch.length) {
        bestMatch = candidate;
      }
    }

    debugPrint('[VoiceListing] merged_price_tokens=${bestMatch ?? 'none'}');
    return bestMatch;
  }

  static Map<String, String> _localFallbackParse(String transcript) {
    final normalized = normalizeVoiceText(transcript);
    final lower = normalized;
    final data = <String, String>{
      'category': '',
      'subcategory': '',
      'quantity': '',
      'unit': '',
      'price': '',
      'province': '',
      'district': '',
      'tehsil': '',
      'localArea': '',
      'description': '',
    };

    // ── CATEGORY + SUBCATEGORY ────────────────────────────────────────────
    // Sort keywords longest-first so "shimla mirch" beats "mirch"
    final sortedKeywords = categoryKeywords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final keyword in sortedKeywords) {
      if (lower.contains(keyword)) {
        data['category'] = categoryKeywords[keyword]!;
        data['subcategory'] = subcategoryKeywords[keyword] ?? '';
        debugPrint('[VOICE] fallback_category=${data['category']} subcategory=${data['subcategory']}');
        break;
      }
    }

    final qtyUnitRegex = RegExp(
      r'\b(\d+(?:[.,]\d+)?)\s*(mann|man|maund|kilo|kg|kilogram|litre|liter|ltr|peti|crate)\b',
    );
    final qtyMatch = qtyUnitRegex.firstMatch(lower);
    if (qtyMatch != null) {
      final num = (qtyMatch.group(1) ?? '').replaceAll(',', '');
      final rawUnit = (qtyMatch.group(2) ?? '').trim();
      final unit = switch (rawUnit) {
        'man' || 'maund' => 'mann',
        'kilogram' => 'kg',
        'liter' || 'ltr' => 'litre',
        'crate' => 'peti',
        _ => rawUnit,
      };
      if (num.isNotEmpty) {
        data['quantity'] = num;
        data['unit'] = unit;
      }
    } else {
      final justNum = RegExp(r'\b(\d+(?:[.,]\d+)?)\b').firstMatch(lower);
      if (justNum != null) {
        final num = (justNum.group(1) ?? '').replaceAll(',', '');
        if (num.isNotEmpty) {
          data['quantity'] = num;
        }
      }
    }

    final mergedPrice = extractMergedPriceTokens(lower);
    if ((mergedPrice ?? '').isNotEmpty) {
      data['price'] = mergedPrice!;
    } else {
      final allNumbers = RegExp(r'\b(\d+(?:[.,]\d+)?)\b').allMatches(lower);
      if (allNumbers.length > 1) {
        final price = (allNumbers.elementAt(1).group(1) ?? '').replaceAll(',', '');
        if (price.isNotEmpty) {
          data['price'] = price;
        }
      }
    }

    // ── LOCATION ─────────────────────────────────────────────────────────
    // Scan AppConstants.pakistanLocations for district match (all provinces)
    bool locationFound = false;
    outer:
    for (final entry in AppConstants.pakistanLocations.entries) {
      for (final district in entry.value) {
        final dLower = district.toLowerCase();
        if (RegExp('\\b${RegExp.escape(dLower)}\\b').hasMatch(lower)) {
          data['district'] = district;
          data['province'] = entry.key;
          data['localArea'] = district;
          locationFound = true;
          debugPrint('[VOICE] fallback_location=district:$district province:${entry.key}');
          break outer;
        }
      }
    }
    // No district found – check province aliases
    if (!locationFound) {
      final sortedAliases = _provinceAliases.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      for (final alias in sortedAliases) {
        if (RegExp('\\b${RegExp.escape(alias)}\\b').hasMatch(lower)) {
          data['province'] = _provinceAliases[alias]!;
          debugPrint('[VOICE] fallback_location=province:${data['province']}');
          break;
        }
      }
    }

    // ── DESCRIPTION: strip numbers, units, rupay, and any found locations ──
    String desc = normalized;
    desc = desc.replaceAll(
      RegExp(
        r'\b\d+(?:[.,]\d+)?\s*(mann|man|maund|kilo|kg|kilogram|litre|liter|ltr|peti|crate)?\b',
        caseSensitive: false,
      ),
      ' ',
    );
    desc = desc.replaceAll(
      RegExp(r'\b(rupay|rupees?|rs\.?|pkr)\b', caseSensitive: false),
      ' ',
    );
    // Strip any found location tokens from description
    final foundDistrict = (data['district'] ?? '').trim();
    final foundProvince = (data['province'] ?? '').trim();
    if (foundDistrict.isNotEmpty) {
      desc = desc.replaceAll(
        RegExp('\\b${RegExp.escape(foundDistrict)}\\b', caseSensitive: false),
        ' ',
      );
    }
    if (foundProvince.isNotEmpty) {
      desc = desc.replaceAll(
        RegExp('\\b${RegExp.escape(foundProvince.split(' ').first)}\\b', caseSensitive: false),
        ' ',
      );
    }
    // Strip known category keyword(s) from description
    final foundSubcategory = (data['subcategory'] ?? '').trim();
    if (foundSubcategory.isNotEmpty) {
      final subLower = foundSubcategory.split('/').first.trim().toLowerCase();
      desc = desc.replaceAll(
        RegExp('\\b${RegExp.escape(subLower)}\\b', caseSensitive: false),
        ' ',
      );
    }
    // Strip connectors like "se", "ka", "ki", "ke"
    desc = desc.replaceAll(
      RegExp(r'\b(se|ka|ki|ke|wala|walay|ki|hai|hain|mera|meri)\b',
          caseSensitive: false),
      ' ',
    );
    desc = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (desc.isNotEmpty) {
      data['description'] = desc;
    }

    // Keep empty when nothing useful remains; do not dump full raw transcript.
    return data;
  }

  static double? parsePositiveNumber(String raw) {
    final cleaned = normalizeVoiceText(raw)
      .replaceAll(RegExp(r'[^0-9.,]'), '')
        .replaceAll(',', '');
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    return value;
  }

  static Map<String, dynamic> _decodeBestEffortJson(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Empty AI response');
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Continue to best-effort extraction.
    }

    final start = trimmed.indexOf('{');
    final end = trimmed.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = trimmed.substring(start, end + 1);
      final decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) return decoded;
    }

    throw const FormatException('AI did not return valid JSON');
  }
}
