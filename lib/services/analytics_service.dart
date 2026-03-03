import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AnalyticsService {
  AnalyticsService._internal();
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> logJoinAttribution({
    required String source,
    String listingId = '',
    String campaign = 'engagement_polish',
  }) async {
    final uid = _auth.currentUser?.uid ?? '';

    await _db.collection('marketing_stats').add({
      'event': 'join_attribution',
      'source': source,
      'campaign': campaign,
      'listingId': listingId,
      'uid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'platform': 'flutter_app',
    });
  }
}

