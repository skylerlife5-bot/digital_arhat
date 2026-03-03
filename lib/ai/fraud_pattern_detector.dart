import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as developer;

/// Digital Arhat - Smart Security Guard
/// Yeh class har bid (boli) ka tajziya karti hai taake fraud roka ja sakay.
class FraudPatternDetector {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Placeholder method (Updated to be useful)
  bool detectFraudPattern(Map<String, dynamic> userData) {
    // Agar user ka trust score 1.0 se kam hai toh foran fraud flag karein
    if ((userData['trustScore'] ?? 5.0) < 1.0) {
      return true;
    }
    return false;
  }

  // 2. Real-time Bid Analysis Logic
  static Future<Map<String, dynamic>> analyzeBid({
    required String userId,
    required double bidAmount,
    required double marketPrice,
    required String listingId,
  }) async {
    
    // --- Rule A: Extreme Price Deviation (3x Rule) ---
    // Agar boli market rate se 3 guna zyada hai toh fake ho sakti hai
    if (bidAmount > (marketPrice * 3)) {
      return {
        "isSuspicious": true,
        "reason": "Extreme Price Deviation",
        "action": "PENDING_ADMIN_APPROVAL",
        "message": "Aapki boli market rate se bohot zyada hai. Admin ki tasdeeq tak ye pending rahegi."
      };
    }

    // --- Rule B: Shill Bidding (Rapid Fire Bids) ---
    // Check karein ke kahin ek hi banda baar baar rate toh nahi barha raha
    try {
      QuerySnapshot recentBids = await _db
          .collection('listings')
          .doc(listingId)
          .collection('bids')
          .where('bidderId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();

      // Agar aakhri 5 boliyon mein se 3 isi bande ki hain, toh warning dein
      if (recentBids.docs.length >= 3) {
        return {
          "isSuspicious": true,
          "reason": "Rapid Shill Bidding Pattern",
          "action": "FLAG_USER",
          "message": "Bohat teizi se boliyan lagayi ja rahi hain. System aapko monitor kar raha hai."
        };
      }
    } catch (e) {
      // Agar index missing ho ya koi error aaye toh safe mode mein false return karein
      developer.log("Security Engine Error: $e");
    }

    return {"isSuspicious": false};
  }
}
