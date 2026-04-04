class MandiRateSeedItem {
  const MandiRateSeedItem({
    required this.id,
    required this.urduName,
    required this.unit,
    required this.isTickerEligible,
    required this.basePrice,
    required this.group,
    this.commodityNameUr,
  });

  final String id;
  final String urduName;
  final String unit;
  final bool isTickerEligible;
  final double basePrice;
  final String group;
  final String? commodityNameUr;
}

class MandiRatesSeed {
  const MandiRatesSeed._();

  // Lahore-focused catalog (40+ items)
  static const List<MandiRateSeedItem> lahoreCatalog = <MandiRateSeedItem>[
    // --- Meats (kg) ---
    MandiRateSeedItem(id: 'live_chicken', urduName: 'زندہ مرغی', unit: 'کلو', isTickerEligible: true, basePrice: 620, group: 'meat'),
    MandiRateSeedItem(id: 'chicken_meat', urduName: 'مرغی کا گوشت', unit: 'کلو', isTickerEligible: true, basePrice: 890, group: 'meat'),
    MandiRateSeedItem(id: 'beef', urduName: 'بڑا گوشت', unit: 'کلو', isTickerEligible: true, basePrice: 1220, group: 'meat'),
    MandiRateSeedItem(id: 'mutton', urduName: 'چھوٹا گوشت', unit: 'کلو', isTickerEligible: true, basePrice: 2380, group: 'meat'),

    // --- Bulk / grains ---
    MandiRateSeedItem(id: 'wheat', urduName: 'گندم', unit: '40 کلو', isTickerEligible: true, basePrice: 4100, group: 'grain'),
    MandiRateSeedItem(id: 'rice_irri', urduName: 'چاول اری', unit: '40 کلو', isTickerEligible: true, basePrice: 6200, group: 'grain'),
    MandiRateSeedItem(id: 'rice_basmati', urduName: 'چاول باسمتی', unit: '40 کلو', isTickerEligible: true, basePrice: 12800, group: 'grain'),
    MandiRateSeedItem(id: 'lentil_masoor', urduName: 'دال مسور', unit: '40 کلو', isTickerEligible: true, basePrice: 9200, group: 'grain'),
    MandiRateSeedItem(id: 'lentil_moong', urduName: 'دال مونگ', unit: '40 کلو', isTickerEligible: true, basePrice: 10400, group: 'grain'),
    MandiRateSeedItem(id: 'lentil_mash', urduName: 'دال ماش', unit: '40 کلو', isTickerEligible: true, basePrice: 11500, group: 'grain'),
    MandiRateSeedItem(id: 'gram', urduName: 'چنا', unit: '40 کلو', isTickerEligible: true, basePrice: 7900, group: 'grain'),
    MandiRateSeedItem(id: 'sugar', urduName: 'چینی (50 کلو تھیلا)', unit: '50 کلو تھیلا', isTickerEligible: true, basePrice: 7400, group: 'grain'),

    // --- Essentials ---
    MandiRateSeedItem(id: 'flour_20kg', urduName: 'آٹا 20 کلو', unit: '20 کلو تھیلا', isTickerEligible: true, basePrice: 2850, group: 'essential'),
    MandiRateSeedItem(id: 'cooking_oil_5l', urduName: 'ککنگ آئل 5 لیٹر', unit: '5 لیٹر', isTickerEligible: true, basePrice: 2950, group: 'essential'),
    MandiRateSeedItem(id: 'eggs', urduName: 'انڈے', unit: 'درجن', isTickerEligible: true, basePrice: 340, group: 'essential'),
    MandiRateSeedItem(id: 'milk', urduName: 'دودھ', unit: 'لیٹر', isTickerEligible: true, basePrice: 230, group: 'essential'),

    // --- Veg / kitchen ---
    MandiRateSeedItem(id: 'potato', urduName: 'آلو', unit: 'کلو', isTickerEligible: true, basePrice: 95, group: 'veg'),
    MandiRateSeedItem(id: 'onion', urduName: 'پیاز', unit: 'کلو', isTickerEligible: true, basePrice: 170, group: 'veg'),
    MandiRateSeedItem(id: 'tomato', urduName: 'ٹماٹر', unit: 'کلو', isTickerEligible: true, basePrice: 160, group: 'veg'),
    MandiRateSeedItem(id: 'garlic', urduName: 'لہسن', unit: 'کلو', isTickerEligible: true, basePrice: 540, group: 'veg'),
    MandiRateSeedItem(id: 'ginger', urduName: 'ادرک', unit: 'کلو', isTickerEligible: true, basePrice: 620, group: 'veg'),
    MandiRateSeedItem(id: 'lemon', urduName: 'لیموں', unit: 'کلو', isTickerEligible: false, basePrice: 300, group: 'veg'),
    MandiRateSeedItem(id: 'spinach', urduName: 'پالک', unit: 'کلو', isTickerEligible: false, basePrice: 80, group: 'veg'),
    MandiRateSeedItem(id: 'cauliflower', urduName: 'پھول گوبھی', unit: 'کلو', isTickerEligible: false, basePrice: 130, group: 'veg'),
    MandiRateSeedItem(id: 'ladyfinger', urduName: 'بھنڈی', unit: 'کلو', isTickerEligible: false, basePrice: 180, group: 'veg'),
    MandiRateSeedItem(id: 'cabbage', urduName: 'بند گوبھی', unit: 'کلو', isTickerEligible: false, basePrice: 95, group: 'veg'),
    MandiRateSeedItem(id: 'carrot', urduName: 'گاجر', unit: 'کلو', isTickerEligible: false, basePrice: 110, group: 'veg'),
    MandiRateSeedItem(id: 'peas', urduName: 'مٹر', unit: 'کلو', isTickerEligible: false, basePrice: 240, group: 'veg'),
    MandiRateSeedItem(id: 'green_chili', urduName: 'ہری مرچ', unit: 'کلو', isTickerEligible: false, basePrice: 210, group: 'veg'),
    MandiRateSeedItem(id: 'coriander', urduName: 'دھنیا', unit: 'کلو', isTickerEligible: false, basePrice: 160, group: 'veg'),

    // --- Fruits ---
    MandiRateSeedItem(id: 'apple', urduName: 'سیب', unit: 'کلو', isTickerEligible: false, basePrice: 360, group: 'fruit'),
    MandiRateSeedItem(id: 'banana', urduName: 'کیلا', unit: 'درجن', isTickerEligible: false, basePrice: 280, group: 'fruit'),
    MandiRateSeedItem(id: 'guava', urduName: 'امرود', unit: 'کلو', isTickerEligible: false, basePrice: 190, group: 'fruit'),
    MandiRateSeedItem(id: 'citrus', urduName: 'مالٹا', unit: 'کلو', isTickerEligible: false, basePrice: 220, group: 'fruit'),
    MandiRateSeedItem(id: 'orange', urduName: 'سنگترہ', unit: 'کلو', isTickerEligible: false, basePrice: 230, group: 'fruit'),
    MandiRateSeedItem(id: 'mango', urduName: 'آم', unit: 'کلو', isTickerEligible: false, basePrice: 290, group: 'fruit'),
    MandiRateSeedItem(id: 'pomegranate', urduName: 'انار', unit: 'کلو', isTickerEligible: false, basePrice: 410, group: 'fruit'),
    MandiRateSeedItem(id: 'grapes', urduName: 'انگور', unit: 'کلو', isTickerEligible: false, basePrice: 430, group: 'fruit'),

    // --- Additional staples to cross 40+ ---
    MandiRateSeedItem(id: 'chana_dal', urduName: 'چنے کی دال', unit: '40 کلو', isTickerEligible: false, basePrice: 8800, group: 'grain'),
    MandiRateSeedItem(id: 'masoor_dal', urduName: 'مسور دال', unit: '40 کلو', isTickerEligible: false, basePrice: 9400, group: 'grain'),
    MandiRateSeedItem(id: 'white_chana', urduName: 'سفید چنا', unit: '40 کلو', isTickerEligible: false, basePrice: 8600, group: 'grain'),
    MandiRateSeedItem(id: 'black_chana', urduName: 'کالا چنا', unit: '40 کلو', isTickerEligible: false, basePrice: 8200, group: 'grain'),
    MandiRateSeedItem(id: 'mustard_oil_5l', urduName: 'سرسوں کا تیل 5 لیٹر', unit: '5 لیٹر', isTickerEligible: false, basePrice: 3450, group: 'essential'),
    MandiRateSeedItem(id: 'desi_ghee_1kg', urduName: 'دیسی گھی 1 کلو', unit: 'کلو', isTickerEligible: false, basePrice: 1650, group: 'essential'),
    MandiRateSeedItem(id: 'tea_900g', urduName: 'چائے 900 گرام', unit: '900 گرام', isTickerEligible: false, basePrice: 1750, group: 'essential'),
    MandiRateSeedItem(id: 'salt_800g', urduName: 'نمک 800 گرام', unit: '800 گرام', isTickerEligible: false, basePrice: 75, group: 'essential'),
    MandiRateSeedItem(id: 'red_chili_powder', urduName: 'لال مرچ پاؤڈر', unit: 'کلو', isTickerEligible: false, basePrice: 1100, group: 'essential'),
    MandiRateSeedItem(id: 'turmeric_powder', urduName: 'ہلدی پاؤڈر', unit: 'کلو', isTickerEligible: false, basePrice: 760, group: 'essential'),
  ];

  // Exactly 15 essentials for ticker rotation.
  static const List<String> tickerTop15Ids = <String>[
    'live_chicken',
    'chicken_meat',
    'beef',
    'mutton',
    'wheat',
    'rice_irri',
    'lentil_masoor',
    'gram',
    'sugar',
    'eggs',
    'milk',
    'potato',
    'onion',
    'tomato',
    'flour_20kg',
  ];
}
