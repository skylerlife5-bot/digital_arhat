import 'package:geolocator/geolocator.dart';

import '../models/live_mandi_rate.dart';
import 'mandi_rate_location_service.dart';
import 'mandi_rate_trust_policy_service.dart';

class MandiRatePrioritizationService {
  const MandiRatePrioritizationService({
    MandiRateTrustPolicyService? trustPolicy,
  }) : _trustPolicy = trustPolicy ?? const MandiRateTrustPolicyService();

  final MandiRateTrustPolicyService _trustPolicy;

  List<LiveMandiRate> rank({
    required List<LiveMandiRate> rates,
    required MandiLocationContext location,
  }) {
    final sorted = List<LiveMandiRate>.from(rates);
    sorted.sort((a, b) {
      final scoreA = _score(a, location);
      final scoreB = _score(b, location);
      final scoreCompare = scoreB.compareTo(scoreA);
      if (scoreCompare != 0) return scoreCompare;
      return b.lastUpdated.compareTo(a.lastUpdated);
    });

    return sorted;
  }

  double _score(LiveMandiRate rate, MandiLocationContext location) {
    double score = 0;

    final city = location.city.trim().toLowerCase();
    final district = location.district.trim().toLowerCase();
    final province = location.province.trim().toLowerCase();

    final rateCity = rate.city.trim().toLowerCase();
    final rateDistrict = rate.district.trim().toLowerCase();
    final rateProvince = rate.province.trim().toLowerCase();

    // Deterministic location priority: city > nearest by coords > district > province.
    if (city.isNotEmpty && rateCity == city) score += 130;
    if (district.isNotEmpty && rateDistrict == district) score += 70;
    if (province.isNotEmpty && rateProvince == province) score += 30;

    final hasCoords = location.latitude != null &&
        location.longitude != null &&
        rate.latitude != null &&
        rate.longitude != null;

    if (hasCoords) {
      final meters = Geolocator.distanceBetween(
        location.latitude!,
        location.longitude!,
        rate.latitude!,
        rate.longitude!,
      );
      final km = meters / 1000;
      if (km <= 25) score += 120;
      if (km > 25 && km <= 80) score += 95;
      if (km > 80 && km <= 150) score += 75;
      if (km > 150 && km <= 300) score += 40;
    }

    if (rate.isLiveFresh) score += 30;
    if (rate.isRecentFresh) score += 18;
    if (rate.freshnessStatus == MandiFreshnessStatus.aging) score += 8;
    if (rate.isStale) score -= 20;

    // Preserve official-source-first order and only boost corroborated human data.
    final rank = _trustPolicy.priorityRank(rate);
    if (rank == 1) score += 80;
    if (rank == 2) score += 55;
    if (rank == 3) score += 24;
    if (rank == 4) score += 12;
    if (rank >= 5) score -= 18;
    if (rate.needsReview || rate.isRejectedContribution) score -= 45;

    if (rate.trend == 'up' || rate.trend == 'down') score += 2;

    return score;
  }
}
