enum MandiType {
  crops,
  fruit,
  vegetables,
  flowers,
  livestock,
  milk,
  seeds,
  fertilizer,
  machinery,
  tools,
  dryFruits,
  spices,
}

extension MandiTypeX on MandiType {
  String get wireValue {
    switch (this) {
      case MandiType.crops:
        return 'CROPS';
      case MandiType.fruit:
        return 'FRUIT';
      case MandiType.vegetables:
        return 'VEGETABLES';
      case MandiType.flowers:
        return 'FLOWERS';
      case MandiType.livestock:
        return 'LIVESTOCK';
      case MandiType.milk:
        return 'MILK_DAIRY';
      case MandiType.seeds:
        return 'SEEDS';
      case MandiType.fertilizer:
        return 'FERTILIZER';
      case MandiType.machinery:
        return 'MACHINERY';
      case MandiType.tools:
        return 'TOOLS';
      case MandiType.dryFruits:
        return 'DRY_FRUITS';
      case MandiType.spices:
        return 'SPICES';
    }
  }

  String get label {
    switch (this) {
      case MandiType.crops:
        return 'Crops / فصلیں';
      case MandiType.fruit:
        return 'Fruits / پھل';
      case MandiType.vegetables:
        return 'Vegetables / سبزیاں';
      case MandiType.flowers:
        return 'Flowers / پھول';
      case MandiType.livestock:
        return 'Livestock / مویشی';
      case MandiType.milk:
        return 'Milk & Dairy / دودھ و ڈیری';
      case MandiType.seeds:
        return 'Seeds / بیج';
      case MandiType.fertilizer:
        return 'Fertilizer / کھاد';
      case MandiType.machinery:
        return 'Machinery / مشینری';
      case MandiType.tools:
        return 'Tools / اوزار';
      case MandiType.dryFruits:
        return 'Dry Fruits / خشک میوہ جات';
      case MandiType.spices:
        return 'Spices / مصالحہ جات';
    }
  }

  String get urduLabel {
    switch (this) {
      case MandiType.crops:
        return 'فصلیں';
      case MandiType.fruit:
        return 'پھل';
      case MandiType.vegetables:
        return 'سبزیاں';
      case MandiType.flowers:
        return 'پھول';
      case MandiType.livestock:
        return 'مویشی';
      case MandiType.milk:
        return 'دودھ و ڈیری';
      case MandiType.seeds:
        return 'بیج';
      case MandiType.fertilizer:
        return 'کھاد';
      case MandiType.machinery:
        return 'مشینری';
      case MandiType.tools:
        return 'اوزار';
      case MandiType.dryFruits:
        return 'خشک میوہ جات';
      case MandiType.spices:
        return 'مصالحہ جات';
    }
  }
}

enum ListingGrade { a, b, c }

extension ListingGradeX on ListingGrade {
  String get wireValue {
    switch (this) {
      case ListingGrade.a:
        return 'A';
      case ListingGrade.b:
        return 'B';
      case ListingGrade.c:
        return 'C';
    }
  }

  String get urduLabel {
    switch (this) {
      case ListingGrade.a:
        return 'درجہ الف';
      case ListingGrade.b:
        return 'درجہ ب';
      case ListingGrade.c:
        return 'درجہ ج';
    }
  }
}

enum UnitType { peti, mann, litre, kg, perHead }

extension UnitTypeX on UnitType {
  String get wireValue {
    switch (this) {
      case UnitType.peti:
        return 'Peti';
      case UnitType.mann:
        return 'Mann';
      case UnitType.litre:
        return 'Litre';
      case UnitType.kg:
        return 'KG';
      case UnitType.perHead:
        return 'Per Head';
    }
  }

  String get urduLabel {
    switch (this) {
      case UnitType.peti:
        return 'پیٹی';
      case UnitType.mann:
        return 'من';
      case UnitType.litre:
        return 'لیٹر';
      case UnitType.kg:
        return 'کلو';
      case UnitType.perHead:
        return 'فی جانور';
    }
  }
}

class CategoryConstants {
  static const List<String> crops = [
    'Wheat / گندم',
    'Rice Crop (Paddy) / دھان',
    'Processed Rice / چاول',
    'Cotton / کپاس',
    'Sugarcane / گنا',
    'Maize / مکئی',
    'Gram / چنا',
    'Mustard / سرسوں',
    'Barley / جو',
    'Millet / باجرا',
    'Sorghum / جوار',
    'Lentils / دالیں',
    'Sunflower / سورج مکھی',
    'Canola / کینولا',
  ];

  static const List<String> riceCropVarieties = [
    'Basmati Paddy / باسمتی دھان',
    'IRRI Paddy / اری دھان',
    'Hybrid Paddy / ہائبرڈ دھان',
    'Kainat Paddy / کائنات دھان',
  ];

  static const List<String> processedRiceVarieties = [
    'Basmati Rice / باسمتی چاول',
    'Super Basmati / سپر باسمتی',
    'IRRI Rice / اری چاول',
    'Sella Rice / سیلہ چاول',
    'Broken Rice / ٹوٹا چاول',
    'Brown Rice / براؤن چاول',
    'Export Rice / ایکسپورٹ چاول',
  ];

  static const List<String> fruits = [
    'Mango / آم',
    'Kinnow / کینو',
    'Orange / مالٹا',
    'Apple / سیب',
    'Banana / کیلا',
    'Guava / امرود',
    'Dates / کھجور',
    'Pomegranate / انار',
    'Peach / آڑو',
    'Apricot / خوبانی',
    'Plum / آلو بخارا',
    'Grapes / انگور',
    'Melon / خربوزہ',
    'Watermelon / تربوز',
  ];

  static const List<String> vegetables = [
    'Potato / آلو',
    'Onion / پیاز',
    'Tomato / ٹماٹر',
    'Chili / مرچ',
    'Garlic / لہسن',
    'Ginger / ادرک',
    'Okra / بھنڈی',
    'Brinjal / بینگن',
    'Cabbage / بند گوبھی',
    'Cauliflower / پھول گوبھی',
    'Spinach / پالک',
    'Peas / مٹر',
    'Carrot / گاجر',
    'Radish / مولی',
    'Turnip / شلجم',
    'Capsicum / شملہ مرچ',
  ];

  static const List<String> flowers = [
    'Rose / گلاب',
    'Jasmine / چنبیلی',
    'Marigold / گیندا',
    'Tuberose / راجنی گندھا',
    'Gladiolus / گلائیڈیولس',
    'Chrysanthemum / گلِ داؤدی',
    'Lotus / کنول',
    'Seasonal Flowers / موسمی پھول',
    'Loose Flowers / کھلے پھول',
    'Garland Flowers / ہار کے پھول',
    'Wedding Flowers / شادی کے پھول',
  ];

  static const List<String> livestock = [
    'Cow / گائے',
    'Buffalo / بھینس',
    'Bull / بیل',
    'Goat / بکری',
    'Sheep / بھیڑ',
    'Camel / اونٹ',
    'Calf / بچھڑا',
    'Poultry / مرغی',
    'Eggs / انڈے',
  ];

  static const List<String> milkAndDairy = [
    'Raw Milk / کچا دودھ',
    'Buffalo Milk / بھینس کا دودھ',
    'Cow Milk / گائے کا دودھ',
    'Yogurt / دہی',
    'Butter / مکھن',
    'Desi Ghee / دیسی گھی',
    'Cream / بالائی',
  ];

  static const List<String> seeds = [
    'Wheat Seed / گندم بیج',
    'Rice Seed / دھان بیج',
    'Cotton Seed / کپاس بیج',
    'Maize Seed / مکئی بیج',
    'Vegetable Seeds / سبزی بیج',
    'Fodder Seeds / چارہ بیج',
    'Hybrid Seeds / ہائبرڈ بیج',
  ];

  static const List<String> fertilizer = [
    'Urea / یوریا',
    'DAP / ڈی اے پی',
    'NP / این پی',
    'NPK / این پی کے',
    'SOP / پوٹاش',
    'SSP / ایس ایس پی',
    'Organic Fertilizer / نامیاتی کھاد',
    'Compost / کمپوسٹ',
  ];

  static const List<String> machinery = [
    'Tractor / ٹریکٹر',
    'Harvester / ہارویسٹر',
    'Seeder / سیڈر',
    'Sprayer / سپرے مشین',
    'Rotavator / روٹاویٹر',
    'Plough / ہل',
    'Thresher / تھریشر',
  ];

  static const List<String> tools = [
    'Shovel / بیلچہ',
    'Spade / پھاؤڑا',
    'Hoe / کدال',
    'Sickle / درانتی',
    'Hand Sprayer / ہینڈ سپرے',
    'Water Pump / واٹر پمپ',
  ];

  static const List<String> dryFruits = [
    'Almond / بادام',
    'Walnut / اخروٹ',
    'Pistachio / پستہ',
    'Raisins / کشمش',
    'Cashew / کاجو',
    'Dry Dates / خشک کھجور',
  ];

  static const List<String> spices = [
    'Red Chili / لال مرچ',
    'Turmeric / ہلدی',
    'Coriander / دھنیا',
    'Cumin / زیرہ',
    'Black Pepper / کالی مرچ',
    'Cloves / لونگ',
    'Cardamom / الائچی',
  ];

  static List<String> riceVarietiesForProduct(String productLabel) {
    final value = productLabel.toLowerCase();
    if (value.contains('rice crop (paddy)') || value.contains('دھان')) {
      return riceCropVarieties;
    }
    if (value.contains('processed rice') || value.contains('چاول')) {
      return processedRiceVarieties;
    }
    return const <String>[];
  }

  static List<String> itemsForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return crops;
      case MandiType.fruit:
        return fruits;
      case MandiType.vegetables:
        return vegetables;
      case MandiType.flowers:
        return flowers;
      case MandiType.livestock:
        return livestock;
      case MandiType.milk:
        return milkAndDairy;
      case MandiType.seeds:
        return seeds;
      case MandiType.fertilizer:
        return fertilizer;
      case MandiType.machinery:
        return machinery;
      case MandiType.tools:
        return tools;
      case MandiType.dryFruits:
        return dryFruits;
      case MandiType.spices:
        return spices;
    }
  }

  static UnitType defaultUnitForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return UnitType.mann;
      case MandiType.fruit:
      case MandiType.vegetables:
      case MandiType.flowers:
        return UnitType.kg;
      case MandiType.milk:
        return UnitType.litre;
      case MandiType.livestock:
        return UnitType.perHead;
      case MandiType.seeds:
      case MandiType.fertilizer:
      case MandiType.spices:
      case MandiType.dryFruits:
        return UnitType.kg;
      case MandiType.machinery:
      case MandiType.tools:
        return UnitType.peti;
    }
  }

  static List<UnitType> allowedUnitsForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return const [UnitType.mann, UnitType.kg];
      case MandiType.fruit:
      case MandiType.vegetables:
      case MandiType.flowers:
      case MandiType.seeds:
      case MandiType.fertilizer:
      case MandiType.spices:
      case MandiType.dryFruits:
        return const [UnitType.kg];
      case MandiType.milk:
        return const [UnitType.litre, UnitType.kg, UnitType.perHead];
      case MandiType.livestock:
        return const [UnitType.perHead];
      case MandiType.machinery:
      case MandiType.tools:
        return const [UnitType.peti, UnitType.kg];
    }
  }

  static const List<String> defaultPredictionItems = [
    'Wheat (Gandum)',
    'Rice - Basmati',
    'Cotton (Phutti)',
    'Maize (Makai)',
    'Gram (Chana)',
  ];

  static const Map<String, double> lastKnownGovRates = {
    'wheat': 4350.0,
    'gandum': 4350.0,
    'rice': 7100.0,
    'chawal': 7100.0,
    'cotton': 8200.0,
    'phutti': 8200.0,
    'kapaas': 8200.0,
    'maize': 2950.0,
    'makai': 2950.0,
    'sugarcane': 420.0,
    'kamad': 420.0,
    'ganna': 420.0,
    'gram': 9500.0,
    'chana': 9500.0,
    'potato': 3200.0,
    'aloo': 3200.0,
    'tomato': 5100.0,
    'tamatar': 5100.0,
    'onion': 3600.0,
    'piaz': 3600.0,
    'milk': 210.0,
    'buffalo': 215.0,
    'cow': 190.0,
  };

  static double? lastKnownGovernmentRate(String itemName) {
    final normalized = itemName.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    for (final entry in lastKnownGovRates.entries) {
      if (normalized.contains(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
}

class AppConstants {
  // �x� AI Proxy Configuration (API keys must stay on backend only)
  static const String aiProxyEndpoint = String.fromEnvironment(
    'AI_PROXY_ENDPOINT',
    defaultValue: '',
  );
  static const String aiProviderHint = String.fromEnvironment(
    'AI_PROVIDER_HINT',
    defaultValue: 'gemini_primary',
  );
  static const String geminiFallbackMessage =
      'Mandi intelligence service is currently unavailable.';

  // Advanced AI Handling (For high traffic)
  static const int geminiRetryAttempts = 3;
  static const int geminiBaseBackoffMs = 800;
  static const int geminiCooldownSeconds = 60;
  static const int geminiFailuresBeforeCooldown = 2;

  // �x� Pakistan Administrative Map (Province -> Major Agricultural Districts)
  static const Map<String, List<String>> pakistanLocations = {
    'Punjab': [
      'Attock',
      'Bahawalnagar',
      'Bahawalpur',
      'Bhakkar',
      'Chakwal',
      'Chiniot',
      'Dera Ghazi Khan',
      'Faisalabad',
      'Gujranwala',
      'Gujrat',
      'Hafizabad',
      'Jhang',
      'Jhelum',
      'Kasur',
      'Khanewal',
      'Khushab',
      'Lahore',
      'Layyah',
      'Lodhran',
      'Mandi Bahauddin',
      'Mianwali',
      'Multan',
      'Muzaffargarh',
      'Narowal',
      'Nankana Sahib',
      'Okara',
      'Pakpattan',
      'Rahim Yar Khan',
      'Rajanpur',
      'Rawalpindi',
      'Sahiwal',
      'Sargodha',
      'Sheikhupura',
      'Sialkot',
      'Toba Tek Singh',
      'Vehari',
    ],
    'Sindh': [
      'Badin',
      'Dadu',
      'Ghotki',
      'Hyderabad',
      'Jacobabad',
      'Jamshoro',
      'Khairpur',
      'Larkana',
      'Mirpurkhas',
      'Naushehro Feroze',
      'Sanghar',
      'Shaheed Benazirabad',
      'Shikarpur',
      'Sujawal',
      'Tando Allahyar',
      'Tando Muhammad Khan',
      'Tharparkar',
      'Thatta',
      'Umerkot',
    ],
    'Khyber Pakhtunkhwa (KPK)': [
      'Abbottabad',
      'Bannu',
      'Charsadda',
      'Dera Ismail Khan',
      'Haripur',
      'Karak',
      'Kohat',
      'Lakki Marwat',
      'Lower Dir',
      'Malakand',
      'Mardan',
      'Nowshera',
      'Peshawar',
      'Shangla',
      'Swabi',
      'Swat',
      'Tank',
      'Upper Dir',
    ],
    'Balochistan': [
      'Barkhan',
      'Gwadar',
      'Jaffarabad',
      'Jhal Magsi',
      'Kachhi',
      'Kalat',
      'Kech',
      'Kharan',
      'Khuzdar',
      'Lasbela',
      'Mastung',
      'Nasirabad',
      'Panjgur',
      'Pishin',
      'Quetta',
      'Sibi',
      'Zhob',
    ],
    'Gilgit-Baltistan': [
      'Astore',
      'Diamer',
      'Ghanche',
      'Ghizer',
      'Gilgit',
      'Hunza',
      'Kharmang',
      'Nagar',
      'Shigar',
      'Skardu',
    ],
    'Azad Jammu & Kashmir (AJK)': [
      'Bagh',
      'Bhimber',
      'Hattian Bala',
      'Haveli',
      'Kotli',
      'Mirpur',
      'Muzaffarabad',
      'Neelum',
      'Poonch',
      'Sudhnoti',
    ],
  };

  static final List<String> punjabDistricts = List<String>.unmodifiable(
    pakistanLocations['Punjab'] ?? const <String>[],
  );

  static List<String> get provinces =>
      pakistanLocations.keys.toList(growable: false);

  static List<String> districtsForProvince(String? province) {
    if (province == null || province.trim().isEmpty) {
      return const <String>[];
    }
    return pakistanLocations[province] ?? const <String>[];
  }

  // �xaa Approx district distance pairs (KM) for fallback logistics context
  static const Map<String, double> districtDistancePairsKm = {
    'kasur|lahore': 55.0,
    'kasur|okara': 92.0,
    'faisalabad|lahore': 132.0,
    'lahore|sahiwal': 180.0,
    'lahore|multan': 340.0,
    'lahore|rawalpindi': 375.0,
    'faisalabad|multan': 250.0,
    'faisalabad|sargodha': 95.0,
    'gujranwala|lahore': 75.0,
    'lahore|sheikhupura': 40.0,
    'lahore|narowal': 95.0,
  };

  // �x� Gemini baseline market prices (per unit) for admin AI insight checks
  static const Map<String, double> marketPriceByCrop = {
    'wheat': 4350.0,
    'gandum': 4350.0,
    'rice': 7100.0,
    'chawal': 7100.0,
    'cotton': 8200.0,
    'kapaas': 8200.0,
    'maize': 2950.0,
    'makai': 2950.0,
    'sugarcane': 420.0,
    'ganna': 420.0,
    'dal chana': 9500.0,
    'chana': 9500.0,
  };

  // �x� Firestore Collection Names
  static const String usersCollection = 'users';
  static const String listingsCollection = 'listings';
  static const String bidsCollection = 'bids';
  static const String dealsCollection = 'deals';
  static const String escrowCollection = 'escrow_transactions';
  static const String earningsCollection = 'Admin_Earnings';
  static const String alertsCollection = 'alerts'; // For AI suspicious flags
  static const String mandiRatesCollection = 'mandi_rates';
  static const String pakistanMandiRatesCollection = 'pakistan_mandi_rates';

  // �x}� Role Names
  static const String roleBuyer = 'buyer';
  static const String roleSeller = 'seller';
  static const String roleArhat = 'arhat';

  // �x� App Info
  static const String appName = 'Digital Arhat';
  static const String currency = 'Rs.';
  static const String firebaseDynamicLinkDomain =
      'https://digitalarhat.page.link';
  static const String appDeepLinkBase = 'https://digitalarhat.app';

  // �x� Commission Rates
  static const double buyerFeeRate = 0.01; // 1%
  static const double sellerFeeRate = 0.01; // 1%
}
