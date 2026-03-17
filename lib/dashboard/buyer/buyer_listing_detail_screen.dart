import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'bid_bottom_sheet.dart';
import '../../services/buyer_engagement_service.dart';
import '../../services/auction_lifecycle_service.dart';
import '../../services/bid_eligibility_service.dart';
import '../../services/trust_safety_service.dart';
import '../../theme/app_colors.dart';

// FIX: Use a single PKR formatter across listing detail UI.
String formatPkr(num amount) => 'Rs. ${amount.toStringAsFixed(0)}';

class BuyerListingDetailScreen extends StatefulWidget {
  const BuyerListingDetailScreen({
    super.key,
    required this.listingId,
    this.initialData,
  });

  final String listingId;
  final Map<String, dynamic>? initialData;

  @override
  State<BuyerListingDetailScreen> createState() =>
      _BuyerListingDetailScreenState();
}

class _BuyerListingDetailScreenState extends State<BuyerListingDetailScreen> {
  static const Color _darkGreen = AppColors.background;
  static const Color _gold = AppColors.accentGold;

  _RiskReport? _riskReport;
  bool _riskAccepted = false;
  bool _highRiskDialogShown = false;
  bool _missingDataNotified = false;
  bool _recentlyViewedTracked = false;
  final BuyerEngagementService _engagementService = BuyerEngagementService();
  final AuctionLifecycleService _auctionLifecycleService =
      AuctionLifecycleService();

  @override
  void initState() {
    super.initState();
    // If route payload is invalid, notify once and return to previous screen.
    if (widget.listingId.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Listing data missing')));
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
    }
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _listingStream() {
    return FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listingId)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _dealStream(String buyerId) {
    return FirebaseFirestore.instance
        .collection('deals')
        .where('listingId', isEqualTo: widget.listingId)
        .where('buyerId', isEqualTo: buyerId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _bidHistoryStream() {
    return FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listingId)
        .collection('bids')
        .orderBy('timestamp', descending: true)
        .limit(8)
        .snapshots();
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  bool _isExpired(Map<String, dynamic> listing) {
    final createdAt = _readDate(listing['createdAt']);
    if (createdAt == null) return false;
    return DateTime.now().toUtc().isAfter(
      createdAt.add(const Duration(hours: 24)),
    );
  }

  Future<_RiskReport> _computeRisk(Map<String, dynamic> listing) async {
    // FIX: Keep checks local and actionable; avoid hard warnings/AI-missing language.
    int score = 0;
    final reasons = <_Reason>[];

    final itemName = _firstText(listing, const ['itemName', 'cropName']);
    final description = _safeText(listing, 'description');
    final video = _firstText(listing, const [
      'videoUrl',
      'verificationVideoUrl',
      'videoURL',
    ]);
    final photo = _firstText(listing, const [
      'photoUrl',
      'imageUrl',
      'mediaImageUrl',
    ]);
    final gps = _gpsText(listing);

    if (gps == null) {
      score += 15;
      reasons.add(
        const _Reason(
          en: 'Tip: Add GPS/video for better trust.',
          ur: 'مشورہ: بھروسے کے لئے GPS/ویڈیو شامل کریں۔',
        ),
      );
    }

    if (video.isEmpty && photo.isEmpty) {
      score += 20;
      reasons.add(
        const _Reason(
          en: 'Tip: Seller should add media for faster approval.',
          ur: 'مشورہ: تیز منظوری کے لئے میڈیا شامل کریں۔',
        ),
      );
    }

    if (itemName.isEmpty || description.isEmpty) {
      score += 20;
      reasons.add(
        const _Reason(
          en: 'Tip: Add item name/details.',
          ur: 'مشورہ: آئٹم کا نام اور تفصیل شامل کریں۔',
        ),
      );
    }

    final level = score >= 70
        ? _RiskLevel.high
        : score >= 35
        ? _RiskLevel.medium
        : _RiskLevel.low;

    return _RiskReport(level: level, score: score, reasons: reasons);
  }

  Future<void> _ensureRiskLoaded(Map<String, dynamic> listing) async {
    if (_riskReport != null) return;
    final report = await _computeRisk(listing);
    if (!mounted) return;
    setState(() {
      _riskReport = report;
    });

    if (report.level == _RiskLevel.high && !_highRiskDialogShown && mounted) {
      _highRiskDialogShown = true;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Verification Notice / تصدیقی نوٹس'),
            content: const Text(
              'Some trust signals are limited for this listing. Please review details carefully before placing a bid.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK / ٹھیک ہے'),
              ),
            ],
          );
        },
      );
    }
  }

  void _trackRecentlyViewed(Map<String, dynamic> listing) {
    if (_recentlyViewedTracked) return;
    if (widget.listingId.trim().isEmpty) return;
    _recentlyViewedTracked = true;
    _engagementService.recordRecentView(
      listingId: widget.listingId,
      listingData: listing,
    );
  }

  @override
  Widget build(BuildContext context) {
    final buyerId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: _darkGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Listing Detail / تفصیل',
          style: TextStyle(color: AppColors.primaryText),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _listingStream(),
            builder: (context, snapshot) {
              final liveDoc = snapshot.data;
              final liveData = liveDoc?.data();
              final data = liveData ?? widget.initialData;

              if (data != null) {
                _trackRecentlyViewed(data);
              }

              if (snapshot.hasError && data == null) {
                return _missingListingView(
                  title: 'Something went wrong / کچھ مسئلہ پیش آیا',
                  subtitle:
                      'Unable to load listing right now. / لسٹنگ ابھی لوڈ نہیں ہو سکی۔',
                );
              }

              if (liveDoc != null && !liveDoc.exists && data == null) {
                return _missingListingView(
                  title: 'Listing not found / لسٹنگ موجود نہیں',
                  subtitle:
                      'This listing may have been removed. / یہ لسٹنگ ہٹائی جا چکی ہے۔',
                );
              }

              if (data == null) {
                if (!_missingDataNotified) {
                  _missingDataNotified = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Listing data missing / لسٹنگ ڈیٹا دستیاب نہیں',
                        ),
                      ),
                    );
                  });
                }
                return _missingListingView(
                  title: 'Listing data missing / لسٹنگ ڈیٹا دستیاب نہیں',
                  subtitle:
                      'Please open this listing from dashboard again. / ڈیش بورڈ سے دوبارہ کھولیں۔',
                );
              }

              _ensureRiskLoaded(data);

              final expired = _isExpired(data);
              final item = _firstText(data, const [
                'itemName',
                'cropName',
              ], fallback: 'Item');
              final qty = _readDouble(data['quantity']);
              final unit = _safeText(data, 'unit', fallback: 'kg');
              final province = _safeText(data, 'province');
              final district = _safeText(data, 'district');
              final rate = _readDouble(
                data['rate'] ?? data['price'] ?? data['unitPrice'],
              );
              final gps = _gpsText(data);
              final marketAvg = _readDouble(
                data['marketAverage'] ??
                    data['marketAverageRate'] ??
                    data['aiMarketRate'],
              );
              final saleType = _safeText(
                data,
                'saleType',
                fallback: 'auction',
              ).toLowerCase();
              final bool isAuction = saleType == 'auction';
              final watchersCount = _readInt(data['watchersCount']);
              final status = _safeText(data, 'status', fallback: 'active');
              final isApproved = data['isApproved'] == true;
              final normalizedStatus = status.toLowerCase();
              final listingStatus = _safeText(
                data,
                'listingStatus',
              ).toLowerCase();
              final auctionStatus = _safeText(
                data,
                'auctionStatus',
              ).toLowerCase();
              final isBuyerVisible =
                  isApproved &&
                  (normalizedStatus == 'approved' ||
                      normalizedStatus == 'active' ||
                      normalizedStatus == 'live' ||
                      listingStatus == 'approved' ||
                      listingStatus == 'active' ||
                      listingStatus == 'live' ||
                      auctionStatus == 'live');
              final previewImage = _firstText(data, const [
                'videoThumbnailUrl',
                'thumbnailUrl',
                'videoThumb',
                'photoUrl',
                'imageUrl',
                'trustPhotoUrl',
                'verificationTrustPhotoUrl',
                'mediaImageUrl',
              ]);
              final videoUrl = _firstText(data, const [
                'videoUrl',
                'verificationVideoUrl',
                'videoURL',
                'mediaVideoUrl',
              ]);
              final hasVideo = videoUrl.isNotEmpty;

              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: buyerId.isEmpty ? null : _dealStream(buyerId),
                builder: (context, dealSnapshot) {
                  final dealDoc = (dealSnapshot.data?.docs.isNotEmpty ?? false)
                      ? dealSnapshot.data!.docs.first
                      : null;
                  final deal = dealDoc?.data();
                  final acceptedForBuyer = isBidAccepted(
                    currentUserUid: buyerId,
                    dealData: deal,
                    listingData: data,
                  );
                  final contactUnlocked = isContactUnlocked(
                    currentUserUid: buyerId,
                    dealData: deal,
                    listingData: data,
                  );
                  final outcomeStatus = _resolveOutcomeStatus(
                    listingData: data,
                    dealData: deal,
                  );
                  final probeBidAmount = (() {
                    final highest = _readDouble(data['highestBid']);
                    if (highest > 0) return highest + 1;
                    final start = _readDouble(
                      data['startingPrice'] ??
                          data['basePrice'] ??
                          data['price'],
                    );
                    if (start > 0) return start + 1;
                    return 1.0;
                  })();
                  final bidEligibility = BidEligibilityService.evaluate(
                    buyerId: buyerId,
                    listingData: data,
                    bidAmount: probeBidAmount,
                  );
                  final sellerPhone = _safeText(
                    deal,
                    'sellerPhone',
                    fallback: _safeText(
                      data,
                      'sellerPhone',
                      fallback: _safeText(
                        data,
                        'phone',
                        fallback: _safeText(data, 'contactPhone'),
                      ),
                    ),
                  );
                  final sellerWhatsApp = _safeText(
                    deal,
                    'sellerWhatsapp',
                    fallback: _safeText(
                      data,
                      'sellerWhatsapp',
                      fallback: sellerPhone,
                    ),
                  );
                  final sellerUid = _safeText(data, 'sellerId');

                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: sellerUid.isEmpty
                        ? null
                        : FirebaseFirestore.instance
                              .collection('users')
                              .doc(sellerUid)
                              .snapshots(),
                    builder: (context, sellerSnapshot) {
                      final sellerData = sellerSnapshot.data?.data();
                      final trustBadges =
                          TrustSafetyService.resolveBuyerTrustBadges(
                            listingData: data,
                            sellerData: sellerData,
                          );
                      final aiInsight = TrustSafetyService.buildBuyerAiInsight(
                        listingData: data,
                      );

                      return ListView(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                        children: [
                          _card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item,
                                        style: const TextStyle(
                                          color: AppColors.primaryText,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    if (_riskReport != null)
                                      _riskBadge(_riskReport!),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // FIX: Improve readability with consistent labels.
                                _line('Item Name', item),
                                _line(
                                  'Quantity + Unit',
                                  '${qty.toStringAsFixed(0)} ${unit.trim().isEmpty ? 'N/A' : unit}',
                                ),
                                _line(
                                  'Province/District',
                                  '${province.trim().isEmpty ? 'N/A' : province} / ${district.trim().isEmpty ? 'N/A' : district}',
                                ),
                                _line(
                                  'Rate',
                                  rate > 0 ? formatPkr(rate) : 'N/A',
                                ),
                                _line(
                                  'Market Avg / مارکیٹ اوسط',
                                  marketAvg > 0 ? formatPkr(marketAvg) : 'N/A',
                                ),
                                _line('Status', expired ? 'Expired' : status),
                                if (isAuction)
                                  _watchSection(
                                    listingData: data,
                                    sellerUid: sellerUid,
                                    watchersCount: watchersCount,
                                  ),
                                const SizedBox(height: 6),
                                if (gps != null)
                                  _line('GPS', gps)
                                else
                                  _smallInfoBadge('GPS not provided'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _bidHistoryCard(),
                          const SizedBox(height: 10),
                          _card(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Media Preview',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: double.infinity,
                                    height: 130,
                                    child: previewImage.isNotEmpty
                                        ? Image.network(
                                            previewImage,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    _mediaPlaceholder(),
                                          )
                                        : _mediaPlaceholder(),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                if (!isBuyerVisible)
                                  _notice(
                                    'Listing under moderation. Details will appear after approval. / لسٹنگ جانچ میں ہے، منظوری کے بعد تفصیل نظر آئے گی۔',
                                  )
                                else
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: hasVideo
                                              ? AppColors.softOverlayGold
                                              : AppColors.cardSurface,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(
                                            color: hasVideo
                                                ? AppColors.accentGold
                                                : AppColors.divider,
                                          ),
                                        ),
                                        child: Text(
                                          hasVideo
                                              ? 'Video attached'
                                              : 'No Video',
                                          style: TextStyle(
                                            color: hasVideo
                                                ? AppColors.ctaTextDark
                                                : AppColors.secondaryText,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        height: 48,
                                        child: FilledButton.icon(
                                          onPressed: hasVideo
                                              ? () {
                                                  Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) =>
                                                          _VideoUrlViewerScreen(
                                                            videoUrl: videoUrl,
                                                          ),
                                                    ),
                                                  );
                                                }
                                              : null,
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'View Product Video',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          _aiInsightPanel(aiInsight),
                          const SizedBox(height: 10),
                          _sellerTrustSummaryCard(
                            listingData: data,
                            sellerData: sellerData,
                            trustBadges: trustBadges,
                            sellerUid: sellerUid,
                          ),
                          const SizedBox(height: 10),
                          _privacyPanel(
                            contactUnlocked:
                                acceptedForBuyer || contactUnlocked,
                          ),
                          const SizedBox(height: 10),
                          if (_riskReport?.level == _RiskLevel.high)
                            CheckboxListTile(
                              value: _riskAccepted,
                              onChanged: (value) => setState(
                                () => _riskAccepted = value ?? false,
                              ),
                              title: const Text(
                                'I understand and will verify before paying / میں ادائیگی سے پہلے تصدیق کروں گا',
                                style: TextStyle(color: AppColors.primaryText),
                              ),
                              subtitle: const Text(
                                'Please review trust signals carefully before placing a bid.',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                ),
                              ),
                              activeColor: _gold,
                              checkColor: AppColors.ctaTextDark,
                            ),
                          if (isAuction && contactUnlocked)
                            _notice(
                              'آپ کی بولی قبول ہوگئی\nرابطہ اَن لاک ہو گیا ہے\nبراہِ راست بات کر کے ادائیگی اور ڈلیوری طے کریں',
                            ),
                          if (isAuction && (acceptedForBuyer || contactUnlocked))
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Contact unlocked after seller acceptance.\nبولی قبول ہونے کے بعد رابطہ کھل گیا ہے',
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.phone_rounded,
                                        size: 16,
                                        color: AppColors.divider,
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          sellerPhone.isEmpty
                                              ? 'Seller contact will appear here once available.'
                                              : 'Seller Phone: $sellerPhone',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.secondaryText,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Complete deal offline after verifying listing and seller details.\n'
                                    'لسٹنگ اور فروخت کنندہ کی تصدیق کے بعد براہِ راست سودا مکمل کریں',
                                    style: TextStyle(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (isAuction && (acceptedForBuyer || contactUnlocked))
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Deal Outcome / سودے کا نتیجہ',
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Current: ${_outcomeLabel(outcomeStatus)}',
                                    style: const TextStyle(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton(
                                        onPressed: () => _updateDealOutcome(
                                          status: 'successful',
                                          note:
                                              'Buyer marked successful completion',
                                        ),
                                        child: const Text('Mark Successful'),
                                      ),
                                      OutlinedButton(
                                        onPressed: () => _updateDealOutcome(
                                          status: 'failed',
                                          note: 'Buyer marked deal failed',
                                        ),
                                        child: const Text('Mark Failed'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          if (isAuction && !(acceptedForBuyer || contactUnlocked))
                            _notice(
                              'Contact unlocks after seller accepts a bid.\nرابطہ بولی قبول ہونے کے بعد کھلتا ہے',
                            ),
                          if (!isAuction)
                            _card(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Direct Contact / براہِ راست رابطہ',
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    sellerPhone.isEmpty
                                        ? 'Seller contact not provided yet.'
                                        : 'Phone: $sellerPhone',
                                    style: const TextStyle(
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.icon(
                                          onPressed: sellerPhone.isEmpty
                                              ? null
                                              : () async {
                                                  final uri = Uri.parse(
                                                    'tel:$sellerPhone',
                                                  );
                                                  await launchUrl(
                                                    uri,
                                                    mode: LaunchMode.externalApplication,
                                                  );
                                                },
                                          icon: const Icon(Icons.phone_rounded),
                                          label: const Text('Call'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: sellerWhatsApp.isEmpty
                                              ? null
                                              : () async {
                                                  final digits = sellerWhatsApp
                                                      .replaceAll(RegExp(r'[^0-9]'), '');
                                                  if (digits.isEmpty) return;
                                                  final uri = Uri.parse(
                                                    'https://wa.me/$digits',
                                                  );
                                                  await launchUrl(
                                                    uri,
                                                    mode: LaunchMode.externalApplication,
                                                  );
                                                },
                                          icon: const Icon(Icons.chat_bubble_outline),
                                          label: const Text('WhatsApp'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          if (isAuction && !contactUnlocked)
                            if (!bidEligibility.allowed)
                              _notice(
                                '${bidEligibility.message} / بولی فی الحال دستیاب نہیں',
                              ),
                          if (isAuction && !contactUnlocked)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    (expired || !bidEligibility.allowed)
                                    ? AppColors.divider.withValues(alpha: 0.55)
                                    : _gold,
                                foregroundColor:
                                    (expired || !bidEligibility.allowed)
                                    ? AppColors.secondaryText
                                    : AppColors.ctaTextDark,
                              ),
                              onPressed:
                                  expired ||
                                      !bidEligibility.allowed ||
                                      (_riskReport?.level == _RiskLevel.high &&
                                          !_riskAccepted)
                                  ? null
                                  : () {
                                      showModalBottomSheet<void>(
                                        context: context,
                                        backgroundColor: Colors.transparent,
                                        isScrollControlled: true,
                                        builder: (_) => BidBottomSheet(
                                          listingId: widget.listingId,
                                          listingData: data,
                                        ),
                                      );
                                    },
                              icon: const Icon(Icons.gavel_rounded),
                              label: Text(
                                expired
                                    ? 'Expired - Bid Disabled / بولی بند'
                                    : 'Place Bid / بولی لگائیں',
                              ),
                            ),
                        ],
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: child,
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: const TextStyle(color: AppColors.primaryText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mediaPlaceholder() {
    return Container(
      color: AppColors.cardSurface,
      alignment: Alignment.center,
      child: const Text(
        'No media available / میڈیا دستیاب نہیں',
        style: TextStyle(
          color: AppColors.secondaryText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _riskBadge(_RiskReport report) {
    final (title, color) = switch (report.level) {
      _RiskLevel.low => ('Trusted Signals', AppColors.divider),
      _RiskLevel.medium => ('Review Details', AppColors.accentGold),
      _RiskLevel.high => ('Verify Carefully', AppColors.urgencyRed),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.85)),
      ),
      child: Text(
        title,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _aiInsightPanel(ListingTrustInsight insight) {
    final Color toneColor = switch (insight.tone) {
      'positive' => AppColors.divider,
      'caution' => AppColors.accentGold,
      _ => AppColors.secondaryText,
    };

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                insight.isCaution
                    ? Icons.info_outline_rounded
                    : Icons.auto_awesome_rounded,
                color: toneColor,
                size: 18,
              ),
              const SizedBox(width: 6),
              const Text(
                'Price Insight / قیمت اشارہ',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            insight.message,
            style: const TextStyle(color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _sellerTrustSummaryCard({
    required Map<String, dynamic> listingData,
    required Map<String, dynamic>? sellerData,
    required List<TrustBadge> trustBadges,
    required String sellerUid,
  }) {
    final sellerName = _firstText(
      sellerData,
      const ['name', 'fullName', 'displayName'],
      fallback: _firstText(listingData, const [
        'sellerName',
        'farmerName',
      ], fallback: 'Seller'),
    );
    final city = _firstText(sellerData, const [
      'city',
      'tehsil',
    ], fallback: _safeText(listingData, 'city'));
    final district = _firstText(sellerData, const [
      'district',
    ], fallback: _safeText(listingData, 'district'));
    final location =
        '${district.isEmpty ? 'N/A' : district}${city.isEmpty ? '' : ' / $city'}';
    final primaryBadge = _primaryTrustBadgeLabel(
      listingData: listingData,
      trustBadges: trustBadges,
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Seller Trust Summary / فروخت کنندہ اعتماد خلاصہ',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _line('Seller', sellerName),
          _line('District/City', location),
          const SizedBox(height: 6),
          if (primaryBadge != null)
            _trustBadge(primaryBadge, AppColors.divider)
          else
            const Text(
              'No verification badge available',
              style: TextStyle(color: AppColors.secondaryText),
            ),
          const SizedBox(height: 10),
          _sellerCheapListingsSummary(sellerUid),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openReportDialog(
                  reportTargetType: 'listing',
                  sellerUid: sellerUid,
                ),
                icon: const Icon(Icons.flag_rounded, size: 16),
                label: const Text('Report Listing'),
              ),
              OutlinedButton.icon(
                onPressed: () => _openReportDialog(
                  reportTargetType: 'seller',
                  sellerUid: sellerUid,
                ),
                icon: const Icon(Icons.person_off_rounded, size: 16),
                label: const Text('Report Seller'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sellerCheapListingsSummary(String sellerUid) {
    if (sellerUid.trim().isEmpty) {
      return const Text(
        'Seller history unavailable',
        style: TextStyle(color: AppColors.secondaryText),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .where('sellerId', isEqualTo: sellerUid)
          .limit(40)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Text(
            'Loading seller history... / فروخت کنندہ کی ہسٹری لوڈ ہو رہی ہے',
            style: TextStyle(color: AppColors.secondaryText),
          );
        }

        final docs =
            snapshot.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        int cheaperCount = 0;
        for (final doc in docs) {
          final data = doc.data();
          final price = _readDouble(data['price']);
          final status = (data['status'] ?? '').toString().toLowerCase();
          if (price > 0 && price <= 1000 && status != 'rejected') {
            cheaperCount += 1;
          }
        }

        return Text(
          'Low-price listings (<= Rs. 1000): $cheaperCount / کم قیمت لسٹنگز',
          style: const TextStyle(color: AppColors.secondaryText),
        );
      },
    );
  }

  Future<void> _openReportDialog({
    required String reportTargetType,
    required String sellerUid,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) {
      _snack('Please sign in to submit report.');
      return;
    }

    final TextEditingController notesController = TextEditingController();
    final List<String> reasons = <String>[
      'Fake listing',
      'Abusive behavior',
      'Wrong information',
      'Spam',
      'Other',
    ];
    String selectedReason = reasons.first;

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(
                'Report ${reportTargetType == 'seller' ? 'Seller' : 'Listing'}',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedReason,
                      items: reasons
                          .map(
                            (reason) => DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedReason = value);
                      },
                      decoration: const InputDecoration(labelText: 'Reason'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );

    if (shouldSubmit != true) {
      notesController.dispose();
      return;
    }

    try {
      await TrustSafetyService.submitReport(
        reportType: 'user_report',
        reportTargetType: reportTargetType,
        listingId: widget.listingId,
        sellerUid: sellerUid,
        reportedByUid: uid,
        reason: selectedReason,
        notes: notesController.text.trim(),
      );
      _snack('Report submitted. Our team will review it.');
    } catch (_) {
      _snack('Failed to submit report. Please try again.');
    } finally {
      notesController.dispose();
    }
  }

  Widget _trustBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.78)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  String? _primaryTrustBadgeLabel({
    required Map<String, dynamic> listingData,
    required List<TrustBadge> trustBadges,
  }) {
    final hasVerified = trustBadges.any(
      (badge) => badge.key == 'verified' || badge.key == 'trusted',
    );
    if (hasVerified) return 'Verified Seller';
    if (listingData['isApproved'] == true) return 'Admin Approved';
    return null;
  }

  Widget _privacyPanel({required bool contactUnlocked}) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Privacy & Contact / رازداری اور رابطہ',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Before bid acceptance: contact remains hidden. / بولی قبول ہونے سے پہلے رابطہ چھپا رہے گا۔',
            style: TextStyle(color: AppColors.secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            contactUnlocked
                ? 'Contact unlocked after seller acceptance. / بولی قبول ہونے کے بعد رابطہ کھل گیا ہے'
                : 'Contact unlocks after seller accepts a bid. / رابطہ بولی قبول ہونے کے بعد کھلتا ہے',
            style: TextStyle(
              color: contactUnlocked ? AppColors.divider : AppColors.accentGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _updateDealOutcome({
    required String status,
    required String note,
  }) async {
    try {
      await _auctionLifecycleService.updateDealOutcome(
        listingId: widget.listingId,
        outcomeStatus: status,
        note: note,
      );
      _snack('Deal outcome updated to ${_outcomeLabel(status)}');
    } catch (e) {
      _snack('Outcome update failed: $e');
    }
  }

  String _resolveOutcomeStatus({
    required Map<String, dynamic> listingData,
    required Map<String, dynamic>? dealData,
  }) {
    final deal = dealData ?? const <String, dynamic>{};
    final raw =
        (deal['outcomeStatus'] ?? listingData['dealOutcomeStatus'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
    if (raw.isEmpty) return 'pending_contact';
    return raw;
  }

  String _outcomeLabel(String status) {
    switch (status.toLowerCase()) {
      case 'successful':
        return 'Successful';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'disputed':
        return 'Disputed';
      case 'no_bids':
        return 'No Bids';
      default:
        return 'Pending Contact';
    }
  }

  Widget _bidHistoryCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bid History / بولی ہسٹری',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _bidHistoryStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Text(
                  'Loading recent bids... / حالیہ بولیاں لوڈ ہو رہی ہیں',
                  style: TextStyle(color: AppColors.secondaryText),
                );
              }

              final docs =
                  snapshot.data?.docs ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              if (docs.isEmpty) {
                return const Text(
                  'No bids yet for this listing / اس لسٹنگ پر ابھی کوئی بولی نہیں',
                  style: TextStyle(color: AppColors.secondaryText),
                );
              }

              return Column(
                children: docs
                    .take(5)
                    .map((doc) {
                      final bid = doc.data();
                      final bidder = _safeBidderName(bid);
                      final amount = _readDouble(
                        bid['bidAmount'] ?? bid['amount'],
                      );
                      final timeLabel = _bidTimeLabel(
                        bid['timestamp'] ?? bid['createdAt'],
                      );

                      return Container(
                        margin: const EdgeInsets.only(bottom: 7),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.softGlassSurface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                bidder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              formatPkr(amount),
                              style: const TextStyle(
                                color: AppColors.accentGold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              timeLabel,
                              style: const TextStyle(
                                color: AppColors.secondaryText,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      );
                    })
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }

  String _safeBidderName(Map<String, dynamic> bid) {
    final raw = _safeText(
      bid,
      'buyerName',
      fallback: _safeText(bid, 'bidderName', fallback: 'Bidder'),
    ).trim();
    if (raw.isEmpty) return 'Anonymous bidder';

    final token = raw.split(RegExp(r'\s+')).first.trim();
    if (token.isEmpty) return 'Anonymous bidder';
    if (token.length == 1) return '$token***';
    if (token.length == 2) return '${token[0]}***';
    return '${token.substring(0, 2)}***';
  }

  String _bidTimeLabel(dynamic value) {
    final date = _readDate(value);
    if (date == null) return '--';
    final local = date.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} $hh:$mm';
  }

  Widget _notice(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.secondaryText),
      ),
    );
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  Widget _watchSection({
    required Map<String, dynamic> listingData,
    required String sellerUid,
    required int watchersCount,
  }) {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sellerUid.isNotEmpty && sellerUid == currentUserUid) {
      return const SizedBox.shrink();
    }

    final watcherText = watchersCount > 0
        ? '👁️ $watchersCount watching'
        : null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {
                _snack('Login required to watch auctions');
              },
              icon: const Icon(Icons.star_border_rounded, size: 18),
              label: const Text('Watch'),
            ),
            if (watcherText != null) ...[
              const SizedBox(width: 10),
              Text(
                watcherText,
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: StreamBuilder<bool>(
        stream: _engagementService.isListingSavedStream(widget.listingId),
        builder: (context, snapshot) {
          final isSaved = snapshot.data ?? false;
          return Row(
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final saved = await _engagementService.toggleWatchlist(
                    listingId: widget.listingId,
                    listingData: listingData,
                  );
                  _snack(
                    saved ? 'Watching this auction' : 'Removed from watchlist',
                  );
                },
                icon: Icon(
                  isSaved ? Icons.star_rounded : Icons.star_border_rounded,
                  size: 18,
                  color: isSaved ? AppColors.primaryText : AppColors.accentGold,
                ),
                label: Text(isSaved ? 'Watching' : 'Watch'),
              ),
              if (watcherText != null) ...[
                const SizedBox(width: 10),
                Text(
                  watcherText,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double? _tryReadDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String? _gpsText(Map<String, dynamic> listing) {
    // FIX: Smart nested GPS lookup without crashes.
    final verificationGeo = listing['verificationGeo'];
    final geo = listing['geo'];

    final lat =
        _tryReadDouble(
          verificationGeo is Map ? verificationGeo['lat'] : null,
        ) ??
        _tryReadDouble(geo is Map ? geo['lat'] : null) ??
        _tryReadDouble(listing['lat']) ??
        _tryReadDouble(listing['latitude']);
    final lng =
        _tryReadDouble(
          verificationGeo is Map ? verificationGeo['lng'] : null,
        ) ??
        _tryReadDouble(geo is Map ? geo['lng'] : null) ??
        _tryReadDouble(listing['lng']) ??
        _tryReadDouble(listing['longitude']);

    if (lat == null || lng == null) return null;
    return '${lat.toStringAsFixed(2)}, ${lng.toStringAsFixed(2)}';
  }

  Widget _smallInfoBadge(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.divider),
        ),
        child: Text(
          text,
          style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
        ),
      ),
    );
  }

  String _safeText(
    Map<String, dynamic>? map,
    String key, {
    String fallback = '',
  }) {
    if (map == null) return fallback;
    final value = map[key];
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  bool _isTrue(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  /// Phase-1 accepted detection supports multiple existing fields safely.
  bool isBidAccepted({
    required String currentUserUid,
    required Map<String, dynamic>? dealData,
    required Map<String, dynamic> listingData,
  }) {
    final deal = dealData ?? const <String, dynamic>{};
    final acceptedBuyerUid =
        (deal['acceptedBuyerUid'] ?? listingData['acceptedBuyerUid'] ?? '')
            .toString()
            .trim();
    if (acceptedBuyerUid.isNotEmpty &&
        currentUserUid.isNotEmpty &&
        acceptedBuyerUid != currentUserUid) {
      return false;
    }

    final status =
        (deal['status'] ??
                deal['dealStatus'] ??
                listingData['status'] ??
                listingData['listingStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final acceptedBidId =
        (deal['acceptedBidId'] ?? listingData['acceptedBidId'] ?? '')
            .toString()
            .trim();
    final bool acceptedForCurrentBuyer =
        acceptedBuyerUid.isNotEmpty && acceptedBuyerUid == currentUserUid;
    final bool dealOwnedByCurrentBuyer =
        (deal['buyerId'] ?? '').toString().trim() == currentUserUid;
    final bool dealHasAcceptedSignal =
        status == 'bid_accepted' ||
        deal['acceptedAt'] != null ||
        acceptedBidId.isNotEmpty;

    return acceptedForCurrentBuyer ||
        (dealOwnedByCurrentBuyer && dealHasAcceptedSignal);
  }

  /// Contact unlocks when accepted state is present for current buyer.
  bool isContactUnlocked({
    required String currentUserUid,
    required Map<String, dynamic>? dealData,
    required Map<String, dynamic> listingData,
  }) {
    final deal = dealData ?? const <String, dynamic>{};
    final acceptedBuyerUid =
        (deal['acceptedBuyerUid'] ?? listingData['acceptedBuyerUid'] ?? '')
            .toString()
            .trim();
    final bool acceptedForCurrentBuyer =
        acceptedBuyerUid.isNotEmpty && acceptedBuyerUid == currentUserUid;
    final bool explicitUnlockForAcceptedBuyer =
        (_isTrue(deal['contactUnlocked']) ||
            _isTrue(listingData['contactUnlocked'])) &&
        acceptedForCurrentBuyer;

    return explicitUnlockForAcceptedBuyer ||
        isBidAccepted(
          currentUserUid: currentUserUid,
          dealData: deal,
          listingData: listingData,
        );
  }

  String _firstText(
    Map<String, dynamic>? map,
    List<String> keys, {
    String fallback = '',
  }) {
    final data = map ?? const <String, dynamic>{};
    for (final key in keys) {
      final value = _safeText(data, key);
      if (value.isNotEmpty) {
        return value;
      }
    }

    final media = data['mediaMetadata'];
    if (media is Map) {
      for (final key in keys) {
        final value = (media[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }

      final verificationVideo = media['verificationVideo'];
      if (verificationVideo is Map) {
        final url = (verificationVideo['url'] ?? '').toString().trim();
        if (url.isNotEmpty && url.toLowerCase() != 'null') {
          return url;
        }
      }

      final trustPhoto = media['verificationTrustPhoto'];
      if (trustPhoto is Map) {
        final url = (trustPhoto['url'] ?? '').toString().trim();
        if (url.isNotEmpty && url.toLowerCase() != 'null') {
          return url;
        }
      }
    }
    return fallback;
  }

  Widget _missingListingView({
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(18),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline_rounded, color: _gold, size: 30),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.secondaryText),
            ),
            const SizedBox(height: 6),
            Text(
              'Listing ID: ${widget.listingId}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryText,
                side: BorderSide(color: _gold.withValues(alpha: 0.6)),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoUrlViewerScreen extends StatelessWidget {
  const _VideoUrlViewerScreen({required this.videoUrl});

  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _BuyerListingDetailScreenState._darkGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.primaryText,
        title: const Text('Product Video URL'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Video URL',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                videoUrl,
                style: const TextStyle(color: AppColors.secondaryText),
              ),
              const SizedBox(height: 12),
              IconButton.filledTonal(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: videoUrl));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video URL copied.')),
                  );
                },
                icon: const Icon(Icons.copy),
                tooltip: 'Copy URL',
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste in browser to verify video',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RiskLevel { low, medium, high }

class _Reason {
  const _Reason({required this.en, required this.ur});

  final String en;
  final String ur;
}

class _RiskReport {
  const _RiskReport({
    required this.level,
    required this.score,
    required this.reasons,
  });

  final _RiskLevel level;
  final int score;
  final List<_Reason> reasons;
}

class _DigitalBackground extends StatelessWidget {
  const _DigitalBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.background),
    );
  }
}
