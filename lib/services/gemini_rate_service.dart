import 'package:cloud_firestore/cloud_firestore.dart';

import 'ai_generative_service.dart';

class GeminiRateService {
  GeminiRateService._internal();
  static final GeminiRateService _instance = GeminiRateService._internal();
  factory GeminiRateService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MandiIntelligenceService _aiService = MandiIntelligenceService();

  Future<double?> getAverageRateFromGeminiFallback({
    required String item,
    required String location,
    required double fallbackListingPrice,
  }) async {
    final normalizedItem = item.trim();
    final normalizedLocation = location.trim().isEmpty ? 'Pakistan' : location.trim();

    if (normalizedItem.isEmpty) {
      return fallbackListingPrice > 0 ? fallbackListingPrice : null;
    }

    try {
      final bids = await _fetchRecentSuccessfulBidRates(
        item: normalizedItem,
        location: normalizedLocation,
      );

      final baseline = _average(bids);
      final prompt =
          'Based on the last 7 days of successful bids for $normalizedItem in $normalizedLocation from our Firestore database, calculate a fair average market rate. Return only the number. '
          'Bid samples (PKR): ${bids.join(', ')}. '
          '${baseline != null ? 'Current moving average: ${baseline.toStringAsFixed(0)}.' : ''}';

      final response = await _aiService.getAIResponse(prompt);
      final parsed = _extractNumber(response);
      if (parsed != null && parsed > 0) {
        return parsed;
      }

      if (baseline != null && baseline > 0) {
        return baseline;
      }

      return fallbackListingPrice > 0 ? fallbackListingPrice : null;
    } catch (_) {
      return fallbackListingPrice > 0 ? fallbackListingPrice : null;
    }
  }

  Future<List<double>> _fetchRecentSuccessfulBidRates({
    required String item,
    required String location,
  }) async {
    final now = DateTime.now().toUtc();
    final sevenDaysAgo = now.subtract(const Duration(days: 7));

    final listingSnap = await _db
        .collection('listings')
        .orderBy('updatedAt', descending: true)
        .limit(250)
        .get();

    final rates = <double>[];
    final itemLower = item.toLowerCase();
    final locationLower = location.toLowerCase();

    for (final doc in listingSnap.docs) {
      final map = doc.data();
      final product = (map['product'] ?? map['cropName'] ?? '').toString().toLowerCase();
      if (!product.contains(itemLower) && !itemLower.contains(product)) {
        continue;
      }

      final status = (map['status'] ?? map['auctionStatus'] ?? '').toString().toLowerCase();
      final paymentStatus = (map['paymentStatus'] ?? '').toString().toLowerCase();
      final isSuccessful = status == 'completed' ||
          status == 'contact_released' ||
          paymentStatus == 'verified' ||
          paymentStatus == 'completed';
      if (!isSuccessful) continue;

      final updatedAtRaw = map['updatedAt'] ?? map['highestBidAt'] ?? map['bidClosedAt'];
      final updatedAt = updatedAtRaw is Timestamp ? updatedAtRaw.toDate().toUtc() : null;
      if (updatedAt != null && updatedAt.isBefore(sevenDaysAgo)) {
        continue;
      }

      final listingLocation = (map['district'] ?? map['city'] ?? map['location'] ?? 'pakistan')
          .toString()
          .toLowerCase();
      if (locationLower != 'pakistan' && !listingLocation.contains(locationLower)) {
        continue;
      }

      final candidate = _toDouble(map['highestBid']) ??
          _toDouble(map['finalPrice']) ??
          _toDouble(map['price']);
      if (candidate != null && candidate > 0) {
        rates.add(candidate);
      }
    }

    return rates;
  }

  double? _average(List<double> values) {
    final valid = values.where((value) => value > 0).toList();
    if (valid.isEmpty) return null;
    final sum = valid.fold<double>(0, (acc, value) => acc + value);
    return sum / valid.length;
  }

  double? _extractNumber(String text) {
    final normalized = text.replaceAll(',', '');
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)').firstMatch(normalized);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

