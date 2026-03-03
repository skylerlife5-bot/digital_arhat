import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ListingModeration extends StatefulWidget {
  const ListingModeration({super.key});

  @override
  State<ListingModeration> createState() => _ListingModerationState();
}

class _ListingModerationState extends State<ListingModeration> {
  static const Color _bg = Color(0xFF0B1F3A);
  static const Color _panel = Color(0xFF122B4A);
  static const Color _gold = Color(0xFFFFD700);
  static const Color _danger = Color(0xFFEF4444);

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _alertsStream;

  @override
  void initState() {
    super.initState();
    _alertsStream = _db
        .collection('admin_alerts')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _resolveAlert({
    required String alertId,
    required String listingId,
    required String action,
  }) async {
    final batch = _db.batch();

    final alertRef = _db.collection('admin_alerts').doc(alertId);
    batch.update(alertRef, {
      'status': 'resolved',
      'resolutionAction': action,
      'resolvedAt': FieldValue.serverTimestamp(),
    });

    final listingRef = _db.collection('listings').doc(listingId);
    if (action == 'approve') {
      batch.update(listingRef, {
        'isSuspicious': false,
        'moderationStatus': 'approved',
        'moderatedAt': FieldValue.serverTimestamp(),
      });
    } else if (action == 'review') {
      batch.update(listingRef, {
        'moderationStatus': 'under_review',
        'moderatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      batch.update(listingRef, {
        'status': 'rejected',
        'moderationStatus': 'rejected',
        'moderatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        title: const Text('AI Suspicious Post Alerts'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _alertsStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _gold));
          }

          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'Admin alerts load nahi ho rahe. Dobara try karein.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final docs = snapshot.data?.docs ?? const [];
          final openAlerts = docs
              .where((doc) => (doc.data()['status'] ?? 'open').toString() != 'resolved')
              .toList();

          if (openAlerts.isEmpty) {
            return const Center(
              child: Text(
                'Koi suspicious AI alert pending nahi hai.',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: openAlerts.length,
            itemBuilder: (context, index) {
              final doc = openAlerts[index];
              final data = doc.data();
              final listingId = (data['listingId'] ?? '').toString();
              final reason = (data['reason'] ?? data['message'] ?? 'AI flagged suspicious pricing.')
                  .toString();
              final confidence = (data['confidence'] ?? '').toString();
              final crop = (data['cropName'] ?? data['title'] ?? 'Unknown Listing').toString();

              return Card(
                color: _panel,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Colors.white24),
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
                              crop,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _danger.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: _danger),
                            ),
                            child: Text(
                              confidence.isEmpty
                                  ? 'Suspicious Alert'
                                  : 'Suspicious ⬢ $confidence',
                              style: const TextStyle(
                                color: Color(0xFFFCA5A5),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        reason,
                        style: const TextStyle(color: Colors.white70, height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Listing ID: $listingId',
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: listingId.isEmpty
                                  ? null
                                  : () => _resolveAlert(
                                        alertId: doc.id,
                                        listingId: listingId,
                                        action: 'review',
                                      ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white38),
                              ),
                              child: const Text('Review'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: listingId.isEmpty
                                  ? null
                                  : () => _resolveAlert(
                                        alertId: doc.id,
                                        listingId: listingId,
                                        action: 'approve',
                                      ),
                              style: FilledButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: _bg,
                              ),
                              child: const Text('Approve'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton(
                              onPressed: listingId.isEmpty
                                  ? null
                                  : () => _resolveAlert(
                                        alertId: doc.id,
                                        listingId: listingId,
                                        action: 'reject',
                                      ),
                              style: FilledButton.styleFrom(backgroundColor: _danger),
                              child: const Text('Reject'),
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
      ),
    );
  }
}

