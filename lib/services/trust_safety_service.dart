import 'package:cloud_firestore/cloud_firestore.dart';

class TrustBadge {
  const TrustBadge({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;
}

class ListingTrustInsight {
  const ListingTrustInsight({
    required this.message,
    required this.tone,
    required this.isCaution,
  });

  final String message;
  final String tone;
  final bool isCaution;
}

class BidBlockStatus {
  const BidBlockStatus({
    required this.isBlocked,
    required this.reason,
    required this.reasonUr,
    this.blockedUntil,
    this.strikeCount = 0,
  });

  final bool isBlocked;
  final String reason;
  final String reasonUr;
  final DateTime? blockedUntil;
  final int strikeCount;

  static const BidBlockStatus clear = BidBlockStatus(
    isBlocked: false,
    reason: '',
    reasonUr: '',
  );
}

class TrustSafetyService {
  const TrustSafetyService._();

  static const int strikeBlockThreshold = 3;

  static List<TrustBadge> resolveSellerTrustBadges({
    required Map<String, dynamic> listingData,
    Map<String, dynamic>? sellerData,
  }) {
    final List<TrustBadge> badges = <TrustBadge>[];

    if (_readTrustFlag(
      listingData,
      sellerData,
      const <String>[
        'phoneVerified',
        'isPhoneVerified',
        'phone_verified',
        'is_phone_verified',
        'mobileVerified',
      ],
    )) {
      badges.add(const TrustBadge(key: 'phone', label: 'Phone Verified'));
    }

    if (_readTrustFlag(
      listingData,
      sellerData,
      const <String>[
        'cnicVerified',
        'isCnicVerified',
        'isCNICVerified',
        'cnic_verified',
        'idVerified',
        'isIdVerified',
        'videoVerified',
        'isFaceVerified',
      ],
    )) {
      badges.add(const TrustBadge(key: 'cnic', label: 'CNIC Verified'));
    }

    if (_readTrustFlag(
      listingData,
      sellerData,
      const <String>[
        'adminVerified',
        'isAdminVerified',
        'verifiedByAdmin',
        'isVerified',
        'kycApproved',
      ],
    )) {
      badges.add(const TrustBadge(key: 'admin', label: 'Admin Verified'));
    }

    return badges;
  }

  static List<TrustBadge> resolveBuyerTrustBadges({
    required Map<String, dynamic> listingData,
    Map<String, dynamic>? sellerData,
  }) {
    final List<TrustBadge> badges = <TrustBadge>[];

    final bool isVerifiedSeller = _readTrustFlag(
      listingData,
      sellerData,
      const <String>[
        'phoneVerified',
        'isPhoneVerified',
        'phone_verified',
        'is_phone_verified',
        'mobileVerified',
        'cnicVerified',
        'isCnicVerified',
        'isCNICVerified',
        'cnic_verified',
        'idVerified',
        'isIdVerified',
        'videoVerified',
        'isFaceVerified',
        'adminVerified',
        'isAdminVerified',
        'verifiedByAdmin',
        'isVerified',
        'kycApproved',
      ],
    );

    final bool isTrustedSeller = _readTrustFlag(
      listingData,
      sellerData,
      const <String>[
        'trustedSeller',
        'isTrustedSeller',
        'sellerTrusted',
      ],
    );

    final bool isModerated = _isModeratedListing(listingData);
    final bool isAiReviewed = _isAiReviewedListing(listingData);

    if (isVerifiedSeller) {
      badges.add(const TrustBadge(key: 'verified', label: 'Verified Seller'));
    }
    if (isTrustedSeller) {
      badges.add(const TrustBadge(key: 'trusted', label: 'Trusted Seller'));
    }
    if (isModerated) {
      badges.add(const TrustBadge(key: 'moderated', label: 'Moderated Listing'));
    }
    if (isAiReviewed) {
      badges.add(const TrustBadge(key: 'ai', label: 'AI Reviewed'));
    }

    return badges;
  }

  static ListingTrustInsight buildBuyerAiInsight({
    required Map<String, dynamic> listingData,
  }) {
    final int riskScore = _readRiskScore(listingData);
    final bool isSuspicious = _toBool(listingData['isSuspicious']);
    final List<String> flags = _readStringList(
      listingData['riskFlags'] ?? listingData['fraudFlags'],
    );
    final String summary = (listingData['riskSummary'] ?? listingData['suspiciousReason'] ?? '')
        .toString()
        .trim();

    final bool hasLimitedSignals = flags.any(
      (flag) => const <String>{
        'thin_description',
        'missing_media',
        'missing_location',
        'missing_verification_media',
        'ai_not_configured',
      }.contains(flag.toLowerCase()),
    );

    if (isSuspicious || riskScore >= 70) {
      return const ListingTrustInsight(
        message:
            'Use extra care: verify media, location, and seller details before payment.',
        tone: 'caution',
        isCaution: true,
      );
    }

    if (hasLimitedSignals || riskScore >= 40) {
      return const ListingTrustInsight(
        message:
            'Limited verification signals are available. Review listing details carefully.',
        tone: 'neutral',
        isCaution: false,
      );
    }

    final bool safeSummary =
        summary.isNotEmpty && !_looksTechnical(summary) && summary.length <= 140;
    if (safeSummary) {
      return ListingTrustInsight(
        message: summary,
        tone: 'positive',
        isCaution: false,
      );
    }

    return const ListingTrustInsight(
      message:
          'Signals look consistent with normal marketplace listings.',
      tone: 'positive',
      isCaution: false,
    );
  }

  static BidBlockStatus evaluateBidBlock({
    required Map<String, dynamic> userData,
    DateTime? nowUtc,
  }) {
    final DateTime now = (nowUtc ?? DateTime.now()).toUtc();
    final int strikeCount = _toInt(userData['strikeCount']);

    final DateTime? blockedUntil = _toDateTime(userData['bidBlockedUntil']);
    if (blockedUntil != null && now.isBefore(blockedUntil.toUtc())) {
      return BidBlockStatus(
        isBlocked: true,
        reason: 'Bidding is temporarily blocked due to policy violations.',
        reasonUr: 'پالیسی خلاف ورزی کی وجہ سے بولی عارضی طور پر بند ہے۔',
        blockedUntil: blockedUntil.toUtc(),
        strikeCount: strikeCount,
      );
    }

    if (_toBool(userData['bidBlocked']) ||
        _toBool(userData['blockedFromBidding']) ||
        _toBool(userData['spamLock'])) {
      return BidBlockStatus(
        isBlocked: true,
        reason: 'Bidding is currently blocked on your account.',
        reasonUr: 'آپ کے اکاؤنٹ پر اس وقت بولی لگانا بند ہے۔',
        blockedUntil: blockedUntil?.toUtc(),
        strikeCount: strikeCount,
      );
    }

    if (strikeCount >= strikeBlockThreshold &&
        !_toBool(userData['allowBidWithStrikes'])) {
      return BidBlockStatus(
        isBlocked: true,
        reason: 'Bidding is blocked after repeated violations.',
        reasonUr: 'بار بار خلاف ورزی کے بعد بولی لگانا بند کر دیا گیا ہے۔',
        blockedUntil: blockedUntil?.toUtc(),
        strikeCount: strikeCount,
      );
    }

    return BidBlockStatus.clear;
  }

  static Future<void> submitReport({
    required String reportType,
    required String reportTargetType,
    required String listingId,
    required String sellerUid,
    required String reportedByUid,
    required String reason,
    required String notes,
    FirebaseFirestore? firestore,
  }) async {
    final db = firestore ?? FirebaseFirestore.instance;
    await db.collection('reports').add(<String, dynamic>{
      'reportType': reportType,
      'reportTargetType': reportTargetType,
      'listingId': listingId,
      'sellerUid': sellerUid,
      'reportedByUid': reportedByUid,
      'reason': reason,
      'notes': notes,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> registerStrike({
    required String userId,
    required String reason,
    required String source,
    required FirebaseFirestore db,
    int blockForHours = 24,
  }) async {
    final userRef = db.collection('users').doc(userId);
    final userSnap = await userRef.get();
    final userData = userSnap.data() ?? <String, dynamic>{};
    final int strikeCount = _toInt(userData['strikeCount']) + 1;

    final updates = <String, dynamic>{
      'strikeCount': strikeCount,
      'lastStrikeReason': reason,
      'lastStrikeSource': source,
      'lastStrikeAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (strikeCount >= strikeBlockThreshold) {
      updates['bidBlocked'] = true;
      updates['bidBlockedUntil'] = Timestamp.fromDate(
        DateTime.now().toUtc().add(Duration(hours: blockForHours)),
      );
    }

    await userRef.set(updates, SetOptions(merge: true));
  }

  static bool _readTrustFlag(
    Map<String, dynamic> listingData,
    Map<String, dynamic>? sellerData,
    List<String> keys,
  ) {
    for (final key in keys) {
      if (_toBool(listingData[key])) return true;
      if (sellerData != null && _toBool(sellerData[key])) return true;
    }
    return false;
  }

  static bool _isModeratedListing(Map<String, dynamic> listingData) {
    if (_toBool(listingData['isApproved'])) return true;

    final String status = (listingData['status'] ?? '').toString().toLowerCase();
    final String listingStatus =
        (listingData['listingStatus'] ?? '').toString().toLowerCase();
    final String auctionStatus =
        (listingData['auctionStatus'] ?? '').toString().toLowerCase();

    const activeStates = <String>{'approved', 'active', 'live'};
    return activeStates.contains(status) ||
        activeStates.contains(listingStatus) ||
        activeStates.contains(auctionStatus);
  }

  static bool _isAiReviewedListing(Map<String, dynamic> listingData) {
    if (_toBool(listingData['isVerifiedSource'])) return true;
    return listingData.containsKey('riskSummary') ||
        listingData.containsKey('riskScore') ||
        listingData.containsKey('aiRiskScore') ||
        listingData.containsKey('heuristicRiskScore');
  }

  static int _readRiskScore(Map<String, dynamic> data) {
    final double raw = _toDouble(
          data['riskScore'] ?? data['aiRiskScore'] ?? data['heuristicRiskScore'],
        ) ??
        0;
    return raw.round().clamp(0, 100);
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static bool _looksTechnical(String text) {
    final lower = text.toLowerCase();
    return lower.contains('_') ||
        lower.contains('riskscore') ||
        lower.contains('heuristic') ||
        lower.contains('ai_not_configured') ||
        lower.contains('thin_description');
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
