import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/phase1_notification_engine.dart';

class ListingModeration extends StatefulWidget {
  const ListingModeration({super.key});

  @override
  State<ListingModeration> createState() => _ListingModerationState();
}

class _ListingModerationState extends State<ListingModeration> {
  static const Color _bg = Color(0xFF0B1F3A);
  static const Color _gold = Color(0xFFFFD700);
  static const Color _danger = Color(0xFFEF4444);
  static const Color _ok = Color(0xFF22C55E);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();
  final Set<String> _loadingIds = <String>{};

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
  void initState() {
    super.initState();
  }

  Future<void> _approveListing({
    required String listingId,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _setLoading(listingId, true);
    try {
      final listingSnap = await _db.collection('listings').doc(listingId).get();
      final sellerId =
          ((listingSnap.data() ?? <String, dynamic>{})['sellerId'] ?? '')
              .toString()
              .trim();

      await _db.collection('listings').doc(listingId).set({
        'status': 'approved',
        'isApproved': true,
        'approvedAt': FieldValue.serverTimestamp(),
        'approvedBy': uid,
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing approved successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to approve listing.')),
      );
    } finally {
      _setLoading(listingId, false);
    }
  }

  Future<void> _rejectListing({required String listingId}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    _setLoading(listingId, true);
    try {
      await _db.collection('listings').doc(listingId).set({
        'status': 'rejected',
        'isApproved': false,
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Listing rejected successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to reject listing.')),
      );
    } finally {
      _setLoading(listingId, false);
    }
  }

  void _setLoading(String listingId, bool value) {
    if (!mounted) return;
    setState(() {
      if (value) {
        _loadingIds.add(listingId);
      } else {
        _loadingIds.remove(listingId);
      }
    });
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _mergeDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> pendingDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> notApprovedDocs,
  ) {
    final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final doc in pendingDocs) {
      byId[doc.id] = doc;
    }
    for (final doc in notApprovedDocs) {
      byId[doc.id] = doc;
    }

    final merged = byId.values.where((doc) {
      final data = doc.data();
      final status = _str(data, 'status').toLowerCase();
      final isApproved = data['isApproved'] == true;
      return !isApproved ||
          status == 'pending' ||
          status == 'review' ||
          status == 'under_review' ||
          status == 'pending_verification';
    }).toList()
      ..sort((a, b) => _toMillis(b.data()['createdAt']).compareTo(_toMillis(a.data()['createdAt'])));

    return merged.take(50).toList(growable: false);
  }

  int _toMillis(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    return 0;
  }

  String _str(Map<String, dynamic>? data, String key, {String fallback = ''}) {
    if (data == null || !data.containsKey(key) || data[key] == null) return fallback;
    final text = data[key].toString().trim();
    return text.isEmpty ? fallback : text;
  }

  String _previewImageUrl(Map<String, dynamic> data) {
    return _firstNonEmpty(data, const [
      'videoThumbnailUrl',
      'thumbnailUrl',
      'videoThumb',
      'photoUrl',
      'imageUrl',
      'mediaImageUrl',
    ]);
  }

  String _firstNonEmpty(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = _str(data, key);
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    return '';
  }

  Widget _statusBadge(String statusRaw) {
    final status = statusRaw.toLowerCase();
    final bool approved = status == 'approved';
    final bool rejected = status == 'rejected';
    final Color color = approved ? _ok : (rejected ? _danger : Colors.orange);
    final String label = approved ? 'Approved' : (rejected ? 'Rejected' : 'Pending');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.8)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }

  bool _canModerate(String statusRaw, bool isApproved) {
    final status = statusRaw.toLowerCase();
    if (status == 'approved') return false;
    if (status == 'rejected') return false;
    if (status == 'pending' ||
        status == 'review' ||
        status == 'under_review' ||
        status == 'pending_verification') {
      return true;
    }
    return !isApproved;
  }

  Widget _aiSuggestionPanel(Map<String, dynamic> data) {
    final rawLevel = _str(data, 'aiRiskLevel');
    final rawScore = data['aiRiskScore'];
    final scoreText = rawScore == null ? '' : rawScore.toString();
    if (rawLevel.isEmpty && scoreText.isEmpty) {
      return const SizedBox.shrink();
    }

    final level = rawLevel.isEmpty
        ? 'Unknown'
        : '${rawLevel[0].toUpperCase()}${rawLevel.substring(1).toLowerCase()}';

    final reasons = <String>[];
    final dynamic reasonData = data['aiReasons'] ?? data['aiRiskReasons'] ?? data['reasons'];
    if (reasonData is List) {
      for (final item in reasonData) {
        final text = item?.toString().trim() ?? '';
        if (text.isNotEmpty) reasons.add(text);
      }
    } else if (reasonData is String) {
      final text = reasonData.trim();
      if (text.isNotEmpty) reasons.add(text);
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            scoreText.isEmpty
                ? 'AI Suggestion: $level'
                : 'AI Suggestion: $level ($scoreText)',
            style: const TextStyle(
              color: Color(0xFFBFDBFE),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                iconColor: Colors.white70,
                collapsedIconColor: Colors.white70,
                title: const Text(
                  'Reasons',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                children: reasons
                    .map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '- $reason',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openVideoUrlViewer(String videoUrl) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _VideoUrlViewerScreen(videoUrl: videoUrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('Listing Moderation Queue'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _pendingStream(),
        builder: (context, pendingSnapshot) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _notApprovedStream(),
            builder: (context, notApprovedSnapshot) {
              if (pendingSnapshot.connectionState == ConnectionState.waiting ||
                  notApprovedSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _gold));
              }

              if (pendingSnapshot.hasError || notApprovedSnapshot.hasError) {
                return const Center(
                  child: Text(
                    'Unable to load moderation queue. Please try again.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final docs = _mergeDocs(
                pendingSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                notApprovedSnapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
              );

              if (docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No listings currently need moderation.',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  final data = doc.data();
                  final listingId = doc.id;
                  final loading = _loadingIds.contains(listingId);

                  final title = _str(
                    data,
                    'itemName',
                    fallback: _str(data, 'cropName', fallback: 'Untitled listing'),
                  );
                  final district = _str(data, 'district');
                  final province = _str(data, 'province');
                  final quantity = _str(data, 'quantity');
                  final unit = _str(data, 'unit');
                  final status = _str(data, 'status', fallback: 'pending');
                  final isApproved = data['isApproved'] == true;
                  final canModerate = _canModerate(status, isApproved);

                  final imageUrl = _previewImageUrl(data);
                  final videoUrl = (data['videoUrl'] ?? '').toString().trim();
                  final hasVideo = videoUrl.isNotEmpty;

                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Color(0xFF0F172A),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _openReportBadge(listingId),
                              const SizedBox(width: 8),
                              _statusBadge(status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Location: ${district.isEmpty ? 'N/A' : district} / ${province.isEmpty ? 'N/A' : province}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Quantity: ${quantity.isEmpty ? 'N/A' : quantity} ${unit.isEmpty ? '' : unit}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 120,
                              width: double.infinity,
                              child: imageUrl.isNotEmpty
                                  ? Image.network(
                                      imageUrl,
                                      fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              _mediaPlaceholder(),
                                    )
                                  : _mediaPlaceholder(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: hasVideo
                                      ? const Color(0xFFE0E7FF)
                                      : const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: hasVideo
                                        ? const Color(0xFF6366F1)
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                                child: Text(
                                  hasVideo ? 'Video evidence attached' : 'No video attached',
                                  style: TextStyle(
                                    color: hasVideo
                                        ? const Color(0xFF4338CA)
                                        : const Color(0xFF475569),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              OutlinedButton.icon(
                                onPressed: hasVideo ? () => _openVideoUrlViewer(videoUrl) : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(120, 48),
                                ),
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('Open video'),
                              ),
                            ],
                          ),
                          _aiSuggestionPanel(data),
                          const SizedBox(height: 12),
                          if (canModerate)
                            Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: OutlinedButton.icon(
                                      onPressed: loading ? null : () => _rejectListing(listingId: listingId),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: _danger,
                                        side: const BorderSide(color: _danger),
                                      ),
                                      icon: loading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(strokeWidth: 2),
                                            )
                                          : const Icon(Icons.close, size: 18),
                                      label: const Text('Reject'),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: SizedBox(
                                    height: 48,
                                    child: FilledButton.icon(
                                      onPressed: loading ? null : () => _approveListing(listingId: listingId),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: _ok,
                                        foregroundColor: Colors.white,
                                      ),
                                      icon: loading
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.check_circle, size: 18),
                                      label: const Text('Approve'),
                                    ),
                                  ),
                                ),
                              ],
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
      ),
    );
  }

  Widget _mediaPlaceholder() {
    return Container(
      color: const Color(0xFFF8FAFC),
      alignment: Alignment.center,
      child: const Text(
        'No Photo / No Video',
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _openReportBadge(String listingId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('reports')
          .where('listingId', isEqualTo: listingId)
          .where('status', isEqualTo: 'open')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        final Color color = count > 0 ? const Color(0xFFFB7185) : const Color(0xFF94A3B8);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.75)),
          ),
          child: Text(
            'Open reports: $count',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
          ),
        );
      },
    );
  }
}

class _VideoUrlViewerScreen extends StatelessWidget {
  const _VideoUrlViewerScreen({required this.videoUrl});

  final String videoUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1F3A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B1F3A),
        foregroundColor: Colors.white,
        title: const Text('Video Review URL'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF122B4A),
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
              IconButton.filledTonal(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: videoUrl));
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Video URL copied to clipboard.')),
                  );
                },
                icon: const Icon(Icons.copy),
                tooltip: 'Copy URL',
              ),
              const SizedBox(height: 10),
              const Text(
                'Paste in browser to verify video',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

