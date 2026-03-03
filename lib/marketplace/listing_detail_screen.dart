import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/constants.dart';
import '../core/security_filter.dart';
import '../core/widgets/glass_button.dart';
import '../dashboard/components/bid_dialog.dart';
import '../models/deal_status.dart';
class ListingDetailScreen extends StatefulWidget {
  const ListingDetailScreen({
    super.key,
    required this.listingId,
    this.initialData = const <String, dynamic>{},
  });

  final String listingId;
  final Map<String, dynamic> initialData;

  static String buildEscrowDeepLink(String id) {
    return '${AppConstants.appDeepLinkBase}/listing/$id?entry=escrow';
  }

  static String buildFirebaseDynamicListingLink(String id) {
    final baseLink = buildEscrowDeepLink(id);
    final encoded = Uri.encodeComponent(baseLink);
    return '${AppConstants.firebaseDynamicLinkDomain}/?link=$encoded&apn=com.yourname.digital_arhat';
  }

  @override
  State<ListingDetailScreen> createState() => _ListingDetailScreenState();
}

class _ListingDetailScreenState extends State<ListingDetailScreen> {
  static const Color _gold = Color(0xFFFFD700);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  final NumberFormat _currencyFormat = NumberFormat('#,##0.00', 'en_US');

  bool _uploadingReceipt = false;
  double _receiptUploadProgress = 0.0;
  bool _confirmingDelivery = false;

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  double? _toNullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  String _weatherLabel(Map<String, dynamic> data) {
    final weatherMap = data['weather'];
    final weatherDataMap = data['weatherData'];
    final dynamic rawTemp =
        data['temp'] ??
        data['weatherTemp'] ??
        (weatherMap is Map ? weatherMap['temp'] : null) ??
        (weatherDataMap is Map ? weatherDataMap['temp'] : null);
    final parsedTemp = _toNullableDouble(rawTemp);
    if (parsedTemp == null) {
      return 'Weather: --°C';
    }
    return 'Weather: ${parsedTemp.round()}°C';
  }

  String _money(double value) => value.toStringAsFixed(0);

  Future<void> _notifyAdminsPaymentUploaded({
    required String listingId,
    required String buyerId,
    required double amount,
  }) async {
    try {
      await _db.collection('notifications').add({
        'type': 'escrow_verification',
        'listingId': listingId,
        'buyerId': buyerId,
        'amount': amount,
        'message': 'New payment receipt uploaded for verification.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      return;
    }
  }

  bool _isPaymentPending(Map<String, dynamic> data) {
    final status =
        (data['status'] ?? data['listingStatus'] ?? data['auctionStatus'] ?? '')
            .toString()
            .toLowerCase();
    final payment = (data['paymentStatus'] ?? '').toString().toLowerCase();
    return status == DealStatus.paymentPendingVerification.value ||
        payment == 'pending_verification' ||
        payment == 'pending';
  }

  bool _isPaymentConfirmed(Map<String, dynamic> data) {
    final status =
        (data['status'] ?? data['listingStatus'] ?? data['auctionStatus'] ?? '')
            .toString()
            .toLowerCase();
    final payment = (data['paymentStatus'] ?? '').toString().toLowerCase();
    return status == DealStatus.paymentConfirmed.value ||
        payment == 'confirmed' ||
        payment == 'paid';
  }

  Future<void> _confirmDelivery(Map<String, dynamic> data) async {
    if (_confirmingDelivery) return;
    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Please sign in first.')));
      return;
    }

    final bool? shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Delivery'),
        content: const Text(
          'Are you sure item has been delivered? This action will move deal to payout-ready stage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (shouldConfirm != true) return;

    setState(() => _confirmingDelivery = true);
    try {
      final double finalPrice = _toDouble(data['currentPrice']) > 0
          ? _toDouble(data['currentPrice'])
          : (_toDouble(data['finalPrice']) > 0
                ? _toDouble(data['finalPrice'])
                : (_toDouble(data['highestBid']) > 0
                      ? _toDouble(data['highestBid'])
                      : _toDouble(data['price'])));
      final double adminCommission = (finalPrice * 0.01).toDouble();
      final double sellerPayable = (finalPrice - adminCommission).toDouble();
      final payoutDetails = <String, dynamic>{
        'total': finalPrice,
        'commission': adminCommission,
        'sellerNet': sellerPayable,
        'confirmedAt': FieldValue.serverTimestamp(),
      };

      await _db.collection('listings').doc(widget.listingId).set({
        'status': 'delivered_pending_release',
        'listingStatus': 'delivered_pending_release',
        'auctionStatus': 'delivered_pending_release',
        'paymentStatus': 'delivered_pending_release',
        'payoutDetails': payoutDetails,
        'deliveredConfirmedBy': currentUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final dealId = (data['dealId'] ?? '').toString().trim();
      if (dealId.isNotEmpty) {
        await _db.collection('deals').doc(dealId).set({
          'status': 'delivered_pending_release',
          'paymentStatus': 'delivered_pending_release',
          'payoutDetails': payoutDetails,
          'lastUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final dealRef = dealId.isNotEmpty ? dealId : widget.listingId;
      await _db.collection('notifications').add({
        'type': 'payout_ready',
        'listingId': widget.listingId,
        'dealId': dealRef,
        'message':
            'Payout Ready: Deal $dealRef completed. Commission Earned: Rs. ${_currencyFormat.format(adminCommission)}. Please release funds to Seller.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
          content: Text(
            'Delivery confirmed. Seller payable Rs. ${_currencyFormat.format(sellerPayable)}',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Delivery confirmation failed.')),
      );
    } finally {
      if (mounted) {
        setState(() => _confirmingDelivery = false);
      }
    }
  }

  Widget _buildLifecycleStepper({required String listingStatus}) {
    final normalized = listingStatus.toLowerCase();
    final bool verifiedDone =
        normalized == 'escrow_confirmed' ||
        normalized == 'dispatched' ||
        normalized == 'delivered_pending_release' ||
        normalized == 'completed';
    final bool dispatchedDone =
        normalized == 'dispatched' ||
        normalized == 'delivered_pending_release' ||
        normalized == 'completed';
    final bool deliveredDone =
        normalized == 'delivered_pending_release' || normalized == 'completed';

    Widget stepNode(String label, bool done) {
      return Column(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: done ? Colors.green : Colors.white24,
            child: Icon(
              done ? Icons.check : Icons.radio_button_unchecked,
              size: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: done ? Colors.greenAccent : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      );
    }

    Widget connector(bool done) {
      return Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          height: 2,
          color: done ? Colors.green : Colors.white24,
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          stepNode('Verified', verifiedDone),
          connector(dispatchedDone),
          stepNode('Dispatched', dispatchedDone),
          connector(deliveredDone),
          stepNode('Delivered', deliveredDone),
        ],
      ),
    );
  }

  Future<void> _uploadPaymentReceipt(Map<String, dynamic> data) async {
    if (_uploadingReceipt) return;

    final currentUser = _auth.currentUser;
    if (currentUser == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Please sign in first.')));
      return;
    }

    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() => _uploadingReceipt = true);
    setState(() => _receiptUploadProgress = 0.0);

    try {
      final ref = _storage
          .ref()
          .child('escrow_receipts')
          .child(widget.listingId)
          .child(
            '${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}.jpg',
          );

      final uploadTask = ref.putFile(File(image.path));
      uploadTask.snapshotEvents.listen((snapshot) {
        final totalBytes = snapshot.totalBytes;
        if (totalBytes <= 0 || !mounted) return;
        setState(
          () =>
              _receiptUploadProgress = snapshot.bytesTransferred / totalBytes,
        );
      });
      await uploadTask;
      final receiptUrl = await ref.getDownloadURL();

      final amount = _toDouble(data['currentPrice']);
      final updates = <String, dynamic>{
        'status': 'awaiting_admin_approval',
        'listingStatus': 'awaiting_admin_approval',
        'auctionStatus': 'awaiting_admin_approval',
        'paymentStatus': 'pending_verification',
        'escrowStatus': 'PENDING_PAYMENT',
        'paymentReceiptUrl': receiptUrl,
        'receiptUploadedAt': FieldValue.serverTimestamp(),
        'adminRejectionReason': '',
        'paymentReceiptBy': currentUser.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await _db
          .collection('listings')
          .doc(widget.listingId)
          .set(updates, SetOptions(merge: true));

      final dealId = (data['dealId'] ?? '').toString().trim();
      if (dealId.isNotEmpty) {
        await _db.collection('deals').doc(dealId).set({
          'paymentStatus': 'pending_verification',
          'paymentReceiptUrl': receiptUrl,
          'receiptUploadedAt': FieldValue.serverTimestamp(),
          'adminRejectionReason': '',
          'lastUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      await _notifyAdminsPaymentUploaded(
        listingId: widget.listingId,
        buyerId: currentUser.uid,
        amount: amount,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Receipt uploaded. Admin verification is pending.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Receipt upload failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _uploadingReceipt = false;
          _receiptUploadProgress = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = _auth.currentUser?.uid ?? '';
    final data = widget.initialData;
    final bool isWinner =
        (currentUserId.trim() == (data['winnerId'] ?? '').toString().trim() ||
        currentUserId.trim() == (data['buyerId'] ?? '').toString().trim());

    if (isWinner) {
      return _buildWinnerEscrowScaffold(
        data: data,
        currentUserId: currentUserId,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('listings').doc(widget.listingId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? widget.initialData;
        final currentUserId = _auth.currentUser?.uid ?? '';
        final bool isWinner =
            (currentUserId.trim() ==
                (data['winnerId'] ?? '').toString().trim() ||
            currentUserId.trim() == (data['buyerId'] ?? '').toString().trim());

        // ignore: avoid_print
        print(
          'DEBUG: UserID: $currentUserId matches WinnerID: ${data['winnerId']}',
        );

        if (isWinner) {
          return _buildWinnerEscrowScaffold(
            data: data,
            currentUserId: currentUserId,
          );
        }

        return Scaffold(
          backgroundColor: const Color(0xFF011A0A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'Listing Ki Tafseel',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: () {
            if (snapshot.connectionState == ConnectionState.waiting &&
                data.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: _gold),
              );
            }
            if (data.isEmpty) {
              return const Center(
                child: Text(
                  'Listing not found',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            final sellerId = (data['sellerId'] ?? '').toString();
            final isSeller =
                currentUserId.isNotEmpty &&
                sellerId.trim() == currentUserId.trim();

            final listingStatus =
                (data['listingStatus'] ??
                        data['status'] ??
                        data['auctionStatus'] ??
                        '')
                    .toString()
                    .toLowerCase();
            final isActiveStatus =
                listingStatus == DealStatus.active.value ||
                listingStatus == DealStatus.active.name.toLowerCase();
            final isAwaitingStatus =
                listingStatus == 'awaiting_payment' ||
                listingStatus == DealStatus.awaitingPayment.value ||
                listingStatus == DealStatus.awaitingPayment.name.toLowerCase();
            final canRenderDetailView =
                isActiveStatus || (isAwaitingStatus && isSeller);

            final bidAmount = _toDouble(data['finalPrice']) > 0
                ? _toDouble(data['finalPrice'])
                : (_toDouble(data['winningBid']) > 0
                      ? _toDouble(data['winningBid'])
                      : (_toDouble(data['highestBid']) > 0
                            ? _toDouble(data['highestBid'])
                            : _toDouble(data['price'])));

            final product = (data['product'] ?? data['itemName'] ?? 'Item')
                .toString();
            final category =
                (data['category'] ?? data['mandiType'] ?? 'Category')
                    .toString();
            final district = (data['district'] ?? 'Pakistan').toString();
            final rate = bidAmount > 0 ? _money(bidAmount) : '--';
            final unit = (data['unit'] ?? '').toString();
            final location = (data['location'] ?? district).toString();
            final maskedProduct = SecurityFilter.maskAll(product);
            final maskedCategory = SecurityFilter.maskAll(category);
            final maskedDistrict = SecurityFilter.maskAll(district);
            final maskedLocation = SecurityFilter.maskAll(location);
            final weatherLabel = _weatherLabel(data);
            final hasVideo = (data['videoUrl'] ?? '')
                .toString()
                .trim()
                .isNotEmpty;
            final isVerifiedSource =
                data['isVerifiedSource'] == true && hasVideo;

            if (!canRenderDetailView) {
              return const Center(
                child: Text(
                  'Listing is not available for this user right now.',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryCard(
                    product: maskedProduct,
                    category: maskedCategory,
                    rate: rate,
                    unit: unit,
                    district: maskedDistrict,
                    location: maskedLocation,
                    weatherLabel: weatherLabel,
                    hasVideo: isVerifiedSource,
                  ),
                  const SizedBox(height: 14),
                  _privacyCard(),
                  const SizedBox(height: 18),
                  if (isSeller &&
                      (_isPaymentPending(data) || _isPaymentConfirmed(data)))
                    _buildSellerSettlementView(
                      bidAmount: bidAmount,
                      paymentConfirmed: _isPaymentConfirmed(data),
                    )
                  else
                    _buildDefaultActionView(
                      context,
                      data: data,
                      product: product,
                      category: category,
                      rate: rate,
                      district: district,
                    ),
                ],
              ),
            );
          }(),
        );
      },
    );
  }

  Widget _buildDefaultActionView(
    BuildContext context, {
    required Map<String, dynamic> data,
    required String product,
    required String category,
    required String rate,
    required String district,
  }) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share, color: Colors.black),
            label: Text(
              'WhatsApp Par Share Karein',
              style: GoogleFonts.poppins(
                color: Colors.black,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _shareToWhatsApp(
              context,
              product: product,
              category: category,
              rate: rate,
              district: district,
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.handshake, color: _gold),
            label: Text(
              'Deal Shuru Karein (Escrow)',
              style: GoogleFonts.poppins(
                color: _gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _gold),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (_) =>
                    BidDialog(productData: data, listingId: widget.listingId),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
                  content: Text(
                    'In-app chat escrow shuru hone ke baad active hogi.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.chat_bubble_outline, color: Colors.white70),
            label: Text(
              'In-App Chat',
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWinnerEscrowScaffold({
    required Map<String, dynamic> data,
    required String currentUserId,
  }) {
    final detectedBidAmount = _toDouble(data['finalPrice']) > 0
        ? _toDouble(data['finalPrice'])
        : (_toDouble(data['winningBid']) > 0
              ? _toDouble(data['winningBid'])
              : (_toDouble(data['highestBid']) > 0
                    ? _toDouble(data['highestBid'])
                    : _toDouble(data['price'])));
    final double quantity = double.tryParse(data['quantity'].toString()) ?? 0;
    final double bidAmount =
        double.tryParse(data['bidAmount'].toString()) ?? detectedBidAmount;
    final double subTotal = quantity * bidAmount;
    final double commission = subTotal * 0.01;
    final double grandTotal = quantity > 0
        ? (subTotal + commission)
        : bidAmount;
    final weatherLabel = _weatherLabel(data);
    final paymentStatus = (data['paymentStatus'] ?? '').toString().toLowerCase();
    final listingStatus = (data['status'] ?? '').toString().toLowerCase();
    final adminRejectionReason =
      (data['adminRejectionReason'] ?? data['rejectionReason'] ?? '')
        .toString()
        .trim();
    final receiptUrl =
        (data['paymentReceiptUrl'] ?? data['paymentScreenshotUrl'] ?? '')
            .toString()
            .trim();
    final bool hasUploadedReceipt = receiptUrl.isNotEmpty;
    final bool isPaymentRejected =
      listingStatus == 'payment_rejected' || paymentStatus == 'rejected';
    final bool verificationInProgress =
      paymentStatus == 'pending_verification' ||
      listingStatus == 'awaiting_admin_approval';
    final bool canConfirmDelivery = listingStatus == 'dispatched';
    const iban = 'PK93FAYS3456786000005200';

    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Escrow Payment',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFD54F).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.95),
                  width: 1.3,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.account_balance, color: _gold),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text(
                          'AMIR GHAFFAR (Official Escrow)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Rs. ${grandTotal.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w900,
                      fontSize: 32,
                    ),
                  ),
                  if (quantity > 0)
                    Text(
                      '(Includes 1% Commission: Rs. ${commission.toStringAsFixed(0)})',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 10),
                  const Text(
                    'Bank: Faysal Bank',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Account: 3456786000005200',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Flexible(
                        child: Text(
                          'IBAN: PK93FAYS3456786000005200',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () async {
                          await Clipboard.setData(
                            const ClipboardData(text: iban),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('IBAN copied')),
                          );
                        },
                        icon: const Icon(Icons.copy, color: _gold),
                        tooltip: 'Copy IBAN',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'Please upload the payment receipt after transfer for Admin verification.',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.thermostat, size: 18, color: Colors.white70),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    weatherLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLifecycleStepper(listingStatus: listingStatus),
            if (canConfirmDelivery) ...[
              const SizedBox(height: 12),
              GlassButton(
                label: _confirmingDelivery
                    ? 'Confirming...'
                    : 'Confirm Delivery',
                loading: _confirmingDelivery,
                onPressed: _confirmingDelivery
                    ? null
                    : () => _confirmDelivery(data),
                textStyle: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: GoogleFonts.poppins().fontFamily,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (isPaymentRejected) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: Text(
                  'Rejected: ${adminRejectionReason.isNotEmpty ? adminRejectionReason : 'Receipt invalid. Please upload again.'}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (!hasUploadedReceipt)
              GlassButton(
                label: _uploadingReceipt
                    ? 'Uploading...'
                    : 'Upload Receipt',
                loading: _uploadingReceipt,
                onPressed: () async {
                  await _uploadPaymentReceipt(data);
                },
                textStyle: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            if (_uploadingReceipt) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: _receiptUploadProgress > 0
                    ? _receiptUploadProgress.clamp(0.0, 1.0)
                    : null,
                color: _gold,
                backgroundColor: Colors.white12,
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
                  'Verification in Progress (Admin aap ki receipt check kar raha hai)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(receiptUrl);
                    if (uri == null) return;
                    final opened = await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
                          content: Text('Could not open uploaded receipt.'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.receipt_long, color: _gold),
                  label: const Text(
                    'View Uploaded Receipt',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _gold),
                  ),
                ),
              ),
            ],
            if (receiptUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  receiptUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            if (detectedBidAmount > 0) ...[
              const SizedBox(height: 12),
              _financialRow(
                'Detected Bid Amount',
                'Rs. ${_money(detectedBidAmount)}',
              ),
            ],
            const SizedBox(height: 6),
            _financialRow('Winner User ID', currentUserId),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerSettlementView({
    required double bidAmount,
    required bool paymentConfirmed,
  }) {
    final sellerFee = bidAmount * 0.01;
    final expectedPayout = bidAmount - sellerFee;
    final totalRevenue = bidAmount * 0.02;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _gold.withValues(alpha: 0.72)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            paymentConfirmed
                ? 'Payment Confirmed / Adaigi ki tasdeeq ho gayi'
                : 'Buyer has paid. Funds are being verified by Admin.',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              fontFamily: GoogleFonts.poppins().fontFamily,
            ),
          ),
          const SizedBox(height: 10),
          _financialRow(
            'Expected Payout',
            'Rs. ${_money(expectedPayout)}',
            highlight: true,
          ),
          _financialRow(
            'Platform Profit (1% Buyer + 1% Seller)',
            'Rs. ${_money(totalRevenue)}',
          ),
          const SizedBox(height: 6),
          Text(
            'Expected Payout = Bid Amount - 1% Arhat Fee',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _financialRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: highlight ? _gold : Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard({
    required String product,
    required String category,
    required String rate,
    required String unit,
    required String district,
    required String location,
    required String weatherLabel,
    required bool hasVideo,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Category: $category',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Price: Rs. $rate ${unit.isNotEmpty ? '/ $unit' : ''}',
            style: const TextStyle(
              color: Colors.green,
              fontWeight: FontWeight.w900,
              fontSize: 30,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.thermostat, size: 18, color: Colors.white70),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  weatherLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('District: $district', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            'Location: $location',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasVideo ? Icons.verified : Icons.info_outline,
                color: hasVideo ? Colors.greenAccent : Colors.white54,
                size: 18,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  hasVideo
                      ? 'Verified video app ke andar dastiyab hai'
                      : 'Video tafseel app ke andar dastiyab hai',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _privacyCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Privacy Guard: Farokht karne wale ka zaati number mukammal tor par makhfi hai. Sirf deal shuru karein ya in-app chat istemal karein. Tamam len den escrow se mehfooz hai.',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Future<void> _shareToWhatsApp(
    BuildContext context, {
    required String product,
    required String category,
    required String rate,
    required String district,
  }) async {
    final appLink = ListingDetailScreen.buildFirebaseDynamicListingLink(
      widget.listingId,
    );
    final message =
      'MashaAllah! Check out this verified listing on Digital Arhat.\nItem: $category / $product\nLocation: $district\nPrice: $rate\nWatch Video & Buy: $appLink';

    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('WhatsApp open nahi ho saka.')),
      );
    }
  }
}

