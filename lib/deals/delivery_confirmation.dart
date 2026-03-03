import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PaymentService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final double sellerCommissionRate = 0.01; // 1%
  final double buyerCommissionRate = 0.01;  // 1%

  // �S& 1. Buyer Payment Logic
  Future<void> initiateEscrowPayment({
    required String dealId,
    required double baseAmount,
    required String paymentMethod,
    required String buyerId,
    required String sellerId,
  }) async {
    try {
      double buyerFee = baseAmount * buyerCommissionRate;
      double totalChargedToBuyer = baseAmount + buyerFee;

      await _db.runTransaction((transaction) async {
        DocumentReference escrowRef = _db.collection('escrow_transactions').doc(dealId);
        transaction.set(escrowRef, {
          'dealId': dealId,
          'buyerId': buyerId,
          'sellerId': sellerId,
          'baseAmount': baseAmount,
          'buyerServiceFee': buyerFee,
          'totalPaidByBuyer': totalChargedToBuyer,
          'method': paymentMethod,
          'status': 'Paisa Moosul (Held by System)',
          'createdAt': FieldValue.serverTimestamp(),
          'isReleasedToSeller': false,
        });

        transaction.update(_db.collection('deals').doc(dealId), {
          'paymentStatus': 'PAID_TO_ESCROW',
          'totalWithFee': totalChargedToBuyer,
          'currentStep': 'AWAITING_DELIVERY',
        });
      });
    } catch (e) {
      debugPrint("�R Payment Error: $e");
      rethrow;
    }
  }

  // �S& 2. RELEASE Logic (Fix: Method name matched with UI)
  Future<void> releasePaymentToSeller(String dealId) async {
    try {
      final escrowDoc = await _db.collection('escrow_transactions').doc(dealId).get();
      if (!escrowDoc.exists) return;

      final data = escrowDoc.data()!;
      if (data['isReleasedToSeller'] == true) return;

      double baseAmount = data['baseAmount'].toDouble();
      double buyerFeeCollected = data['buyerServiceFee'].toDouble();
      String sellerId = data['sellerId'];

      double sellerFeeDeducted = baseAmount * sellerCommissionRate;
      double finalPayoutToSeller = baseAmount - sellerFeeDeducted;
      double totalAdminRevenue = buyerFeeCollected + sellerFeeDeducted;

      await _db.runTransaction((transaction) async {
        // Update Escrow
        transaction.update(_db.collection('escrow_transactions').doc(dealId), {
          'isReleasedToSeller': true,
          'sellerServiceFee': sellerFeeDeducted,
          'totalAdminEarnings': totalAdminRevenue,
          'finalPayoutToSeller': finalPayoutToSeller,
          'status': 'Completed',
          'releasedAt': FieldValue.serverTimestamp(),
        });

        // Update Seller Wallet
        transaction.update(_db.collection('users').doc(sellerId), {
          'walletBalance': FieldValue.increment(finalPayoutToSeller),
        });

        // Track Admin Earnings
        DocumentReference adminRef = _db.collection('Admin_Earnings').doc('total_revenue');
        transaction.set(adminRef, {
          'totalCommissionEarned': FieldValue.increment(totalAdminRevenue),
          'dealsProcessed': FieldValue.increment(1),
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Finalize Deal
        transaction.update(_db.collection('deals').doc(dealId), {
          'paymentStatus': 'COMPLETED',
          'currentStep': 'DEAL_FINISHED',
        });
      });
      debugPrint("�S& Payment Released Successfully!");
    } catch (e) {
      debugPrint("�R Release Error: $e");
    }
  }
}
