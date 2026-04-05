import 'dart:async';

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

/// Rates are sourced exclusively from Firestore (mandi_rates collection).
/// This service returns empty until a Firestore-backed implementation is wired up.
class RealtimeAgriRatesService {
  List<AgriRatePoint> allRatesSnapshot() => const <AgriRatePoint>[];

  Stream<List<AgriRatePoint>> watchTickerRates() async* {
    yield const <AgriRatePoint>[];
  }

  Stream<List<AgriRatePoint>> watchRates() async* {
    yield* watchTickerRates();
  }
}

