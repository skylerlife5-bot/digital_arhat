import 'constants.dart';

class MarketSubcategoryOption {
  const MarketSubcategoryOption({
    required this.id,
    required this.labelEn,
    required this.labelUr,
  });

  final String id;
  final String labelEn;
  final String labelUr;

  String get bilingualLabel => '$labelEn / $labelUr';
}

class MarketCategoryOption {
  const MarketCategoryOption({
    required this.id,
    required this.mandiType,
    required this.labelEn,
    required this.labelUr,
  });

  final String id;
  final MandiType mandiType;
  final String labelEn;
  final String labelUr;

  String get bilingualLabel => '$labelEn / $labelUr';
}

class MarketHierarchy {
  static const String pakistanCountry = 'Pakistan';

  static const List<MarketCategoryOption> categories = <MarketCategoryOption>[
    MarketCategoryOption(
      id: 'crops',
      mandiType: MandiType.crops,
      labelEn: 'Crops',
      labelUr: 'فصلیں',
    ),
    MarketCategoryOption(
      id: 'fruit',
      mandiType: MandiType.fruit,
      labelEn: 'Fruits',
      labelUr: 'پھل',
    ),
    MarketCategoryOption(
      id: 'vegetables',
      mandiType: MandiType.vegetables,
      labelEn: 'Vegetables',
      labelUr: 'سبزیاں',
    ),
    MarketCategoryOption(
      id: 'flowers',
      mandiType: MandiType.flowers,
      labelEn: 'Flowers',
      labelUr: 'پھول',
    ),
    MarketCategoryOption(
      id: 'livestock',
      mandiType: MandiType.livestock,
      labelEn: 'Livestock',
      labelUr: 'مویشی',
    ),
    MarketCategoryOption(
      id: 'milk',
      mandiType: MandiType.milk,
      labelEn: 'Milk & Dairy',
      labelUr: 'دودھ و ڈیری',
    ),
    MarketCategoryOption(
      id: 'seeds',
      mandiType: MandiType.seeds,
      labelEn: 'Seeds',
      labelUr: 'بیج',
    ),
    MarketCategoryOption(
      id: 'fertilizer',
      mandiType: MandiType.fertilizer,
      labelEn: 'Fertilizer',
      labelUr: 'کھاد',
    ),
    MarketCategoryOption(
      id: 'machinery',
      mandiType: MandiType.machinery,
      labelEn: 'Machinery',
      labelUr: 'مشینری',
    ),
    MarketCategoryOption(
      id: 'tools',
      mandiType: MandiType.tools,
      labelEn: 'Tools',
      labelUr: 'اوزار',
    ),
    MarketCategoryOption(
      id: 'dry_fruits',
      mandiType: MandiType.dryFruits,
      labelEn: 'Dry Fruits',
      labelUr: 'خشک میوہ جات',
    ),
    MarketCategoryOption(
      id: 'spices',
      mandiType: MandiType.spices,
      labelEn: 'Spices',
      labelUr: 'مصالحہ جات',
    ),
  ];

  static String categoryIdForMandiType(MandiType mandiType) {
    for (final option in categories) {
      if (option.mandiType == mandiType) {
        return option.id;
      }
    }
    return 'crops';
  }

  static String categoryLabelForMandiType(MandiType mandiType) {
    for (final option in categories) {
      if (option.mandiType == mandiType) {
        return option.bilingualLabel;
      }
    }
    return 'Crops / فصلیں';
  }

  static List<MarketSubcategoryOption> subcategoriesForMandiType(
    MandiType mandiType,
  ) {
    final items = CategoryConstants.itemsForMandiType(mandiType);
    return items
        .map(
          (item) {
            final parts = _splitBilingual(item);
            return MarketSubcategoryOption(
              id: _slug(item),
              labelEn: parts.$1,
              labelUr: parts.$2,
            );
          },
        )
        .toList(growable: false);
  }

  static String subcategoryIdFromProduct(String productLabel) {
    return _slug(productLabel);
  }

  static String subcategoryDisplayFromProduct(String productLabel) {
    final cleaned = productLabel.trim();
    if (cleaned.isEmpty) return '';
    if (cleaned.contains('/')) return cleaned;
    return '$cleaned / ${_urduHint(cleaned)}';
  }

  static String _slug(String input) {
    final englishOnly = input.split('/').first.trim();
    final normalized = englishOnly.toLowerCase();
    final collapsed = normalized.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return collapsed
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  static (String, String) _splitBilingual(String input) {
    final parts = input.split('/');
    final en = parts.isNotEmpty ? parts.first.trim() : input.trim();
    final ur = parts.length > 1 ? parts[1].trim() : _urduHint(input).trim();
    return (en, ur);
  }

  static String _urduHint(String input) {
    if (input.contains('/')) {
      final parts = input.split('/');
      if (parts.length > 1) {
        return parts[1].trim();
      }
    }

    final lower = input.toLowerCase();
    if (lower.contains('wheat') || lower.contains('gandum')) return 'گندم';
    if (lower.contains('rice') || lower.contains('chawal')) return 'چاول';
    if (lower.contains('cotton')) return 'کپاس';
    if (lower.contains('maize') || lower.contains('makai')) return 'مکئی';
    if (lower.contains('potato') || lower.contains('aloo')) return 'آلو';
    if (lower.contains('onion') || lower.contains('piaz')) return 'پیاز';
    if (lower.contains('tomato') || lower.contains('tamatar')) return 'ٹماٹر';
    if (lower.contains('mango') || lower.contains('aam')) return 'آم';
    if (lower.contains('citrus') || lower.contains('kinnow')) return 'کنو';
    if (lower.contains('apple')) return 'سیب';
    if (lower.contains('milk') || lower.contains('doodh')) return 'دودھ';
    if (lower.contains('cow')) return 'گائے';
    if (lower.contains('buffalo')) return 'بھینس';
    if (lower.contains('goat') || lower.contains('bakri')) return 'بکری';
    if (lower.contains('sheep')) return 'بھیڑ';
    if (lower.contains('camel')) return 'اونٹ';
    return _urduSubcategoryHints[lower] ?? input;
  }

  static const Map<String, String> _urduSubcategoryHints = <String, String>{
    'sugarcane (kamad)': 'گنا',
    'gram (chana)': 'چنا',
    'mustard (sarson/raya)': 'سرسوں',
    'barley (jao)': 'جو',
    'millet (bajra)': 'باجرا',
    'sorghum (jawar)': 'جوار',
    'sesame (til)': 'تل',
    'canola': 'کینولا',
    'lentil (masoor)': 'مسور',
    'lentil (moong)': 'مونگ',
    'lentil (mash/urad)': 'ماش',
    'chickpea (kabuli chana)': 'کابلی چنا',
    'peas (dried matar)': 'خشک مٹر',
    'okra (bhindi)': 'بھنڈی',
    'eggplant (baingan)': 'بینگن',
    'cauliflower (phool gobi)': 'پھول گوبھی',
    'cabbage (band gobi)': 'بند گوبھی',
    'bitter gourd (karela)': 'کریلا',
    'spinach (palak)': 'پالک',
    'radish (mooli)': 'مولی',
    'carrot (gajar)': 'گاجر',
    'pumpkin (kaddu)': 'کدو',
    'turnip (shaljam)': 'شلجم',
    'capsicum (shimla mirch)': 'شملہ مرچ',
    'cucumber (kheera)': 'کھیرا',
    'peas (matar)': 'مٹر',
    'banana (kela)': 'کیلا',
    'grapes (angoor)': 'انگور',
    'pomegranate (anar)': 'انار',
    'apricot (khubani)': 'خوبانی',
    'peach (aaroo)': 'آڑو',
    'plum (aloo bukhara)': 'آلو بخارا',
    'melon (kharbooza)': 'خربوزہ',
    'watermelon (tarbooz)': 'تربوز',
    'lychee (lichi)': 'لیچی',
    'strawberry': 'اسٹرابیری',
    'pear (nashpati)': 'ناشپاتی',
    'cow (gaaye)': 'گائے',
    'buffalo (bhains)': 'بھینس',
    'goat (bakri)': 'بکری',
    'sheep (bhair)': 'بھیڑ',
    'bull (saand/wacha)': 'سانڈ',
    'calf (bachra/bachri)': 'بچھڑا / بچھڑی',
    'desi cow': 'دیسی گائے',
    'milk (cow)': 'گائے کا دودھ',
    'milk (buffalo)': 'بھینس کا دودھ',
    'desi ghee': 'دیسی گھی',
    'eggs (farm)': 'فارم انڈے',
    'eggs (desi)': 'دیسی انڈے',
    'chicken (broiler)': 'برائلر مرغی',
    'yogurt (dahi)': 'دہی',
    'butter (makhan)': 'مکھن',
    'cream (malai)': 'ملائی',
  };
}

class PakistanLocationHierarchy {
  static List<String> get provinces {
    final result = AppConstants.pakistanLocations.keys.toList()..sort();
    return result;
  }

  static List<String> districtsForProvince(String province) {
    final list = AppConstants.pakistanLocations[province] ?? const <String>[];
    final result = list.toList()..sort();
    return result;
  }

  static List<String> tehsilsForDistrict(String district) {
    final key = district.trim();
    final tehsils = _tehsilsByDistrict[key] ?? const <String>[];
    if (tehsils.isNotEmpty) return tehsils;
    if (key.isEmpty) return const <String>[];
    return <String>['$key City', '$key Saddar', '$key Rural'];
  }

  static List<String> citiesForTehsil({
    required String district,
    required String tehsil,
  }) {
    final composite = '${district.trim()}|${tehsil.trim()}';
    final cities = _citiesByDistrictTehsil[composite] ?? const <String>[];
    if (cities.isNotEmpty) return cities;

    final districtClean = district.trim();
    if (districtClean.isEmpty) return const <String>[];
    final tehsilClean = tehsil.trim();
    if (tehsilClean.isEmpty) return <String>[districtClean];
    return <String>['$tehsilClean City', '$tehsilClean Bazar', districtClean];
  }

  static const Map<String, List<String>>
  _tehsilsByDistrict = <String, List<String>>{
    'Lahore': <String>['Ravi', 'Shalimar', 'Model Town', 'Cantt'],
    'Rawalpindi': <String>['Rawalpindi City', 'Kahuta', 'Taxila', 'Gujar Khan'],
    'Faisalabad': <String>[
      'Faisalabad City',
      'Jaranwala',
      'Samundri',
      'Tandlianwala',
    ],
    'Multan': <String>['Multan City', 'Shujabad', 'Jalalpur Pirwala'],
    'Gujranwala': <String>['Gujranwala City', 'Kamoke', 'Nowshera Virkan'],
    'Sialkot': <String>['Sialkot City', 'Daska', 'Sambrial', 'Pasrur'],
    'Karachi East': <String>['Gulshan', 'Jamshed', 'Ferozabad'],
    'Karachi South': <String>['Saddar', 'Civil Lines', 'Lyari'],
    'Karachi Central': <String>['Nazimabad', 'Liaquatabad', 'North Nazimabad'],
    'Hyderabad': <String>['Hyderabad City', 'Latifabad', 'Qasimabad'],
    'Peshawar': <String>['Peshawar City', 'Badaber', 'Chamkani'],
    'Mardan': <String>['Mardan City', 'Takht Bhai', 'Katlang'],
    'Quetta': <String>['Quetta City', 'Sariab', 'Chiltan'],
    'Islamabad': <String>['Islamabad City', 'Rural Islamabad'],
  };

  static const Map<String, List<String>> _citiesByDistrictTehsil =
      <String, List<String>>{
        'Lahore|Ravi': <String>['Shahdara', 'Data Ganj Bakhsh'],
        'Lahore|Shalimar': <String>['Mughalpura', 'Harbanspura'],
        'Lahore|Model Town': <String>['Model Town', 'Kot Lakhpat'],
        'Lahore|Cantt': <String>['DHA', 'Lahore Cantt'],
        'Rawalpindi|Rawalpindi City': <String>['Raja Bazar', 'Sadiqabad'],
        'Rawalpindi|Taxila': <String>['Taxila', 'Wah Cantt'],
        'Faisalabad|Faisalabad City': <String>['Madina Town', 'Lyallpur Town'],
        'Faisalabad|Jaranwala': <String>['Jaranwala'],
        'Multan|Multan City': <String>['Shah Rukn-e-Alam', 'Cantt Multan'],
        'Gujranwala|Gujranwala City': <String>['Satellite Town', 'Model Town'],
        'Sialkot|Sialkot City': <String>['Sialkot Cantt', 'Allama Iqbal Chowk'],
        'Karachi East|Gulshan': <String>['Gulshan-e-Iqbal', 'Johar'],
        'Karachi South|Saddar': <String>['Saddar', 'Clifton'],
        'Hyderabad|Hyderabad City': <String>['Hirabad', 'Market Tower'],
        'Peshawar|Peshawar City': <String>['University Town', 'Hayatabad'],
        'Mardan|Mardan City': <String>['Par Hoti', 'Bagh-e-Irum'],
        'Quetta|Quetta City': <String>['Jinnah Town', 'Satellite Town Quetta'],
        'Islamabad|Islamabad City': <String>['F-10', 'G-11', 'I-8'],
      };
}

class SeasonalMarketRules {
  // Approximate Qurbani shopping window to keep behavior deterministic
  // without introducing a Hijri calendar dependency.
  static bool get isQurbaniSeason {
    final now = DateTime.now();
    final start = DateTime(now.year, 5, 15);
    final end = DateTime(now.year, 8, 31, 23, 59, 59);
    return !now.isBefore(start) && !now.isAfter(end);
  }

  static bool isQurbaniEligibleProduct(String product) {
    final key = product.trim().toLowerCase();
    if (key.isEmpty) return false;
    return key.contains('goat') ||
        key.contains('bakra') ||
        key.contains('bakri') ||
        key.contains('sheep') ||
        key.contains('bhair') ||
        key.contains('cow') ||
        key.contains('gaye') ||
        key.contains('buffalo') ||
        key.contains('bhains') ||
        key.contains('camel') ||
        key.contains('oont') ||
        key.contains('bull');
  }
}
