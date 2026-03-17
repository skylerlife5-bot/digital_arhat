import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../chat/chat_screen.dart';
import '../../theme/app_colors.dart';

class BuyerEscrowPaymentScreen extends StatefulWidget {
  const BuyerEscrowPaymentScreen({
    super.key,
    required this.dealId,
    required this.listingId,
  });

  final String dealId;
  final String listingId;

  @override
  State<BuyerEscrowPaymentScreen> createState() => _BuyerEscrowPaymentScreenState();
}

class _BuyerEscrowPaymentScreenState extends State<BuyerEscrowPaymentScreen> {
  static const Color _lightGreen = Color(0xFF11422B);
  static const Color _darkGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  bool _submitting = false;
  bool _uploadingSlip = false;
  bool _markingExpired = false;
  String _paymentSlipUrl = '';
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // Fallback escrow account so buyer always sees payment details even if settings are incomplete.
  static const String _fallbackBankName = 'Faysal Bank';
  static const String _fallbackAccountTitle = 'AMIR GHAFFAR';
  static const String _fallbackBranchName = 'IBB PATOKI';
  static const String _fallbackAccountNumber = '3456786000005200';
  static const String _fallbackIban = 'PK93FAYS3456786000005200';

  Stream<DocumentSnapshot<Map<String, dynamic>>> _dealStream() {
    return FirebaseFirestore.instance.collection('deals').doc(widget.dealId).snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _escrowAccountStream() {
    return FirebaseFirestore.instance.collection('settings').doc('escrowAccount').snapshots();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirmPaymentSubmission() async {
    if (_submitting) return;
    if (_paymentSlipUrl.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload payment slip first / پہلے سلپ اپلوڈ کریں')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final dealRef = FirebaseFirestore.instance.collection('deals').doc(widget.dealId);
      final dealSnap = await dealRef.get();
      final latest = dealSnap.data() ?? const <String, dynamic>{};
      final effectiveRef = _referenceController.text.trim().isEmpty
          ? (latest['paymentReference'] ?? '').toString().trim()
          : _referenceController.text.trim();
      final effectiveSlip = _paymentSlipUrl.trim().isNotEmpty
          ? _paymentSlipUrl.trim()
          : (latest['escrowSlipUrl'] ?? latest['paymentSlipUrl'] ?? '').toString().trim();
      if (effectiveSlip.isEmpty) {
        throw Exception('Slip is missing');
      }

      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).set({
        'paymentReference': effectiveRef,
        if (_notesController.text.trim().isNotEmpty) 'paymentNotes': _notesController.text.trim(),
        'paymentSlipUrl': effectiveSlip,
        'escrowSlipUrl': effectiveSlip,
        'escrowState': 'SUBMITTED',
        'paymentStatus': 'payment_submitted',
        'escrowSlipUploadedAt': FieldValue.serverTimestamp(),
        'escrowSlipUploadedBy': FirebaseAuth.instance.currentUser?.uid,
        'paymentSubmittedAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _notifySlipSubmitted(latest, effectiveSlip);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slip submitted - waiting admin confirmation / سلپ جمع ہوگئی')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment submission failed. Please retry.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _uploadSlip(ImageSource source) async {
    if (_uploadingSlip) return;
    setState(() => _uploadingSlip = true);
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 75,
      );
      if (image == null) return;

      final file = File(image.path);
      final ref = FirebaseStorage.instance
          .ref()
          .child('escrow_slips')
          .child(widget.dealId)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      await ref.putFile(file);
      final url = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).set({
        'escrowSlipUrl': url,
        'paymentSlipUrl': url,
        'escrowSlipUploadedAt': FieldValue.serverTimestamp(),
        'escrowSlipUploadedBy': FirebaseAuth.instance.currentUser?.uid,
        'escrowState': 'SUBMITTED',
        'paymentStatus': 'payment_submitted',
        'paymentSubmittedAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final dealSnap = await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).get();
      await _notifySlipSubmitted(dealSnap.data() ?? const <String, dynamic>{}, url);

      if (!mounted) return;
      setState(() => _paymentSlipUrl = url);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment slip uploaded / سلپ اپلوڈ ہوگئی')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slip upload failed. Please retry.')),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingSlip = false);
      }
    }
  }

  Future<void> _showSlipSourcePicker() async {
    if (_uploadingSlip) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _lightGreen,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded, color: Colors.white),
                title: const Text('Camera', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _uploadSlip(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_rounded, color: Colors.white),
                title: const Text('Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _uploadSlip(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _notifySlipSubmitted(Map<String, dynamic> deal, String slipUrl) async {
    final sellerId = (deal['sellerId'] ?? '').toString().trim();
    final listingId = (deal['listingId'] ?? widget.listingId).toString().trim();
    final payload = <String, dynamic>{
      'type': 'escrow_slip_submitted',
      'title': 'Escrow Slip Submitted',
      'body': 'Buyer ne escrow slip upload kar di. Delivery process start karein.',
      'dealId': widget.dealId,
      'listingId': listingId,
      'escrowSlipUrl': slipUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'timestamp': FieldValue.serverTimestamp(),
      'read': false,
      'isRead': false,
    };

    final batch = FirebaseFirestore.instance.batch();
    if (sellerId.isNotEmpty) {
      batch.set(
        FirebaseFirestore.instance.collection('notifications').doc(),
        <String, dynamic>{...payload, 'toUid': sellerId, 'userId': sellerId},
      );
    }

    try {
      final adminSnaps = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .limit(10)
          .get();
      for (final admin in adminSnaps.docs) {
        final adminUid = admin.id.trim();
        if (adminUid.isEmpty) continue;
        batch.set(
          FirebaseFirestore.instance.collection('notifications').doc(),
          <String, dynamic>{...payload, 'toUid': adminUid, 'userId': adminUid},
        );
      }
    } catch (_) {
      // Keep deal update successful even if admin fan-out is unavailable.
    }

    await batch.commit();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _formatPkr(num value) {
    final rounded = value.round();
    final raw = rounded.toString();
    final withCommas = raw.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
    return 'Rs. $withCommas';
  }

  DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Future<void> _markExpiredIfNeeded({required bool isExpired}) async {
    if (!isExpired || _markingExpired) return;
    _markingExpired = true;
    try {
      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).set({
        'status': 'expired',
        'paymentStatus': 'expired',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Best-effort status write; UI still reflects computed expiry.
    } finally {
      _markingExpired = false;
    }
  }

  int _timelineStep({
    required String paymentStatus,
    required bool escrowPaid,
  }) {
    if (escrowPaid ||
        paymentStatus == 'verified' ||
        paymentStatus == 'paid_to_escrow' ||
        paymentStatus == 'completed') {
      return 4;
    }
    if (paymentStatus == 'payment_submitted' || paymentStatus == 'pending_admin_verification') {
      return 3;
    }
    if (paymentStatus == 'submitted') {
      return 2;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: _darkGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Escrow Payment / ایسکرو ادائیگی', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _dealStream(),
            builder: (context, dealSnapshot) {
              if (dealSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: _gold));
              }
              final dealDoc = dealSnapshot.data;
              final dealData = dealDoc?.data();
              if (dealData == null) {
                return const Center(
                  child: Text('Deal not found / ڈیل دستیاب نہیں', style: TextStyle(color: Colors.white)),
                );
              }

              final buyerId = (dealData['buyerId'] ?? '').toString();
              if (uid.isNotEmpty && buyerId.isNotEmpty && uid != buyerId) {
                return const Center(
                  child: Text('Unauthorized deal access', style: TextStyle(color: Colors.white)),
                );
              }

              final status = (dealData['status'] ?? '').toString().toLowerCase();
              final paymentStatus = (dealData['paymentStatus'] ?? '').toString().toLowerCase();
              final escrowPaid = dealData['escrowPaid'] == true || status == 'paid';
              final canPay = !escrowPaid &&
                  status != 'expired' &&
                  (status == 'awaiting_escrow_payment' ||
                    status == 'awaiting_payment' ||
                      status == 'approved' ||
                    paymentStatus == 'awaiting_payment' ||
                      paymentStatus == 'awaiting_escrow_payment' ||
                    paymentStatus == 'submitted' ||
                    paymentStatus == 'payment_submitted' ||
                    paymentStatus == 'pending_admin_verification');

              final dealAmount = _toDouble(dealData['dealAmount']);
              final appCommission = _toDouble(dealData['appCommission']);
              final buyerTotal = _toDouble(dealData['buyerTotal']) > 0
                  ? _toDouble(dealData['buyerTotal'])
                  : (dealAmount + appCommission);

              final createdAt = _toDateTime(
                dealData['approvedAt'] ?? dealData['createdAt'],
              );
              final deadline =
                  (createdAt ?? DateTime.now()).add(const Duration(hours: 24));
              final expired = DateTime.now().isAfter(deadline) && !escrowPaid;
              _markExpiredIfNeeded(isExpired: expired && status != 'expired');

              final currentStep = _timelineStep(
                paymentStatus: paymentStatus,
                escrowPaid: escrowPaid,
              );

              final existingSlipUrl = (dealData['paymentSlipUrl'] ?? '').toString().trim();
              final existingEscrowSlipUrl = (dealData['escrowSlipUrl'] ?? '').toString().trim();
              final effectiveSlipUrl = _paymentSlipUrl.trim().isNotEmpty
                  ? _paymentSlipUrl.trim()
                  : (existingEscrowSlipUrl.isNotEmpty ? existingEscrowSlipUrl : existingSlipUrl);
              final existingReference = (dealData['paymentReference'] ?? '').toString().trim();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: _escrowAccountStream(),
                builder: (context, accountSnapshot) {
                  final accountData = accountSnapshot.data?.data() ?? const <String, dynamic>{};
                  final bankName = _firstNonEmptyString(
                    <String?>[
                      accountData['escrowBankName']?.toString(),
                      accountData['bankName']?.toString(),
                    ],
                    fallback: _fallbackBankName,
                  );
                  final accountTitle = _firstNonEmptyString(
                    <String?>[
                      accountData['escrowAccountTitle']?.toString(),
                      accountData['accountTitle']?.toString(),
                    ],
                    fallback: _fallbackAccountTitle,
                  );
                  final branchName = _firstNonEmptyString(
                    <String?>[
                      accountData['escrowBranchName']?.toString(),
                      accountData['branchName']?.toString(),
                    ],
                    fallback: _fallbackBranchName,
                  );
                  final accountNumber = _firstNonEmptyString(
                    <String?>[
                      accountData['escrowAccountNumber']?.toString(),
                      accountData['accountNumber']?.toString(),
                    ],
                    fallback: _fallbackAccountNumber,
                  );
                  final iban = _firstNonEmptyString(
                    <String?>[
                      accountData['escrowIban']?.toString(),
                      accountData['iban']?.toString(),
                    ],
                    fallback: _fallbackIban,
                  );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                    children: [
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Deal Status / ڈیل اسٹیٹس',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _line('Deal ID', widget.dealId),
                            _line('Status', status.isEmpty ? 'unknown' : status),
                            _line('Payment Status', paymentStatus.isEmpty ? '--' : paymentStatus),
                            _line('Escrow Paid', escrowPaid ? 'Yes / جی ہاں' : 'No / نہیں'),
                            _line(
                              'Payment Deadline',
                              expired
                                  ? 'Expired / ختم'
                                  : '24 hours (due ${deadline.day}/${deadline.month}/${deadline.year} ${deadline.hour.toString().padLeft(2, '0')}:${deadline.minute.toString().padLeft(2, '0')})',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Payment Breakdown / ادائیگی تفصیل',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _line('Deal Amount', _formatPkr(dealAmount)),
                            _line('Admin Fee', _formatPkr(appCommission)),
                            _lineWithCopy(
                              context: context,
                              label: 'Total Payable',
                              value: _formatPkr(buyerTotal),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _card(
                        child: _timeline(currentStep),
                      ),
                      const SizedBox(height: 10),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Escrow Account / ایڈمن ایسکرو اکاؤنٹ',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _line('Bank Name', bankName),
                            _line('Account Title', accountTitle),
                            _line('Branch Name', branchName),
                            _lineWithCopy(
                              context: context,
                              label: 'Account number',
                              value: accountNumber,
                            ),
                            _lineWithCopy(
                              context: context,
                              label: 'IBAN',
                              value: iban,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pay only to above admin escrow account. Direct seller payment is not allowed.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Upload Payment Proof',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _referenceController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'Transaction ID / Reference Number',
                                hintText: existingReference,
                                labelStyle: const TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _gold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _notesController,
                              style: const TextStyle(color: Colors.white),
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Optional Notes',
                                labelStyle: const TextStyle(color: Colors.white70),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: Colors.white24),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _gold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.white38),
                                ),
                                onPressed: !canPay || expired || _uploadingSlip ? null : _showSlipSourcePicker,
                                icon: _uploadingSlip
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.upload_file_rounded),
                                label: Text(_uploadingSlip ? 'Uploading...' : 'Upload Slip'),
                              ),
                            ),
                            if (effectiveSlipUrl.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Slip Submitted - waiting admin confirmation',
                                style: TextStyle(color: Color(0xFF9EF4C0), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _card(
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('⚠ Only transfer to this escrow account.', style: TextStyle(color: Colors.white70)),
                            SizedBox(height: 4),
                            Text('⚠ Direct seller payment is forbidden.', style: TextStyle(color: Colors.white70)),
                            SizedBox(height: 4),
                            Text('⚠ Fake payment proofs lead to account suspension.', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!escrowPaid)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: canPay ? _gold : Colors.grey,
                            foregroundColor: canPay ? Colors.black : Colors.white70,
                          ),
                          onPressed: !canPay || expired || _submitting ? null : _confirmPaymentSubmission,
                          icon: _submitting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.verified_rounded),
                          label: Text(
                            expired
                                ? 'Expired / ختم'
                                : (canPay
                                    ? 'Confirm Payment'
                                    : 'Awaiting Admin Approval / منظوری کا انتظار'),
                          ),
                        ),
                      if (escrowPaid)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2ECC71)),
                          onPressed: () {
                            final sellerId = (dealData['sellerId'] ?? '').toString();
                            final product =
                                (dealData['productName'] ?? dealData['itemName'] ?? 'Product').toString();
                            if (sellerId.trim().isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ChatScreen(
                                  dealId: widget.dealId,
                                  receiverId: sellerId,
                                  productName: product,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_rounded, color: Colors.white),
                          label: const Text('Open Secure Chat / محفوظ چیٹ کھولیں'),
                        ),
                    ],
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
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.34)),
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
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _lineWithCopy({
    required BuildContext context,
    required String label,
    required String value,
  }) {
    final clean = value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                clean,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Copy $label',
            icon: const Icon(Icons.copy_rounded, color: Colors.white70, size: 18),
            onPressed: clean.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: clean));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Copied / کاپی ہوگیا')),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _timeline(int currentStep) {
    const labels = <String>[
      '1 Awaiting Payment',
      '2 Payment Submitted',
      '3 Admin Verifying',
      '4 Escrow Secured',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Escrow Status Timeline',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...List.generate(labels.length, (index) {
          final step = index + 1;
          final done = currentStep >= step;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: done ? _gold : Colors.white24,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$step',
                    style: TextStyle(
                      color: done ? Colors.black : Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labels[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: done ? Colors.white : Colors.white70,
                      fontWeight: done ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _firstNonEmptyString(List<String?> values, {required String fallback}) {
    for (final raw in values) {
      final value = (raw ?? '').trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return fallback;
  }
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

// ============================
// Firestore Schema Notes
// ============================
// listings/{listingId}
// - status: "approved" | "expired" | ...
// - isApproved: bool
// - createdAt: Timestamp (server)
// - itemName, quantity, unit, province, district
// - marketAverage / marketAverageRate / aiMarketRate
// - sellerId
// - videoUrl / verificationVideoUrl
// - latitude/longitude or lat/lng
//
// listings/{listingId}/bids/{bidId}
// - listingId, sellerId, buyerId
// - buyerName, buyerPhone
// - bidRate, quantity, unit
// - total, arhatFee, payableNow
// - status: "active" | "accepted" | "rejected"
// - createdAt, updatedAt (server)
//
// deals/{dealId}
// - listingId, sellerId, buyerId
// - status: "awaiting_admin_approval" | "awaiting_escrow_payment" | "paid"
// - escrowPaid: bool
// - escrowPaidAt: Timestamp
// - chatUnlocked: bool
// - createdAt, updatedAt
//
// settings/escrowAccount
// - bankName, accountTitle, accountNumber, iban
