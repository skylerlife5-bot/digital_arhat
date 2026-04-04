import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuctionLifecycleService {
  AuctionLifecycleService({FirebaseFirestore? db, FirebaseAuth? auth})
    : _db = db ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  Future<void> finalizeAuctionIfEnded({
    required String listingId,
    bool force = false,
    String source = 'client',
  }) async {
    final id = listingId.trim();
    if (id.isEmpty) return;

    final listingRef = _db.collection('listings').doc(id);
    final listingSnap = await listingRef.get();
    if (!listingSnap.exists) return;

    final listing = listingSnap.data() ?? <String, dynamic>{};
    final now = DateTime.now().toUtc();
    final endTime =
        _toDate(listing['endTime'])?.toUtc() ??
        _toDate(listing['bidExpiryTime'])?.toUtc() ??
        _toDate(listing['startTime'])?.toUtc().add(const Duration(hours: 24));

    final status = _normalizeStatus(
      listing['status'] ?? listing['listingStatus'] ?? listing['auctionStatus'],
    );
    final auctionStatus = _normalizeStatus(listing['auctionStatus']);

    final alreadyTerminal =
        _terminalStatuses.contains(status) ||
        _terminalStatuses.contains(auctionStatus);
    if (!force && alreadyTerminal) {
      return;
    }
    if (!force && (endTime == null || now.isBefore(endTime))) {
      return;
    }

    final bidsRef = listingRef.collection('bids');
    final topBidSnap = await bidsRef
        .orderBy('bidAmount', descending: true)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    final batch = _db.batch();
    if (topBidSnap.docs.isEmpty) {
      batch.set(listingRef, {
        'status': 'expired_unsold',
        'listingStatus': 'expired_unsold',
        'auctionStatus': 'expired_unsold',
        'isBidForceClosed': true,
        'bidClosedAt': FieldValue.serverTimestamp(),
        'contactUnlocked': false,
        'winnerId': null,
        'buyerId': null,
        'finalBidId': null,
        'acceptedBidId': null,
        'acceptedBuyerUid': null,
        'dealOutcomeStatus': 'no_bids',
        'auctionCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await batch.commit();
      await _writeAudit(
        listingId: id,
        actionType: 'auction_auto_expired_no_bids',
        source: source,
        note: 'Auction finalized without bids',
      );
      return;
    }

    final topBidDoc = topBidSnap.docs.first;
    final topBid = topBidDoc.data();
    final winnerId = (topBid['buyerId'] ?? '').toString().trim();
    final finalPrice = _toDouble(topBid['bidAmount']) > 0
        ? _toDouble(topBid['bidAmount'])
        : (_toDouble(listing['highestBid']) > 0
              ? _toDouble(listing['highestBid'])
              : _toDouble(listing['price']));

    batch.set(listingRef, {
      'status': 'ended_waiting_seller',
      'listingStatus': 'ended_waiting_seller',
      'auctionStatus': 'ended_waiting_seller',
      'isBidForceClosed': true,
      'bidClosedAt': FieldValue.serverTimestamp(),
      // Highest bid becomes seller-visible top candidate only.
      'topCandidateBuyerUid': winnerId,
      'topCandidateBidId': topBidDoc.id,
      'topCandidateBidAmount': finalPrice,
      'winnerId': null,
      'buyerId': null,
      'finalBidId': topBidDoc.id,
      'acceptedBidId': null,
      'acceptedBuyerUid': null,
      'finalPrice': finalPrice,
      'contactUnlocked': false,
      'dealOutcomeStatus': 'pending_contact',
      'auctionCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    batch.set(topBidDoc.reference, {
      'status': 'leading_candidate',
      'candidateAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final activeBids = await bidsRef
        .where('status', whereIn: const <String>['pending', 'warned'])
        .limit(80)
        .get();
    for (final doc in activeBids.docs) {
      if (doc.id == topBidDoc.id) continue;
      batch.set(doc.reference, {
        'status': 'ended_outbid',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    await batch.commit();
    await _writeAudit(
      listingId: id,
      actionType: 'auction_auto_ended_waiting_seller',
      source: source,
      note: 'Top candidate set as $winnerId with bid ${topBidDoc.id}',
    );
  }

  Future<void> updateDealOutcome({
    required String listingId,
    required String outcomeStatus,
    String note = '',
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Please sign in first.');
    }

    final normalized = outcomeStatus.trim().toLowerCase();
    if (!_allowedOutcomeStatuses.contains(normalized)) {
      throw Exception('Invalid deal outcome status.');
    }

    final normalizedListingId = listingId.trim();
    if (normalizedListingId.isEmpty) {
      throw Exception('Listing not found.');
    }

    final listingRef = _db.collection('listings').doc(normalizedListingId);
    final listingSnap = await listingRef.get();
    if (!listingSnap.exists) {
      throw Exception('Listing not found.');
    }

    final listing = listingSnap.data() ?? <String, dynamic>{};
    final sellerId = (listing['sellerId'] ?? '').toString().trim();

    final callerUid = user.uid;
    final callerIsSeller = callerUid == sellerId;
    final callerIsAdmin = await _isAdmin(callerUid);

    if (!callerIsSeller && !callerIsAdmin) {
      throw Exception('Only listing seller can update this deal outcome.');
    }

    final dealRef = await _resolveDealRef(
      listingId: listingId,
      listing: listing,
    );

    final batch = _db.batch();
    final outcomePayload = <String, dynamic>{
      'outcomeStatus': normalized,
      'outcomeNote': note.trim(),
      'outcomeUpdatedBy': callerUid,
      'outcomeUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    batch.set(listingRef, {
      'dealOutcomeStatus': normalized,
      'dealOutcomeNote': note.trim(),
      'dealOutcomeUpdatedBy': callerUid,
      'dealOutcomeUpdatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (dealRef != null) {
      batch.set(dealRef, outcomePayload, SetOptions(merge: true));
    }

    await batch.commit();

    if (callerIsAdmin) {
      await _writeAudit(
        listingId: normalizedListingId,
        actionType: 'admin_update_deal_outcome',
        source: 'admin_ui',
        note: 'Outcome set to $normalized',
      );
    }
  }

  Future<DocumentReference<Map<String, dynamic>>?> _resolveDealRef({
    required String listingId,
    required Map<String, dynamic> listing,
  }) async {
    final sellerId = (listing['sellerId'] ?? '').toString().trim();
    final buyerId = (
      listing['buyerId'] ?? listing['acceptedBuyerUid'] ?? listing['winnerId'] ?? ''
    ).toString().trim();
    final dealId = (listing['dealId'] ?? '').toString().trim();
    if (dealId.isNotEmpty) {
      final dealRef = _db.collection('deals').doc(dealId);
      final dealSnap = await dealRef.get();
      if (dealSnap.exists) {
        final deal = dealSnap.data() ?? <String, dynamic>{};
        final dealSellerId = (deal['sellerId'] ?? '').toString().trim();
        final dealListingId = (deal['listingId'] ?? '').toString().trim();
        if (dealSellerId == sellerId && dealListingId == listingId) {
          return dealRef;
        }
      }
    }

    Query<Map<String, dynamic>> query = _db
        .collection('deals')
        .where('listingId', isEqualTo: listingId)
        .where('sellerId', isEqualTo: sellerId);
    if (buyerId.isNotEmpty) {
      query = query.where('buyerId', isEqualTo: buyerId);
    }

    final snap = await query.orderBy('createdAt', descending: true).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.reference;
  }

  Future<bool> _isAdmin(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final user = userSnap.data() ?? <String, dynamic>{};
    final role = (user['role'] ?? user['userRole'] ?? user['userType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'admin';
  }

  Future<void> _writeAudit({
    required String listingId,
    required String actionType,
    required String source,
    required String note,
  }) async {
    await _db.collection('admin_action_logs').add({
      'entityType': 'listing',
      'entityId': listingId,
      'actionType': actionType,
      'actionBy': source,
      'actionAt': FieldValue.serverTimestamp(),
      'targetCollection': 'listings',
      'targetDocId': listingId,
      'notes': note,
      'result': 'success',
    });
  }

  static const Set<String> _terminalStatuses = <String>{
    'expired',
    'expired_unsold',
    'ended',
    'ended_waiting_seller',
    'closed',
    'cancelled',
    'canceled',
    'rejected',
    'bid_accepted',
    'completed',
  };

  static const Set<String> _allowedOutcomeStatuses = <String>{
    'pending_contact',
    'successful',
    'failed',
    'cancelled',
    'disputed',
    'no_bids',
  };

  String _normalizeStatus(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0.0;
  }
}
