import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BuyerEngagementService {
  BuyerEngagementService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String? get _uid => _auth.currentUser?.uid;

  CollectionReference<Map<String, dynamic>> _watchlistCollection(String uid) {
    return _db.collection('users').doc(uid).collection('watchlist');
  }

  CollectionReference<Map<String, dynamic>> _recentlyViewedCollection(String uid) {
    return _db.collection('users').doc(uid).collection('recentlyViewed');
  }

  Stream<bool> isListingSavedStream(String listingId) {
    final uid = _uid;
    if (uid == null || listingId.trim().isEmpty) {
      return Stream<bool>.value(false);
    }
    return _watchlistCollection(uid)
        .doc(listingId.trim())
        .snapshots()
        .map((doc) => doc.exists);
  }

  Stream<int> watchlistCountStream() {
    final uid = _uid;
    if (uid == null) return Stream<int>.value(0);
    return _watchlistCollection(uid)
        .orderBy('savedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((snap) => snap.docs.length);
  }

  Stream<int> listingWatchersCountStream(String listingId) {
    final normalizedId = listingId.trim();
    if (normalizedId.isEmpty) return Stream<int>.value(0);
    return _db
        .collection('listings')
        .doc(normalizedId)
        .snapshots()
        .map((doc) {
          final data = doc.data() ?? const <String, dynamic>{};
          final value = data['watchersCount'];
          if (value is int) return value < 0 ? 0 : value;
          if (value is num) {
            final parsed = value.toInt();
            return parsed < 0 ? 0 : parsed;
          }
          final parsed = int.tryParse((value ?? '').toString()) ?? 0;
          return parsed < 0 ? 0 : parsed;
        });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watchlistStream({int limit = 60}) {
    final uid = _uid;
    if (uid == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _watchlistCollection(uid)
        .orderBy('savedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> recentlyViewedStream({
    int limit = 20,
  }) {
    final uid = _uid;
    if (uid == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }
    return _recentlyViewedCollection(uid)
        .orderBy('viewedAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<bool> toggleWatchlist({
    required String listingId,
    required Map<String, dynamic> listingData,
  }) async {
    final uid = _uid;
    final normalizedId = listingId.trim();
    if (uid == null || normalizedId.isEmpty) return false;

    final sellerId = _safeText(listingData, 'sellerId');
    if (sellerId.isNotEmpty && sellerId == uid) return false;

    final saleType =
        _safeText(listingData, 'saleType', fallback: 'auction').toLowerCase();
    if (saleType != 'auction') return false;

    final ref = _watchlistCollection(uid).doc(normalizedId);
    final snapshot = await ref.get();

    if (snapshot.exists) {
      await ref.delete();
      return false;
    }

    await ref.set({
      'listingId': normalizedId,
      'savedAt': FieldValue.serverTimestamp(),
      'watchedAt': FieldValue.serverTimestamp(),
      'watchSource': 'auction_watch',
      'category': _safeText(listingData, 'category', fallback: _safeText(listingData, 'mandiType')),
      'subcategory': _safeText(listingData, 'subcategory', fallback: _safeText(listingData, 'product')),
      'province': _safeText(listingData, 'province'),
      'district': _safeText(listingData, 'district'),
      'city': _safeText(listingData, 'city', fallback: _safeText(listingData, 'cityVillage')),
      'country': _safeText(listingData, 'country', fallback: 'Pakistan'),
      'saleType': _safeText(listingData, 'saleType', fallback: 'auction').toLowerCase(),
      'price': _toDouble(listingData['price'] ?? listingData['basePrice']),
      'title': _safeText(
        listingData,
        'product',
        fallback: _safeText(listingData, 'subcategoryLabel', fallback: 'Listing'),
      ),
      'thumbnailUrl': _safeText(
        listingData,
        'thumbnailUrl',
        fallback: _safeText(listingData, 'imageUrl'),
      ),
    }, SetOptions(merge: true));

    return true;
  }

  Future<void> removeFromWatchlist(String listingId) async {
    final uid = _uid;
    final normalizedId = listingId.trim();
    if (uid == null || normalizedId.isEmpty) return;
    await _watchlistCollection(uid).doc(normalizedId).delete();
  }

  Future<void> recordRecentView({
    required String listingId,
    required Map<String, dynamic> listingData,
    int keepLatest = 30,
  }) async {
    final uid = _uid;
    final normalizedId = listingId.trim();
    if (uid == null || normalizedId.isEmpty) return;

    final ref = _recentlyViewedCollection(uid).doc(normalizedId);
    await ref.set({
      'listingId': normalizedId,
      'viewedAt': FieldValue.serverTimestamp(),
      'category': _safeText(listingData, 'category', fallback: _safeText(listingData, 'mandiType')),
      'subcategory': _safeText(listingData, 'subcategory', fallback: _safeText(listingData, 'product')),
      'province': _safeText(listingData, 'province'),
      'district': _safeText(listingData, 'district'),
      'city': _safeText(listingData, 'city', fallback: _safeText(listingData, 'cityVillage')),
      'country': _safeText(listingData, 'country', fallback: 'Pakistan'),
      'saleType': _safeText(listingData, 'saleType', fallback: 'auction').toLowerCase(),
      'price': _toDouble(listingData['price'] ?? listingData['basePrice']),
      'title': _safeText(
        listingData,
        'product',
        fallback: _safeText(listingData, 'subcategoryLabel', fallback: 'Listing'),
      ),
      'thumbnailUrl': _safeText(
        listingData,
        'thumbnailUrl',
        fallback: _safeText(listingData, 'imageUrl'),
      ),
      'source': 'buyer_listing_detail',
    }, SetOptions(merge: true));

    await _trimRecentViews(uid: uid, keepLatest: keepLatest);
  }

  Future<void> _trimRecentViews({required String uid, required int keepLatest}) async {
    final snap = await _recentlyViewedCollection(uid)
        .orderBy('viewedAt', descending: true)
        .limit(80)
        .get();
    if (snap.docs.length <= keepLatest) return;

    final batch = _db.batch();
    for (var i = keepLatest; i < snap.docs.length; i++) {
      batch.delete(snap.docs[i].reference);
    }
    await batch.commit();
  }

  String _safeText(Map<String, dynamic> data, String key, {String fallback = ''}) {
    final value = (data[key] ?? '').toString().trim();
    if (value.isEmpty || value.toLowerCase() == 'null') return fallback;
    return value;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }
}
