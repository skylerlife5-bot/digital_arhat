import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_colors.dart';
import '../core/widgets/customer_support_button.dart';
import '../core/widgets/ethical_verse_banner.dart';
import '../core/widgets/media_preview_widget.dart';
import '../dashboard/components/bid_dialog.dart';
import '../dashboard/buyer/payment_dialog.dart';
import '../dashboard/components/rate_ticker.dart';
import '../models/deal_status.dart';

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
        backgroundColor: const Color(0xFFF4F7F1),
        drawer: _buildAppDrawer(context),
        appBar: AppBar(
          title: Image.asset(
            'assets/logo.png',
            height: 34,
            fit: BoxFit.contain,
          ),
          backgroundColor: AppColors.primaryGreen,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 4,
          actions: [
            const CustomerSupportIconAction(),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.search_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            const RateTicker(),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: EthicalVerseBanner(maxItems: 1),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 6, 12, 0),
              child: _CategoryChipsRow(),
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
                        color: AppColors.primaryGreen,
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildEmptyState();
                  }

                  final listings = snapshot.data!.docs;
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
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
              color: AppColors.primaryGreen,
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
                          color: Colors.white,
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
                      color: Colors.white,
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
                    backgroundColor: Colors.green.shade600,
                    child: const Text(
                      'WA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.support_agent,
                    color: AppColors.primaryGreen,
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
    final List<String> imageUrls = _extractImageUrls(data);
    final String videoUrl = (data['videoUrl'] ?? '').toString();
    final String audioUrl = (data['audioUrl'] ?? '').toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
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
                  Colors.redAccent,
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: _buildBadge(
                  data['quality'] ?? 'Mayari',
                  Icons.verified,
                  const Color(0xFFFFD700),
                  isGold: true,
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
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Rs. ${data['basePrice'] ?? data['price'] ?? '--'}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
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
                      color: const Color(0xFFFFD700).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFFFD700)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.verified,
                          size: 14,
                          color: Color(0xFFFFD700),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'AI Verified',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'Miqdar (Quantity): ${data['quantity'] ?? '--'}',
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2F18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: MediaPreviewWidget(
                    imageUrls: imageUrls,
                    videoUrl: videoUrl,
                    audioUrl: audioUrl,
                    title: 'Media Section',
                  ),
                ),
                const Divider(height: 30, thickness: 1),

                Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFE8F5E9),
                      radius: 18,
                      child: Icon(
                        Icons.person,
                        size: 20,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Tasdeeq Shuda Seller',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    isCompletedWinner
                        ? ElevatedButton.icon(
                            onPressed: () {
                              showDialog<void>(
                                context: context,
                                builder: (_) => PaymentDialog(
                                  listingId: docId,
                                  listingData: data,
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.account_balance_wallet,
                              size: 18,
                            ),
                            label: const Text('Payment Karein'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                              foregroundColor: Colors.white,
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
                        : ElevatedButton.icon(
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (context) => BidDialog(
                                  productData: data,
                                  listingId: docId,
                                ),
                              );
                            },
                            icon: const Icon(Icons.gavel_rounded, size: 18),
                            label: const Text('Boli Lagaen'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryGreen,
                              foregroundColor: Colors.white,
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
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
            ? const Color(0xFF2E7D32)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(30),
        border: isGold
            ? Border.all(color: const Color(0xFFFFD700), width: 1.5)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: isGold ? const Color(0xFFFFD700) : color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isGold ? Colors.white : Colors.black87,
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
          colors: [Colors.grey[200]!, Colors.grey[300]!],
        ),
      ),
      child: const Icon(
        Icons.agriculture_rounded,
        size: 60,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.eco_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 10),
          const Text(
            'Mandi mein abhi koi maal dastiyab nahi hai.',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ],
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

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow();

  @override
  Widget build(BuildContext context) {
    const labels = <String>['All', 'Crops', 'Livestock', 'Fruits'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: labels
            .map(
              (label) => Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.primaryGreen.withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primaryGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

