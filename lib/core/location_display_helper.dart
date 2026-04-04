import 'market_hierarchy.dart';

class LocationDisplayHelper {
  static String urduFor(String english, {Map<String, String>? preferredMap}) {
    final String en = english.trim();
    if (en.isEmpty) return '';
    final String preferred = (preferredMap?[en] ?? '').trim();
    if (preferred.isNotEmpty && !_isEquivalentLabel(en, preferred)) {
      return preferred;
    }
    final String mapped = PakistanLocationHierarchy.urduLabelForLocation(en).trim();
    if (mapped.isNotEmpty && !_isEquivalentLabel(en, mapped)) {
      return mapped;
    }
    final String transliterated = _toUrduTransliteration(en).trim();
    if (transliterated.isNotEmpty && !_isEquivalentLabel(en, transliterated)) {
      return transliterated;
    }
    return '';
  }

  static String bilingualLabel(String english, {Map<String, String>? preferredMap}) {
    return bilingualLabelFromParts(english, preferredMap: preferredMap);
  }

  static String resolvedUrduLabel(
    String english, {
    String? candidateUrdu,
    Map<String, String>? preferredMap,
  }) {
    final String en = english.trim();
    if (en.isEmpty) return '';
    final String candidate = (candidateUrdu ?? '').trim();
    if (candidate.isNotEmpty && !_isEquivalentLabel(en, candidate)) {
      return candidate;
    }
    final String ur = urduFor(en, preferredMap: preferredMap);
    if (ur.isNotEmpty && !_isEquivalentLabel(en, ur)) {
      return ur;
    }
    return '';
  }

  static String bilingualLabelFromParts(
    String english, {
    String? candidateUrdu,
    Map<String, String>? preferredMap,
  }) {
    final String en = english.trim();
    if (en.isEmpty) return '';
    final String ur = resolvedUrduLabel(
      en,
      candidateUrdu: candidateUrdu,
      preferredMap: preferredMap,
    );
    if (ur.isEmpty || _isEquivalentLabel(en, ur)) {
      return en;
    }
    return '$en / $ur';
  }

  static String locationDisplayFromData(Map<String, dynamic> data) {
    final _LocationParts parts = _extractLocationParts(data);
    final List<String> displayParts = <String>[];

    void addPart(String en, String ur) {
      final String enValue = en.trim();
      if (enValue.isEmpty) return;
      displayParts.add(
        bilingualLabelFromParts(enValue, candidateUrdu: ur),
      );
    }

    addPart(parts.cityEn, parts.cityUr);
    addPart(parts.tehsilEn, parts.tehsilUr);
    addPart(parts.districtEn, parts.districtUr);
    addPart(parts.provinceEn, parts.provinceUr);

    if (displayParts.isNotEmpty) {
      return displayParts.join(', ');
    }

    final String locationDisplay = (data['locationDisplay'] ?? '').toString().trim();
    if (locationDisplay.isNotEmpty) {
      return _bilingualizeDelimited(locationDisplay);
    }

    final String location = (data['location'] ?? '').toString().trim();
    if (location.isNotEmpty) {
      return _bilingualizeDelimited(location);
    }

    return 'Pakistan / پاکستان';
  }

  static String searchTextFromData(Map<String, dynamic> data) {
    final _LocationParts parts = _extractLocationParts(data);
    final String locationDisplay = locationDisplayFromData(data);
    final String locationUr = (data['locationUr'] ?? '').toString();

    final List<String> values = <String>[
      (data['itemName'] ?? '').toString(),
      (data['product'] ?? '').toString(),
      (data['description'] ?? '').toString(),
      (data['location'] ?? '').toString(),
      (data['locationDisplay'] ?? '').toString(),
      locationDisplay,
      locationUr,
      parts.cityEn,
      parts.cityUr,
      parts.tehsilEn,
      parts.tehsilUr,
      parts.districtEn,
      parts.districtUr,
      parts.provinceEn,
      parts.provinceUr,
    ];

    return values.join(' ').toLowerCase();
  }

  static _LocationParts _extractLocationParts(Map<String, dynamic> data) {
    final Map<String, dynamic> nodes = _toStringDynamicMap(data['locationNodes']);
    final Map<String, dynamic> locationData = _toStringDynamicMap(data['locationData']);

    final Map<String, dynamic> provinceNode = _toStringDynamicMap(nodes['province']);
    final Map<String, dynamic> districtNode = _toStringDynamicMap(nodes['district']);
    final Map<String, dynamic> tehsilNode = _toStringDynamicMap(nodes['tehsil']);
    final Map<String, dynamic> cityNode = _toStringDynamicMap(nodes['city']);

    final Map<String, dynamic> provinceObj = _toStringDynamicMap(locationData['provinceObj']);
    final Map<String, dynamic> districtObj = _toStringDynamicMap(locationData['districtObj']);
    final Map<String, dynamic> tehsilObj = _toStringDynamicMap(locationData['tehsilObj']);
    final Map<String, dynamic> cityObj = _toStringDynamicMap(locationData['cityObj']);

    final String provinceEn = _firstNonEmpty(<String>[
      (provinceNode['name_en'] ?? '').toString(),
      (provinceObj['name_en'] ?? '').toString(),
      (data['province'] ?? '').toString(),
      (locationData['province'] ?? '').toString(),
    ]);
    final String districtEn = _firstNonEmpty(<String>[
      (districtNode['name_en'] ?? '').toString(),
      (districtObj['name_en'] ?? '').toString(),
      (data['district'] ?? '').toString(),
      (locationData['district'] ?? '').toString(),
    ]);
    final String tehsilEn = _firstNonEmpty(<String>[
      (tehsilNode['name_en'] ?? '').toString(),
      (tehsilObj['name_en'] ?? '').toString(),
      (data['tehsil'] ?? '').toString(),
      (locationData['tehsil'] ?? '').toString(),
    ]);
    final String cityEn = _firstNonEmpty(<String>[
      (cityNode['name_en'] ?? '').toString(),
      (cityObj['name_en'] ?? '').toString(),
      (data['city'] ?? '').toString(),
      (locationData['city'] ?? '').toString(),
      (data['village'] ?? '').toString(),
      (locationData['village'] ?? '').toString(),
    ]);

    final String provinceUr = _firstNonEmpty(<String>[
      (provinceNode['name_ur'] ?? '').toString(),
      (provinceObj['name_ur'] ?? '').toString(),
      urduFor(provinceEn),
    ]);
    final String districtUr = _firstNonEmpty(<String>[
      (districtNode['name_ur'] ?? '').toString(),
      (districtObj['name_ur'] ?? '').toString(),
      urduFor(districtEn),
    ]);
    final String tehsilUr = _firstNonEmpty(<String>[
      (tehsilNode['name_ur'] ?? '').toString(),
      (tehsilObj['name_ur'] ?? '').toString(),
      urduFor(tehsilEn),
    ]);
    final String cityUr = _firstNonEmpty(<String>[
      (cityNode['name_ur'] ?? '').toString(),
      (cityObj['name_ur'] ?? '').toString(),
      urduFor(cityEn),
    ]);

    return _LocationParts(
      provinceEn: provinceEn,
      provinceUr: provinceUr,
      districtEn: districtEn,
      districtUr: districtUr,
      tehsilEn: tehsilEn,
      tehsilUr: tehsilUr,
      cityEn: cityEn,
      cityUr: cityUr,
    );
  }

  static Map<String, dynamic> _toStringDynamicMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  static String _firstNonEmpty(List<String> values) {
    for (final String value in values) {
      final String clean = value.trim();
      if (clean.isNotEmpty) return clean;
    }
    return '';
  }

  static String _bilingualizeDelimited(String raw) {
    final List<String> chunks = raw
        .replaceAll('\n', ',')
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (chunks.isEmpty) {
      return raw.trim();
    }
    return chunks
        .map((part) {
          if (part.contains('/')) {
            final List<String> pair = part.split('/');
            final String en = pair.first.trim();
            final String ur = pair.length > 1 ? pair.last.trim() : '';
            return bilingualLabelFromParts(en, candidateUrdu: ur);
          }
          return bilingualLabel(part);
        })
        .where((part) => part.trim().isNotEmpty)
        .join(', ');
  }

  static String _toUrduTransliteration(String value) {
    final String input = value.trim();
    if (input.isEmpty) return '';

    final List<String> words = input
        .replaceAll('&', ' and ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .split(' ')
        .where((part) => part.trim().isNotEmpty)
        .toList(growable: false);

    final List<String> mappedWords = words
        .map((word) => _transliterateWord(word))
        .where((word) => word.trim().isNotEmpty)
        .toList(growable: false);

    return mappedWords.join(' ');
  }

  static bool _isEquivalentLabel(String left, String right) {
    String normalize(String value) {
      return value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'\s+'), ' ')
          .replaceAll('/', '')
          .replaceAll('-', ' ');
    }

    final String normalizedLeft = normalize(left);
    final String normalizedRight = normalize(right);
    return normalizedLeft.isNotEmpty && normalizedLeft == normalizedRight;
  }

  static String _transliterateWord(String rawWord) {
    final String cleaned = rawWord
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (cleaned.isEmpty) return '';

    final String? direct = _urduByEnglishToken[cleaned];
    if (direct != null && direct.trim().isNotEmpty) {
      return direct;
    }

    final StringBuffer out = StringBuffer();
    int i = 0;
    while (i < cleaned.length) {
      String? token;
      String? mapped;
      int tokenLength = 1;

      if (i + 3 <= cleaned.length) {
        token = cleaned.substring(i, i + 3);
        mapped = _romanToUrdu[token];
        if (mapped != null) tokenLength = 3;
      }
      if (mapped == null && i + 2 <= cleaned.length) {
        token = cleaned.substring(i, i + 2);
        mapped = _romanToUrdu[token];
        if (mapped != null) tokenLength = 2;
      }
      if (mapped == null) {
        token = cleaned.substring(i, i + 1);
        mapped = _romanToUrdu[token] ?? token;
        tokenLength = 1;
      }

      out.write(mapped);
      i += tokenLength;
    }

    return out.toString();
  }

  static const Map<String, String> _urduByEnglishToken = <String, String>{
    'punjab': 'پنجاب',
    'sindh': 'سندھ',
    'balochistan': 'بلوچستان',
    'khyber': 'خیبر',
    'pakhtunkhwa': 'پختونخوا',
    'islamabad': 'اسلام آباد',
    'gilgit': 'گلگت',
    'baltistan': 'بلتستان',
    'azad': 'آزاد',
    'jammu': 'جموں',
    'kashmir': 'کشمیر',
    'and': 'اور',
    'city': 'شہر',
    'saddar': 'صدر',
    'rural': 'دیہی',
    'north': 'شمالی',
    'south': 'جنوبی',
    'east': 'مشرقی',
    'west': 'مغربی',
    'upper': 'بالائی',
    'lower': 'زیریں',
    'town': 'ٹاؤن',
    'tehsil': 'تحصیل',
    'district': 'ضلع',
  };

  static const Map<String, String> _romanToUrdu = <String, String>{
    'a': 'ا',
    'b': 'ب',
    'c': 'ک',
    'd': 'د',
    'e': 'ی',
    'f': 'ف',
    'g': 'گ',
    'h': 'ہ',
    'i': 'ی',
    'j': 'ج',
    'k': 'ک',
    'l': 'ل',
    'm': 'م',
    'n': 'ن',
    'o': 'و',
    'p': 'پ',
    'q': 'ق',
    'r': 'ر',
    's': 'س',
    't': 'ت',
    'u': 'و',
    'v': 'و',
    'w': 'و',
    'x': 'کس',
    'y': 'ی',
    'z': 'ز',
    'aa': 'ا',
    'ai': 'ے',
    'ay': 'ے',
    'ch': 'چ',
    'dh': 'دھ',
    'ee': 'ی',
    'gh': 'غ',
    'kh': 'خ',
    'oo': 'و',
    'ou': 'و',
    'ph': 'ف',
    'rh': 'ر',
    'sh': 'ش',
    'th': 'تھ',
    'ts': 'ٹس',
    'zh': 'ژ',
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
    '-': '-',
  };
}

class _LocationParts {
  const _LocationParts({
    required this.provinceEn,
    required this.provinceUr,
    required this.districtEn,
    required this.districtUr,
    required this.tehsilEn,
    required this.tehsilUr,
    required this.cityEn,
    required this.cityUr,
  });

  final String provinceEn;
  final String provinceUr;
  final String districtEn;
  final String districtUr;
  final String tehsilEn;
  final String tehsilUr;
  final String cityEn;
  final String cityUr;
}
