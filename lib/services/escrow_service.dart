import 'package:cloud_firestore/cloud_firestore.dart';

import '../deals/transaction_model.dart';

class EscrowService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final double sellerCommissionRate = 0.02;
  final double buyerCommissionRate = 0.01;

  Future<void> approveEscrowPayment(String listingId) async {
    final normalizedListingId = listingId.trim();
    if (normalizedListingId.isEmpty) {
      throw Exception('Listing id is required for escrow approval.');
    }

    final listingRef = _db.collection('listings').doc(normalizedListingId);
    final listingSnap = await listingRef.get();
    if (!listingSnap.exists) {
      throw Exception('Listing not found for escrow approval.');
    }

    final listingData = listingSnap.data() ?? <String, dynamic>{};
    final sellerId = (listingData['sellerId'] ?? '').toString().trim();
    if (sellerId.isEmpty) {
      throw Exception('Seller not found for this listing.');
    }

    await listingRef.set({
      'status': 'escrow_confirmed',
      'listingStatus': 'escrow_confirmed',
      'auctionStatus': 'escrow_confirmed',
      'paymentStatus': 'verified',
      'escrowStatus': 'PAID_TO_ESCROW',
      'escrowApprovedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final dealId = (listingData['dealId'] ?? '').toString().trim();
    if (dealId.isNotEmpty) {
      await _db.collection('deals').doc(dealId).set({
        'paymentStatus': 'VERIFIED',
        'status': 'escrow_confirmed',
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await _db.collection('notifications').add({
      'type': 'escrow_confirmed',
      'listingId': normalizedListingId,
      'userId': sellerId,
      'message':
          'Payment received in Escrow! You can now safely dispatch the items.',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> initiateEscrowPayment({
    required String dealId,
    required double baseAmount,
    required String paymentMethod,
    required String buyerId,
    required String sellerId,
    String? listingId,
  }) async {
    final buyerFee = baseAmount * buyerCommissionRate;
    final totalChargedToBuyer = baseAmount + buyerFee;

    await _db.runTransaction((transaction) async {
      final dealRef = _db.collection('deals').doc(dealId);
      final dealSnap = await transaction.get(dealRef);
      if (!dealSnap.exists) {
        throw Exception('Deal not found');
      }

      final dealData = dealSnap.data() ?? <String, dynamic>{};
      final resolvedListingId = ((listingId ?? dealData['listingId']) ?? '').toString().trim();
      if (resolvedListingId.isEmpty) {
        throw Exception('Listing reference missing in deal');
      }

      final listingRef = _db.collection('listings').doc(resolvedListingId);
      final listingSnap = await transaction.get(listingRef);
      if (!listingSnap.exists) {
        throw Exception('Listing not found for escrow cross-check');
      }
      final listingData = listingSnap.data() ?? <String, dynamic>{};

      final expectedSellerId = (dealData['sellerId'] ?? listingData['sellerId'] ?? '').toString();
      final expectedBuyerId = (dealData['buyerId'] ?? '').toString();
      final dealAmount = _toDouble(dealData['dealAmount']);
      final listingAmount = _toDouble(listingData['finalPrice']) > 0
          ? _toDouble(listingData['finalPrice'])
          : _toDouble(listingData['highestBid']);

      if (expectedSellerId.isEmpty || expectedSellerId != sellerId) {
        throw Exception('Anti-tamper check failed: seller mismatch');
      }
      if (expectedBuyerId.isNotEmpty && expectedBuyerId != buyerId) {
        throw Exception('Anti-tamper check failed: buyer mismatch');
      }
      if (dealAmount > 0 && !_isAmountClose(baseAmount, dealAmount)) {
        throw Exception('Anti-tamper check failed: deal amount mismatch');
      }
      if (listingAmount > 0 && !_isAmountClose(baseAmount, listingAmount)) {
        throw Exception('Anti-tamper check failed: listing amount mismatch');
      }

      final bool highRisk = await _isHighRiskBid(
        transaction: transaction,
        listingRef: listingRef,
        listingData: listingData,
        buyerId: buyerId,
      );

      final escrowRef = _db.collection('escrow_transactions').doc(dealId);
      final escrowPayload = EscrowModel(
        dealId: dealId,
        listingId: resolvedListingId,
        buyerId: buyerId,
        sellerId: sellerId,
        baseAmount: baseAmount,
        buyerServiceFee: buyerFee,
        totalPaidByBuyer: totalChargedToBuyer,
        method: paymentMethod,
        state: EscrowTransactionState.fundsLocked,
        isHighRisk: highRisk,
        fundsLockedAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
        createdAt: DateTime.now().toUtc(),
      ).toMap();

      transaction.set(escrowRef, escrowPayload, SetOptions(merge: true));

      transaction.update(dealRef, {
        'paymentStatus': 'PAID_TO_ESCROW',
        'currentStep': 'AWAITING_DELIVERY',
        'totalWithFee': totalChargedToBuyer,
        'lastUpdate': FieldValue.serverTimestamp(),
        'escrowState': EscrowTransactionState.fundsLocked.wireValue,
        'isHighRisk': highRisk,
      });

      transaction.update(listingRef, {
        'status': 'completed',
        'escrowStatus': 'PAID_TO_ESCROW',
        'isBidForceClosed': true,
        'dealId': dealId,
        'buyerId': buyerId,
        'finalPrice': baseAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final buyerHistoryRef = _db
          .collection('users')
          .doc(buyerId)
          .collection('transactions')
          .doc();
      transaction.set(buyerHistoryRef, {
        'type': 'PAYMENT_SENT',
        'amount': totalChargedToBuyer,
        'baseAmount': baseAmount,
        'serviceFee': buyerFee,
        'dealId': dealId,
        'status': 'SUCCESS',
        'timestamp': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> transitionEscrowState({
    required String dealId,
    required EscrowTransactionState toState,
    required String callerUid,
    String callerRole = '',
    String verificationNote = '',
  }) async {
    await _db.runTransaction((transaction) async {
      final escrowRef = _db.collection('escrow_transactions').doc(dealId);
      final escrowSnap = await transaction.get(escrowRef);
      if (!escrowSnap.exists) {
        throw Exception('Escrow record not found');
      }

      final escrow = EscrowModel.fromMap(escrowSnap.data() ?? <String, dynamic>{});
      final fromState = escrow.state;

      if (!EscrowStateMachine.canTransition(from: fromState, to: toState)) {
        throw Exception('Invalid state transition: ${fromState.wireValue} -> ${toState.wireValue}');
      }

      final isAdmin = await _isVerifiedAdmin(
        transaction: transaction,
        callerUid: callerUid,
        callerRoleHint: callerRole,
      );

      if (!isAdmin) {
        throw Exception('Security rule simulation failed: caller.role must be ADMIN');
      }

      if (toState == EscrowTransactionState.fundsReleased) {
        if (fromState != EscrowTransactionState.stockVerified) {
          throw Exception('Security rule simulation failed: status must be STOCK_VERIFIED before payout');
        }
        if (escrow.isHighRisk && verificationNote.trim().isEmpty) {
          throw Exception('High-risk escrow requires admin verification note before release');
        }
      }

      final updates = <String, dynamic>{
        'state': toState.wireValue,
        'updatedAt': FieldValue.serverTimestamp(),
        if (verificationNote.trim().isNotEmpty) 'verificationNote': verificationNote.trim(),
      };

      switch (toState) {
        case EscrowTransactionState.stockInTransit:
          updates['stockInTransitAt'] = FieldValue.serverTimestamp();
          break;
        case EscrowTransactionState.stockVerified:
          updates['stockVerifiedAt'] = FieldValue.serverTimestamp();
          break;
        case EscrowTransactionState.disputed:
          updates['disputedAt'] = FieldValue.serverTimestamp();
          break;
        case EscrowTransactionState.refunded:
          await _applyRefundAtomically(
            transaction: transaction,
            dealId: dealId,
            escrow: escrow,
            note: verificationNote,
          );
          updates['refundedAt'] = FieldValue.serverTimestamp();
          break;
        case EscrowTransactionState.fundsReleased:
          updates['fundsReleasedAt'] = FieldValue.serverTimestamp();
          await _applyPayoutAtomically(
            transaction: transaction,
            dealId: dealId,
            escrow: escrow,
            verificationNote: verificationNote,
          );
          break;
        case EscrowTransactionState.fundsLocked:
          break;
      }

      transaction.update(escrowRef, updates);
      transaction.update(_db.collection('deals').doc(dealId), {
        'escrowState': toState.wireValue,
        if (toState == EscrowTransactionState.fundsReleased) 'paymentStatus': 'COMPLETED',
        'lastUpdate': FieldValue.serverTimestamp(),
      });

      _writeAuditLog(
        transaction: transaction,
        dealId: dealId,
        adminId: callerUid,
        oldState: fromState,
        newState: toState,
        note: verificationNote,
      );
    });
  }

  Future<void> triggerDisputeRefund({
    required String dealId,
    required String callerUid,
    String callerRole = '',
    String note = '',
  }) async {
    await _db.runTransaction((transaction) async {
      final escrowRef = _db.collection('escrow_transactions').doc(dealId);
      final escrowSnap = await transaction.get(escrowRef);
      if (!escrowSnap.exists) {
        throw Exception('Escrow record not found');
      }

      final escrow = EscrowModel.fromMap(escrowSnap.data() ?? <String, dynamic>{});
      final fromState = escrow.state;

      final isAdmin = await _isVerifiedAdmin(
        transaction: transaction,
        callerUid: callerUid,
        callerRoleHint: callerRole,
      );

      if (!isAdmin) {
        throw Exception('Security rule simulation failed: caller.role must be ADMIN');
      }

      if (fromState == EscrowTransactionState.fundsReleased) {
        throw Exception('Refund blocked: funds already released');
      }
      if (fromState == EscrowTransactionState.refunded) {
        return;
      }

      await _applyRefundAtomically(
        transaction: transaction,
        dealId: dealId,
        escrow: escrow,
        note: note,
      );

      transaction.update(escrowRef, {
        'state': EscrowTransactionState.refunded.wireValue,
        'disputedAt': FieldValue.serverTimestamp(),
        'refundedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (note.trim().isNotEmpty) 'verificationNote': note.trim(),
      });

      transaction.update(_db.collection('deals').doc(dealId), {
        'escrowState': EscrowTransactionState.refunded.wireValue,
        'paymentStatus': 'REFUNDED',
        'currentStep': 'DEAL_REFUNDED',
        'lastUpdate': FieldValue.serverTimestamp(),
      });

      _writeAuditLog(
        transaction: transaction,
        dealId: dealId,
        adminId: callerUid,
        oldState: fromState,
        newState: EscrowTransactionState.refunded,
        note: note,
      );
    });
  }

  Future<void> _applyPayoutAtomically({
    required Transaction transaction,
    required String dealId,
    required EscrowModel escrow,
    required String verificationNote,
  }) async {
    if (escrow.state != EscrowTransactionState.stockVerified) {
      throw Exception('Payout blocked: escrow must be STOCK_VERIFIED');
    }

    final baseAmount = escrow.baseAmount;
    final buyerFeeCollected = escrow.buyerServiceFee;
    final sellerFeeDeducted = baseAmount * sellerCommissionRate;
    final finalPayoutToSeller = baseAmount - sellerFeeDeducted;
    final totalAdminRevenue = buyerFeeCollected + sellerFeeDeducted;

    final sellerRef = _db.collection('users').doc(escrow.sellerId);
    final adminRef = _db.collection('Admin_Earnings').doc('total_revenue');
    final dealRef = _db.collection('deals').doc(dealId);

    transaction.update(sellerRef, {
      'walletBalance': FieldValue.increment(finalPayoutToSeller),
    });

    transaction.set(
      adminRef,
      {
        'totalCommissionEarned': FieldValue.increment(totalAdminRevenue),
        'dealsProcessed': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    transaction.update(_db.collection('escrow_transactions').doc(dealId), {
      'isReleasedToSeller': true,
      'sellerServiceFee': sellerFeeDeducted,
      'totalAdminEarnings': totalAdminRevenue,
      'finalPayoutToSeller': finalPayoutToSeller,
      'verificationNote': verificationNote.trim().isEmpty ? null : verificationNote.trim(),
    });

    transaction.update(dealRef, {
      'paymentStatus': 'COMPLETED',
      'currentStep': 'DEAL_FINISHED',
      'finishedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _applyRefundAtomically({
    required Transaction transaction,
    required String dealId,
    required EscrowModel escrow,
    required String note,
  }) async {
    final refundAmount = escrow.totalPaidByBuyer > 0 ? escrow.totalPaidByBuyer : escrow.baseAmount;
    final buyerRef = _db.collection('users').doc(escrow.buyerId);
    final dealRef = _db.collection('deals').doc(dealId);

    transaction.update(buyerRef, {
      'walletBalance': FieldValue.increment(refundAmount),
    });

    final buyerHistoryRef = _db
        .collection('users')
        .doc(escrow.buyerId)
        .collection('transactions')
        .doc();
    transaction.set(buyerHistoryRef, {
      'type': 'ESCROW_REFUND',
      'amount': refundAmount,
      'dealId': dealId,
      'status': 'SUCCESS',
      'note': note,
      'timestamp': FieldValue.serverTimestamp(),
    });

    transaction.update(_db.collection('escrow_transactions').doc(dealId), {
      'isReleasedToSeller': false,
      'finalPayoutToSeller': 0,
    });

    transaction.update(dealRef, {
      'paymentStatus': 'REFUNDED',
      'currentStep': 'DEAL_REFUNDED',
      'lastUpdate': FieldValue.serverTimestamp(),
    });
  }

  void _writeAuditLog({
    required Transaction transaction,
    required String dealId,
    required String adminId,
    required EscrowTransactionState oldState,
    required EscrowTransactionState newState,
    required String note,
  }) {
    final logRef = _db.collection('transaction_audit_logs').doc();
    transaction.set(logRef, {
      'dealId': dealId,
      'timestamp': FieldValue.serverTimestamp(),
      'adminId': adminId,
      'oldState': oldState.wireValue,
      'newState': newState.wireValue,
      'note': note.trim(),
    });
  }

  Future<bool> _isVerifiedAdmin({
    required Transaction transaction,
    required String callerUid,
    required String callerRoleHint,
  }) async {
    if (callerUid.trim().isEmpty) return false;

    final userRef = _db.collection('users').doc(callerUid);
    final userSnap = await transaction.get(userRef);
    if (!userSnap.exists) return false;

    final userData = userSnap.data() ?? <String, dynamic>{};
    final role = (userData['role'] ?? callerRoleHint).toString().toLowerCase();
    final isVerified = userData['isVerified'] == true;

    return role == 'admin' && isVerified;
  }

  Future<bool> _isHighRiskBid({
    required Transaction transaction,
    required DocumentReference<Map<String, dynamic>> listingRef,
    required Map<String, dynamic> listingData,
    required String buyerId,
  }) async {
    final finalBidId = (listingData['finalBidId'] ?? '').toString().trim();

    if (finalBidId.isNotEmpty) {
      final bidRef = listingRef.collection('bids').doc(finalBidId);
      final bidSnap = await transaction.get(bidRef);
      if (bidSnap.exists) {
        final bidData = bidSnap.data() ?? <String, dynamic>{};
        return bidData['isSuspicious'] == true;
      }
    }

    final acceptedBidQuery = await listingRef
        .collection('bids')
        .where('buyerId', isEqualTo: buyerId)
        .where('status', isEqualTo: 'accepted')
        .limit(1)
        .get();

    if (acceptedBidQuery.docs.isNotEmpty) {
      final acceptedBid = acceptedBidQuery.docs.first.data();
      return acceptedBid['isSuspicious'] == true;
    }

    return false;
  }

  bool _isAmountClose(double a, double b) {
    final diff = (a - b).abs();
    return diff <= 0.01;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  void debugLog(String message) {}
}
