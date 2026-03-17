import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/buyer_engagement_service.dart';
import '../../theme/app_colors.dart';
import 'buyer_listing_detail_screen.dart';

class WatchlistScreen extends StatelessWidget {
  WatchlistScreen({super.key});

  final BuyerEngagementService _engagementService = BuyerEngagementService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Watchlist / محفوظ لسٹنگز',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _engagementService.watchlistStream(limit: 100),
        builder: (context, watchlistSnapshot) {
          if (watchlistSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accentGold),
            );
          }

          final docs = watchlistSnapshot.data?.docs ?? const [];
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.accentGold,
                      size: 54,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No saved listings yet',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Tap the heart icon on listings to build your watchlist / لسٹنگ پر دل کا بٹن دبائیں',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        height: 1.35,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = docs[index].data();
              final listingId = (item['listingId'] ?? docs[index].id)
                  .toString()
                  .trim();

              return _WatchlistRow(
                listingId: listingId,
                watchlistData: item,
                onRemove: () async {
                  await _engagementService.removeFromWatchlist(listingId);
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _WatchlistRow extends StatelessWidget {
  const _WatchlistRow({
    required this.listingId,
    required this.watchlistData,
    required this.onRemove,
  });

  final String listingId;
  final Map<String, dynamic> watchlistData;
  final Future<void> Function() onRemove;

  @override
  Widget build(BuildContext context) {
    if (listingId.isEmpty) {
      return const SizedBox.shrink();
    }

    final listingStream = FirebaseFirestore.instance
        .collection('listings')
        .doc(listingId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: listingStream,
      builder: (context, listingSnapshot) {
        final listingData = listingSnapshot.data?.data() ?? watchlistData;
        final exists = listingSnapshot.data?.exists ?? true;

        final title = (listingData['product'] ??
                listingData['subcategoryLabel'] ??
                watchlistData['title'] ??
                'Listing')
            .toString();
        final price = (listingData['price'] ??
                listingData['basePrice'] ??
                watchlistData['price'] ??
                0)
            .toString();
        final location = (listingData['city'] ??
                listingData['district'] ??
                listingData['province'] ??
                watchlistData['district'] ??
                watchlistData['province'] ??
                'Pakistan')
            .toString();
        final thumb = (listingData['thumbnailUrl'] ??
                listingData['imageUrl'] ??
                watchlistData['thumbnailUrl'] ??
                '')
            .toString();

        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: !exists
              ? null
              : () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => BuyerListingDetailScreen(
                        listingId: listingId,
                        initialData: listingData,
                      ),
                    ),
                  );
                },
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 70,
                    height: 70,
                    child: thumb.trim().isEmpty
                        ? Container(
                            color: AppColors.background,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.inventory_2_rounded,
                              color: AppColors.secondaryText,
                            ),
                          )
                        : Image.network(
                            thumb,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AppColors.background,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                                color: AppColors.secondaryText,
                              ),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rs. $price',
                        style: const TextStyle(
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        exists ? location : 'Listing no longer available',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: exists
                              ? AppColors.secondaryText
                              : AppColors.urgencyRed,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () async {
                    await onRemove();
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        duration: Duration(seconds: 2),
                        content: Text('Removed from watchlist'),
                      ),
                    );
                  },
                  icon: const Icon(
                    Icons.favorite,
                    color: AppColors.urgencyRed,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
