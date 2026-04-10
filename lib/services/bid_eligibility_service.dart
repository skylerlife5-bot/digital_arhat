import 'package:cloud_firestore/cloud_firestore.dart';

class BidEligibilityResult {
  const BidEligibilityResult({
    required this.allowed,
    required this.message,
    this.minimumAllowedBid,
  });

  final bool allowed;
  final String message;
  final double? minimumAllowedBid;
}

class BidEligibilityService {
  const BidEligibilityService._();

  static double calculateMinIncrement(double currentBid) {
    if (currentBid < 10000) {
      return 100;
    }
    if (currentBid <= 50000) {
      return 500;
    }
    if (currentBid <= 100000) {
      return 1000;
    }
    if (currentBid <= 500000) {
      return 2000;
    }
    return 5000;
  }

  static double calculateMinimumAllowedBid(Map<String, dynamic> listingData) {
    final startingPrice = _toDouble(listingData['startingPrice']) ??
        _toDouble(listingData['basePrice']) ??
        _toDouble(listingData['price']) ??
        0;
    final currentHighest = _toDouble(listingData['highestBid']) ?? startingPrice;
    final baseline = currentHighest > startingPrice ? currentHighest : startingPrice;
    final increment = calculateMinIncrement(baseline);
    return baseline + increment;
  }

  static BidEligibilityResult evaluate({
    required String buyerId,
    required Map<String, dynamic> listingData,
    required double bidAmount,
    DateTime? nowUtc,
  }) {
    final normalizedBuyerId = buyerId.trim();
    if (normalizedBuyerId.isEmpty) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Please sign in to place a bid.',
      );
    }

    final sellerId = _safeText(listingData['sellerId']);
    if (sellerId.isNotEmpty && sellerId == normalizedBuyerId) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'You cannot bid on your own listing.',
      );
    }

    final approved = _toBool(listingData['isApproved']);
    final status = _normalizeStatus(
      listingData['status'] ?? listingData['listingStatus'] ?? listingData['auctionStatus'],
    );
    final listingStatus = _normalizeStatus(listingData['listingStatus']);
    final auctionStatus = _normalizeStatus(listingData['auctionStatus']);

    if (_terminalStatus(status) || _terminalStatus(listingStatus) || _terminalStatus(auctionStatus)) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Bidding is not available for this listing status.',
      );
    }

    if (!approved) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Bidding is not live yet.',
      );
    }

    final openStatus = _openStatus(status) || _openStatus(listingStatus) || _openStatus(auctionStatus);
    if (!openStatus) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Bidding is not live yet.',
      );
    }

    if (_toBool(listingData['isBidForceClosed'])) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Auction is closed for bidding.',
      );
    }

    final now = (nowUtc ?? DateTime.now()).toUtc();
    final startTime = _toDate(listingData['startTime'])?.toUtc() ?? _toDate(listingData['approvedAt'])?.toUtc();
    final endTime = _toDate(listingData['endTime'])?.toUtc() ??
      startTime?.add(const Duration(hours: 24));

    if (startTime != null && now.isBefore(startTime)) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Bidding is not live yet.',
      );
    }

    if (endTime != null && !now.isBefore(endTime)) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Auction has ended.',
      );
    }

    if (bidAmount <= 0) {
      return const BidEligibilityResult(
        allowed: false,
        message: 'Please enter a valid bid amount.',
      );
    }

    final minimumAllowed = calculateMinimumAllowedBid(listingData);

    if (bidAmount < minimumAllowed) {
      return BidEligibilityResult(
        allowed: false,
        message: 'Bid must be at least Rs. ${minimumAllowed.toStringAsFixed(0)}.',
        minimumAllowedBid: minimumAllowed,
      );
    }

    return BidEligibilityResult(
      allowed: true,
      message: 'Eligible to bid.',
      minimumAllowedBid: minimumAllowed,
    );
  }

  static bool _openStatus(String value) {
    return const <String>{'live'}.contains(_canonicalAuctionState(value));
  }

  static bool _terminalStatus(String value) {
    return const <String>{
      'cancelled',
      'ended_waiting_seller',
      'bid_accepted',
      'expired_unsold',
    }.contains(_canonicalAuctionState(value));
  }

  static String _normalizeStatus(dynamic value) {
    return _canonicalAuctionState(_safeText(value).toLowerCase());
  }

  static String _canonicalAuctionState(String value) {
    switch (value) {
      case 'pending':
      case 'awaiting_admin_approval':
      case 'under_review':
      case 'pending_approval':
        return 'pending_approval';
      case 'approved':
      case 'active':
      case 'open':
      case 'running':
      case 'auction_live':
      case 'live':
        return 'live';
      case 'paused':
        return 'paused';
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return 'cancelled';
      case 'ended':
      case 'closed':
      case 'completed':
      case 'ended_waiting_seller':
        return 'ended_waiting_seller';
      case 'expired':
      case 'expired_unsold':
      case 'payment_rejected':
      case 'dispatched':
      case 'delivered_pending_release':
        return 'expired_unsold';
      case 'bid_accepted':
      case 'approved_winner':
        return 'bid_accepted';
      case 'scheduled':
        return 'scheduled';
      default:
        return value;
    }
  }

  static String _safeText(dynamic value) {
    return (value ?? '').toString().trim();
  }

  static bool _toBool(dynamic value) {
    if (value is bool) return value;
    final text = _safeText(value).toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(_safeText(value));
  }

  static DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }
}
