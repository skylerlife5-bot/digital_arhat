import 'dart:async';

import 'mandi_rates_seed.dart';

class AgriRatePoint {
  final String id;
  final String urduName;
  final String unit;
  final bool isTickerEligible;
  final String group;
  final String market;
  final double pricePkr;
  final double changePercent;
  final DateTime updatedAt;

  const AgriRatePoint({
    required this.id,
    required this.urduName,
    required this.unit,
    required this.isTickerEligible,
    required this.group,
    required this.market,
    required this.pricePkr,
    required this.changePercent,
    required this.updatedAt,
  });
}

class RealtimeAgriRatesService {
  static final List<AgriRatePoint> _seedData = MandiRatesSeed.lahoreCatalog
      .map(
        (seed) => AgriRatePoint(
          id: seed.id,
          urduName: seed.urduName,
          unit: seed.unit,
          isTickerEligible: seed.isTickerEligible,
          group: seed.group,
          market: 'لاہور',
          pricePkr: seed.basePrice,
          changePercent: 0.0,
          updatedAt: DateTime(2026, 1, 1),
        ),
      )
      .toList(growable: false);

  static const Map<String, int> _groupPriority = <String, int>{
    'meat': 1,
    'grain': 2,
    'essential': 3,
    'veg': 4,
    'fruit': 5,
  };

  List<AgriRatePoint> _tickerOnlySorted(List<AgriRatePoint> rates) {
    final top15 = MandiRatesSeed.tickerTop15Ids.toSet();
    final filtered = rates
        .where((item) => item.isTickerEligible && top15.contains(item.id))
        .toList(growable: false);
    final sorted = List<AgriRatePoint>.from(filtered)
      ..sort((a, b) {
        final ga = _groupPriority[a.group] ?? 99;
        final gb = _groupPriority[b.group] ?? 99;
        if (ga != gb) return ga.compareTo(gb);
        final ia = MandiRatesSeed.tickerTop15Ids.indexOf(a.id);
        final ib = MandiRatesSeed.tickerTop15Ids.indexOf(b.id);
        return ia.compareTo(ib);
      });
    return sorted;
  }

  List<AgriRatePoint> allRatesSnapshot() => _seedData;

  Stream<List<AgriRatePoint>> watchTickerRates() async* {
    while (true) {
      final now = DateTime.now();
      final refreshed = _seedData
          .map(
            (item) => AgriRatePoint(
              id: item.id,
              urduName: item.urduName,
              unit: item.unit,
              isTickerEligible: item.isTickerEligible,
              group: item.group,
              market: item.market,
              pricePkr: item.pricePkr,
              changePercent: item.changePercent,
              updatedAt: now,
            ),
          )
          .toList(growable: false);
      yield _tickerOnlySorted(refreshed);
      await Future<void>.delayed(const Duration(seconds: 20));
    }
  }

  Stream<List<AgriRatePoint>> watchRates() async* {
    yield* watchTickerRates();
  }
}

