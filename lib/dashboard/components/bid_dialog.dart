import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/app_colors.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../services/bidding_service.dart';
import '../../services/bid_eligibility_service.dart';
import '../../services/marketplace_service.dart';
import '../../bidding/bid_model.dart';
import '../../config/fee_policy.dart';

class BidDialog extends StatefulWidget {
  final Map<String, dynamic> productData;
  final String listingId;

  const BidDialog({
    super.key,
    required this.productData,
    required this.listingId,
  });

  @override
  State<BidDialog> createState() => _BidDialogState();
}

class _BidDialogState extends State<BidDialog> {
  final _bidController = TextEditingController();
  final BiddingService _biddingService = BiddingService();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final NumberFormat _moneyFormat = NumberFormat('#,##0.##', 'en_US');
  bool _loading = false;
  bool _isSubmitting = false;

  double _currentBidInput = 0.0;
  double get _lotQuantity {
    final double quantity =
        _toDouble(widget.productData['quantity']) ??
        _toDouble(widget.productData['qty']) ??
        _toDouble(widget.productData['lotSize']) ??
        0.0;
    return quantity > 0 ? quantity : 1.0;
  }

  double get _subtotal => _currentBidInput * _lotQuantity;
  double get _fee =>
      FeePolicy.bidFeeActive ? (_subtotal * FeePolicy.bidFeeRate) : 0.0;
  double get _total => _subtotal + _fee;

  String get _lotQuantityText {
    if (_lotQuantity % 1 == 0) {
      return _lotQuantity.toStringAsFixed(0);
    }
    return _lotQuantity.toStringAsFixed(2);
  }

  String get _displayUnit {
    final String unit = (widget.productData['unit'] ?? '').toString().trim();
    return unit.isEmpty ? 'Mann' : unit;
  }

  @override
  void initState() {
    super.initState();
    _bidController.addListener(() {
      if (mounted) {
        setState(() {
          _currentBidInput = double.tryParse(_bidController.text) ?? 0.0;
        });
      }
    });
  }

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _listingLiveStream() {
    return FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listingId)
        .snapshots();
  }

  void _submitBid() async {
    if (_isSubmitting) return;

    final bidText = _bidController.text.trim();
    if (bidText.isEmpty) return;

    double? bidPrice = double.tryParse(bidText);
    if (bidPrice == null || bidPrice <= 0) return;

    final user = FirebaseAuth.instance.currentUser;
    final writePath = 'listings/${widget.listingId}/bids/{bidId}';
    debugPrint(
      '[BidFlowUI] submit_attempt currentUser=${user == null ? 'null' : 'present'} uid=${user?.uid ?? 'null'} listingId=${widget.listingId} writePath=$writePath',
    );
    if (user == null) {
      const mapped = 'Please sign in to place a bid.';
      debugPrint(
        '[BidFlowUI] submit_blocked listingId=${widget.listingId} writePath=$writePath finalMappedError=$mapped',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(mapped),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _loading = true;
    });

    Map<String, dynamic> latest = <String, dynamic>{};

    try {
      latest = await _marketplaceService.getListingBidContext(widget.listingId);

      final eligibility = BidEligibilityService.evaluate(
        buyerId: user.uid,
        listingData: latest,
        bidAmount: bidPrice,
      );
      if (!eligibility.allowed) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(eligibility.message),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final double basePrice =
          _toDouble(
            latest.containsKey('basePrice') ? latest['basePrice'] : null,
          ) ??
          0.0;
      final double currentHighest =
          _toDouble(
            latest.containsKey('highestBid') ? latest['highestBid'] : null,
          ) ??
          basePrice;
      final DateTime nowUtc = DateTime.now().toUtc();
      final DateTime? biddingEnd = latest['biddingEnd'] is DateTime
          ? (latest['biddingEnd'] as DateTime).toUtc()
          : null;

      if (biddingEnd == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 5),
              content: Text('Awaiting Admin Approval'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (nowUtc.isAfter(biddingEnd)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 5),
              content: Text('Boli ka waqt khatam ho chuka hai.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final double minimumRequired =
          eligibility.minimumAllowedBid ??
          BidEligibilityService.calculateMinimumAllowedBid(latest);

      if (bidPrice < minimumRequired) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(
                "Boli kam az kam Rs. ${_moneyFormat.format(minimumRequired)} honi chahiye!",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final newBid = BidModel(
        listingId: widget.listingId,
        sellerId: latest.containsKey('sellerId')
            ? (latest['sellerId']?.toString() ?? '')
            : (widget.productData.containsKey('sellerId')
                  ? (widget.productData['sellerId']?.toString() ?? '')
                  : ''),
        buyerId: user.uid,
        buyerName: user.displayName ?? "Mandi Kharidar",
        buyerPhone: '',
        productName: widget.productData.containsKey('product')
            ? (widget.productData['product']?.toString() ?? 'Fasal')
            : 'Fasal',
        bidAmount: bidPrice,
        status: 'pending',
        createdAt: DateTime.now(),
      );

      await _biddingService.placeSmartBid(
        bid: newBid,
        marketPrice: currentHighest > 0 ? currentHighest : basePrice,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on FirebaseException catch (e) {
      final mapped = _mapBidError(
        e.code,
        e.message,
        currentUser: FirebaseAuth.instance.currentUser,
      );
      debugPrint(
        '[BidFlowUI] submit_error currentUser=${FirebaseAuth.instance.currentUser == null ? 'null' : 'present'} uid=${FirebaseAuth.instance.currentUser?.uid ?? 'null'} listingId=${widget.listingId} writePath=$writePath finalMappedError=$mapped raw=${e.toString()}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(mapped),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      final mapped = _mapBidError(
        '',
        e.toString(),
        currentUser: FirebaseAuth.instance.currentUser,
      );
      debugPrint(
        '[BidFlowUI] submit_error currentUser=${FirebaseAuth.instance.currentUser == null ? 'null' : 'present'} uid=${FirebaseAuth.instance.currentUser?.uid ?? 'null'} listingId=${widget.listingId} writePath=$writePath finalMappedError=$mapped raw=${e.toString()}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(mapped),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.86,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  25,
                  20,
                  25 + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBarkatHeader(),
                    const SizedBox(height: 15),
                    Text(
                      _categoryMarketLabel(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildVerifiedBadge(),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _bidController,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryGreen,
                      ),
                      decoration: InputDecoration(
                        hintText: "0.00",
                        prefixText: "Rs. ",
                        labelText: "Apni Boli Likhen (Enter Bid Amount)",
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(
                            color: AppColors.primaryGreen,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildBidReferenceInfo(),
                    _buildCalculator(),
                    const SizedBox(height: 25),
                    Column(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            "Wapis",
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                          stream: _listingLiveStream(),
                          builder: (context, snapshot) {
                            final live =
                                snapshot.data?.data() ?? widget.productData;
                            final eligibility = BidEligibilityService.evaluate(
                              buyerId:
                                  FirebaseAuth.instance.currentUser?.uid ?? '',
                              listingData: live,
                              bidAmount: _currentBidInput,
                            );
                            final disabledReason = eligibility.allowed
                                ? null
                                : eligibility.message;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (disabledReason != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Text(
                                      disabledReason,
                                      style: const TextStyle(
                                        color: Colors.orange,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                SizedBox(
                                  width: double.infinity,
                                  child: GlassButton(
                                    label: 'Boli Lagaen (Place Bid)',
                                    onPressed:
                                        (_currentBidInput <= 0 ||
                                            _loading ||
                                            _isSubmitting ||
                                            !eligibility.allowed)
                                        ? null
                                        : _submitBid,
                                    loading: _loading || _isSubmitting,
                                    height: 54,
                                    radius: 12,
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => CustomerSupportHelper.openWhatsAppSupport(
                  context,
                  userName: FirebaseAuth.instance.currentUser?.displayName,
                ),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFF25D366),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.support_agent,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _mapBidError(String code, String? rawMessage, {User? currentUser}) {
    final message = (rawMessage ?? '').replaceAll('Exception: ', '').trim();
    if (code == 'permission-denied' ||
        message.toLowerCase().contains('permission-denied')) {
      if (currentUser == null) {
        return 'Please sign in to place a bid.';
      }
      return 'Bid could not be placed due to permission rules. Please retry.';
    }
    if (message.toLowerCase().contains('validation failed') ||
        message.toLowerCase().contains('required')) {
      return 'Please enter a valid bid and try again. / درست بولی درج کریں اور دوبارہ کوشش کریں۔';
    }
    return message.isEmpty
        ? 'Bid failed. Please try again. / بولی ناکام رہی، دوبارہ کوشش کریں۔'
        : message;
  }

  // UI Components
  Widget _buildBarkatHeader() {
    return const Column(
      children: [
        Text(
          'بِسْمِ اللّٰهِ الرَّحْمٰنِ الرَّحِيمِ',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.primaryGreen,
          ),
        ),
        SizedBox(height: 5),
        Text(
          "\"Aur Allah pak rizq dainay wala hai.\"",
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: Colors.brown,
          ),
        ),
      ],
    );
  }

  Widget _buildVerifiedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.primaryGreen.withValues(alpha: 0.3),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 14, color: AppColors.primaryGreen),
          SizedBox(width: 6),
          Text(
            'Trusted Seller / قابلِ اعتماد فروخت کنندہ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalculator() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          _breakdownRow(
            "Boli (Per Mann):",
            "Rs. ${_moneyFormat.format(_currentBidInput)}",
          ),
          const SizedBox(height: 8),
          _breakdownRow(
            "Kul Wazan (Total Weight):",
            "$_lotQuantityText $_displayUnit",
          ),
          const SizedBox(height: 8),
          _breakdownRow("Subtotal:", "Rs. ${_moneyFormat.format(_subtotal)}"),
          if (FeePolicy.bidFeeActive) ...[
            const SizedBox(height: 8),
            const Divider(height: 1, thickness: 0.8, color: Color(0x22000000)),
            const SizedBox(height: 8),
            _breakdownRow(
              "Arhat Fee (${(FeePolicy.bidFeeRate * 100).toStringAsFixed(0)}%):",
              "Rs. ${_moneyFormat.format(_fee)}",
              isRed: true,
            ),
          ],
          const SizedBox(height: 8),
          _breakdownRow(
            FeePolicy.bidFeeActive
                ? "Total Adaigi (Net Payable):"
                : "Total Bid:",
            "Rs. ${_moneyFormat.format(_total)}",
            isBold: true,
          ),
          if (!FeePolicy.bidFeeActive) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No platform fee is currently applied. / اس وقت پلیٹ فارم فیس لاگو نہیں۔',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
          ],
        ],
      ),
    );
  }

  MandiType _resolveMandiType(Map<String, dynamic> data) {
    try {
      final rawType = (data['mandiType'] ?? '').toString().trim().toUpperCase();
      for (final type in MandiType.values) {
        if (type.wireValue == rawType) return type;
      }

      final product = (data['product'] ?? '').toString().toLowerCase();
      if (product.contains('milk') || product.contains('doodh')) {
        return MandiType.milk;
      }
      if (product.contains('goat') ||
          product.contains('bakra') ||
          product.contains('bhains') ||
          product.contains('bail')) {
        return MandiType.livestock;
      }
      if (product.contains('aam') ||
          product.contains('mango') ||
          product.contains('apple') ||
          product.contains('banana')) {
        return MandiType.fruit;
      }
      if (product.contains('aloo') ||
          product.contains('pyaz') ||
          product.contains('tamatar') ||
          product.contains('potato')) {
        return MandiType.vegetables;
      }
    } catch (_) {}
    return MandiType.crops;
  }

  String _categoryMarketLabel() {
    final type = _resolveMandiType(widget.productData);
    return '${type.wireValue} MARKET';
  }

  Widget _buildBidReferenceInfo() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _listingLiveStream(),
      builder: (context, snapshot) {
        final live = snapshot.data?.data() ?? widget.productData;
        final double startingPrice =
            _toDouble(live['startingPrice']) ??
            _toDouble(live['basePrice']) ??
            _toDouble(live['price']) ??
            0.0;
        final double persistedHighest =
            _toDouble(live['highestBid']) ?? startingPrice;
        final double minimumNext =
            BidEligibilityService.calculateMinimumAllowedBid(live);
        final bool belowMinimum =
            _currentBidInput > 0 && _currentBidInput < minimumNext;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: belowMinimum
                ? const Color(0xFFFFEBEE)
                : const Color(0xFFF4F6F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: belowMinimum ? const Color(0xFFE53935) : Colors.black12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current Highest Bid: Rs. ${_moneyFormat.format(persistedHighest)}',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Minimum Next Bid: Rs. ${_moneyFormat.format(minimumNext)}',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Starting Price: Rs. ${_moneyFormat.format(startingPrice)}',
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
              ),
              if (belowMinimum) ...[
                const SizedBox(height: 6),
                Text(
                  'Aap ki boli kam az kam Rs. ${_moneyFormat.format(minimumNext)} honi chahiye.',
                  style: const TextStyle(
                    color: Color(0xFFC62828),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Widget _breakdownRow(
    String label,
    String value, {
    bool isRed = false,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 6,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              color: isBold ? Colors.black : Colors.black54,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 4,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: isRed
                    ? Colors.red
                    : (isBold ? AppColors.primaryGreen : Colors.black87),
              ),
            ),
          ),
        ),
      ],
    );
  }

}
