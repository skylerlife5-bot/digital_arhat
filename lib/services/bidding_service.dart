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

    final double minimumAllowed =
        BidEligibilityService.calculateMinimumAllowedBid(listingData);

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
      throw Exception(
        'Same bid amount already submitted. Please increase your bid.',
      );
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
    String stage = 'init';
    final User? currentUser = FirebaseAuth.instance.currentUser;
    final String sellerUid = currentUser?.uid ?? '';

    debugPrint(
      '[AcceptBid] start seller=$sellerUid listing=$listingId bid=$bidId',
    );
    debugPrint('[AcceptBid] write_mode=batch');

    try {
      if (currentUser == null || sellerUid.isEmpty) {
        throw Exception('Seller must be signed in before accepting a bid');
      }

      final WriteBatch batch = _firestore.batch();
      final DocumentReference<Map<String, dynamic>> listingRef = _firestore
          .collection('listings')
          .doc(listingId);
      final DocumentReference<Map<String, dynamic>> bidRef = listingRef
          .collection('bids')
          .doc(bidId);
      debugPrint('[AcceptBid] path listing=${listingRef.path}');
      debugPrint('[AcceptBid] path bid=${bidRef.path}');

      stage = 'read_listing';
      final listingSnap = await listingRef.get();
      final listingData = listingSnap.data() ?? <String, dynamic>{};
      final String resolvedSellerId =
          (listingData['sellerId'] ?? sellerUid).toString().trim().isEmpty
          ? sellerUid
          : (listingData['sellerId'] ?? sellerUid).toString().trim();
      debugPrint('[AcceptBidContact] sellerId=$resolvedSellerId');

      Map<String, dynamic> sellerProfile = <String, dynamic>{};
      if (resolvedSellerId.isNotEmpty) {
        final sellerSnap = await _firestore
            .collection('users')
            .doc(resolvedSellerId)
            .get();
        sellerProfile = sellerSnap.data() ?? <String, dynamic>{};
      }
      final String sellerPhone = _firstNonEmptyText(
        sellerProfile,
        const <String>[
          'phone',
          'phoneNumber',
          'contact',
          'mobile',
          'contactPhone',
          'sellerPhone',
        ],
      );
      final String resolvedSellerPhone = sellerPhone.isNotEmpty
          ? sellerPhone
          : _firstNonEmptyText(listingData, const <String>[
              'sellerPhone',
              'phone',
              'contactPhone',
            ]);
      final String sellerName = _firstNonEmptyText(
        sellerProfile,
        const <String>['name', 'fullName', 'displayName', 'sellerName'],
      );
      debugPrint('[AcceptBidContact] fetchedSellerPhone=$resolvedSellerPhone');

      debugPrint('[AcceptBid] listing_snapshot_exists=${listingSnap.exists}');
      debugPrint(
        '[AcceptBid] listing_snapshot_status=${(listingData['status'] ?? '').toString()}',
      );

      final nowUtc = DateTime.now().toUtc();
      final DateTime? endTime =
          _toDate(listingData['endTime'])?.toUtc() ??
          _toDate(listingData['bidExpiryTime'])?.toUtc();
      final bool forceClosed = listingData['isBidForceClosed'] == true;
      if (endTime != null && nowUtc.isBefore(endTime) && !forceClosed) {
        debugPrint(
          '[AcceptBid] pre_end_accept_override=true endTime=$endTime now=$nowUtc',
        );
      }

      final existingAcceptedBidId = (listingData['acceptedBidId'] ?? '')
          .toString()
          .trim();
      if (existingAcceptedBidId.isNotEmpty && existingAcceptedBidId != bidId) {
        throw Exception('Is listing par ek bid pehle hi accept ho chuki hai');
      }

      stage = 'top_bid_scan';
      final QuerySnapshot<Map<String, dynamic>> allBidsSnap = await listingRef
          .collection('bids')
          .get();
      debugPrint(
        '[AcceptBid] top_bid_scan_count=${allBidsSnap.docs.length} requested_bid=$bidId',
      );
      if (allBidsSnap.docs.isEmpty) {
        throw Exception('Accept karne ke liye koi valid top bid mojood nahi');
      }

      final sortedBids = allBidsSnap.docs.toList()
        ..sort((a, b) {
          final double amountA = _toDouble(a.data()['bidAmount']) ?? 0.0;
          final double amountB = _toDouble(b.data()['bidAmount']) ?? 0.0;
          final int amountCompare = amountB.compareTo(amountA);
          if (amountCompare != 0) return amountCompare;

          final DateTime timeA =
              _toDate(a.data()['timestamp']) ??
              _toDate(a.data()['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final DateTime timeB =
              _toDate(b.data()['timestamp']) ??
              _toDate(b.data()['createdAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final int timeCompare = timeB.compareTo(timeA);
          if (timeCompare != 0) return timeCompare;

          return b.id.compareTo(a.id);
        });

      if (sortedBids.first.id != bidId) {
        throw Exception('Sirf sab se unchi bid ko accept kiya ja sakta hai');
      }

      stage = 'read_selected_bid';
      final bidSnap = await bidRef.get();
      if (!bidSnap.exists) throw Exception('Boli ka record nahi mila');

      final Map<String, dynamic> bidData =
          bidSnap.data() ?? <String, dynamic>{};
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

      final currentBidStatus = (bidData['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (currentBidStatus == 'rejected') {
        throw Exception(
          'Rejection ke baad is bid ko accept nahi kiya ja sakta',
        );
      }

      debugPrint(
        '[AcceptBid] bid_snapshot buyerId=$buyerId bidAmount=$bidAmount status=$currentBidStatus sellerInBid=${(bidData['sellerId'] ?? '').toString()}',
      );

      final double commissionPerSide = bidAmount * 0.01;
      final double buyerTotal = bidAmount + commissionPerSide;
      final double sellerReceivable = bidAmount - commissionPerSide;
      final double totalAppCommission = commissionPerSide * 2;

      final DocumentReference<Map<String, dynamic>> dealRef = _firestore
          .collection('deals')
          .doc();
      final newDeal = DealModel(
        dealId: dealRef.id,
        listingId: listingId,
        sellerId: resolvedSellerId,
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

      final Map<String, dynamic> dealPayload = {
        ...newDeal.toMap(),
        'status': 'bid_accepted',
        'dealStatus': 'bid_accepted',
        'acceptedBidId': bidId,
        'acceptedBuyerUid': buyerId,
        'acceptedAt': FieldValue.serverTimestamp(),
        'contactUnlocked': true,
        'sellerPhone': resolvedSellerPhone,
        'sellerName': sellerName,
        'buyerNextAction': 'contact_seller',
        'currentStep': 'BID_ACCEPTED',
        'lastUpdated': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final Map<String, dynamic> bidUpdatePayload = {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
      };

      final Map<String, dynamic> listingUpdatePayload = {
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
        'sellerPhone': resolvedSellerPhone,
        'sellerName': sellerName,
        'buyerId': buyerId,
        'finalPrice': bidAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      debugPrint('[AcceptBid] deal_create_payload=$dealPayload');
      debugPrint('[AcceptBid] bid_update_payload=$bidUpdatePayload');
      debugPrint('[AcceptBid] listing_update_payload=$listingUpdatePayload');

      stage = 'queue_deal_create';
      debugPrint('[AcceptBid] write_stage=$stage path=${dealRef.path}');
      batch.set(dealRef, dealPayload);

      stage = 'queue_bid_update';
      debugPrint('[AcceptBid] write_stage=$stage path=${bidRef.path}');
      batch.update(bidRef, bidUpdatePayload);

      stage = 'queue_listing_update';
      debugPrint('[AcceptBid] write_stage=$stage path=${listingRef.path}');
      batch.update(listingRef, listingUpdatePayload);

      stage = 'read_other_bids';
      final QuerySnapshot<Map<String, dynamic>> otherBids = await listingRef
          .collection('bids')
          .get();
      debugPrint('[AcceptBid] other_bids_count=${otherBids.docs.length}');

      for (final doc in otherBids.docs) {
        if (doc.id != bidId) {
          final data = doc.data();
          final status = (data['status'] ?? '').toString().trim().toLowerCase();
          if (status != 'rejected' &&
              status != 'accepted' &&
              status != 'bid_accepted') {
            stage = 'queue_other_bid_reject';
            debugPrint(
              '[AcceptBid] write_stage=$stage path=${doc.reference.path} payload={status: rejected}',
            );
            batch.update(doc.reference, {'status': 'rejected'});
          }
        }
      }

      stage = 'batch_commit';
      debugPrint('[AcceptBid] write_stage=$stage');
      await batch.commit();
      debugPrint(
        '[AcceptBid] batch_commit_success listing=$listingId bid=$bidId',
      );

      final sellerId = resolvedSellerId;
      stage = 'notifications';
      debugPrint(
        '[AcceptBid] notification_payload={buyerId: $buyerId, sellerId: $sellerId, listingId: $listingId, bidId: $bidId}',
      );
      await _sendBidAcceptedNotifications(
        listingId: listingId,
        bidId: bidId,
        buyerId: buyerId,
        sellerId: sellerId,
      );
      debugPrint(
        '[AcceptBid] success seller=$sellerUid listing=$listingId bid=$bidId',
      );
    } on FirebaseException catch (e, st) {
      debugPrint(
        '[AcceptBid] ERROR stage=$stage code=${e.code} message=${e.message ?? ''} details=${e.toString()}',
      );
      debugPrint('[AcceptBid] STACKTRACE $st');
      throw Exception('Deal process fail: ${e.toString()}');
    } catch (e, st) {
      debugPrint('[AcceptBid] ERROR stage=$stage message=${e.toString()}');
      debugPrint('[AcceptBid] STACKTRACE $st');
      throw Exception('Deal process fail: ${e.toString()}');
    }
  }

  // --- HELPER FUNCTIONS & STREAMS ---

  Future<void> _sendBidAcceptedNotifications({
    required String listingId,
    required String bidId,
    required String buyerId,
    required String sellerId,
  }) async {
    debugPrint(
      '[AcceptBid] write_stage=notification_buyer_create path=notifications/{eventKey} payload={toUid: $buyerId, type: ${Phase1NotificationType.bidAccepted}, listingId: $listingId, bidId: $bidId, targetRole: buyer}',
    );
    await _phase1Notifications.createOnce(
      userId: buyerId,
      type: Phase1NotificationType.bidAccepted,
      listingId: listingId,
      bidId: bidId,
      targetRole: 'buyer',
    );

    if (sellerId.isNotEmpty) {
      debugPrint(
        '[AcceptBid] write_stage=notification_seller_create path=notifications/{eventKey} payload={toUid: $sellerId, type: ${Phase1NotificationType.bidAcceptedConfirmation}, listingId: $listingId, bidId: $bidId, targetRole: seller}',
      );
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

  String _firstNonEmptyText(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }
}
