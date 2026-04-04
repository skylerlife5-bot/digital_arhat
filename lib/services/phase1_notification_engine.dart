import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class Phase1NotificationType {
  static const String listingApproved = 'LISTING_APPROVED';
  static const String listingRejected = 'LISTING_REJECTED';
  static const String newBidReceived = 'NEW_BID_RECEIVED';
  static const String bidPlacedConfirmation = 'BID_PLACED_CONFIRMATION';
  static const String outbid = 'OUTBID';
  static const String bidAcceptedConfirmation = 'BID_ACCEPTED_CONFIRMATION';
  static const String bidAccepted = 'BID_ACCEPTED';
  static const String auctionEndingSoon = 'AUCTION_ENDING_SOON';
  static const String newRelevantListing = 'NEW_RELEVANT_LISTING';

  static const Set<String> all = <String>{
    listingApproved,
    listingRejected,
    newBidReceived,
    bidPlacedConfirmation,
    outbid,
    bidAcceptedConfirmation,
    bidAccepted,
    auctionEndingSoon,
    newRelevantListing,
  };
}

class Phase1NotificationEngine {
  Phase1NotificationEngine({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<void> createOnce({
    required String userId,
    required String type,
    required String listingId,
    String? bidId,
    String? actorUserId,
    String? eventSuffix,
    String? titleEn,
    String? bodyEn,
    String? titleUr,
    String? bodyUr,
    String? targetRole,
    double? amount,
  }) async {
    final normalizedUser = userId.trim();
    final normalizedType = type.trim().toUpperCase();
    final normalizedListing = listingId.trim();
    if (normalizedUser.isEmpty ||
        normalizedType.isEmpty ||
        normalizedListing.isEmpty) {
      return;
    }

    final defaults = _defaultCopy(normalizedType);
    final englishTitle = (titleEn ?? defaults.titleEn).trim();
    final englishBody = (bodyEn ?? defaults.bodyEn).trim();
    final urduTitle = (titleUr ?? defaults.titleUr).trim();
    final urduBody = (bodyUr ?? defaults.bodyUr).trim();

    final eventKey = _buildEventKey(
      userId: normalizedUser,
      type: normalizedType,
      listingId: normalizedListing,
      bidId: bidId,
      eventSuffix: eventSuffix,
    );
    final docRef = _db.collection('notifications').doc(eventKey);
    debugPrint(
      '[NotifWrite] type=$normalizedType toUid=$normalizedUser listingId=$normalizedListing bidId=${(bidId ?? '').trim()} role=${(targetRole ?? '').trim().toLowerCase()}',
    );

    await _db.runTransaction((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) return;

      transaction.set(docRef, {
        'toUid': normalizedUser,
        'userId': normalizedUser,
        'type': normalizedType,
        'entityId': normalizedListing,
        'listingId': normalizedListing,
        if (bidId?.trim().isNotEmpty ?? false) 'bidId': bidId?.trim(),
        if (actorUserId?.trim().isNotEmpty ?? false)
          'actorUserId': actorUserId?.trim(),
        if (targetRole?.trim().isNotEmpty ?? false)
          'targetRole': targetRole?.trim().toLowerCase(),
        'amount': amount,
        'title': '$englishTitle | $urduTitle',
        'body': '$englishBody | $urduBody',
        'titleEn': englishTitle,
        'bodyEn': englishBody,
        'titleUr': urduTitle,
        'bodyUr': urduBody,
        'isRead': false,
        'read': false,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'phase': 'PHASE_1',
        'eventKey': eventKey,
        'tapAction': 'OPEN_LISTING_DETAILS',
        'routeName': '/listing-details',
        'routeArgs': <String, dynamic>{'listingId': normalizedListing},
      });
    });
  }

  String _buildEventKey({
    required String userId,
    required String type,
    required String listingId,
    String? bidId,
    String? eventSuffix,
  }) {
    final parts = <String>[
      'p1',
      userId,
      type,
      listingId,
      if ((bidId ?? '').trim().isNotEmpty) bidId!.trim(),
      if ((eventSuffix ?? '').trim().isNotEmpty) eventSuffix!.trim(),
    ];

    final raw = parts.join('_').toLowerCase();
    final sanitized = raw
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (sanitized.length <= 120) return sanitized;
    return sanitized.substring(0, 120);
  }

  _NotificationCopy _defaultCopy(String type) {
    switch (type) {
      case Phase1NotificationType.listingApproved:
        return const _NotificationCopy(
          titleEn: 'Listing Approved',
          bodyEn: 'Your listing is now live.',
          titleUr: 'لسٹنگ منظور ہوگئی',
          bodyUr: 'آپ کی لسٹنگ اب لائیو ہے',
        );
      case Phase1NotificationType.listingRejected:
        return const _NotificationCopy(
          titleEn: 'Listing Rejected',
          bodyEn: 'Your listing was rejected by admin review.',
          titleUr: 'لسٹنگ مسترد ہوگئی',
          bodyUr: 'ایڈمن ریویو میں آپ کی لسٹنگ مسترد ہوگئی',
        );
      case Phase1NotificationType.newBidReceived:
        return const _NotificationCopy(
          titleEn: 'New Bid',
          bodyEn: 'A buyer placed a new bid on your listing.',
          titleUr: 'نئی بولی موصول ہوئی',
          bodyUr: 'آپ کی لسٹنگ پر نئی بولی آئی ہے',
        );
      case Phase1NotificationType.bidPlacedConfirmation:
        return const _NotificationCopy(
          titleEn: 'Bid Placed',
          bodyEn: 'Your bid has been submitted successfully.',
          titleUr: 'بولی لگ گئی',
          bodyUr: 'آپ کی بولی کامیابی سے لگ گئی ہے',
        );
      case Phase1NotificationType.outbid:
        return const _NotificationCopy(
          titleEn: 'Outbid Alert',
          bodyEn: 'Another buyer placed a higher bid.',
          titleUr: 'آپ کی بولی پیچھے رہ گئی',
          bodyUr: 'کسی اور نے زیادہ بولی لگا دی ہے',
        );
      case Phase1NotificationType.bidAcceptedConfirmation:
        return const _NotificationCopy(
          titleEn: 'Bid Accepted',
          bodyEn: 'Contact has been unlocked.',
          titleUr: 'بولی قبول کر لی گئی',
          bodyUr: 'رابطہ اَن لاک ہو گیا ہے',
        );
      case Phase1NotificationType.bidAccepted:
        return const _NotificationCopy(
          titleEn: 'Bid Accepted',
          bodyEn: 'Contact is now unlocked.',
          titleUr: 'آپ کی بولی قبول ہوگئی',
          bodyUr: 'رابطہ اَن لاک ہو گیا ہے',
        );
      case Phase1NotificationType.auctionEndingSoon:
        return const _NotificationCopy(
          titleEn: 'Auction Ending Soon',
          bodyEn: 'This auction is about to close.',
          titleUr: 'بولی جلد ختم ہو رہی ہے',
          bodyUr: 'یہ بولی جلد بند ہونے والی ہے',
        );
      case Phase1NotificationType.newRelevantListing:
        return const _NotificationCopy(
          titleEn: 'New Listing Near You',
          bodyEn: 'A relevant listing is available in your area.',
          titleUr: 'آپ کے علاقے میں نئی لسٹنگ',
          bodyUr: 'آپ کے علاقے میں نئی آفر آئی ہے',
        );
      default:
        return const _NotificationCopy(
          titleEn: 'Marketplace Update',
          bodyEn: 'There is an update on your listing activity.',
          titleUr: 'مارکیٹ اپڈیٹ',
          bodyUr: 'آپ کی لسٹنگ سرگرمی میں نیا اپڈیٹ ہے۔',
        );
    }
  }
}

class _NotificationCopy {
  const _NotificationCopy({
    required this.titleEn,
    required this.bodyEn,
    required this.titleUr,
    required this.bodyUr,
  });

  final String titleEn;
  final String bodyEn;
  final String titleUr;
  final String bodyUr;
}
