import 'package:cloud_firestore/cloud_firestore.dart';
import '../bidding/bid_model.dart';
import '../core/security_filter.dart';
import '../deals/deal_model.dart';
import '../models/deal_status.dart' as deal_status;
import '../services/marketplace_service.dart';

class BiddingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final MarketplaceService _marketplaceService = MarketplaceService();

  // --- BUYER SIDE: SMART BIDDING ---

  /// �S& Smart Bid Placement with AI Fraud Check & Outbid Alerts
  Future<void> placeSmartBid({
    required BidModel bid,
    double marketPrice = 0.0,
  }) async {
    final String listingId = bid.listingId.trim();
    final String buyerId = bid.buyerId.trim();

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
    final double startingPrice =
        _toDouble(listingData['startingPrice']) ??
        _toDouble(listingData['basePrice']) ??
        _toDouble(listingData['price']) ??
        0.0;
    final double currentHighest =
        _toDouble(listingData['highestBid']) ?? startingPrice;
    final double minimumAllowed = currentHighest > startingPrice
        ? currentHighest
        : startingPrice;

    if (bid.bidAmount <= minimumAllowed) {
      throw Exception(
        'Validation Failed: Bid must be higher than current highest or starting price.',
      );
    }

    final normalizedBid = BidModel(
      bidId: bid.bidId,
      listingId: listingId,
      sellerId: bid.sellerId,
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
    );
  }

  // --- SELLER SIDE: DEAL MANAGEMENT ---

  /// �S& Accept Bid & Start Escrow (Amanat Pending)
  Future<void> acceptBid(String bidId, String listingId) async {
    try {
      WriteBatch batch = _firestore.batch();
      DocumentReference listingRef = _firestore
          .collection('listings')
          .doc(listingId);
      DocumentReference bidRef = listingRef.collection('bids').doc(bidId);

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
        throw Exception('Bid data invalid hai. د��بارہ ک��شش کر�Rں');
      }

      // �x� Commission Logic (1% from Buyer + 1% from Seller)
      double commissionPerSide = bidAmount * 0.01;
      double buyerTotal = bidAmount + commissionPerSide;
      double sellerReceivable = bidAmount - commissionPerSide;
      double totalAppCommission = commissionPerSide * 2;

      // Create Deal record
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
        status: deal_status.DealStatus.awaitingPayment.value,
        createdAt: DateTime.now(),
      );

      batch.set(dealRef, {
        ...newDeal.toMap(),
        'paymentStatus': 'PENDING_ADMIN_APPROVAL',
        'escrowState': 'PENDING',
        'currentStep': 'PENDING_ADMIN_APPROVAL',
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      batch.update(bidRef, {'status': 'accepted'});

      // Update Listing to Escrow status
      batch.update(listingRef, {
        'status': deal_status.DealStatus.pendingAdminApproval.name,
        'listingStatus': deal_status.DealStatus.pendingAdminApproval.name,
        'auctionStatus': deal_status.DealStatus.pendingAdminApproval.name,
        'escrowStatus': 'PENDING_PAYMENT',
        'isBidForceClosed': true,
        'bidClosedAt': FieldValue.serverTimestamp(),
        'winnerId': buyerId,
        'finalBidId': bidId,
        'dealId': dealRef.id,
        'buyerId': buyerId,
        'finalPrice': bidAmount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Reject other competing bids
      QuerySnapshot otherBids = await _firestore
          .collection('listings')
          .doc(listingId)
          .collection('bids')
          .where('status', isEqualTo: 'pending')
          .get();

      for (var doc in otherBids.docs) {
        if (doc.id != bidId) {
          batch.update(doc.reference, {'status': 'rejected'});
        }
      }

      await batch.commit();

      // �x Winning Notification
      _sendWinningNotification(buyerId, bidAmount);
    } catch (e) {
      throw Exception("Deal process fail: ${e.toString()}");
    }
  }

  // --- HELPER FUNCTIONS & STREAMS ---

  void _sendWinningNotification(String buyerId, double amount) async {
    final title = SecurityFilter.maskAll('Mubarak ho! Boli Qabool ho gayi �x}`');
    final body = SecurityFilter.maskAll(
      'Rs. $amount ki boli qabool kar li gayi hai. Admin approval ka intezar karein.',
    );
    await _firestore.collection('notifications').add({
      'userId': buyerId,
      'title': title,
      'body': body,
      'type': 'BID_ACCEPTED',
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });
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
}

