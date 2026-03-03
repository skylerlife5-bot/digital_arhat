import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../core/widgets/custom_app_bar.dart';
import 'admin_verification_logic.dart';

class AdminPaymentVerificationScreen extends StatefulWidget {
  const AdminPaymentVerificationScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminPaymentVerificationScreen> createState() =>
      _AdminPaymentVerificationScreenState();
}

class _AdminPaymentVerificationScreenState
    extends State<AdminPaymentVerificationScreen> {
  static const Color _navy = Color(0xFF0A1931);
  static const Color _royalBlue = Color(0xFF122B4A);
  static const Color _cardBlue = Color(0xFF183B63);
  static const Color _textLight = Colors.white;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AdminVerificationLogic _verificationLogic = AdminVerificationLogic();
  final Set<String> _verifyingListingIds = <String>{};
  final Set<String> _rejectingListingIds = <String>{};
  int _refreshTick = 0;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _money(double value) => value.toStringAsFixed(0);

  bool _isBusy(String listingId) {
    return _verifyingListingIds.contains(listingId) ||
        _rejectingListingIds.contains(listingId);
  }

  Future<void> _showActionResultDialog({
    required String title,
    required String message,
    required Color accent,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'payment_action_result',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 360),
      pageBuilder: (context, animation, secondaryAnimation) {
        return AlertDialog(
          backgroundColor: _navy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            title,
            style: TextStyle(color: accent, fontWeight: FontWeight.w700),
          ),
          content: Text(message, style: const TextStyle(color: Colors.white)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: curved, child: child),
        );
      },
    );
  }

  Future<void> _verifyPayment({
    required String listingId,
    required Map<String, dynamic> data,
  }) async {
    if (_isBusy(listingId)) return;

    setState(() => _verifyingListingIds.add(listingId));
    try {
      await _verificationLogic.confirmPayment(
        listingId: listingId,
        listingData: data,
      );

      if (!mounted) return;
      await _showActionResultDialog(
        title: 'Payment Approved',
        message: 'Buyer and seller have been notified successfully.',
        accent: Colors.greenAccent,
      );
    } catch (_) {
      if (!mounted) return;
      await _showActionResultDialog(
        title: 'Approval Failed',
        message: 'Unable to approve payment right now. Please try again.',
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => _verifyingListingIds.remove(listingId));
      }
    }
  }

  Future<void> _rejectPayment({
    required String listingId,
    required Map<String, dynamic> data,
    required String reason,
  }) async {
    if (_isBusy(listingId)) return;

    setState(() => _rejectingListingIds.add(listingId));
    try {
      await _verificationLogic.rejectPayment(
        listingId: listingId,
        listingData: data,
        reason: reason,
      );

      if (!mounted) return;
      await _showActionResultDialog(
        title: 'Receipt Rejected',
        message: 'Buyer has been notified to re-upload a valid receipt.',
        accent: Colors.orangeAccent,
      );
    } catch (_) {
      if (!mounted) return;
      await _showActionResultDialog(
        title: 'Reject Failed',
        message: 'Unable to complete reject action right now. Please retry.',
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => _rejectingListingIds.remove(listingId));
      }
    }
  }

  Future<void> _refreshReceipts() async {
    await _db
        .collection('listings')
        .where('status', isEqualTo: 'awaiting_admin_approval')
        .limit(20)
        .get();
    if (mounted) {
      setState(() => _refreshTick++);
    }
  }

  Future<String?> _askRejectionReason() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reason of Rejection'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Image not clear / Wrong amount',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) return;
              Navigator.pop(context, reason);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _openInspectionDialog({
    required String listingId,
    required Map<String, dynamic> data,
  }) async {
    final busy = _isBusy(listingId);
    final receiptUrl = (data['paymentReceiptUrl'] ?? '').toString().trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: _navy,
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Receipt Inspection',
                    style: TextStyle(
                      color: _textLight,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (receiptUrl.isNotEmpty)
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          receiptUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stackTrace) => const SizedBox(
                            height: 180,
                            child: Center(
                              child: Text(
                                'Unable to load receipt image',
                                style: TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Receipt image not found.',
                        style: TextStyle(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  Navigator.pop(context);
                                  await _verifyPayment(
                                    listingId: listingId,
                                    data: data,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('�S& APPROVE PAYMENT'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final navigator = Navigator.of(context);
                                  final reason = await _askRejectionReason();
                                  if (reason == null || reason.trim().isEmpty) {
                                    return;
                                  }
                                  if (!mounted) return;
                                  navigator.pop();
                                  await _rejectPayment(
                                    listingId: listingId,
                                    data: data,
                                    reason: reason,
                                  );
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('�R REJECT RECEIPT'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBody() {
    return Container(
      color: _navy,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db
            .collection('listings')
            .where('status', isEqualTo: 'awaiting_admin_approval')
            .orderBy('updatedAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          final docs =
              snapshot.data?.docs ??
              <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final pendingDocs = docs.toList();

          if (pendingDocs.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refreshReceipts,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 220),
                  Center(
                    child: Text(
                      'No receipts awaiting admin approval',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refreshReceipts,
            child: ListView.separated(
              key: ValueKey<int>(_refreshTick),
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 700,
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 22),
              itemCount: pendingDocs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final doc = pendingDocs[index];
                final data = doc.data();
                final listingId = doc.id;
                final title =
                    (data['product'] ?? data['itemName'] ?? 'Untitled Listing')
                        .toString();
                final amount = _toDouble(data['currentPrice']) > 0
                    ? _toDouble(data['currentPrice'])
                    : (_toDouble(data['finalPrice']) > 0
                          ? _toDouble(data['finalPrice'])
                          : (_toDouble(data['highestBid']) > 0
                                ? _toDouble(data['highestBid'])
                                : _toDouble(data['price'])));
                final buyerId =
                    (data['buyerId'] ?? data['winnerId'] ?? '--').toString();

                return Material(
                  color: _cardBlue,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _isBusy(listingId)
                        ? null
                        : () => _openInspectionDialog(
                            listingId: listingId,
                            data: data,
                          ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: _textLight,
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Price: Rs. ${_money(amount)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Buyer ID: $buyerId',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Listing ID: $listingId',
                            style: const TextStyle(color: Colors.white54),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (_verifyingListingIds.contains(listingId) ||
                                  _rejectingListingIds.contains(listingId))
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Text(
                                  'Tap to inspect receipt',
                                  style: TextStyle(color: Colors.white70),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return _buildBody();
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Admin Escrow Verification',
        backgroundColor: _royalBlue,
      ),
      body: _buildBody(),
    );
  }
}

