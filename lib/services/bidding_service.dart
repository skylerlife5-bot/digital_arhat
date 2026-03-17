import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../bidding/bid_model.dart';
import '../deals/deal_model.dart';
import '../services/marketplace_service.dart';
import 'bid_eligibility_service.dart';
import 'phase1_notification_engine.dart';

class BiddingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MarketplaceService _marketplaceService = MarketplaceService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();

  // --- BUYER SIDE: SMART BIDDING ---

  /// �S& Smart Bid Placement with AI Fraud Check & Outbid Alerts
  Future<void> placeSmartBid({
    required BidModel bid,
    double marketPrice = 0.0,
    Map<String, dynamic>? aiMeta,
  }) async {
    final String listingId = bid.listingId.trim();
    final User? authUser = FirebaseAuth.instance.currentUser;
    final String writePath = 'listings/$listingId/bids/{bidId}';

    debugPrint(
      '[BidFlow] ui_submit_guard currentUser=${authUser == null ? 'null' : 'present'} uid=${authUser?.uid ?? 'null'} listing=$listingId writePath=$writePath',
    );

    if (authUser == null) {
      throw Exception('Please sign in to place a bid.');
    }

    final String buyerId = authUser.uid;
    if (bid.buyerId.trim().isNotEmpty && bid.buyerId.trim() != buyerId) {
      debugPrint(
        '[BidFlow] buyer_uid_mismatch passed=${bid.buyerId.trim()} auth=$buyerId listing=$listingId',
      );
    }

    if (buyerId.isEmpty || listingId.isEmpty || bid.bidAmount <= 0) {
      throw Exception(
        'Validation Failed: buyerId, listingId, bidAmount required',
      );
    }

    final listingSnap = await _firestore
        .collection('listings')
        .doc(listingId)
        .get();
    if (!listingSnap.exists) {
      throw Exception('Validation Failed: listing not found');
    }

    final Map<String, dynamic> listingData =
        listingSnap.data() ?? <String, dynamic>{};
    final eligibility = BidEligibilityService.evaluate(
      buyerId: buyerId,
      listingData: listingData,
      bidAmount: bid.bidAmount,
    );
    if (!eligibility.allowed) {
      throw Exception(eligibility.message);
    }

    // Targeted trace for mismatch debugging between UI and service checks.
    debugPrint(
      '[BidFlow] placeSmartBid listing=$listingId buyer=$buyerId amount=${bid.bidAmount.toStringAsFixed(2)} min=${eligibility.minimumAllowedBid?.toStringAsFixed(2) ?? 'n/a'}',
    );

    final String sellerId = (listingData['sellerId'] ?? bid.sellerId)
      .toString()
      .trim();
    if (sellerId.isNotEmpty && sellerId == buyerId) {
      throw Exception('Seller apni listing par bid nahi laga sakta.');
    }

    final double minimumAllowed = BidEligibilityService.calculateMinimumAllowedBid(
      listingData,
    );

    if (bid.bidAmount < minimumAllowed) {
      throw Exception(
      'Validation Failed: Bid must be at least Rs. ${minimumAllowed.toStringAsFixed(0)}.',
      );
    }

    final sameBidSnap = await _firestore
      .collection('listings')
      .doc(listingId)
      .collection('bids')
      .where('buyerId', isEqualTo: buyerId)
      .where('bidAmount', isEqualTo: bid.bidAmount)
      .where('status', whereIn: const <String>['pending', 'warned'])
      .limit(1)
      .get();
    if (sameBidSnap.docs.isNotEmpty) {
      throw Exception('Same bid amount already submitted. Please increase your bid.');
    }

    final normalizedBid = BidModel(
      bidId: bid.bidId,
      listingId: listingId,
      sellerId: sellerId,
      buyerId: buyerId,
      buyerName: bid.buyerName,
      buyerPhone: bid.buyerPhone,
      productName: bid.productName,
      bidAmount: bid.bidAmount,
      status: 'pending',
      createdAt: bid.createdAt,
    );

    await _marketplaceService.placeBid(
      bid: normalizedBid,
      marketPrice: marketPrice,
      aiMeta: aiMeta,
    );
  }

  // --- SELLER SIDE: DEAL MANAGEMENT ---

  /// Accept bid for Phase-1 flow (no escrow/payment/admin-deal-approval).
  Future<void> acceptBid(String bidId, String listingId) async {
    try {
      WriteBatch batch = _firestore.batch();
      DocumentReference listingRef = _firestore
          .collection('listings')
          .doc(listingId);
      DocumentReference bidRef = listingRef.collection('bids').doc(bidId);

      final listingSnap = await listingRef.get();
      final listingData = listingSnap.data() as Map<String, dynamic>? ??
          <String, dynamic>{};
      final nowUtc = DateTime.now().toUtc();
      final DateTime? endTime =
          _toDate(listingData['endTime'])?.toUtc() ??
          _toDate(listingData['bidExpiryTime'])?.toUtc();
      final bool forceClosed = listingData['isBidForceClosed'] == true;
      if (endTime != null && nowUtc.isBefore(endTime) && !forceClosed) {
        throw Exception('Auction ابھی ختم نہیں ہوئی، قبولیت اختتام کے بعد ہوگی');
      }

      final existingAcceptedBidId =
          (listingData['acceptedBidId'] ?? '').toString().trim();
      if (existingAcceptedBidId.isNotEmpty && existingAcceptedBidId != bidId) {
        throw Exception('Is listing par ek bid pehle hi accept ho chuki hai');
      }

      final topBidSnap = await listingRef
          .collection('bids')
          .orderBy('bidAmount', descending: true)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (topBidSnap.docs.isEmpty) {
        throw Exception('Accept karne ke liye koi valid top bid mojood nahi');
      }
      if (topBidSnap.docs.first.id != bidId) {
        throw Exception('Sirf sab se unchi bid ko accept kiya ja sakta hai');
      }

      DocumentSnapshot bidSnap = await bidRef.get();
      if (!bidSnap.exists) throw Exception("Boli ka record nahi mila");

      final Map<String, dynamic> bidData =
          bidSnap.data() as Map<String, dynamic>? ?? <String, dynamic>{};
      final double bidAmount =
          _toDouble(
            bidData.containsKey('bidAmount') ? bidData['bidAmount'] : null,
          ) ??
          0.0;
      final String buyerId = bidData.containsKey('buyerId')
          ? (bidData['buyerId']?.toString() ?? '')
          : '';

      if (bidAmount <= 0 || buyerId.isEmpty) {
        throw Exception('Bid data invalid hai. دوبارہ کوشش کریں');
      }

      final currentBidStatus =
          (bidData['status'] ?? '').toString().trim().toLowerCase();
      if (currentBidStatus == 'rejected') {
        throw Exception('Rejection ke baad is bid ko accept nahi kiya ja sakta');
      }

      // �x� Commission Logic (1% from Buyer + 1% from Seller)
      double commissionPerSide = bidAmount * 0.01;
      double buyerTotal = bidAmount + commissionPerSide;
      double sellerReceivable = bidAmount - commissionPerSide;
      double totalAppCommission = commissionPerSide * 2;

      // Create deal record with a simple accepted state for Phase-1.
      DocumentReference dealRef = _firestore.collection('deals').doc();
      final newDeal = DealModel(
        dealId: dealRef.id,
        listingId: listingId,
        sellerId: bidData.containsKey('sellerId')
            ? (bidData['sellerId']?.toString() ?? '')
            : '',
        buyerId: buyerId,
        productName: bidData.containsKey('productName')
            ? (bidData['productName']?.toString() ?? 'Fasal')
            : 'Fasal',
        dealAmount: bidAmount,
        buyerTotal: buyerTotal,
        sellerReceivable: sellerReceivable,
        appCommission: totalAppCommission,
        status: 'bid_accepted',
        createdAt: DateTime.now(),
      );

      batch.set(dealRef, {
        ...newDeal.toMap(),
        'status': 'bid_accepted',
        'dealStatus': 'bid_accepted',
        'acceptedBidId': bidId,
        'acceptedBuyerUid': buyerId,
        'acceptedAt': FieldValue.serverTimestamp(),
        'contactUnlocked': true,
        'buyerNextAction': 'contact_seller',
        'currentStep': 'BID_ACCEPTED',
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      batch.update(bidRef, {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      });

      // Update listing to accepted state and unlock direct contact.
      batch.update(listingRef, {
        'status': 'bid_accepted',
        'listingStatus': 'bid_accepted',
        'auctionStatus': 'bid_accepted',
        'isBidForceClosed': true,
        'bidClosedAt': FieldValue.serverTimestamp(),
        'winnerId': buyerId,
        'finalBidId': bidId,
        'acceptedBidId': bidId,
        'acceptedBuyerUid': buyerId,
        'acceptedAt': FieldValue.serverTimestamp(),
        'contactUnlocked': true,
        'dealId': dealRef.id,
        'buyerId': buyerId,
        'finalPrice': bidAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reject all non-winning bids so only one accepted bidder remains actionable.
      QuerySnapshot otherBids = await _firestore
          .collection('listings')
          .doc(listingId)
          .collection('bids')
          .get();

      for (var doc in otherBids.docs) {
        if (doc.id != bidId) {
          final data = doc.data() as Map<String, dynamic>? ??
              <String, dynamic>{};
          final status = (data['status'] ?? '').toString().trim().toLowerCase();
          if (status != 'rejected' && status != 'accepted' && status != 'bid_accepted') {
            batch.update(doc.reference, {'status': 'rejected'});
          }
        }
      }

      await batch.commit();

      final sellerId = (bidData['sellerId'] ?? '').toString().trim();
      await _sendBidAcceptedNotifications(
        listingId: listingId,
        bidId: bidId,
        buyerId: buyerId,
        sellerId: sellerId,
      );
    } catch (e) {
      throw Exception("Deal process fail: ${e.toString()}");
    }
  }

  // --- HELPER FUNCTIONS & STREAMS ---

  Future<void> _sendBidAcceptedNotifications({
    required String listingId,
    required String bidId,
    required String buyerId,
    required String sellerId,
  }) async {
    await _phase1Notifications.createOnce(
      userId: buyerId,
      type: Phase1NotificationType.bidAccepted,
      listingId: listingId,
      bidId: bidId,
      targetRole: 'buyer',
    );

    if (sellerId.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerId,
        type: Phase1NotificationType.bidAcceptedConfirmation,
        listingId: listingId,
        bidId: bidId,
        targetRole: 'seller',
      );
    }
  }

  Stream<DocumentSnapshot> getLiveListing(String listingId) {
    return _firestore.collection('listings').doc(listingId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getLiveBidsForListing(
    String listingId,
  ) {
    return _firestore
        .collectionGroup('bids')
        .where('listingId', isEqualTo: listingId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}

