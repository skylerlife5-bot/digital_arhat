import 'package:flutter_test/flutter_test.dart';

import 'package:digital_arhat/core/constants.dart';
import 'package:digital_arhat/core/mandi_unit_mapper.dart';

void main() {
  group('MandiUnitMapper defaults by Pakistan mandi context', () {
    test('Wheat defaults to mann', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'crops',
        fallbackType: MandiType.crops,
        subcategoryLabel: 'Wheat / گندم',
      );

      expect(config.defaultUnit, UnitType.mann);
      expect(config.allowedUnits, contains(UnitType.mann));
    });

    test('Eggs defaults to peti in poultry', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'poultry',
        fallbackType: MandiType.livestock,
        subcategoryLabel: 'Eggs / انڈے',
      );

      expect(config.defaultUnit, UnitType.peti);
      expect(config.allowedUnits, contains(UnitType.peti));
      expect(config.allowedUnits, isNot(contains(UnitType.perHead)));
    });

    test('Raw milk defaults to litre', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'milk',
        fallbackType: MandiType.milk,
        subcategoryLabel: 'Raw Milk / کچا دودھ',
      );

      expect(config.defaultUnit, UnitType.litre);
      expect(config.allowedUnits, contains(UnitType.litre));
    });

    test('Goat defaults to per head', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'livestock',
        fallbackType: MandiType.livestock,
        subcategoryLabel: 'Goat / بکری',
      );

      expect(config.defaultUnit, UnitType.perHead);
      expect(config.allowedUnits, equals(<UnitType>[UnitType.perHead]));
    });

    test('Coriander prefers peti for practical mandi trading', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'vegetables',
        fallbackType: MandiType.vegetables,
        subcategoryLabel: 'Coriander / دھنیا',
      );

      expect(config.defaultUnit, UnitType.peti);
      expect(config.allowedUnits, contains(UnitType.kg));
    });

    test('Fertilizer defaults to kg and supports mann', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'fertilizer',
        fallbackType: MandiType.fertilizer,
        subcategoryLabel: 'Urea / یوریا',
      );

      expect(config.defaultUnit, UnitType.kg);
      expect(config.allowedUnits, contains(UnitType.kg));
      expect(config.allowedUnits, contains(UnitType.mann));
    });

    test('Tomato defaults to kg', () {
      final config = MandiUnitMapper.resolve(
        categoryId: 'vegetables',
        fallbackType: MandiType.vegetables,
        subcategoryLabel: 'Tomato / ٹماٹر',
      );

      expect(config.defaultUnit, UnitType.kg);
      expect(config.allowedUnits, contains(UnitType.kg));
    });

    test('Legacy piece normalizes contextually to per head for livestock', () {
      final normalized = MandiUnitMapper.normalizeUnitType(
        rawUnit: 'piece',
        categoryId: 'livestock',
        fallbackType: MandiType.livestock,
        subcategoryLabel: 'Goat / بکری',
      );

      expect(normalized, UnitType.perHead);
    });

    test('Legacy piece does not become per head for vegetables', () {
      final normalized = MandiUnitMapper.normalizeUnitType(
        rawUnit: 'piece',
        categoryId: 'vegetables',
        fallbackType: MandiType.vegetables,
        subcategoryLabel: 'Tomato / ٹماٹر',
      );

      expect(normalized, UnitType.peti);
    });

    test('No universal kg fallback for poultry eggs', () {
      final normalized = MandiUnitMapper.normalizeUnitType(
        rawUnit: '',
        categoryId: 'poultry',
        fallbackType: MandiType.livestock,
        subcategoryLabel: 'Eggs / انڈے',
      );

      expect(normalized, UnitType.peti);
    });
  });
}
