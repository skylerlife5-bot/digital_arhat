import 'package:cloud_firestore/cloud_firestore.dart';

class BiddingLogicEngine {
  static Map<String, dynamic> validateBid(double bidAmount, double currentAvg) {
    if (currentAvg <= 0) {
      throw Exception('INVALID_CURRENT_AVG|value=$currentAvg');
    }

    final isAnomalous =
        bidAmount > currentAvg * 1.3 || bidAmount < currentAvg * 0.7;

    return {
      'isSuspicious': isAnomalous,
      'reason': isAnomalous ? 'Price Anomaly Detected' : 'VALID_BID',
      'code': isAnomalous ? 'SUSPICIOUS_BID' : 'CLEAR',
      'thresholdLow': currentAvg * 0.7,
      'thresholdHigh': currentAvg * 1.3,
    };
  }

  static Future<Map<String, dynamic>> enforceVelocityAndLock({
    required FirebaseFirestore db,
    required String userId,
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(minutes: 5));

    final recent = await db
        .collectionGroup('bids')
        .where('buyerId', isEqualTo: userId)
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
        .get();

    final count = recent.docs.length;
    if (count > 10) {
      await db.collection('users').doc(userId).set({
        'spamLock': true,
        'spamLockReason': 'SPAM_LOCK',
        'spamLockAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await db.collection('security_alerts').add({
        'type': 'SPAM_LOCK',
        'userId': userId,
        'bidCountLast5Mins': count,
        'message': 'User exceeded velocity threshold (>10 bids in 5 minutes).',
        'createdAt': FieldValue.serverTimestamp(),
      });

      return {
        'isSuspicious': true,
        'reason': 'SPAM_LOCK',
        'code': 'SPAM_LOCK',
        'bidCountLast5Mins': count,
      };
    }

    return {
      'isSuspicious': false,
      'reason': 'VELOCITY_OK',
      'code': 'VELOCITY_OK',
      'bidCountLast5Mins': count,
    };
  }

  static Future<Map<String, dynamic>> evaluateBidRisk({
    required FirebaseFirestore db,
    required String userId,
    required double bidAmount,
    required double marketAvg,
  }) async {
    final anomaly = validateBid(bidAmount, marketAvg);
    final velocity = await enforceVelocityAndLock(db: db, userId: userId);

    if (velocity['code'] == 'SPAM_LOCK') {
      return velocity;
    }

    return anomaly;
  }

  // �x� Trigger 1: Outbid Alert
  static void handleOutbid(String previousBuyerToken, String cropName) {
    _sendFCM(
      token: previousBuyerToken,
      title: "�a�️ Aapki boli peeche reh gayi!",
      body: "$cropName ka maal hath se nikal raha hai, foran boli barhayein!",
    );
  }

  // �x" Trigger 2: Time Ticking (Aakhri 10 Minute)
  static void handleTimeWarning(List<String> allBidderTokens, String cropName) {
    for (String token in allBidderTokens) {
      _sendFCM(
        token: token,
        title: "⏰ Aakhri 10 Minute!",
        body:
            "$cropName ki bidding khatam hone wali hai. Mauka hath se na janay dein!",
      );
    }
  }

  // �x�  Trigger 3: Winning Notification
  static void handleWinning(
    String winnerToken,
    String cropName,
    double amount,
  ) {
    _sendFCM(
      token: winnerToken,
      title: "�x}0 Mubarak ho! Aap Jeet Gaye!",
      body:
          "Kisan ne Rs. $amount ki boli qabool kar li hai. Payment process shuru karein.",
    );
  }

  static void _sendFCM({
    required String token,
    required String title,
    required String body,
  }) {
    // Yahan Backend API call hogi jo Firebase Admin SDK ke zariye message bhejegi
  }
}

