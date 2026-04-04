import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../deals/deal_model.dart';
import '../models/deal_status.dart' as deal_status;
import 'escrow_service.dart';

class DealService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  final EscrowService _escrowService = EscrowService();
  static const Set<String> _sellerOnlyOutcomeStatuses = <String>{
    'successful',
    'failed',
    'cancelled',
    'disputed',
    'pending_contact',
    'no_bids',
  };

  // 1. Create a New Deal with Escrow Logic ✅
  // Note: Isay BiddingService se call kiya jata hai jab seller bid accept kare
  Future<void> createDealFromBid(
    Map<String, dynamic> bidData,
    String bidId,
  ) async {
    try {
      DocumentReference dealRef = _db.collection('deals').doc();

      double bidAmount = (bidData['bidAmount'] as num).toDouble();

      // 🧠 1% + 1% Calculation (Platform Fee)
      double commissionPerSide = bidAmount * 0.01;
      double buyerTotal = bidAmount + commissionPerSide;
      double sellerReceivable = bidAmount - commissionPerSide;
      double totalAppCommission = commissionPerSide * 2;

      DealModel newDeal = DealModel(
        dealId: dealRef.id,
        listingId: bidData['listingId'],
        sellerId: bidData['sellerId'],
        buyerId: bidData['buyerId'],
        productName: bidData['productName'] ?? 'Fasal',
        dealAmount: bidAmount,
        buyerTotal: buyerTotal,
        sellerReceivable: sellerReceivable,
        appCommission: totalAppCommission,
        status: deal_status
            .DealStatus
            .awaitingPayment
            .value, // Shuruat yahan se hogi
        createdAt: DateTime.now(),
      );

      await dealRef.set(newDeal.toMap());
    } catch (e) {
      throw Exception("Deal creation failed: $e");
    }
  }

  // 2. Get My Deals (Real-time Stream) ✅
  Stream<List<DealModel>> getMyDeals(bool isSeller) {
    if (_uid.isEmpty) return Stream.value([]);

    return _db
        .collection('deals')
        .where(isSeller ? 'sellerId' : 'buyerId', isEqualTo: _uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => DealModel.fromMap(doc.data(), doc.id))
              .toList(),
        );
  }

  // 3. Update Deal Status & Trigger Admin Alerts ✅
  Future<void> updateDealStatus(String dealId, String newStatus) async {
    try {
      if (_uid.isEmpty) {
        throw Exception('Please sign in first.');
      }

      final dealRef = _db.collection('deals').doc(dealId);
      final dealSnap = await dealRef.get();
      if (!dealSnap.exists) {
        throw Exception('Deal record not found');
      }

      final dealData = dealSnap.data() ?? <String, dynamic>{};
      final sellerId = (dealData['sellerId'] ?? '').toString().trim();
      final buyerId = (dealData['buyerId'] ?? '').toString().trim();
      if (_uid != sellerId && _uid != buyerId) {
        throw Exception('Only deal participants can update deal status.');
      }

      final normalizedStatus = newStatus.trim().toLowerCase();
      if (_sellerOnlyOutcomeStatuses.contains(normalizedStatus) &&
          (sellerId.isEmpty || _uid != sellerId)) {
        throw Exception('Only seller can update deal outcome.');
      }

      if (normalizedStatus == 'escrow_locked') {
        await _lockFundsInEscrow(dealId);
      } else {
        await dealRef.update({
          'status': newStatus,
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      // Agar deal 'completed' ho jaye, toh Admin ko wallet update ka ishara dein
      if (normalizedStatus == deal_status.DealStatus.dealCompleted.value) {
        await _notifyAdminForPayout(dealId);
      }
    } catch (e) {
      throw Exception("Status update failed: ${_readableError(e)}");
    }
  }

  Future<void> _lockFundsInEscrow(String dealId) async {
    final dealRef = _db.collection('deals').doc(dealId);
    final dealSnap = await dealRef.get();
    if (!dealSnap.exists) {
      throw Exception('Deal record not found');
    }

    final data = dealSnap.data() ?? <String, dynamic>{};
    final paymentStatus = (data['paymentStatus'] ?? '')
        .toString()
        .toUpperCase();
    final existingEscrowState = (data['escrowState'] ?? '')
        .toString()
        .toUpperCase();

    if (paymentStatus == 'PAID_TO_ESCROW' ||
        existingEscrowState == 'FUNDS_LOCKED') {
      await dealRef.update({
        'status': 'escrow_locked',
        'currentStep': 'AWAITING_DELIVERY',
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      return;
    }

    final listingId = (data['listingId'] ?? '').toString().trim();
    final buyerId = (data['buyerId'] ?? '').toString().trim();
    final sellerId = (data['sellerId'] ?? '').toString().trim();
    final amount = _toDouble(data['dealAmount']);

    if (listingId.isEmpty ||
        buyerId.isEmpty ||
        sellerId.isEmpty ||
        amount <= 0) {
      throw Exception('Escrow lock failed: deal data incomplete');
    }

    await _escrowService.initiateEscrowPayment(
      dealId: dealId,
      baseAmount: amount,
      paymentMethod: 'IN_APP_ESCROW',
      buyerId: buyerId,
      sellerId: sellerId,
      listingId: listingId,
    );

    await dealRef.update({
      'status': 'escrow_locked',
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _readableError(Object error) {
    return error.toString().replaceAll('Exception: ', '').trim();
  }

  // Admin ko batana ke ab Seller ko paise bhaijne ka waqt aa gaya hai
  Future<void> _notifyAdminForPayout(String dealId) async {
    await _db.collection('admin_alerts').add({
      'type': 'payout_ready',
      'dealId': dealId,
      'timestamp': FieldValue.serverTimestamp(),
      'processed': false,
    });
  }
}
