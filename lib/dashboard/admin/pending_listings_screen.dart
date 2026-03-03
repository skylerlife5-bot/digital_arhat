import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/widgets/media_preview_widget.dart';
import '../../services/marketplace_service.dart';

class PendingListingsScreen extends StatelessWidget {
  PendingListingsScreen({super.key});

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MarketplaceService _marketplaceService = MarketplaceService();

  static const Color panel = Color(0xFF122B4A);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _marketplaceService.getPendingListingsStream(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.verified_rounded,
                  size: 48,
                  color: Colors.greenAccent,
                ),
                SizedBox(height: 10),
                Text(
                  'Maal Saf Hai!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Abhi koi pending listing mojood nahi.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.90,
          ),
          itemBuilder: (context, index) {
            final doc = docs[index];
            final data = doc.data();
            final imageUrl = _str(data, 'imageUrl');
            final crop = _str(data, 'product', fallback: 'Fasal');
            final price = _num(data, 'price');
            final insight = _geminiInsight(data);

            return InkWell(
              onTap: () => _openReviewDialog(context, doc),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                        child: imageUrl.isNotEmpty
                            ? Image.network(
                                imageUrl,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                color: Colors.white10,
                                child: const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                      child: Text(
                        crop,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Rs. ${price.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () =>
                              _openListingBidsDialog(context, doc.id, data),
                          icon: const Icon(Icons.gavel, size: 16),
                          label: const Text('View Bids'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white24),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: _aiInsightBox(insight),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _openReviewDialog(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> listingDoc,
  ) {
    final data = listingDoc.data();
    final crop = _str(data, 'product', fallback: 'N/A');
    final location = _str(
      data,
      'location',
      fallback: _str(data, 'city', fallback: 'N/A'),
    );
    final price = _num(data, 'price');
    final imageUrl = _str(data, 'imageUrl');
    final videoUrl = _str(data, 'videoUrl');
    final audioUrl = _str(data, 'audioUrl');
    final insight = _geminiInsight(data);
    final mediaImages = _extractImageUrls(data);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: const Text(
          'Listing Review',
          style: TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Crop Name: $crop',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  'Base Price: Rs. ${price.toStringAsFixed(0)}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 6),
                Text(
                  'Location: $location',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                MediaPreviewWidget(
                  imageUrls: mediaImages,
                  videoUrl: videoUrl,
                  audioUrl: audioUrl,
                  title: 'Media Section',
                ),
                const SizedBox(height: 10),
                _aiInsightBox(insight, expanded: true),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: imageUrl.isEmpty
                            ? null
                            : () => _showImage(context, imageUrl),
                        icon: const Icon(Icons.photo),
                        label: const Text('View Photo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: videoUrl.isEmpty
                            ? null
                            : () => _openExternalUrl(videoUrl),
                        icon: const Icon(Icons.video_library),
                        label: const Text('View Video'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _db.collection('listings').doc(listingDoc.id).update({
                  'status': 'rejected',
                  'isApproved': false,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
                if (!context.mounted) return;
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Listing reject kar di gayi.')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                elevation: 3,
              ),
              icon: const Icon(Icons.cancel),
              label: const Text(
                'Reject',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: () => _approveListing(
                context,
                listingDoc.id,
                data,
                dialogContext: ctx,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                elevation: 3,
              ),
              icon: const Icon(Icons.check_circle),
              label: const Text(
                'Approve',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _approveListing(
    BuildContext context,
    String listingId,
    Map<String, dynamic> data, {
    BuildContext? dialogContext,
  }) async {
    final insight = _geminiInsight(data);

    await _marketplaceService.approveAndStartAuction(
      listingId,
      isSuspicious: insight.isUnusual,
      deviationPercent: insight.deviationPercent,
    );

    if (!context.mounted) return;
    if (dialogContext != null) {
      Navigator.pop(dialogContext);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
        content: Text('Mubarak! Maal Mandi mein Live ho gaya hai'),
      ),
    );
  }

  void _openListingBidsDialog(
    BuildContext context,
    String listingId,
    Map<String, dynamic> listingData,
  ) {
    final crop = _str(listingData, 'product', fallback: 'Fasal');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: panel,
        title: Text(
          '$crop ⬢ Recent Bids',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 320,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _marketplaceService.getBidsStream(listingId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Listing bids load nahi ho sakin',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final bids = snapshot.data?.docs ?? [];
              if (bids.isEmpty) {
                return const Center(
                  child: Text(
                    'Abhi tak koi boli nahi lagi',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }

              return ListView.separated(
                itemCount: bids.length,
                separatorBuilder: (context, index) =>
                    const Divider(color: Colors.white12, height: 1),
                itemBuilder: (context, index) {
                  final bidData = bids[index].data();
                  final amount = _num(bidData, 'bidAmount');
                  final buyer = _str(
                    bidData,
                    'buyerName',
                    fallback: 'Kharidar',
                  );
                  final status = _str(bidData, 'status', fallback: 'normal');
                  return ListTile(
                    dense: true,
                    title: Row(
                      children: [
                        Text(
                          'Rs. ${amount.toStringAsFixed(0)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            buyer,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'Status: $status',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _aiInsightBox(_AiCheck insight, {bool expanded = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: insight.isUnusual
            ? Colors.red.withValues(alpha: 0.18)
            : Colors.blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: insight.isUnusual ? Colors.redAccent : Colors.blueAccent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            insight.isUnusual
                ? 'AI Alert: Unusual Price!'
                : 'AI Insight: Price looks normal',
            style: TextStyle(
              color: insight.isUnusual ? Colors.redAccent : Colors.blueAccent,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          if (expanded)
            Text(
              'Deviation: ${insight.deviationPercent.toStringAsFixed(1)}%',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }

  _AiCheck _geminiInsight(Map<String, dynamic> data) {
    final product = _str(data, 'product').toLowerCase();
    final price = _num(data, 'price');

    double? baseline;
    for (final entry in AppConstants.marketPriceByCrop.entries) {
      final key = entry.key.toLowerCase();
      if (product.contains(key) || key.contains(product)) {
        baseline = entry.value;
        break;
      }
    }

    if (baseline == null || baseline <= 0 || price <= 0) {
      return const _AiCheck(isUnusual: false, deviationPercent: 0);
    }

    final deviation = ((price - baseline) / baseline) * 100;
    return _AiCheck(
      isUnusual: deviation.abs() > 20,
      deviationPercent: deviation,
    );
  }

  String _str(Map<String, dynamic>? data, String key, {String fallback = ''}) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return fallback;
    }
    return data[key].toString();
  }

  double _num(Map<String, dynamic>? data, String key, {double fallback = 0}) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return fallback;
    }
    final value = data[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  Future<void> _openExternalUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showImage(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: Image.network(imageUrl, fit: BoxFit.contain),
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

class _AiCheck {
  final bool isUnusual;
  final double deviationPercent;

  const _AiCheck({required this.isUnusual, required this.deviationPercent});
}

