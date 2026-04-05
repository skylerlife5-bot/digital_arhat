// Shared utilities for mandi display name curation and unit normalization.
// Used across Home ticker, Nearby Snapshot, and All Mandi Rates explorer.

enum MandiDisplayLanguage { urdu, english }

const Map<String, String> _cityToUrduMap = <String, String>{
  'lahore': 'لاہور',
  'gujranwala': 'گوجرانوالہ',
  'faisalabad': 'فیصل آباد',
  'okara': 'اوکاڑہ',
  'multan': 'ملتان',
  'karachi': 'کراچی',
  'rawalpindi': 'راولپنڈی',
  'bahawalpur': 'بہاولپور',
  'sahiwal': 'ساہیوال',
  'vehari': 'وہاڑی',
  'rahim yar khan': 'رحیم یار خان',
  'sargodha': 'سرگودھا',
  'gujrat': 'گجرات',
  'hyderabad': 'حیدرآباد',
  'punjab': 'پنجاب',
  'sindh': 'سندھ',
  'pakistan': 'پاکستان',
};

const Map<String, String> _urduToEnglishCityMap = <String, String>{
  'لاہور': 'Lahore',
  'گوجرانوالہ': 'Gujranwala',
  'گوجرانوالا': 'Gujranwala',
  'فیصل آباد': 'Faisalabad',
  'اوکاڑہ': 'Okara',
  'ملتان': 'Multan',
  'کراچی': 'Karachi',
  'راولپنڈی': 'Rawalpindi',
  'بہاولپور': 'Bahawalpur',
  'ساہیوال': 'Sahiwal',
  'وہاڑی': 'Vehari',
  'رحیم یار خان': 'Rahim Yar Khan',
  'سرگودھا': 'Sargodha',
  'گجرات': 'Gujrat',
  'حیدرآباد': 'Hyderabad',
  'پنجاب': 'Punjab',
  'سندھ': 'Sindh',
  'پاکستان': 'Pakistan',
};

const Map<String, String> _englishUnitMap = <String, String>{
  '100 کلو': '100 kg',
  '50 کلو': '50 kg',
  '40 کلو': '40 kg',
  'کلو': 'kg',
  'درجن': 'dozen',
  'عدد': 'piece',
  'ٹری': 'tray',
  'کریٹ': 'crate',
};

String _titleCaseWords(String value) {
  return value
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .map((part) => part[0].toUpperCase() + part.substring(1).toLowerCase())
      .join(' ');
}

bool _containsUrdu(String value) => RegExp(r'[\u0600-\u06FF]').hasMatch(value);

bool _containsLatin(String value) => RegExp(r'[A-Za-z]').hasMatch(value);

String _normalizeSpacesAndSeparators(String value) {
  return value
      .replaceAll(RegExp(r'\s*[,/|]+\s*'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _onlyUrduText(String value) {
  return _normalizeSpacesAndSeparators(
    value
        .replaceAll(RegExp(r'[A-Za-z]+'), ' ')
        .replaceAll(RegExp(r'[^\u0600-\u06FF0-9\s\-]'), ' '),
  );
}

String _onlyEnglishText(String value) {
  return _normalizeSpacesAndSeparators(
    value
        .replaceAll(RegExp(r'[\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'[^A-Za-z0-9\s\-]'), ' '),
  );
}

String _dedupeTokens(String value) {
  final parts = value
      .split(RegExp(r'\s+'))
      .where((part) => part.trim().isNotEmpty)
      .toList(growable: false);
  if (parts.length <= 1) return value.trim();

  final out = <String>[];
  final seen = <String>{};
  for (final part in parts) {
    final key = part.toLowerCase();
    if (seen.contains(key)) continue;
    seen.add(key);
    out.add(part);
  }
  return out.join(' ').trim();
}

/// Map of English/raw commodity names to curated Urdu display labels.
const Map<String, String> englishToUrduCommodityMap = <String, String>{
  // Cereals/grains
  'wheat': 'گندم',
  'rice': 'چاول',
  'paddy': 'چاول',
  'corn': 'مکئی',
  'maize': 'مکئی',

  // Fruits
  'mango': 'آم',
  'banana': 'کیلا',
  'banana dozen': 'کیلا (درجن)',
  'banana dozenes': 'کیلا (درجن)',
  'banana dozen pack': 'کیلا (درجن)',
  'banana dozen price': 'کیلا (درجن)',
  'banana dozn': 'کیلا (درجن)',
  'banana(dozen)': 'کیلا (درجن)',

  // Vegetables
  'tomato': 'ٹماٹر',
  'potato': 'آلو',
  'potato fresh': 'آلو',
  'capsicum': 'شملہ مرچ',
  'capsicum shimla mirch': 'شملہ مرچ',
  'onion': 'پیاز',
  'garlic': 'لہسن',
  'garlic china': 'لہسن چائنہ',
  'garlic chinese': 'لہسن چائنہ',
  'coriander': 'دھنیا',

  // Pulses
  'gram black': 'کالا چنا',
  'black gram': 'کالا چنا',
  'gram': 'چنا',
  'moong': 'مونگ',
  'moong bean': 'مونگ',
  'lentil': 'مسور',
  'masoor': 'مسور',
  'chickpea': 'چنا',
  'chana': 'چنا',
  'sugar': 'چینی',

  // Meat / poultry
  'live chicken': 'زندہ مرغی',
  'chicken': 'زندہ مرغی',
  'chicken meat': 'مرغی کا گوشت',
  'beef': 'بڑا گوشت',
  'mutton': 'چھوٹا گوشت',

  // Vegetables (extended)
  'chili': 'مرچ',
  'chilli': 'مرچ',
  'green chili': 'ہری مرچ',
  'red chili': 'لال مرچ',
  'bitter gourd': 'کریلا',
  'bottle gourd': 'لوکی',
  'brinjal': 'بینگن',
  'eggplant': 'بینگن',
  'spinach': 'پالک',
  'cauliflower': 'پھول گوبھی',
  'cabbage': 'بند گوبھی',
  'carrot': 'گاجر',
  'radish': 'مولی',
  'turnip': 'شلجم',
  'peas': 'مٹر',
  'ginger': 'ادرک',
  'turmeric': 'ہلدی',

  // Fruits (extended)
  'apple': 'سیب',
  'orange': 'مالٹا',
  'guava': 'امرود',
  'grape': 'انگور',
  'grapes': 'انگور',
  'watermelon': 'تربوز',
  'melon': 'خربوزہ',
  'pomegranate': 'انار',
  'dates': 'کھجور',
  'date': 'کھجور',

  // Cash crops
  'sugarcane': 'گنا',
  'dap': 'ڈی اے پی',
  'urea': 'یوریا',
};

String _sanitizeRawLabel(String input) {
  return input
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll(RegExp(r'\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'\([^\)]*(kg|dozen|doz|tray|crate|peti)[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\([^\)]*raw[^\)]*\)', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _normalizeLookupKey(String input) {
  return _sanitizeRawLabel(input)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z\u0600-\u06FF0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _pickPrimaryLocation(String city, String district, String province) {
  final tokens = <String>[
    _sanitizeRawLabel(city),
    _sanitizeRawLabel(district),
    _sanitizeRawLabel(province),
  ].where((value) => value.isNotEmpty).toList(growable: false);

  if (tokens.isEmpty) return 'پاکستان';
  return tokens.first;
}

String getLocalizedCityName(String city, MandiDisplayLanguage language) {
  final clean = _dedupeTokens(_sanitizeRawLabel(city));
  if (clean.isEmpty) {
    return language == MandiDisplayLanguage.urdu ? 'پاکستان' : 'Pakistan';
  }

  final lookup = _normalizeLookupKey(clean);
  if (language == MandiDisplayLanguage.urdu) {
    if (_cityToUrduMap.containsKey(lookup)) return _cityToUrduMap[lookup]!;

    for (final entry in _cityToUrduMap.entries) {
      if (lookup.contains(entry.key)) return entry.value;
    }

    final urduOnly = _onlyUrduText(clean);
    if (urduOnly.isNotEmpty) return urduOnly;
    return 'پاکستان';
  }

  if (_urduToEnglishCityMap.containsKey(clean)) return _urduToEnglishCityMap[clean]!;
  if (_urduToEnglishCityMap.containsKey(lookup)) return _urduToEnglishCityMap[lookup]!;

  for (final entry in _urduToEnglishCityMap.entries) {
    if (clean.contains(entry.key)) return entry.value;
  }

  final englishOnly = _onlyEnglishText(clean);
  if (englishOnly.isNotEmpty) return _titleCaseWords(englishOnly);
  if (_containsUrdu(clean)) return 'Pakistan';
  return _titleCaseWords(clean);
}

String getLocalizedCommodityName(
  String commodity,
  MandiDisplayLanguage language,
) {
  final clean = _dedupeTokens(_sanitizeRawLabel(commodity));
  if (clean.isEmpty) {
    return language == MandiDisplayLanguage.urdu ? 'اجناس' : 'Commodity';
  }

  if (language == MandiDisplayLanguage.urdu) {
    final localized = getCuratedCommodityName(clean);
    final urduOnly = _onlyUrduText(localized);
    return urduOnly.isNotEmpty ? urduOnly : 'اجناس';
  }

  final lookup = _normalizeLookupKey(clean);
  if (englishToUrduCommodityMap.containsKey(lookup)) {
    return _titleCaseWords(lookup);
  }
  if (_containsUrdu(clean)) {
    final english = englishToUrduCommodityMap.entries
        .firstWhere(
          (entry) => entry.value == clean,
          orElse: () => const MapEntry<String, String>('', ''),
        )
        .key;
    if (english.isNotEmpty) return _titleCaseWords(english);
    final englishOnly = _onlyEnglishText(clean);
    if (englishOnly.isNotEmpty) return _titleCaseWords(englishOnly);
    return 'Commodity';
  }
  if (!_containsLatin(clean)) return 'Commodity';
  return _titleCaseWords(clean);
}

String getLocalizedUnit(
  String unit,
  MandiDisplayLanguage language, {
  String commodity = '',
}) {
  final urdu = normalizeRateUnit(unit, commodity);
  if (language == MandiDisplayLanguage.urdu) return urdu;

  final mapped = _englishUnitMap[urdu];
  if (mapped != null && mapped.trim().isNotEmpty) return mapped;

  final clean = _dedupeTokens(_sanitizeRawLabel(unit));
  if (_containsUrdu(clean) || !_containsLatin(clean)) return 'unit';
  return _titleCaseWords(clean);
}

String formatUnitDisplay(String unitRaw) {
  final unit = unitRaw.trim().toLowerCase();
  switch (unit) {
    case 'per_kg':
      return 'فی کلو';
    case 'per_40kg':
      return '40 کلو (1 من)';
    case 'per_50kg':
      return '50 کلو تھیلا';
    case 'per_20kg':
      return '20 کلو تھیلا';
    case 'per_dozen':
      return 'فی درجن';
    case 'per_litre':
      return 'فی لیٹر';
    case 'per_5litre':
      return '5 لیٹر';
    case 'per_100kg':
      return 'فی 100 کلو';
    default:
      return unitRaw;
  }
}

String enforceUrduOnlyText(String value, {required String fallback}) {
  final urdu = _onlyUrduText(value);
  if (urdu.isEmpty) return fallback;
  return _containsLatin(urdu) ? fallback : urdu;
}

String getCleanUrduUnitForDisplay(
  String unitRaw, {
  required String commodityRaw,
}) {
  final localized = getLocalizedUnit(
    unitRaw,
    MandiDisplayLanguage.urdu,
    commodity: commodityRaw,
  );
  final clean = _dedupeTokens(localized);
  return enforceUrduOnlyText(clean, fallback: 'کلو');
}

bool hasMixedLatinInUrdu(String value) => _containsLatin(value);

String formatLocalizedPrice(double price, MandiDisplayLanguage language) {
  final rounded = price.toStringAsFixed(0);
  return language == MandiDisplayLanguage.urdu
      ? '$rounded روپے'
      : 'Rs $rounded';
}

String getLocalizedRelativeTime(
  DateTime? dateTime,
  MandiDisplayLanguage language,
) {
  if (dateTime == null) {
    return language == MandiDisplayLanguage.urdu ? '--' : '--';
  }

  final diff = DateTime.now().toUtc().difference(dateTime.toUtc());
  if (language == MandiDisplayLanguage.urdu) {
    if (diff.inMinutes < 1) return 'ابھی';
    if (diff.inMinutes < 60) return '${diff.inMinutes} منٹ پہلے';
    if (diff.inHours < 24) return '${diff.inHours} گھنٹے پہلے';
    return '${diff.inDays} دن پہلے';
  }

  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

String getLocalizedPrimaryLocation({
  required String city,
  required String district,
  required String province,
  required MandiDisplayLanguage language,
}) {
  return getLocalizedCityName(
    _pickPrimaryLocation(city, district, province),
    language,
  );
}

/// Get curated Urdu display name for a commodity.
/// Returns the curated name if mapped, otherwise returns the input (possibly
/// with Urdu extraction from parentheses).
String getCuratedCommodityName(String commodityRaw) {
  final cleanRaw = _sanitizeRawLabel(commodityRaw);
  if (cleanRaw.isEmpty) return 'اجناس';

  // First, try to extract Urdu from parentheses: "Banana (درجن)" -> "درجن"
  final urduMatch = RegExp(r'\(([\u0600-\u06FF\s]+)\)')
      .firstMatch(cleanRaw);
  if (urduMatch != null) {
    final extracted = urduMatch.group(1)?.trim();
    if (extracted != null && extracted.isNotEmpty) {
      // Return full mapping if available, else return extracted Urdu
        final normalized = cleanRaw
          .replaceAll(RegExp(r'[\(\)]'), '')
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (englishToUrduCommodityMap.containsKey(normalized)) {
        return englishToUrduCommodityMap[normalized]!;
      }
      // Return the extracted Urdu text directly (not hardcoded banana)
      return extracted;
    }
  }

  // Normalize for map lookup
  final lowerInput = cleanRaw.toLowerCase();
  if (englishToUrduCommodityMap.containsKey(lowerInput)) {
    return englishToUrduCommodityMap[lowerInput]!;
  }

  // Try normalized form (remove special chars, collapse spaces)
  final normalized = lowerInput
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (englishToUrduCommodityMap.containsKey(normalized)) {
    return englishToUrduCommodityMap[normalized]!;
  }

  // Check for contained keywords
  if (lowerInput.contains('banana') && lowerInput.contains('dozen')) {
    return 'کیلا (درجن)';
  }
  if (lowerInput.contains('capsicum') ||
      lowerInput.contains('shimla') ||
      lowerInput.contains('شملہ مرچ')) {
    return 'شملہ مرچ';
  }
  if (lowerInput.contains('gram') && lowerInput.contains('black')) {
    return 'کالا چنا';
  }
  if (lowerInput.contains('potato') && lowerInput.contains('fresh')) {
    return 'آلو';
  }
  if (lowerInput.contains('garlic') && lowerInput.contains('china')) {
    return 'لہسن چائنہ';
  }

  // Hard fallback: never leak raw English commodity labels in user-facing UI.
  return 'اجناس';
}

/// Normalize a rate unit string to a short, readable Urdu display label.
/// Commodity name takes priority for exceptions (e.g., banana always per dozen).
String normalizeRateUnit(String unitRaw, String commodityRaw) {
  final commodity = commodityRaw.trim().toLowerCase();

  if (commodity.contains('live chicken') ||
      commodity.contains('chicken meat') ||
      commodity.contains('beef') ||
      commodity.contains('mutton') ||
      commodity.contains('زندہ مرغی') ||
      commodity.contains('مرغی کا گوشت') ||
      commodity.contains('بڑا گوشت') ||
      commodity.contains('چھوٹا گوشت')) {
    return 'کلو';
  }

  if (commodity.contains('milk') || commodity.contains('دودھ')) {
    return 'لیٹر';
  }

  if (commodity.contains('egg') || commodity.contains('eggs') ||
      commodity.contains('انڈا')) {
    return 'درجن';
  }

  if (commodity.contains('wheat') ||
      commodity.contains('rice') ||
      commodity.contains('lentil') ||
      commodity.contains('dal') ||
      commodity.contains('daal') ||
      commodity.contains('sugar') ||
      commodity.contains('gram') ||
      commodity.contains('chana') ||
      commodity.contains('گندم') ||
      commodity.contains('چاول') ||
      commodity.contains('دال') ||
      commodity.contains('چینی') ||
      commodity.contains('چنا')) {
    return '40 کلو';
  }
  
  // Commodity-based overrides take priority, but respect explicit unit signals
  if (commodity.contains('banana') || commodity.contains('کیلا')) {
    final u = _sanitizeRawLabel(unitRaw).toLowerCase();
    if (u.contains('crate') || u.contains('کریٹ')) return 'کریٹ';
    if (u.contains('peti') || u.contains('پیٹی')) return 'پیٹی';
    return 'درجن';
  }
  if (commodity.contains('egg') || commodity.contains('eggs') ||
      commodity.contains('انڈا')) {
    final u = _sanitizeRawLabel(unitRaw).toLowerCase();
    if (u.contains('tray') || u.contains('ٹری')) return 'ٹری';
    return 'درجن';
  }
  if (commodity.contains('lemon') || commodity.contains('لیموں') ||
      commodity.contains('nimbu')) {
    return 'درجن';
  }
  
  final unit = _sanitizeRawLabel(unitRaw).toLowerCase();
  final hasKg = unit.contains('kg');
  final hasDozen = unit.contains('dozen') || unit.contains('doz');
  if (hasKg && hasDozen) return 'درجن';
  if (unit.contains('piece') || unit == 'pc' || unit == 'pcs') return 'عدد';
  
  // Standard units
  if (unit.contains('100') && unit.contains('kg')) return '100 کلو';
  if (unit.contains('40') && unit.contains('kg')) return '40 کلو';
  if (unit.contains('maund') ||
      unit.contains('mond') ||
      unit.contains('mann')) {
    return '40 کلو';
  }
  if (unit.contains('50') && unit.contains('kg')) return '50 کلو';
  if (unit.contains('dozen') || unit.contains('doz')) return 'درجن';
  if (unit == 'kg' || unit == 'per kg' || unit == 'perkg') return 'کلو';
  if (unit.contains('kg')) return 'کلو';
  
  // Default: per 100kg (AMIS standard)
  return '100 کلو';
}

/// Clean and deduplicate a location string.
/// Input example: "Gujranwala, Gujranwala, Gujranwala, Punjab"
/// Output example: "Gujranwala, Punjab"
String cleanLocationString({
  required String city,
  required String district,
  required String province,
}) {
  final cleanCity = _sanitizeRawLabel(city)
      .replaceAll(RegExp(r'\b(mandi|market|wholesale)\b', caseSensitive: false), '')
      .trim();
  final cleanDistrict = _sanitizeRawLabel(district)
      .replaceAll(RegExp(r'\b(district|mandi|market)\b', caseSensitive: false), '')
      .trim();
  final cleanProvince = _sanitizeRawLabel(province).trim();

  final parts = <String>{
    cleanCity,
    cleanDistrict,
    cleanProvince,
  }.where((e) => e.isNotEmpty).toList(growable: false);

  if (parts.isEmpty) return 'پاکستان';
  
  // Return deduplicated, in order of preference: city, district, province
  final result = <String>[];
  if (cleanCity.isNotEmpty) result.add(cleanCity);
  if (cleanDistrict.isNotEmpty && cleanDistrict.toLowerCase() != cleanCity.toLowerCase()) {
    result.add(cleanDistrict);
  }
  if (cleanProvince.isNotEmpty &&
      cleanProvince.toLowerCase() != cleanCity.toLowerCase() &&
      cleanProvince.toLowerCase() != cleanDistrict.toLowerCase()) {
    result.add(cleanProvince);
  }

  return result.isEmpty ? 'پاکستان' : result.join(', ');
}
