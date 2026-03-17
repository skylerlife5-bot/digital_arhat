import 'package:cloud_firestore/cloud_firestore.dart';
import 'market_rate_service.dart';
import 'phase1_notification_engine.dart';

class FraudScoreResult {
  final double marketAverage;
  final double listingPrice;
  final double ratio;
  final bool isRisky;

  const FraudScoreResult({
    required this.marketAverage,
    required this.listingPrice,
    required this.ratio,
    required this.isRisky,
  });
}

class WeeklyAnalytics {
  final List<double> sales;
  final List<double> commissions;

  const WeeklyAnalytics({required this.sales, required this.commissions});
}

class AdminService {
  AdminService._internal();
  static final AdminService _instance = AdminService._internal();
  factory AdminService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MarketRateService _marketRateService = MarketRateService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();

  Future<double> calculateTotalCommission() async {
    final listingSnap = await _db.collection('listings').get();
    double totalCommission = 0;

    for (final doc in listingSnap.docs) {
      final map = doc.data();
      final String normalizedStatus = (map['status']?.toString().toLowerCase() ?? '');

      if (normalizedStatus == 'sold' || normalizedStatus == 'completed') {
        final double finalPrice = _toDouble(map['finalPrice']) ??
            _toDouble(map['winningBid']) ??
            _toDouble(map['highestBid']) ??
            0;
        totalCommission += (finalPrice * 0.02);
      }
    }

    return totalCommission;
  }

  FraudScoreResult calculateFraudScore(Map<String, dynamic> listingData, {double? marketAverage}) {
    final listingPrice = _toDouble(listingData['price']) ?? 0;
    final resolvedAverage = marketAverage ??
        _toDouble(listingData['market_average']) ??
        _toDouble(listingData['marketAverage']) ??
        0;

    if (listingPrice <= 0 || resolvedAverage <= 0) {
      return const FraudScoreResult(
        marketAverage: 0,
        listingPrice: 0,
        ratio: 0,
        isRisky: false,
      );
    }

    final ratio = listingPrice / resolvedAverage;
    return FraudScoreResult(
      marketAverage: resolvedAverage,
      listingPrice: listingPrice,
      ratio: ratio,
      isRisky: ratio >= 1.5,
    );
  }

  Future<double?> resolveMarketAverage(Map<String, dynamic> listingData) async {
    final fromListing = _toDouble(listingData['market_average']) ?? _toDouble(listingData['marketAverage']);
    if (fromListing != null && fromListing > 0) return fromListing;

    final cropNameRaw = (listingData['product'] ?? '').toString().trim().toLowerCase();
    if (cropNameRaw.isEmpty) return null;

    final rates = await _marketRateService.fetchRealTimeRatesFromAI();
    for (final rate in rates) {
      final candidate = rate.cropName.toLowerCase();
      if (candidate.contains(cropNameRaw) || cropNameRaw.contains(candidate)) {
        return rate.currentPrice;
      }
    }

    return null;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingListingsStream() {
    return _db
        .collection('listings')
        .where('isApproved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> approveListingVisibility(String listingId) async {
    final listingSnap = await _db.collection('listings').doc(listingId).get();
    final listingData = listingSnap.data() ?? <String, dynamic>{};
    final sellerId = (listingData['sellerId'] ?? '').toString().trim();

    await _db.collection('listings').doc(listingId).update({
      'isApproved': true,
      'status': 'active',
      'approvedAt': FieldValue.serverTimestamp(),
    });

    if (sellerId.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerId,
        type: Phase1NotificationType.listingApproved,
        listingId: listingId,
        targetRole: 'seller',
      );
    }
  }

  Future<void> forceActivateListing(String docId) async {
    final now = DateTime.now();
    await _db.collection('listings').doc(docId).update({
      'status': 'active',
      'isApproved': true,
      'approvedAt': FieldValue.serverTimestamp(),
      'startTime': FieldValue.serverTimestamp(),
      'endTime': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'bidStartTime': FieldValue.serverTimestamp(),
      'bidExpiryTime': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'isBidForceClosed': false,
      'bidClosedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> forceCloseAuctionAndAssignWinner(String listingId) async {
    final listingRef = _db.collection('listings').doc(listingId);

    await _db.runTransaction((transaction) async {
      final listingSnap = await transaction.get(listingRef);
      if (!listingSnap.exists) {
        throw Exception('Listing not found');
      }

      final bidsQuery = await listingRef
          .collection('bids')
          .orderBy('bidAmount', descending: true)
          .limit(1)
          .get();

      String? winnerId;
      String? winningBidId;
      double? winningBid;

      if (bidsQuery.docs.isNotEmpty) {
        final topBidDoc = bidsQuery.docs.first;
        final topBid = topBidDoc.data();
        winnerId = topBid['buyerId']?.toString();
        winningBidId = topBidDoc.id;
        winningBid = _toDouble(topBid['bidAmount']);
      }

      final updatePayload = <String, dynamic>{
        'status': 'Completed',
        'isBidForceClosed': true,
        'bidClosedAt': FieldValue.serverTimestamp(),
        'winnerId': winnerId,
        'buyerId': winnerId,
        'winningBid': winningBid,
        'finalPrice': winningBid ?? _toDouble(listingSnap.data()?['highestBid']) ?? 0,
        'finalBidId': winningBidId,
      };

      transaction.update(listingRef, updatePayload);
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingUsersForVerification() {
    return _db.collection('users').where('isVerified', isEqualTo: false).snapshots();
  }

  Future<void> verifyUser(String userId) async {
    await _db.collection('users').doc(userId).update({
      'isVerified': true,
      'verifiedAt': FieldValue.serverTimestamp(),
    });
  }

  List<String> extractCnicDocumentUrls(Map<String, dynamic> userData) {
    const possibleKeys = [
      'cnicFrontUrl',
      'cnicBackUrl',
      'cnicImageUrl',
      'cnicPhotoUrl',
      'documentUrl',
      'idCardFrontUrl',
      'idCardBackUrl',
    ];

    final urls = <String>[];
    for (final key in possibleKeys) {
      final value = userData[key];
      if (value is String && value.trim().isNotEmpty) {
        urls.add(value.trim());
      }
    }
    return urls;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getLast7DaysDealsStream() {
    final start = DateTime.now().subtract(const Duration(days: 6));
    return _db
        .collection('deals')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(DateTime(start.year, start.month, start.day)))
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  WeeklyAnalytics calculateWeeklyAnalytics(List<QueryDocumentSnapshot<Map<String, dynamic>>> deals) {
    final sales = List<double>.filled(7, 0);
    final commissions = List<double>.filled(7, 0);
    final today = DateTime.now();

    for (final doc in deals) {
      final map = doc.data();
      final createdAt = (map['createdAt'] as Timestamp?)?.toDate();
      if (createdAt == null) continue;

      final int daysAgo = DateTime(today.year, today.month, today.day)
          .difference(DateTime(createdAt.year, createdAt.month, createdAt.day))
          .inDays;
      if (daysAgo < 0 || daysAgo > 6) continue;

      final index = 6 - daysAgo;
      final dealAmount = _toDouble(map['dealAmount']) ?? _toDouble(map['finalPrice']) ?? 0;
      final appCommission = _toDouble(map['appCommission']) ?? (dealAmount * 0.02);

      sales[index] += dealAmount;
      commissions[index] += appCommission;
    }

    return WeeklyAnalytics(sales: sales, commissions: commissions);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

