import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/fee_policy.dart';
import '../../services/auction_lifecycle_service.dart';
import '../../services/bidding_service.dart';
import '../../services/marketplace_service.dart';

class SellerBidsScreen extends StatefulWidget {
  final String listingId;
  final String productName;
  final double basePrice;

  const SellerBidsScreen({
    super.key,
    required this.listingId,
    required this.productName,
    required this.basePrice,
  });

  @override
  State<SellerBidsScreen> createState() => _SellerBidsScreenState();
}

class _SellerBidsScreenState extends State<SellerBidsScreen> {
  final BiddingService _biddingService = BiddingService();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final AuctionLifecycleService _auctionLifecycleService =
      AuctionLifecycleService();

  bool _isProcessing = false;

  static const Color goldColor = Color(0xFFFFD700);
  static const Color darkGreen = Color(0xFF011A0A);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkGreen,
      appBar: AppBar(
        title: Text(
          '${widget.productName} ki Boliyaan',
          style: GoogleFonts.notoSerif(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sellerBidsStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: goldColor),
                );
              }
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Unable to load bids / بولیاں لوڈ نہیں ہو سکیں',
                    style: TextStyle(color: Colors.white54),
                  ),
                );
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return _buildEmptyState();
              }

              final sellerId = FirebaseAuth.instance.currentUser?.uid ?? '';
              final allDocs = snapshot.data!.docs.where((doc) {
                if (sellerId.isEmpty) return false;
                final data = doc.data();
                return (data['sellerId']?.toString() ?? '') == sellerId;
              }).toList();

              final DateTime cutoff = DateTime.now().subtract(
                const Duration(hours: 24),
              );
              final bids = allDocs.where((doc) {
                final data = doc.data();
                final createdAt =
                    _toDate(data['createdAt']) ?? _toDate(data['timestamp']);
                return createdAt != null && createdAt.isAfter(cutoff);
              }).toList();

              bids.sort((a, b) {
                final ad = a.data();
                final bd = b.data();
                final at =
                    _toDate(ad['createdAt']) ??
                    _toDate(ad['timestamp']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bt =
                    _toDate(bd['createdAt']) ??
                    _toDate(bd['timestamp']) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bt.compareTo(at);
              });

              if (bids.isEmpty) {
                return _buildEmptyState();
              }

              double highestBidAmount = 0.0;
              for (final doc in bids) {
                final amount = _toDouble(doc.data()['bidAmount']) ?? 0.0;
                if (amount > highestBidAmount) {
                  highestBidAmount = amount;
                }
              }

              return Column(
                children: [
                  _buildHighestBidHeader(highestBidAmount),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
                      cacheExtent: 650,
                      itemCount: bids.length,
                      itemBuilder: (context, index) {
                        final bidDoc = bids[index];
                        final bidData = bidDoc.data();
                        final double bidAmount =
                            _toDouble(bidData['bidAmount']) ?? 0.0;
                        final double quantity =
                            _toDouble(bidData['quantity']) ?? 0.0;
                        final double totalBidAmount = quantity > 0
                            ? (bidAmount * quantity)
                            : bidAmount;
                        final double commission = FeePolicy.bidFeeActive
                            ? (totalBidAmount * FeePolicy.bidFeeRate)
                            : 0.0;
                        final double finalAmountToSeller =
                            totalBidAmount - commission;

                        return KeyedSubtree(
                          key: ValueKey(bidDoc.id),
                          child: _buildBidCard(
                            bidDoc.id,
                            bidData,
                            totalBidAmount,
                            finalAmountToSeller,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: goldColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHighestBidHeader(double highestBid) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(10),
        border: const Border(bottom: BorderSide(color: Colors.white10)),
      ),
      child: Column(
        children: [
          const Text(
            'Sab se Bari Boli (Current Highest)',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Text(
            'Rs. ${highestBid.toStringAsFixed(0)}',
            style: const TextStyle(
              color: goldColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Text(
            'Aapki Base Price: Rs. ${widget.basePrice.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildBidCard(
    String bidId,
    Map<String, dynamic> data,
    double totalBidAmount,
    double finalAmount,
  ) {
    final String productName = data['productName']?.toString() ?? 'Fasal';
    final String listingId = data['listingId']?.toString() ?? widget.listingId;
    final bool accepted = isBidAccepted(bidId: bidId, bidData: data);
    final bool unlocked = isContactUnlocked(bidId: bidId, bidData: data);
    final String buyerName = (data['buyerName'] ?? 'Kharidar').toString();
    final String buyerPhone = (data['buyerPhone'] ?? '').toString().trim();
    final String acceptedAt = _dateLabel(data['acceptedAt']);
    final double quantity = _toDouble(data['quantity']) ?? 0.0;
    final bool hasQuantity = quantity > 0;

    return Card(
      color: Colors.white.withAlpha(15),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Colors.white10),
      ),
      margin: const EdgeInsets.only(bottom: 15),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Colors.white10,
                child: Icon(Icons.person, color: Colors.white70),
              ),
              title: Text(
                buyerName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                accepted
                    ? '$productName | Contact Unlocked / رابطہ اَن لاک'
                    : '$productName | Contact unlocks after acceptance',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _buildTrustBadge(data['buyerRating'] ?? 0.0),
            ),
            const Divider(color: Colors.white10),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Boli ki Raqam',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                    Text(
                      'Rs. ${(_toDouble(data['bidAmount']) ?? 0).toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: goldColor,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (hasQuantity)
                      Text(
                        'Total (${quantity.toStringAsFixed(0)} x unit): Rs. ${totalBidAmount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
                ElevatedButton(
                  onPressed: accepted
                      ? null
                      : () => _showAcceptDialog(
                          bidId,
                          data,
                          finalAmount,
                          listingId,
                        ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accepted
                        ? const Color(0xFF5E8D6E)
                        : goldColor,
                    foregroundColor: accepted ? Colors.white70 : Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: const Size(120, 42),
                    maximumSize: const Size(170, 42),
                  ),
                  child: Text(
                    accepted
                        ? 'Accepted / قبول شدہ'
                        : 'Accept Bid / بولی قبول کریں',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildArhatFeeInfo(totalBidAmount, finalAmount),
            if (accepted && unlocked) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2ECC71).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF2ECC71).withValues(alpha: 0.7),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Bid Accepted / بولی قبول کر لی گئی',
                      style: TextStyle(
                        color: Color(0xFF9EF4C0),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Buyer contact unlocked / خریدار کا رابطہ اَن لاک ہو گیا ہے',
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'براہِ راست بات کر کے سودا مکمل کریں',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Buyer: $buyerName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      buyerPhone.isEmpty
                          ? 'Buyer contact will appear here once available.'
                          : 'Buyer Phone: $buyerPhone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Accepted Amount: Rs. ${(_toDouble(data['bidAmount']) ?? 0).toStringAsFixed(0)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    Text(
                      'Accepted Time: $acceptedAt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Complete deal offline after verifying listing and buyer details.\nلسٹنگ اور خریدار کی تصدیق کے بعد براہِ راست سودا مکمل کریں',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton(
                          onPressed: () => _updateDealOutcome(
                            listingId: listingId,
                            status: 'successful',
                            note: 'Seller marked successful completion',
                          ),
                          child: const Text('Successful / کامیاب'),
                        ),
                        OutlinedButton(
                          onPressed: () => _updateDealOutcome(
                            listingId: listingId,
                            status: 'failed',
                            note: 'Seller marked deal failed',
                          ),
                          child: const Text('Failed / ناکام'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildArhatFeeInfo(double totalBidAmount, double finalAmount) {
    final int feePercent = (FeePolicy.bidFeeRate * 100).round();
    final double feeValue = FeePolicy.bidFeeActive
        ? (totalBidAmount * FeePolicy.bidFeeRate)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              FeePolicy.bidFeeActive
                  ? 'Arhat Fee ($feePercent%): -Rs. ${feeValue.toStringAsFixed(0)} | Aap ko milenge: Rs. ${finalAmount.toStringAsFixed(0)}'
                  : 'No platform fee right now | Aap ko milenge: Rs. ${finalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAcceptDialog(
    String bidId,
    Map<String, dynamic> data,
    double finalAmount,
    String listingId,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: darkGreen,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: goldColor),
        ),
        title: const Text(
          'Sauda Pakka Karein?',
          style: TextStyle(color: goldColor),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Kharidar: ${data['buyerName']}',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 10),
            Text(
              'Final Amount: Rs. ${finalAmount.toStringAsFixed(0)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.greenAccent,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Accept karne ke baad buyer contact unlock ho jayega. براہِ راست بات کر کے سودا مکمل کریں۔',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processBidAction(bidId, listingId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: goldColor),
            child: const Text(
              'Confirm Deal',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _processBidAction(String bidId, String listingId) async {
    setState(() => _isProcessing = true);
    try {
      await _biddingService.acceptBid(bidId, listingId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Bid Accepted / بولی قبول کر لی گئی۔ Buyer contact unlocked / خریدار کا رابطہ اَن لاک ہو گیا ہے۔',
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Could not accept bid. Please try again. / بولی قبول نہ ہو سکی۔',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sellerBidsStream() {
    final sellerId = FirebaseAuth.instance.currentUser?.uid;
    if (sellerId == null || sellerId.isEmpty) {
      return FirebaseFirestore.instance
          .collection('listings')
          .doc('__none__')
          .collection('bids')
          .snapshots();
    }

    if (widget.listingId != 'ALL') {
      return _marketplaceService.getBidsStream(widget.listingId);
    }

    return _marketplaceService.getSellerIncomingBidsStream(sellerId);
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  bool _isTrue(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  bool isBidAccepted({
    required String bidId,
    required Map<String, dynamic> bidData,
  }) {
    final status = (bidData['status'] ?? '').toString().trim().toLowerCase();
    final acceptedBidId = (bidData['acceptedBidId'] ?? '').toString().trim();
    final hasAcceptedAt = bidData['acceptedAt'] != null;
    return _isTrue(bidData['contactUnlocked']) ||
        status == 'accepted' ||
        status == 'bid_accepted' ||
        (acceptedBidId.isNotEmpty && acceptedBidId == bidId) ||
        hasAcceptedAt;
  }

  bool isContactUnlocked({
    required String bidId,
    required Map<String, dynamic> bidData,
  }) {
    return _isTrue(bidData['contactUnlocked']) ||
        isBidAccepted(bidId: bidId, bidData: bidData);
  }

  String _dateLabel(dynamic value) {
    final dt = _toDate(value);
    if (dt == null) return 'Accepted recently';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildTrustBadge(dynamic score) {
    final double rating = _toDouble(score) ?? 0.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified, size: 16, color: Colors.amber),
          Text(
            rating > 0 ? rating.toStringAsFixed(1) : 'New',
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.gavel_rounded,
            size: 60,
            color: Colors.white.withAlpha(30),
          ),
          const SizedBox(height: 15),
          const Text(
            'No bids yet / ابھی تک کوئی بولی نہیں آئی',
            style: TextStyle(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  Future<void> _updateDealOutcome({
    required String listingId,
    required String status,
    required String note,
  }) async {
    try {
      await _auctionLifecycleService.updateDealOutcome(
        listingId: listingId,
        outcomeStatus: status,
        note: note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Deal outcome updated: ${_outcomeLabel(status)}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text('Outcome update failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _outcomeLabel(String status) {
    switch (status.toLowerCase()) {
      case 'successful':
        return 'Successful';
      case 'failed':
        return 'Failed';
      case 'cancelled':
        return 'Cancelled';
      case 'disputed':
        return 'Disputed';
      default:
        return 'Pending Contact';
    }
  }
}
