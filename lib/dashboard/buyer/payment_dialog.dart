import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/glass_button.dart';
import '../../core/widgets/spiritual_header.dart';

class PaymentDialog extends StatefulWidget {
  const PaymentDialog({
    super.key,
    required this.listingId,
    required this.listingData,
  });

  final String listingId;
  final Map<String, dynamic> listingData;

  @override
  State<PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<PaymentDialog> {
  static final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en_US');

  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String _uploadedReceiptUrl = '';

  bool get _isVerificationInProgress {
    final paymentStatus =
        (widget.listingData['paymentStatus'] ?? '').toString().toLowerCase();
    final listingStatus =
        (widget.listingData['status'] ?? '').toString().toLowerCase();
    return paymentStatus == 'pending_verification' ||
        listingStatus == 'awaiting_admin_approval';
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  String _resolveTotalAmount() {
    final double total = _toDouble(widget.listingData['finalPrice']) > 0
        ? _toDouble(widget.listingData['finalPrice'])
        : (_toDouble(widget.listingData['highestBid']) > 0
              ? _toDouble(widget.listingData['highestBid'])
              : _toDouble(widget.listingData['price']));
    return 'Rs. ${_moneyFormat.format(total)}';
  }

  static const String _bankName = 'Faysal Bank';
  static const String _accountName = 'Amir Ghaffar';
  static const String _accountNo = '3456786000005200';

  Future<void> _copyAccountNo() async {
    await Clipboard.setData(const ClipboardData(text: _accountNo));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
        content: Text('Account number copy ho gaya.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _createEscrowVerificationNotification({
    required String listingId,
    required String buyerId,
    required double amount,
  }) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'type': 'escrow_verification',
      'listingId': listingId,
      'buyerId': buyerId,
      'amount': amount,
      'message': 'New payment receipt uploaded for verification.',
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _uploadScreenshot() async {
    if (_isUploading) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Pehle login karein phir dobara koshish karein.'),
        ),
      );
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('escrow_receipts')
          .child(widget.listingId)
          .child('${user.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg');

      final uploadTask = storageRef.putFile(File(image.path));
      uploadTask.snapshotEvents.listen((snapshot) {
        final total = snapshot.totalBytes;
        if (total <= 0 || !mounted) return;
        setState(() => _uploadProgress = snapshot.bytesTransferred / total);
      });
      final snapshot = await uploadTask;
      final screenshotUrl = await snapshot.ref.getDownloadURL();

      final amount = _toDouble(widget.listingData['currentPrice']);

      final listingUpdates = <String, dynamic>{
        'status': 'awaiting_admin_approval',
        'listingStatus': 'awaiting_admin_approval',
        'auctionStatus': 'awaiting_admin_approval',
        'paymentStatus': 'pending_verification',
        'paymentReceiptUrl': screenshotUrl,
        'receiptUploadedAt': FieldValue.serverTimestamp(),
        'adminRejectionReason': '',
        'paymentSubmittedBy': user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.listingId)
          .set(listingUpdates, SetOptions(merge: true));

      final String dealId = (widget.listingData['dealId'] ?? '')
          .toString()
          .trim();
      if (dealId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('deals').doc(dealId).set({
          'paymentStatus': 'pending_verification',
          'paymentReceiptUrl': screenshotUrl,
          'receiptUploadedAt': FieldValue.serverTimestamp(),
          'adminRejectionReason': '',
          'lastUpdated': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await _createEscrowVerificationNotification(
        listingId: widget.listingId,
        buyerId: user.uid,
        amount: amount,
      );

      if (!mounted) return;
      setState(() {
        _uploadedReceiptUrl = screenshotUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text(
            'Receipt uploaded successfully. Admin verification is in progress.',
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text(
            'Upload fail hua. Internet check karke dobara koshish karein.',
          ),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = _resolveTotalAmount();
    final receiptUrl = _uploadedReceiptUrl.isNotEmpty
      ? _uploadedReceiptUrl
      : (widget.listingData['paymentReceiptUrl'] ?? '').toString();
    final bool hasUploadedReceipt = receiptUrl.trim().isNotEmpty;
    final bool verificationInProgress =
      _isVerificationInProgress || hasUploadedReceipt;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Raqam Bhejen',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const SpiritualHeader(
              backgroundColor: Color(0x1400C853),
              borderColor: Color(0x5500C853),
            ),
            const SizedBox(height: 10),
            Text(
              'Mubarak ho! Aap ki boli manzoor ho gayi hai. Darj-zail account mein $totalAmount jama karwaein aur screenshot upload karein.',
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Account ki Tafseel',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Bank Name: $_bankName',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Account Name: $_accountName',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Account No: $_accountNo',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _copyAccountNo,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: const Text('Copy'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (!hasUploadedReceipt)
              GlassButton(
                label: _isUploading ? 'Upload ho raha hai...' : 'Upload Receipt',
                onPressed: _isUploading ? null : _uploadScreenshot,
                loading: _isUploading,
                height: 48,
                radius: 12,
              ),
            if (_isUploading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _uploadProgress > 0 ? _uploadProgress : null,
              ),
            ],
            if (verificationInProgress && hasUploadedReceipt) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Text(
                  '�x" Verification in Progress (Admin is checking your receipt)',
                  style: TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final uri = Uri.tryParse(receiptUrl);
                    if (uri == null) return;
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      messenger.showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
                          content: Text('Uploaded receipt open nahi ho saka.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('View Uploaded Receipt'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _isUploading ? null : () => Navigator.pop(context),
                child: const Text('Band Karein'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

