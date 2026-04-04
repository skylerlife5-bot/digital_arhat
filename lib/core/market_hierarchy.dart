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
      id: 'vegetables',
      mandiType: MandiType.vegetables,
      labelEn: 'Vegetables',
      labelUr: 'سبزیاں',
    ),
    MarketCategoryOption(
      id: 'fruit',
      mandiType: MandiType.fruit,
      labelEn: 'Fruits',
      labelUr: 'پھل',
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
    MarketCategoryOption(
      id: 'tools',
      mandiType: MandiType.tools,
      labelEn: 'Tools',
      labelUr: 'اوزار',
    ),
  ];

  static const List<MarketCategoryOption> listingCategories =
      <MarketCategoryOption>[
        MarketCategoryOption(
          id: 'crops',
          mandiType: MandiType.crops,
          labelEn: 'Crops',
          labelUr: 'فصلیں',
        ),
        MarketCategoryOption(
          id: 'vegetables',
          mandiType: MandiType.vegetables,
          labelEn: 'Vegetables',
          labelUr: 'سبزیاں',
        ),
        MarketCategoryOption(
          id: 'fruit',
          mandiType: MandiType.fruit,
          labelEn: 'Fruits',
          labelUr: 'پھل',
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
          id: 'poultry',
          mandiType: MandiType.livestock,
          labelEn: 'Poultry',
          labelUr: 'پولٹری',
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

  static String listingCategoryLabelForId(String categoryId) {
    for (final option in listingCategories) {
      if (option.id == categoryId) {
        return option.bilingualLabel;
      }
    }
    return listingCategories.first.bilingualLabel;
  }

  static MarketCategoryOption? listingCategoryFromLabel(String selected) {
    for (final option in listingCategories) {
      if (option.bilingualLabel == selected) {
        return option;
      }
    }
    return null;
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

  static List<MarketSubcategoryOption> subcategoriesForCategoryId(
    String categoryId,
  ) {
    final items = CategoryConstants.itemsForCategoryId(categoryId);
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

  static String urduLabelForLocation(String locationEn) {
    final key = locationEn.trim();
    if (key.isEmpty) return '';
    return _urduLocationByEnglish[key] ?? '';
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
    'Kasur': <String>['Kasur', 'Pattoki', 'Chunian', 'Kot Radha Kishan'],
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
        'Kasur|Pattoki': <String>['Pattoki', 'Phool Nagar', 'Habibabad'],
        'Kasur|Kasur': <String>['Kasur City', 'Khudian Khas'],
        'Kasur|Chunian': <String>['Chunian', 'Halla', 'Allahabad'],
        'Kasur|Kot Radha Kishan': <String>[
          'Kot Radha Kishan',
          'Mustafabad',
        ],
      };

  static const Map<String, String> _urduLocationByEnglish =
      <String, String>{
        // ── Provinces ────────────────────────────────────────────────────────
        'Punjab': 'پنجاب',
        'Sindh': 'سندھ',
        'Balochistan': 'بلوچستان',
        'Khyber Pakhtunkhwa': 'خیبر پختونخوا',
        'Islamabad': 'اسلام آباد',
        'Gilgit Baltistan': 'گلگت بلتستان',
        'Azad Kashmir': 'آزاد کشمیر',

        // ── Punjab Districts ─────────────────────────────────────────────────
        'Attock': 'اٹک',
        'Bahawalnagar': 'بہاولنگر',
        'Bahawalpur': 'بہاولپور',
        'Bhakkar': 'بھکر',
        'Chakwal': 'چکوال',
        'Chiniot': 'چنیوٹ',
        'Dera Ghazi Khan': 'ڈیرہ غازی خان',
        'Faisalabad': 'فیصل آباد',
        'Gujranwala': 'گوجرانوالہ',
        'Gujrat': 'گجرات',
        'Hafizabad': 'حافظ آباد',
        'Jhang': 'جھنگ',
        'Jhelum': 'جہلم',
        'Kasur': 'قصور',
        'Khanewal': 'خانیوال',
        'Khushab': 'خوشاب',
        'Lahore': 'لاہور',
        'Leiah': 'لیہ',
        'Lodhran': 'لودھراں',
        'Mandi Bahauddin': 'منڈی بہاؤالدین',
        'Mianwali': 'میانوالی',
        'Multan': 'ملتان',
        'Muzaffargarh': 'مظفرگڑھ',
        'Nankana Sahib': 'ننکانہ صاحب',
        'Narowal': 'نارووال',
        'Okara': 'اوکاڑہ',
        'Pakpattan': 'پاکپتن',
        'Rahim Yar Khan': 'رحیم یار خان',
        'Rajanpur': 'راجن پور',
        'Rawalpindi': 'راولپنڈی',
        'Sahiwal': 'ساہیوال',
        'Sargodha': 'سرگودھا',
        'Sheikhupura': 'شیخوپورہ',
        'Sialkot': 'سیالکوٹ',
        'Toba Tek Singh': 'ٹوبہ ٹیک سنگھ',
        'Vehari': 'وہاڑی',

        // ── Punjab Tehsils ────────────────────────────────────────────────────
        'Attock City': 'اٹک شہر',
        'Hazro': 'حضرو',
        'Pindi Gheb': 'پنڈی گھیب',
        'Fateh Jang': 'فتح جنگ',
        'Bahawalnagar City': 'بہاولنگر شہر',
        'Chishtian': 'چشتیاں',
        'Hasilpur': 'حاصلپور',
        'Minchinabad': 'منچن آباد',
        'Bahawalpur City': 'بہاولپور شہر',
        'Ahmadpur East': 'احمد پور مشرقی',
        'Yazman': 'یزمان',
        'Bhakkar City': 'بھکر شہر',
        'Kallur Kot': 'کالور کوٹ',
        'Mankera': 'منکیرہ',
        'Chakwal City': 'چکوال شہر',
        'Talagang': 'تلہ گنگ',
        'Chiniot City': 'چنیوٹ شہر',
        'Bhawana': 'بھوانہ',
        'DG Khan': 'ڈی جی خان',
        'Taunsa': 'ٹونسہ',
        'Faisalabad City': 'فیصل آباد شہر',
        'Jaranwala': 'جڑانوالہ',
        'Samundri': 'سمندری',
        'Tandlianwala': 'ٹانڈلیانوالہ',
        'Gujranwala City': 'گوجرانوالہ شہر',
        'Kamoke': 'کاموکے',
        'Nowshera Virkan': 'نوشہرہ ورکاں',
        'Gujrat City': 'گجرات شہر',
        'Kharian': 'کھاریاں',
        'Hafizabad City': 'حافظ آباد شہر',
        'Pindi Bhattian': 'پنڈی بھٹیاں',
        'Jhang City': 'جھنگ شہر',
        'Shorkot': 'شورکوٹ',
        'Ahmadpur Sial': 'احمد پور سیال',
        'Jhelum City': 'جہلم شہر',
        'Sohawa': 'سوہاوہ',
        'Pattoki': 'پتوکی',
        'Chunian': 'چونیاں',
        'Kot Radha Kishan': 'کوٹ رادھا کشن',
        'Khanewal City': 'خانیوال شہر',
        'Mian Channu': 'میاں چنوں',
        'Kabirwala': 'کبیروالہ',
        'Khushab City': 'خوشاب شہر',
        'Noorpur Thal': 'نورپور تھل',
        'Quaidabad': 'قائد آباد',
        'Ravi': 'راوی',
        'Shalimar': 'شالیمار',
        'Model Town': 'ماڈل ٹاؤن',
        'Cantt': 'چھاؤنی',
        'Leiah City': 'لیہ شہر',
        'Karor Lal Esan': 'کروڑ لعل عیسن',
        'Lodhran City': 'لودھراں شہر',
        'Kehror Pakka': 'کہرور پکا',
        'Mandi Bahauddin City': 'منڈی بہاؤالدین شہر',
        'Phalia': 'پھالیہ',
        'Mianwali City': 'میانوالی شہر',
        'Piplan': 'پی پلاں',
        'Esa Khel': 'عیسی خیل',
        'Multan City': 'ملتان شہر',
        'Shujabad': 'شجاع آباد',
        'Jalalpur Pirwala': 'جلال پور پیروالہ',
        'Muzaffargarh City': 'مظفرگڑھ شہر',
        'Kot Addu': 'کوٹ ادو',
        'Ali Pur': 'علی پور',
        'Nankana Sahib City': 'ننکانہ صاحب شہر',
        'Sangla Hill': 'سانگلہ ہل',
        'Narowal City': 'نارووال شہر',
        'Shakargarh': 'شکرگڑھ',
        'Okara City': 'اوکاڑہ شہر',
        'Depalpur': 'دیپالپور',
        'Renala Khurd': 'رینالہ خورد',
        'Pakpattan City': 'پاکپتن شہر',
        'Arifwala': 'عارف والا',
        'Rahim Yar Khan City': 'رحیم یار خان شہر',
        'Liaquatpur': 'لیاقت پور',
        'Sadiqabad': 'صادق آباد',
        'Rajanpur City': 'راجن پور شہر',
        'Jampur': 'جام پور',
        'Rawalpindi City': 'راولپنڈی شہر',
        'Kahuta': 'کہوٹہ',
        'Taxila': 'ٹیکسلا',
        'Gujar Khan': 'گجر خان',
        'Sahiwal City': 'ساہیوال شہر',
        'Chichawatni': 'چیچہ وطنی',
        'Sargodha City': 'سرگودھا شہر',
        'Bhalwal': 'بھلوال',
        'Sillanwali': 'سلانوالی',
        'Sheikhupura City': 'شیخوپورہ شہر',
        'Safdarabad': 'صفدرآباد',
        'Ferozewala': 'فیروزوالہ',
        'Sialkot City': 'سیالکوٹ شہر',
        'Daska': 'ڈسکہ',
        'Sambrial': 'سمبڑیال',
        'Pasrur': 'پسرور',
        'Toba Tek Singh City': 'ٹوبہ ٹیک سنگھ شہر',
        'Gojra': 'گوجرہ',
        'Kamalia': 'کمالیہ',
        'Vehari City': 'وہاڑی شہر',
        'Burewala': 'بوریوالہ',
        'Mailsi': 'میلسی',

        // ── Punjab Cities ─────────────────────────────────────────────────────
        'Phool Nagar': 'پھول نگر',
        'Habibabad': 'حبیب آباد',
        'Kasur City': 'قصور شہر',
        'Khudian Khas': 'کھڈیاں خاص',
        'Halla': 'ہلہ',
        'Allahabad': 'الہ آباد',
        'Mustafabad': 'مصطفی آباد',
        'Shahdara': 'شاہدرہ',
        'Data Ganj Bakhsh': 'داتا گنج بخش',
        'Mughalpura': 'مغل پورہ',
        'Harbanspura': 'ہربنس پورہ',
        'Kot Lakhpat': 'کوٹ لکھپت',
        'DHA': 'ڈی ایچ اے',
        'Lahore Cantt': 'لاہور چھاؤنی',
        'Raja Bazar': 'راجہ بازار',
        'Wah Cantt': 'واہ چھاؤنی',
        'Madina Town': 'مدینہ ٹاؤن',
        'Lyallpur Town': 'لائلپور ٹاؤن',
        'Jaranwala City': 'جڑانوالہ شہر',
        'Shah Rukn-e-Alam': 'شاہ رکنِ عالم',
        'Cantt Multan': 'ملتان چھاؤنی',
        'Satellite Town': 'سیٹلائٹ ٹاؤن',
        'Sialkot Cantt': 'سیالکوٹ چھاؤنی',
        'Allama Iqbal Chowk': 'علامہ اقبال چوک',

        // ── Sindh Provinces / Districts ──────────────────────────────────────
        'Karachi': 'کراچی',
        'Karachi East': 'کراچی مشرق',
        'Karachi South': 'کراچی جنوب',
        'Karachi Central': 'کراچی وسط',
        'Karachi West': 'کراچی مغرب',
        'Karachi Malir': 'کراچی ملیر',
        'Hyderabad': 'حیدرآباد',
        'Sukkur': 'سکھر',
        'Larkana': 'لاڑکانہ',
        'Nawabshah': 'نوابشاہ',
        'Shaheed Benazirabad': 'شہید بینظیر آباد',
        'Mirpur Khas': 'میرپور خاص',
        'Sanghar': 'سانگھڑ',
        'Tando Allahyar': 'ٹنڈو اللہ یار',
        'Tando Muhammad Khan': 'ٹنڈو محمد خان',
        'Badin': 'بدین',
        'Thatta': 'ٹھٹھہ',
        'Jamshoro': 'جامشورو',
        'Dadu': 'دادو',
        'Naushahro Feroze': 'نوشہروفیروز',
        'Khairpur': 'خیرپور',
        'Shikarpur': 'شکارپور',
        'Jacobabad': 'جیکب آباد',
        'Kashmore': 'کشمور',
        'Kamber Shahdadkot': 'کامبر شہداد کوٹ',
        'Matiari': 'ماٹیاری',
        'Umerkot': 'عمر کوٹ',
        'Ghotki': 'گھوٹکی',
        'Qambar Shahdadkot': 'قمبر شہداد کوٹ',
        'Sujawal': 'سجاول',

        // ── Sindh Tehsils / Cities ────────────────────────────────────────────
        'Saddar': 'صدر',
        'Civil Lines': 'سول لائنز',
        'Lyari': 'لیاری',
        'Gulshan': 'گلشن',
        'Jamshed': 'جمشید',
        'Ferozabad': 'فیروز آباد',
        'Nazimabad': 'نظیم آباد',
        'Liaquatabad': 'لیاقت آباد',
        'North Nazimabad': 'شمالی نظیم آباد',
        'Clifton': 'کلفٹن',
        'Gulshan-e-Iqbal': 'گلشنِ اقبال',
        'Johar': 'جوہر',
        'Hirabad': 'ہیرآباد',
        'Market Tower': 'مارکیٹ ٹاور',
        'Latifabad': 'لطیف آباد',
        'Qasimabad': 'قاسم آباد',
        'Hyderabad City': 'حیدرآباد شہر',

        // ── Khyber Pakhtunkhwa Districts ──────────────────────────────────────
        'Peshawar': 'پشاور',
        'Mardan': 'مردان',
        'Swat': 'سوات',
        'Dir Lower': 'ضلع دیر زیریں',
        'Dir Upper': 'ضلع دیر بالائی',
        'Charsadda': 'چارسدہ',
        'Nowshera': 'نوشہرہ',
        'Kohat': 'کوہاٹ',
        'Buner': 'بونیر',
        'Mansehra': 'مانسہرہ',
        'Abbottabad': 'ایبٹ آباد',
        'Haripur': 'ہری پور',
        'Swabi': 'صوابی',
        'Bannu': 'بنوں',
        'Dera Ismail Khan': 'ڈیرہ اسماعیل خان',
        'Tank': 'ٹانک',
        'Lakki Marwat': 'لکی مروت',
        'Karak': 'کرک',
        'Hangu': 'ہنگو',
        'Shangla': 'شانگلہ',
        'Battagram': 'بٹگرام',
        'Kohistan': 'کوہستان',
        'Tor Ghar': 'تورغر',
        'Malakand': 'مالاکنڈ',
        'Chitral': 'چترال',
        'Chitral Upper': 'بالائی چترال',
        'Chitral Lower': 'زیریں چترال',
        'Kurram': 'کرم',
        'Orakzai': 'اورکزئی',
        'Mohmand': 'مہمند',
        'Bajaur': 'باجوڑ',
        'South Waziristan': 'جنوبی وزیرستان',
        'North Waziristan': 'شمالی وزیرستان',
        'Khyber': 'خیبر',

        // ── KPK Tehsils / Cities ──────────────────────────────────────────────
        'Peshawar City': 'پشاور شہر',
        'Badaber': 'بداب',
        'Chamkani': 'چمکنی',
        'University Town': 'یونیورسٹی ٹاؤن',
        'Hayatabad': 'حیات آباد',
        'Mardan City': 'مردان شہر',
        'Takht Bhai': 'تخت بھائی',
        'Katlang': 'کٹلانگ',
        'Par Hoti': 'پار ہوتی',
        'Bagh-e-Irum': 'باغِ ارم',

        // ── Balochistan Districts ──────────────────────────────────────────────
        'Quetta': 'کوئٹہ',
        'Zhob': 'ژوب',
        'Turbat': 'تربت',
        'Khuzdar': 'خضدار',
        'Sibi': 'سبی',
        'Mastung': 'ماسٹنگ',
        'Chaman': 'چمن',
        'Hub': 'حب',
        'Nushki': 'نوشکی',
        'Panjgur': 'پنجگور',
        'Gwadar': 'گوادر',
        'Makran': 'مکران',
        'Awaran': 'آواران',
        'Kech': 'کیچ',
        'Kalat': 'قلات',
        'Kharan': 'خاران',
        'Bolan': 'بولان',
        'Jhal Magsi': 'جھل مگسی',
        'Lasbela': 'لسبیلہ',
        'Loralai': 'لورالائی',
        'Musakhel': 'موسیٰ خیل',
        'Pishin': 'پشین',
        'Qila Abdullah': 'قلعہ عبداللہ',
        'Qila Saifullah': 'قلعہ سیف اللہ',
        'Sherani': 'شیرانی',
        'Washuk': 'واشک',
        'Ziarat': 'زیارت',
        'Harnai': 'ہرنائی',
        'Kohlu': 'کوہلو',
        'Dera Bugti': 'ڈیرہ بگٹی',
        'Nasirabad': 'نصیرآباد',

        // ── Balochistan Cities ────────────────────────────────────────────────
        'Quetta City': 'کوئٹہ شہر',
        'Sariab': 'ساریاب',
        'Chiltan': 'چلتن',
        'Jinnah Town': 'جناح ٹاؤن',
        'Satellite Town Quetta': 'سیٹلائٹ ٹاؤن کوئٹہ',

        // ── Islamabad ────────────────────────────────────────────────────────
        'Islamabad City': 'اسلام آباد شہر',
        'Rural Islamabad': 'دیہی اسلام آباد',
        'F-10': 'ایف دس',
        'G-11': 'جی گیارہ',
        'I-8': 'آئی آٹھ',

        // ── Gilgit Baltistan ──────────────────────────────────────────────────
        'Gilgit': 'گلگت',
        'Baltistan': 'بلتستان',
        'Skardu': 'سکردو',
        'Hunza': 'ہنزہ',
        'Nagar': 'نگر',
        'Ghizer': 'غذر',
        'Astore': 'اسٹور',
        'Diamer': 'دیامر',
        'Ghanche': 'غانچھے',
        'Shigar': 'شگر',
        'Kharmang': 'خرمنگ',
        'Roundu': 'راؤنڈو',

        // ── Azad Kashmir ──────────────────────────────────────────────────────
        'Bagh': 'باغ',
        'Bhimber': 'بھمبر',
        'Jhelum Valley': 'جہلم ویلی',
        'Haveli': 'ہویلی',
        'Kotli': 'کوٹلی',
        'Mirpur': 'میرپور',
        'Muzaffarabad': 'مظفرآباد',
        'Neelum': 'نیلم',
        'Poonch': 'پونچھ',
        'Sudhnati': 'سدھنوتی',
        'Hattian': 'ہٹیاں',
        'Leepa': 'لیپا',
        'Dhir Kot': 'ڈھیرکوٹ',
        'Harighel': 'ہاریگھیل',
        'Barnala': 'برنالہ',
        'Samahni': 'سماہنی',
        'Chikar': 'چیکار',
        'Khurshid Abad': 'خورشید آباد',
        'Mumtazabad': 'ممتاز آباد',
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
