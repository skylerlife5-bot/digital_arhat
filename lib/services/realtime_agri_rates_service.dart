import 'dart:async';

class AgriRatePoint {
  final String commodity;
  final String market;
  final double pricePkrPer40kg;
  final double changePercent;
  final DateTime updatedAt;

  const AgriRatePoint({
    required this.commodity,
    required this.market,
    required this.pricePkrPer40kg,
    required this.changePercent,
    required this.updatedAt,
  });
}

class RealtimeAgriRatesService {
  static final List<AgriRatePoint> _seedData = <AgriRatePoint>[
    AgriRatePoint(
      commodity: 'Wheat',
      market: 'Lahore',
      pricePkrPer40kg: 4080,
      changePercent: 0.9,
      updatedAt: DateTime(2026, 1, 1),
    ),
    AgriRatePoint(
      commodity: 'Rice IRRI-6',
      market: 'Gujranwala',
      pricePkrPer40kg: 5650,
      changePercent: -0.4,
      updatedAt: DateTime(2026, 1, 1),
    ),
    AgriRatePoint(
      commodity: 'Cotton',
      market: 'Multan',
      pricePkrPer40kg: 8300,
      changePercent: 1.2,
      updatedAt: DateTime(2026, 1, 1),
    ),
  ];

  Stream<List<AgriRatePoint>> watchRates() async* {
    while (true) {
      final now = DateTime.now();
      final refreshed = _seedData
          .map(
            (item) => AgriRatePoint(
              commodity: item.commodity,
              market: item.market,
              pricePkrPer40kg: item.pricePkrPer40kg,
              changePercent: item.changePercent,
              updatedAt: now,
            ),
          )
          .toList(growable: false);
      yield refreshed;
      await Future<void>.delayed(const Duration(seconds: 20));
    }
  }
}

