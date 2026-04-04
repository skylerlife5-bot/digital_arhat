import 'constants.dart';

class MandiUnitConfig {
  const MandiUnitConfig({
    required this.defaultUnit,
    required this.allowedUnits,
  });

  final UnitType defaultUnit;
  final List<UnitType> allowedUnits;
}

class _KeywordUnitRule {
  const _KeywordUnitRule({
    required this.keywords,
    required this.config,
  });

  final List<String> keywords;
  final MandiUnitConfig config;
}

class MandiUnitMapper {
  const MandiUnitMapper._();

  static const MandiUnitConfig _crops = MandiUnitConfig(
    defaultUnit: UnitType.mann,
    allowedUnits: <UnitType>[UnitType.mann, UnitType.kg],
  );

  static const Map<String, MandiUnitConfig> _categoryRules =
      <String, MandiUnitConfig>{
        'crops': _crops,
        'fruit': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg, UnitType.peti],
        ),
        'vegetables': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg, UnitType.peti],
        ),
        'flowers': MandiUnitConfig(
          defaultUnit: UnitType.peti,
          allowedUnits: <UnitType>[UnitType.peti, UnitType.kg],
        ),
        'livestock': MandiUnitConfig(
          defaultUnit: UnitType.perHead,
          allowedUnits: <UnitType>[UnitType.perHead],
        ),
        'poultry': MandiUnitConfig(
          defaultUnit: UnitType.perHead,
          allowedUnits: <UnitType>[UnitType.perHead, UnitType.peti, UnitType.kg],
        ),
        'milk': MandiUnitConfig(
          defaultUnit: UnitType.litre,
          allowedUnits: <UnitType>[UnitType.litre, UnitType.kg],
        ),
        'seeds': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg, UnitType.mann],
        ),
        'fertilizer': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg, UnitType.mann],
        ),
        'machinery': MandiUnitConfig(
          defaultUnit: UnitType.peti,
          allowedUnits: <UnitType>[UnitType.peti],
        ),
        'tools': MandiUnitConfig(
          defaultUnit: UnitType.peti,
          allowedUnits: <UnitType>[UnitType.peti],
        ),
        'dry_fruits': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg],
        ),
        'spices': MandiUnitConfig(
          defaultUnit: UnitType.kg,
          allowedUnits: <UnitType>[UnitType.kg, UnitType.peti],
        ),
      };

  static const Map<String, List<_KeywordUnitRule>> _subcategoryRules =
      <String, List<_KeywordUnitRule>>{
        'crops': <_KeywordUnitRule>[
          _KeywordUnitRule(
            keywords: <String>['processed rice', 'چاول'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.kg,
              allowedUnits: <UnitType>[UnitType.kg, UnitType.mann],
            ),
          ),
          _KeywordUnitRule(
            keywords: <String>['rice crop', 'paddy', 'دھان', 'wheat', 'گندم'],
            config: _crops,
          ),
        ],
        'fruit': <_KeywordUnitRule>[
          _KeywordUnitRule(
            keywords: <String>['banana', 'کیلا', 'kinnow', 'کینو', 'mango', 'آم'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.peti,
              allowedUnits: <UnitType>[UnitType.peti, UnitType.kg],
            ),
          ),
        ],
        'vegetables': <_KeywordUnitRule>[
          _KeywordUnitRule(
            keywords: <String>['coriander', 'دھنیا'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.peti,
              allowedUnits: <UnitType>[UnitType.peti, UnitType.kg],
            ),
          ),
        ],
        'poultry': <_KeywordUnitRule>[
          _KeywordUnitRule(
            keywords: <String>['eggs', 'egg', 'انڈے', 'انڈا'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.peti,
              allowedUnits: <UnitType>[UnitType.peti, UnitType.kg],
            ),
          ),
        ],
        'milk': <_KeywordUnitRule>[
          _KeywordUnitRule(
            keywords: <String>['yogurt', 'دہی', 'ghee', 'گھی', 'butter', 'مکھن', 'cream', 'بالائی'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.kg,
              allowedUnits: <UnitType>[UnitType.kg, UnitType.litre],
            ),
          ),
          _KeywordUnitRule(
            keywords: <String>['milk', 'دودھ'],
            config: MandiUnitConfig(
              defaultUnit: UnitType.litre,
              allowedUnits: <UnitType>[UnitType.litre, UnitType.kg],
            ),
          ),
        ],
      };

  static MandiUnitConfig resolve({
    required String categoryId,
    required MandiType fallbackType,
    String? subcategoryLabel,
  }) {
    final normalizedCategory = categoryId.trim().toLowerCase();
    final normalizedSubcategory = _normalize(subcategoryLabel ?? '');

    final rules = _subcategoryRules[normalizedCategory] ?? const <_KeywordUnitRule>[];
    for (final rule in rules) {
      if (rule.keywords.any((keyword) => normalizedSubcategory.contains(_normalize(keyword)))) {
        return rule.config;
      }
    }

    return _categoryRules[normalizedCategory] ?? _fallbackForMandiType(fallbackType);
  }

  static UnitType normalizeUnitType({
    required dynamic rawUnit,
    required String categoryId,
    required MandiType fallbackType,
    String? subcategoryLabel,
  }) {
    final config = resolve(
      categoryId: categoryId,
      fallbackType: fallbackType,
      subcategoryLabel: subcategoryLabel,
    );

    final parsed = _parseRawUnit(rawUnit);
    if (parsed != null && config.allowedUnits.contains(parsed)) {
      return parsed;
    }

    final raw = _normalize((rawUnit ?? '').toString());
    if (_looksLikePiece(raw)) {
      if (config.allowedUnits.contains(UnitType.perHead)) {
        return UnitType.perHead;
      }
      if (config.allowedUnits.contains(UnitType.peti)) {
        return UnitType.peti;
      }
    }

    return config.defaultUnit;
  }

  static String normalizedUrduUnitLabel({
    required dynamic rawUnit,
    required String categoryId,
    required MandiType fallbackType,
    String? subcategoryLabel,
  }) {
    final unit = normalizeUnitType(
      rawUnit: rawUnit,
      categoryId: categoryId,
      fallbackType: fallbackType,
      subcategoryLabel: subcategoryLabel,
    );
    return unit.urduLabel;
  }

  static UnitType? _parseRawUnit(dynamic rawUnit) {
    final raw = _normalize((rawUnit ?? '').toString());
    if (raw.isEmpty) return null;

    if (raw.contains('per head') || raw.contains('perhead') || raw.contains('فی جانور') || raw.contains('جانور')) {
      return UnitType.perHead;
    }
    if (raw.contains('litre') || raw.contains('liter') || raw == 'ltr' || raw == 'l') {
      return UnitType.litre;
    }
    if (raw.contains('mann') || raw.contains('maund') || raw.contains('mond') || raw == 'man' || raw.contains('من')) {
      return UnitType.mann;
    }
    if (raw.contains('peti') || raw.contains('crate') || raw.contains('box') || raw.contains('carton') || raw.contains('tray') || raw.contains('dozen') || raw.contains('pack')) {
      return UnitType.peti;
    }
    if (raw == 'kg' || raw.contains('kilo') || raw.contains('kilogram') || raw.contains('کلو')) {
      return UnitType.kg;
    }
    if (_looksLikePiece(raw)) {
      return UnitType.peti;
    }

    return null;
  }

  static bool _looksLikePiece(String raw) {
    return raw.contains('piece') ||
        raw == 'pc' ||
        raw == 'pcs' ||
        raw.contains('unit') ||
        raw.contains('item') ||
        raw.contains('عدد');
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static MandiUnitConfig _fallbackForMandiType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return _crops;
      case MandiType.fruit:
        return _categoryRules['fruit']!;
      case MandiType.vegetables:
        return _categoryRules['vegetables']!;
      case MandiType.flowers:
        return _categoryRules['flowers']!;
      case MandiType.livestock:
        return _categoryRules['livestock']!;
      case MandiType.milk:
        return _categoryRules['milk']!;
      case MandiType.seeds:
        return _categoryRules['seeds']!;
      case MandiType.fertilizer:
        return _categoryRules['fertilizer']!;
      case MandiType.machinery:
        return _categoryRules['machinery']!;
      case MandiType.tools:
        return _categoryRules['tools']!;
      case MandiType.dryFruits:
        return _categoryRules['dry_fruits']!;
      case MandiType.spices:
        return _categoryRules['spices']!;
    }
  }
}
