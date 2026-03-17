import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/media_preview_widget.dart';
import '../../services/marketplace_service.dart';
import '../../services/phase1_notification_engine.dart';

class PendingListingsScreen extends StatefulWidget {
  const PendingListingsScreen({super.key});

  @override
  State<PendingListingsScreen> createState() => _PendingListingsScreenState();
}

class _PendingListingsScreenState extends State<PendingListingsScreen> {

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MarketplaceService _marketplaceService = MarketplaceService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();
  final Set<String> _loadingListingIds = <String>{};

  static const Color panel = Color(0xFF122B4A);

  Stream<QuerySnapshot<Map<String, dynamic>>> _pendingStream() {
    return _db
        .collection('listings')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _notApprovedStream() {
    return _db
        .collection('listings')
        .where('isApproved', isEqualTo: false)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _pendingStream(),
      builder: (context, pendingSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _notApprovedStream(),
          builder: (context, notApprovedSnapshot) {
            final docs = _mergeModerationDocs(
              pendingSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              notApprovedSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
            );

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
                      'All Clear',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'No listings are waiting for moderation right now.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 1120 ? 3 : (width >= 700 ? 2 : 1);

                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: docs.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    mainAxisExtent: crossAxisCount == 1 ? 398 : 372,
                  ),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final imageUrl = _previewImageUrl(data);
                    final videoUrl = _videoUrl(data);
                    final hasVideo = videoUrl.isNotEmpty;
                    final crop = _str(data, 'product', fallback: 'Fasal');
                    final price = _num(data, 'price');
                    final riskLevel = _aiRiskLevel(data);
                    final riskScore = _num(data, 'aiRiskScore');
                    final listingStatus = _listingStatus(data);
                    final isLoading = _loadingListingIds.contains(doc.id);

                    return InkWell(
                      onTap: isLoading ? null : () => _openReviewDialog(context, doc),
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
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(12),
                                    ),
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                            errorBuilder: (
                                              context,
                                              error,
                                              stackTrace,
                                            ) => _noMediaPlaceholder(),
                                          )
                                        : _noMediaPlaceholder(),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: _statusChip(listingStatus),
                                  ),
                                  if (hasVideo)
                                    Positioned(
                                      left: 8,
                                      top: 8,
                                      child: _videoBadge(),
                                    ),
                                  if (isLoading)
                                    Positioned.fill(
                                      child: Container(
                                        color: Colors.black45,
                                        child: const Center(
                                          child: SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.6,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
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
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isLoading
                                          ? null
                                          : () => _openListingBidsDialog(context, doc.id, data),
                                      icon: const Icon(Icons.gavel, size: 16),
                                      label: const Text('View Bids'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.white24),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isLoading || !hasVideo
                                          ? null
                                          : () => _openVideoViewer(context, videoUrl),
                                      icon: const Icon(Icons.play_circle_outline, size: 16),
                                      label: const Text('Open video'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.white,
                                        side: const BorderSide(color: Colors.white24),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: isLoading
                                          ? null
                                          : () => _rejectListing(context, doc.id),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.redAccent,
                                        side: const BorderSide(color: Colors.redAccent),
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      icon: const Icon(Icons.close, size: 18),
                                      label: const Text('Reject'),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: isLoading
                                          ? null
                                          : () => _approveListing(context, doc.id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 12),
                                      ),
                                      icon: const Icon(Icons.check_circle, size: 18),
                                      label: const Text('Approve'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: _aiRiskBox(
                                level: riskLevel,
                                score: riskScore,
                                reasons: _aiReasons(data),
                                suggestion: _str(
                                  data,
                                  'aiSuggestedAction',
                                  fallback: 'review',
                                ),
                                expanded: false,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
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
    final imageUrl = _previewImageUrl(data);
    final videoUrl = _videoUrl(data);
    final audioUrl = _str(data, 'audioUrl');
    final riskLevel = _aiRiskLevel(data);
    final riskScore = _num(data, 'aiRiskScore');
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
                  'Product: $crop',
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
                _aiRiskBox(
                  level: riskLevel,
                  score: riskScore,
                  reasons: _aiReasons(data),
                  suggestion: _str(
                    data,
                    'aiSuggestedAction',
                    fallback: 'review',
                  ),
                  expanded: true,
                ),
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
                            : () => _openVideoViewer(context, videoUrl),
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
              onPressed: _loadingListingIds.contains(listingDoc.id)
                  ? null
                  : () async {
                      await _rejectListing(context, listingDoc.id, dialogContext: ctx);
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
              onPressed: _loadingListingIds.contains(listingDoc.id)
                  ? null
                  : () => _approveListing(
                      context,
                      listingDoc.id,
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
    {
    BuildContext? dialogContext,
  }) async {
    _setListingLoading(listingId, true);
    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      final listingSnap = await _db.collection('listings').doc(listingId).get();
      final sellerId =
          ((listingSnap.data() ?? <String, dynamic>{})['sellerId'] ?? '')
              .toString()
              .trim();

      await _db.collection('listings').doc(listingId).set({
        'status': 'approved',
        'isApproved': true,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (sellerId.isNotEmpty) {
        await _phase1Notifications.createOnce(
          userId: sellerId,
          type: Phase1NotificationType.listingApproved,
          listingId: listingId,
          targetRole: 'seller',
        );
      }

      if (!context.mounted) return;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Listing approved and now visible to buyers.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not approve listing. Please try again.'),
        ),
      );
    } finally {
      _setListingLoading(listingId, false);
    }
  }

  Future<void> _rejectListing(
    BuildContext context,
    String listingId, {
    BuildContext? dialogContext,
  }) async {
    _setListingLoading(listingId, true);
    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
      await _db.collection('listings').doc(listingId).set({
        'status': 'rejected',
        'isApproved': false,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': adminId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!context.mounted) return;
      if (dialogContext != null && dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Listing rejected.'),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not reject listing. Please try again.'),
        ),
      );
    } finally {
      _setListingLoading(listingId, false);
    }
  }

  void _setListingLoading(String listingId, bool isLoading) {
    if (!mounted) return;
    setState(() {
      if (isLoading) {
        _loadingListingIds.add(listingId);
      } else {
        _loadingListingIds.remove(listingId);
      }
    });
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
          '$crop - Recent bids',
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
                    'Unable to load bids for this listing.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final bids = snapshot.data?.docs ?? [];
              if (bids.isEmpty) {
                return const Center(
                  child: Text(
                    'No bids have been placed yet.',
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
                    fallback: 'Buyer',
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

  Widget _aiRiskBox({
    required String level,
    required double score,
    required List<String> reasons,
    required String suggestion,
    required bool expanded,
  }) {
    final normalizedLevel = level.toLowerCase();
    final bool isHigh = normalizedLevel == 'high';
    final bool isMedium = normalizedLevel == 'medium';
    final Color tone = isHigh
        ? Colors.redAccent
        : (isMedium ? Colors.orangeAccent : Colors.greenAccent);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AI Risk: ${normalizedLevel.toUpperCase()} (${score.toStringAsFixed(0)})',
            style: TextStyle(
              color: tone,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'AI suggestion - final decision by admin',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          Text(
            'Suggested action: ${suggestion.trim().isEmpty ? 'review' : suggestion}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          if (expanded)
            ...reasons
                .take(4)
                .map(
                  (reason) => Text(
                    '• $reason',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
        ],
      ),
    );
  }

  String _aiRiskLevel(Map<String, dynamic> data) {
    final level = _str(data, 'aiRiskLevel', fallback: 'low').toLowerCase();
    if (level == 'high' || level == 'medium' || level == 'low') {
      return level;
    }
    return 'low';
  }

  List<String> _aiReasons(Map<String, dynamic> data) {
    final raw = data['aiReasons'];
    if (raw is List) {
      final reasons = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
      if (reasons.isNotEmpty) return reasons;
    }

    final fallback = _str(
      data,
      'riskSummary',
      fallback: 'System checks recommend manual review.',
    );
    return <String>[fallback];
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

  Future<void> _openVideoViewer(
    BuildContext context,
    String videoUrl,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _VideoUrlViewerScreen(videoUrl: videoUrl),
      ),
    );
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeModerationDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notApprovedDocs,
  ) {
    // Firestore OR fallback: merge two query results in-memory and de-duplicate by doc id.
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in pendingDocs) {
      byId[doc.id] = doc;
    }
    for (final doc in notApprovedDocs) {
      byId[doc.id] = doc;
    }

    final merged = byId.values.where(_needsModeration).toList()
      ..sort(_moderationComparator);
    return merged.take(50).toList(growable: false);
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

    addIfValid(rawData['photoUrl']);
    addIfValid(rawData['imageUrl']);
    addIfValid(rawData['mediaImageUrl']);
    addIfValid(rawData['thumbnailUrl']);
    addIfValid(rawData['videoThumbnailUrl']);
    addIfValid(rawData['videoThumb']);
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

  String _previewImageUrl(Map<String, dynamic> data) {
    return _firstNonEmpty(
      data,
      const [
        'videoThumbnailUrl',
        'thumbnailUrl',
        'videoThumb',
        'photoUrl',
        'imageUrl',
        'mediaImageUrl',
      ],
    );
  }

  String _videoUrl(Map<String, dynamic> data) {
    return _firstNonEmpty(
      data,
      const ['videoUrl', 'videoURL', 'mediaVideoUrl'],
    );
  }

  String _firstNonEmpty(Map<String, dynamic>? data, List<String> keys) {
    if (data == null) return '';
    for (final key in keys) {
      final value = _str(data, key).trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  bool _needsModeration(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final status = _listingStatus(data);
    final isApproved = data['isApproved'] == true;
    return !isApproved ||
        status == 'pending' ||
        status == 'pending_verification' ||
        status == 'under_review' ||
        status == 'review';
  }

  int _moderationComparator(
    QueryDocumentSnapshot<Map<String, dynamic>> a,
    QueryDocumentSnapshot<Map<String, dynamic>> b,
  ) {
    final statusA = _listingStatus(a.data());
    final statusB = _listingStatus(b.data());
    final priorityA = _statusPriority(statusA);
    final priorityB = _statusPriority(statusB);
    if (priorityA != priorityB) {
      return priorityA.compareTo(priorityB);
    }

    final tsA = _toMillis(a.data()['createdAt']);
    final tsB = _toMillis(b.data()['createdAt']);
    return tsB.compareTo(tsA);
  }

  int _statusPriority(String status) {
    if (status == 'pending') return 0;
    if (status == 'pending_verification' || status == 'under_review' || status == 'review') {
      return 1;
    }
    return 2;
  }

  String _listingStatus(Map<String, dynamic>? data) {
    return _str(data, 'status').trim().toLowerCase();
  }

  int _toMillis(dynamic value) {
    if (value is Timestamp) {
      return value.millisecondsSinceEpoch;
    }
    if (value is DateTime) {
      return value.millisecondsSinceEpoch;
    }
    return 0;
  }

  Widget _statusChip(String status) {
    final normalized = status.trim().toLowerCase();
    final bool isApproved = normalized == 'approved';
    final bool isRejected = normalized == 'rejected';
    final color = isApproved
      ? Colors.greenAccent
      : (isRejected ? Colors.redAccent : Colors.orangeAccent);
    final label = isApproved
      ? 'Approved'
      : (isRejected ? 'Rejected' : 'Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _videoBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white30),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_rounded, color: Colors.white, size: 12),
          SizedBox(width: 4),
          Text(
            'Video attached',
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _noMediaPlaceholder() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, color: Colors.white54),
            SizedBox(height: 4),
            Text(
              'No media available',
              style: TextStyle(color: Colors.white54, fontSize: 11),
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
    // Minimal no-package viewer: selectable URL + copy/open actions.
    return Scaffold(
      backgroundColor: const Color(0xFF122B4A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF122B4A),
        title: const Text('Video Review URL'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Video URL',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              SelectableText(
                videoUrl,
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: videoUrl));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Video URL copied to clipboard.')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy URL'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final uri = Uri.tryParse(videoUrl);
                      if (uri == null) return;
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open Externally'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}


