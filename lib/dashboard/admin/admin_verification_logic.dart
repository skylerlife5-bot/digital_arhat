import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class AdminVerificationLogic {
  AdminVerificationLogic({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> confirmPayment({
    required String listingId,
    required Map<String, dynamic> listingData,
  }) async {
    final buyerId = (listingData['winnerId'] ?? listingData['buyerId'] ?? '')
        .toString()
        .trim();
    final sellerId = (listingData['sellerId'] ?? '').toString().trim();
    final dealId = (listingData['dealId'] ?? '').toString().trim();
    final bidAmount = _resolveBidAmount(listingData);

    final batch = _db.batch();

    batch.set(_db.collection('listings').doc(listingId), {
      'status': 'escrow_confirmed',
      'listingStatus': 'escrow_confirmed',
      'auctionStatus': 'escrow_confirmed',
      'paymentStatus': 'verified',
      'escrowStatus': 'ESCROW_CONFIRMED',
      'isChatActive': true,
      'paymentVerifiedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (dealId.isNotEmpty) {
      batch.set(_db.collection('deals').doc(dealId), {
        'status': 'escrow_confirmed',
        'paymentStatus': 'verified',
        'isChatActive': true,
        'currentStep': 'ESCROW_CONFIRMED',
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (bidAmount > 0) {
      batch.set(_db.collection('Admin_Earnings').doc('total_revenue'), {
        'totalCommissionEarned': FieldValue.increment(bidAmount * 0.02),
        'paymentsVerified': FieldValue.increment(1),
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (buyerId.isNotEmpty) {
      const buyerMessage =
          'Your payment has been verified. Seller is notified to ship.';
      batch.set(_db.collection('notifications').doc(), {
        'userId': buyerId,
        'title': buyerMessage,
        'body': buyerMessage,
        'type': 'buyer_payment_verified',
        'listingId': listingId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    if (sellerId.isNotEmpty) {
      const sellerMessage =
          'Payment Verified! You can now safely dispatch the product.';
      batch.set(_db.collection('notifications').doc(), {
        'userId': sellerId,
        'title': sellerMessage,
        'body': sellerMessage,
        'type': 'seller_dispatch_ready',
        'listingId': listingId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    await batch.commit();

    if (buyerId.isNotEmpty) {
      await _enqueueFcmPlaceholder(
        type: 'buyer_payment_verified',
        targetUserId: buyerId,
        listingId: listingId,
        title: 'Your payment has been verified. Seller is notified to ship.',
        body: 'Your payment has been verified. Seller is notified to ship.',
      );
    }

    if (sellerId.isNotEmpty) {
      await _enqueueFcmPlaceholder(
        type: 'seller_dispatch_ready',
        targetUserId: sellerId,
        listingId: listingId,
        title: 'Payment Verified! You can now safely dispatch the product.',
        body: 'Payment Verified! You can now safely dispatch the product.',
      );
    }
  }

  Future<void> rejectPayment({
    required String listingId,
    required Map<String, dynamic> listingData,
    required String reason,
  }) async {
    final buyerId = (listingData['winnerId'] ?? listingData['buyerId'] ?? '')
        .toString()
        .trim();
    final dealId = (listingData['dealId'] ?? '').toString().trim();

    final batch = _db.batch();

    batch.set(_db.collection('listings').doc(listingId), {
      'status': 'payment_rejected',
      'listingStatus': 'payment_rejected',
      'auctionStatus': 'awaiting_payment',
      'paymentStatus': 'rejected',
      'escrowStatus': 'PENDING_PAYMENT',
      'isChatActive': false,
      'paymentReceiptUrl': '',
      'paymentScreenshotUrl': '',
      'receiptUploadedAt': FieldValue.delete(),
      'adminRejectionReason': reason,
      'paymentRejectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (dealId.isNotEmpty) {
      batch.set(_db.collection('deals').doc(dealId), {
        'status': 'payment_rejected',
        'paymentStatus': 'rejected',
        'isChatActive': false,
        'currentStep': 'AWAITING_PAYMENT',
        'paymentReceiptUrl': '',
        'receiptUploadedAt': FieldValue.delete(),
        'adminRejectionReason': reason,
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (buyerId.isNotEmpty) {
      final buyerMessage =
          'Your receipt was rejected: $reason. Please upload again.';
      batch.set(_db.collection('notifications').doc(), {
        'userId': buyerId,
        'title': buyerMessage,
        'body': buyerMessage,
        'type': 'buyer_receipt_rejected',
        'listingId': listingId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    await batch.commit();

    if (buyerId.isNotEmpty) {
      await _enqueueFcmPlaceholder(
        type: 'buyer_receipt_rejected',
        targetUserId: buyerId,
        listingId: listingId,
        title: 'Your receipt was rejected: $reason. Please upload again.',
        body: 'Your receipt was rejected: $reason. Please upload again.',
      );
    }
  }

  Future<void> _enqueueFcmPlaceholder({
    required String type,
    required String targetUserId,
    required String listingId,
    required String title,
    required String body,
  }) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await _db.collection('notification_dispatch_queue').add({
        'type': type,
        'targetUserId': targetUserId,
        'listingId': listingId,
        'title': title,
        'body': body,
        'tokenPlaceholder': token,
        'provider': 'fcm',
        'status': 'queued',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      return;
    }
  }

  double _resolveBidAmount(Map<String, dynamic> data) {
    final finalPrice = _toDouble(data['finalPrice']);
    if (finalPrice > 0) return finalPrice;

    final winningBid = _toDouble(data['winningBid']);
    if (winningBid > 0) return winningBid;

    final highestBid = _toDouble(data['highestBid']);
    if (highestBid > 0) return highestBid;

    return _toDouble(data['price']);
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
