import 'package:cloud_firestore/cloud_firestore.dart';

class TrustScoreEngine {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // �S& Points Constants (For 0-100 Score System)
  static const int pointsForCNIC = 30;
  static const int pointsForSuccessfulDeal = 10;
  static const int penaltyForFlaggedListing = -20;
  static const int penaltyForCancelledDeal = -15;

  // �S& Star Rating Constants (For 0.0-5.0 Rating System)
  static const double rewardSuccessfulDeal = 0.2;
  static const double penaltyBuyerCancel = -1.5;
  static const double penaltyFakeBid = -2.0;

  /// 1. Full Score Calculation (Database Se history check karke)
  /// Ye function Profile screen ya Admin portal par score dikhane ke liye best hai.
  Future<int> calculateUserScore(String userId) async {
    int score = 50; // Base score (Neutral start)

    try {
      // 1. Check Profile Verification
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && userDoc.data() != null) {
        final data = userDoc.data() as Map<String, dynamic>;
        if (data['isCnicVerified'] == true) score += pointsForCNIC;
      }

      // 2. Check Successful Deals
      QuerySnapshot deals = await _firestore
          .collection('deals')
          .where('sellerId', isEqualTo: userId)
          .where('status', isEqualTo: 'completed')
          .get();
      score += (deals.docs.length * pointsForSuccessfulDeal);

      // 3. Check AI Flagged Listings (Price Anomaly/Suspicious Post Alerts)
      QuerySnapshot alerts = await _firestore
          .collection('alerts')
          .where('userId', isEqualTo: userId)
          .get();
      score += (alerts.docs.length * penaltyForFlaggedListing);

      // Boundary Checks
      return score.clamp(0, 100);
    } catch (e) {
      return 50; // Error ki surat mein neutral score
    }
  }

  /// 2. Live Star-Rating Adjustment
  /// Ye function tab call karein jab koi action perform ho (e.g., deal cancel ho)
  static double calculateNewRating(double currentRating, String action) {
    switch (action) {
      case 'DEAL_CANCELLED_BY_BUYER':
        return (currentRating + penaltyBuyerCancel).clamp(0.0, 5.0);
      case 'FAKE_BID_DETECTED':
        return (currentRating + penaltyFakeBid).clamp(0.0, 5.0);
      case 'SUCCESSFUL_DEAL':
        return (currentRating + rewardSuccessfulDeal).clamp(0.0, 5.0);
      default:
        return currentRating;
      }
  }

  /// 3. Trust Badge Logic
  String getTrustBadge(int score) {
    if (score >= 85) return "Gold Verified Arhat";
    if (score >= 65) return "Silver Seller";
    if (score >= 40) return "Verified Seller";
    return "New/Unverified";
  }
}
