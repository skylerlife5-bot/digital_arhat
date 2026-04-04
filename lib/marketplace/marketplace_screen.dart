import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../core/widgets/premium_ui_kit.dart';
import '../core/widgets/customer_support_button.dart';
import '../core/widgets/media_preview_widget.dart';
import '../dashboard/buyer/bid_bottom_sheet.dart';
import '../models/deal_status.dart';
import '../services/bid_eligibility_service.dart';
import '../services/trust_safety_service.dart';

// Legacy marketplace implementation retained for reference.
// Canonical buyer runtime uses dashboard buyer screens.

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: _buildAppDrawer(context),
        appBar: AppBar(
          title: Image.asset(
            'assets/logo.png',
            height: 28,
            fit: BoxFit.contain,
          ),
          backgroundColor: const Color(0xFF0E3B2E),
          foregroundColor: AppColors.primaryText,
          centerTitle: true,
          elevation: 0,
          actions: [
            const CustomerSupportIconAction(),
            IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.search_rounded,
                color: AppColors.accentGold,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                PremiumSpacing.screenHorizontal,
                PremiumSpacing.s1,
                PremiumSpacing.screenHorizontal,
                PremiumSpacing.s2,
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF145A41).withValues(alpha: 0.45),
                    const Color(0xFF0E3B2E).withValues(alpha: 0.18),
                  ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: AppColors.primaryText12,
                  ),
                ),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PremiumSectionHeader(
                    titleUr: 'سلام، آج کی منڈی ڈیلز دیکھیں',
                    titleEn: 'Salam, explore today\'s mandi deals',
                  ),
                  SizedBox(height: PremiumSpacing.s1_5),
                  PremiumSearchBar(
                    hintText: 'فصل، شہر یا منڈی تلاش کریں / Search crop, city, mandi',
                  ),
                  SizedBox(height: PremiumSpacing.s1),
                  PremiumFilterChipRow(
                    labels: ['Punjab', 'Crops', 'Lahore', 'Filters'],
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(
                PremiumSpacing.screenHorizontal,
                PremiumSpacing.s1_5,
                PremiumSpacing.screenHorizontal,
                PremiumSpacing.s1,
              ),
              child: PremiumSectionHeader(
                titleUr: 'فعال لسٹنگز',
                titleEn: 'Active marketplace listings',
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // Show all active ads + buyer's own awaiting-payment won ad.
                stream: FirebaseFirestore.instance
                    .collection('listings')
                    .where(
                      Filter.or(
                        Filter(
                          'listingStatus',
                          isEqualTo: DealStatus.active.value,
                        ),
                        Filter(
                          'listingStatus',
                          isEqualTo: DealStatus.active.name,
                        ),
                        Filter.and(
                          Filter(
                            'listingStatus',
                            isEqualTo: DealStatus.awaitingPayment.value,
                          ),
                          Filter(
                            'winnerId',
                            isEqualTo:
                                FirebaseAuth.instance.currentUser?.uid ??
                                '__no_user__',
                          ),
                        ),
                        Filter.and(
                          Filter(
                            'listingStatus',
                            isEqualTo: DealStatus.awaitingPayment.name,
                          ),
                          Filter(
                            'winnerId',
                            isEqualTo:
                                FirebaseAuth.instance.currentUser?.uid ??
                                '__no_user__',
                          ),
                        ),
                      ),
                    )
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.accentGold,
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final listings = List<QueryDocumentSnapshot>.from(
                    snapshot.data!.docs,
                  )..sort((a, b) {
                      final aData = a.data() as Map<String, dynamic>;
                      final bData = b.data() as Map<String, dynamic>;
                      final scoreCompare = _featuredVisibilityScore(
                        bData,
                      ).compareTo(_featuredVisibilityScore(aData));
                      if (scoreCompare != 0) return scoreCompare;

                      final aTime = _parseListingTime(
                        aData['bumpedAt'] ?? aData['createdAt'],
                      );
                      final bTime = _parseListingTime(
                        bData['bumpedAt'] ?? bData['createdAt'],
                      );
                      return bTime.compareTo(aTime);
                    });
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PremiumSpacing.screenHorizontal,
                      vertical: PremiumSpacing.s1,
                    ),
                    itemCount: listings.length,
                    itemBuilder: (context, index) {
                      final doc = listings[index];
                      final data = doc.data() as Map<String, dynamic>;
                      return _buildRoyalProductCard(context, data, doc.id);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _promotionStatus(Map<String, dynamic> data) {
    return (data['promotionStatus'] ?? '').toString().trim().toLowerCase();
  }

  bool _isPromotionActive(Map<String, dynamic> data) {
    final status = _promotionStatus(data);
    if (status == 'active') {
      final expires = data['promotionExpiresAt'];
      if (expires is Timestamp) {
        return expires.toDate().isAfter(DateTime.now());
      }
      return true;
    }
    if (status.isNotEmpty && status != 'none') {
      return false;
    }
    final priority = (data['priorityScore'] ?? '').toString().toLowerCase();
    return data['featured'] == true || data['featuredAuction'] == true || priority == 'high';
  }

  DateTime _parseListingTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  double _baseVisibilityScore(Map<String, dynamic> data) {
    final listedAt = _parseListingTime(data['bumpedAt'] ?? data['createdAt']);
    final ageMinutes = DateTime.now().difference(listedAt).inMinutes.toDouble();
    final freshnessScore = -(ageMinutes / 60.0);

    final bidCount = [
      _toInt(data['totalBids']),
      _toInt(data['bidsCount']),
      _toInt(data['bidCount']),
      _toInt(data['bid_count']),
    ].reduce((a, b) => a > b ? a : b);
    final demandScore = bidCount.clamp(0, 6) * 0.05;

    return freshnessScore + demandScore;
  }

  double _featuredVisibilityScore(Map<String, dynamic> data) {
    const promotionBoost = 0.75;
    return _baseVisibilityScore(data) +
        (_isPromotionActive(data) ? promotionBoost : 0.0);
  }

  Widget _buildAppDrawer(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final userName = (user?.displayName ?? 'Digital Arhat User').trim();
    final userId = user?.uid ?? 'unknown_user';

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: AppColors.accentGold,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/logo.png',
                        height: 32,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Digital Arhat',
                        style: TextStyle(
                          color: AppColors.ctaTextDark,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Rabita aur Support',
                    style: TextStyle(
                      color: AppColors.ctaTextDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: AppColors.divider,
                    child: const Text(
                      'WA',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.support_agent,
                    color: AppColors.accentGold,
                  ),
                ],
              ),
              title: const Text('Rabita Support'),
              subtitle: const Text('WhatsApp Business'),
              onTap: () =>
                  _openOfficialSupport(userName: userName, userId: userId),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openOfficialSupport({
    required String userName,
    required String userId,
  }) async {
    const supportNumber = '+923024090114';
    final message =
        'Assalam-o-Alaikum Digital Arhat Team, I am $userName and I need help with my account $userId.';
    final waUri = Uri.parse(
      'https://wa.me/${supportNumber.replaceAll('+', '')}?text=${Uri.encodeComponent(message)}',
    );
    await launchUrl(waUri, mode: LaunchMode.externalApplication);
  }

  // �S& Professional Royal Product Card
  Widget _buildRoyalProductCard(
    BuildContext context,
    Map<String, dynamic> data,
    String docId,
  ) {
    final String auctionStatus = (data['auctionStatus'] ?? data['status'] ?? '')
        .toString()
        .toLowerCase();
    final bool isCompletedAuction =
        auctionStatus == DealStatus.dealCompleted.value;
    final String highestBidderId =
        (data['highestBidderId'] ??
                data['lastBidderId'] ??
                data['buyerId'] ??
                '')
            .toString();
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isCompletedWinner =
        isCompletedAuction &&
        highestBidderId.trim().isNotEmpty &&
        highestBidderId.trim() == currentUserId.trim();

    final bool isAiVerified =
        data['isVerifiedSource'] == true &&
        (data['videoUrl'] ?? '').toString().trim().isNotEmpty;
    final trustBadges = TrustSafetyService.resolveBuyerTrustBadges(
      listingData: data,
    );
    final bool isFeatured = _isPromotionActive(data);
    final bool isHotAuction =
      (data['saleType'] ?? 'auction').toString().toLowerCase() == 'auction' &&
      isFeatured;
    final DateTime now = DateTime.now().toUtc();
    final DateTime? endTime = (data['endTime'] is Timestamp)
      ? (data['endTime'] as Timestamp).toDate().toUtc()
      : null;
    final bool endingSoon =
      endTime != null && endTime.isAfter(now) && endTime.difference(now).inMinutes <= 20;
    final List<String> imageUrls = _extractImageUrls(data);
    final String videoUrl = (data['videoUrl'] ?? '').toString();
    final String audioUrl = (data['audioUrl'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image Section with Status Badges
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: data['imageUrl'] != null && data['imageUrl'] != ""
                    ? Image.network(
                        data['imageUrl'],
                        height: 190,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : _buildImagePlaceholder(),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: _buildBadge(
                  data['district'] ??
                      data['city'] ??
                      data['province'] ??
                      'Pakistan',
                  Icons.location_on,
                  AppColors.divider,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _buildBadge(
                  data['quality'] ?? 'Mayari',
                  Icons.verified,
                  AppColors.accentGold,
                  isGold: true,
                ),
              ),
              if (isFeatured || isHotAuction)
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: _buildBadge(
                    isHotAuction ? '🔥 HOT AUCTION' : 'FEATURED',
                    Icons.workspace_premium_rounded,
                    isHotAuction ? AppColors.urgencyRed : AppColors.accentGold,
                    isGold: !isHotAuction,
                  ),
                ),
              if (endingSoon)
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: _buildBadge(
                    'ENDING SOON',
                    Icons.timer_rounded,
                    AppColors.urgencyRed,
                  ),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        (data['product'] ?? 'Category').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Rs. ${data['basePrice'] ?? data['price'] ?? '--'}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.accentGold,
                      ),
                    ),
                  ],
                ),
                if (isAiVerified) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.accentGold),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          size: 14,
                          color: AppColors.accentGold,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AI Verified',
                          style: TextStyle(
                            color: AppColors.accentGold,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (trustBadges.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: trustBadges
                        .map(
                          (badge) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _trustBadgeColor(badge.key).withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _trustBadgeColor(badge.key).withValues(alpha: 0.7),
                              ),
                            ),
                            child: Text(
                              badge.label,
                              style: TextStyle(
                                color: _trustBadgeColor(badge.key),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Miqdar (Quantity): ${data['quantity'] ?? '--'}',
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.background.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: MediaPreviewWidget(
                    imageUrls: imageUrls,
                    videoUrl: videoUrl,
                    audioUrl: audioUrl,
                    title: 'Media Section',
                  ),
                ),
                const Divider(
                  height: 30,
                  thickness: 1,
                  color: AppColors.divider,
                ),

                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: AppColors.cardSurface,
                      radius: 18,
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: AppColors.accentGold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        trustBadges.any((b) => b.key == 'verified' || b.key == 'trusted')
                            ? 'Verified Seller Signals'
                            : 'Seller details available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryText,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Builder(
                      builder: (context) {
                        final highest = (data['highestBid'] is num)
                            ? (data['highestBid'] as num).toDouble()
                            : double.tryParse((data['highestBid'] ?? '').toString()) ?? 0.0;
                        final base = (data['startingPrice'] is num)
                            ? (data['startingPrice'] as num).toDouble()
                            : double.tryParse((data['startingPrice'] ?? data['basePrice'] ?? data['price'] ?? '').toString()) ?? 0.0;
                        final probeAmount = (highest > 0 ? highest : base) + 1;
                        final bidEligibility = BidEligibilityService.evaluate(
                          buyerId: FirebaseAuth.instance.currentUser?.uid ?? '',
                          listingData: data,
                          bidAmount: probeAmount,
                        );

                        return isCompletedWinner
                            ? ElevatedButton.icon(
                                onPressed: null,
                                icon: const Icon(Icons.handshake_rounded, size: 18),
                                label: const Text('Accepted / قبول شدہ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.divider,
                                  foregroundColor: AppColors.secondaryText,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 4,
                                ),
                              )
                            : Tooltip(
                                message: bidEligibility.allowed ? 'Place Bid' : bidEligibility.message,
                                child: ElevatedButton.icon(
                                  onPressed: !bidEligibility.allowed
                                      ? null
                                      : () async {
                                          await showModalBottomSheet<void>(
                                            context: context,
                                            backgroundColor: Colors.transparent,
                                            isScrollControlled: true,
                                            builder: (_) => BidBottomSheet(
                                              listingId: docId,
                                              listingData: data,
                                            ),
                                          );
                                        },
                                  icon: const Icon(Icons.gavel_rounded, size: 18),
                                  label: const Text('Boli Lagaen'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.accentGold,
                                    foregroundColor: AppColors.ctaTextDark,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 4,
                                  ),
                                ),
                              );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _trustBadgeColor(String key) {
    switch (key) {
      case 'verified':
        return AppColors.divider;
      case 'trusted':
        return AppColors.divider;
      case 'moderated':
        return AppColors.accentGold;
      case 'ai':
        return AppColors.secondaryText;
      default:
        return AppColors.secondaryText;
    }
  }

  Widget _buildBadge(
    String text,
    IconData icon,
    Color color, {
    bool isGold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isGold
            ? AppColors.cardSurface.withValues(alpha: 0.94)
            : AppColors.background.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: isGold ? AppColors.accentGold : color.withValues(alpha: 0.85),
          width: isGold ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isGold ? AppColors.accentGold : color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isGold ? AppColors.primaryText : AppColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      height: 190,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.cardSurface,
            AppColors.background,
          ],
        ),
      ),
      child: const Icon(
        Icons.agriculture_rounded,
        size: 60,
        color: AppColors.secondaryText,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(PremiumSpacing.s2),
        child: PremiumEmptyState(
          icon: Icons.storefront_outlined,
          titleUr: 'ابھی کوئی منڈی آفر موجود نہیں',
          titleEn: 'No mandi offers yet',
          helperUr: 'سب سے پہلا آفر پوسٹ کریں یا فلٹر بدل کر دوبارہ دیکھیں',
          helperEn: 'Post the first offer or adjust filters to explore more',
          primaryAction: const PremiumSecondaryButton(
            label: 'Explore Listings / لسٹنگز دیکھیں',
            onPressed: null,
            icon: Icons.travel_explore_rounded,
          ),
        ),
      ),
    );
  }

  List<String> _extractImageUrls(Map<String, dynamic> rawData) {
    final urls = <String>[];

    void addIfValid(dynamic value) {
      final candidate = (value ?? '').toString().trim();
      if (candidate.isEmpty || candidate.toLowerCase() == 'null') return;
      if (!candidate.startsWith('http')) return;
      if (!urls.contains(candidate)) {
        urls.add(candidate);
      }
    }

    addIfValid(rawData['imageUrl']);
    addIfValid(rawData['image1']);
    addIfValid(rawData['image2']);
    addIfValid(rawData['image3']);
    addIfValid(rawData['image4']);

    final dynamic imagesRaw = rawData['images'];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        addIfValid(item);
      }
    }

    return urls.take(4).toList();
  }
}

