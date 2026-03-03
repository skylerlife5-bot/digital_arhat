enum MandiType { crops, livestock, milk, fruit, vegetables }

extension MandiTypeX on MandiType {
  String get wireValue {
    switch (this) {
      case MandiType.crops:
        return 'CROPS';
      case MandiType.livestock:
        return 'LIVESTOCK';
      case MandiType.milk:
        return 'MILK';
      case MandiType.fruit:
        return 'FRUIT';
      case MandiType.vegetables:
        return 'VEGETABLES';
    }
  }

  String get label {
    switch (this) {
      case MandiType.crops:
        return 'Crop (Fasal)';
      case MandiType.livestock:
        return 'Livestock (Maweshi)';
      case MandiType.milk:
        return 'Milk (Doodh)';
      case MandiType.fruit:
        return 'Fruit (Phal)';
      case MandiType.vegetables:
        return 'Veg (Sabzi)';
    }
  }

  String get urduLabel {
    switch (this) {
      case MandiType.crops:
        return 'غ�ہ/فص��Rں';
      case MandiType.livestock:
        return '�&���Rش�R';
      case MandiType.milk:
        return 'د��دھ �� ���Rر�R';
      case MandiType.fruit:
        return 'پھ�';
      case MandiType.vegetables:
        return 'سبز�Rاں';
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
        return 'درجہ ا�ف';
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
        return 'پ�Rٹ�R';
      case UnitType.mann:
        return '�&� ';
      case UnitType.litre:
        return '��Rٹر';
      case UnitType.kg:
        return 'ک���';
      case UnitType.perHead:
        return 'ف�R جا� ��ر';
    }
  }
}

class CategoryConstants {
  static const List<String> crops = [
    'Wheat (Gandum)',
    'Rice - Basmati',
    'Rice - Irri',
    'Cotton (Phutti)',
    'Sugarcane (Kamad)',
    'Maize (Makai)',
    'Gram (Chana)',
    'Mustard (Sarson/Raya)',
    'Tobacco',
    'Barley (Jao)',
    'Millet (Bajra)',
    'Sorghum (Jawar)',
    'Sesame (Til)',
    'Canola',
  ];

  static const List<String> vegetables = [
    'Potato (Aloo)',
    'Onion (Piaz)',
    'Tomato (Tamatar)',
    'Green Chili (Sabz Mirch)',
    'Garlic (Lehsan)',
    'Ginger (Adrak)',
    'Okra (Bhindi)',
    'Eggplant (Baingan)',
    'Cauliflower (Phool Gobi)',
    'Cabbage (Band Gobi)',
    'Bitter Gourd (Karela)',
    'Spinach (Palak)',
    'Peas (Matar)',
    'Radish (Mooli)',
    'Carrot (Gajar)',
    'Pumpkin (Kaddu)',
  ];

  static const List<String> fruits = [
    'Mango (Aam - Chaunsa/Sindhri/Anwar Ratol)',
    'Citrus (Kinnow/Musambi)',
    'Apple (Saib - Kala Kulu/Gacha)',
    'Dates (Khajoor)',
    'Guava (Amrood)',
    'Banana (Kela)',
    'Grapes (Angoor)',
    'Pomegranate (Anar)',
    'Apricot (Khubani)',
    'Peach (Aaroo)',
    'Plum (Aloo Bukhara)',
    'Melon (Kharbooza)',
    'Watermelon (Tarbooz)',
  ];

  static const List<String> livestock = [
    'Cow (Gaaye)',
    'Buffalo (Bhains)',
    'Goat (Bakri)',
    'Sheep (Bhair)',
    'Camel (Oont)',
    'Bull (Saand/Wacha)',
  ];

  static const List<String> dairyAndPoultry = [
    'Milk (Cow)',
    'Milk (Buffalo)',
    'Desi Ghee',
    'Eggs (Farm)',
    'Eggs (Desi)',
    'Chicken (Broiler)',
  ];

  static List<String> itemsForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return crops;
      case MandiType.vegetables:
        return vegetables;
      case MandiType.fruit:
        return fruits;
      case MandiType.livestock:
        return livestock;
      case MandiType.milk:
        return dairyAndPoultry;
    }
  }

  static UnitType defaultUnitForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return UnitType.mann;
      case MandiType.vegetables:
      case MandiType.fruit:
        return UnitType.kg;
      case MandiType.milk:
        return UnitType.litre;
      case MandiType.livestock:
        return UnitType.perHead;
    }
  }

  static List<UnitType> allowedUnitsForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return const [UnitType.mann, UnitType.kg];
      case MandiType.vegetables:
      case MandiType.fruit:
        return const [UnitType.kg];
      case MandiType.milk:
        return const [UnitType.litre, UnitType.kg, UnitType.perHead];
      case MandiType.livestock:
        return const [UnitType.perHead];
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

  static List<String> get provinces => pakistanLocations.keys.toList(growable: false);

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
  static const String firebaseDynamicLinkDomain = 'https://digitalarhat.page.link';
  static const String appDeepLinkBase = 'https://digitalarhat.app';

  // �x� Commission Rates
  static const double buyerFeeRate = 0.01; // 1%
  static const double sellerFeeRate = 0.01; // 1%
}

