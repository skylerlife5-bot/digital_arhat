import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
// cloud_firestore import hata diya gaya hai kyunke yahan direct use nahi ho raha
import '../../core/constants.dart';
import '../../core/app_colors.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../services/bidding_service.dart';
import '../../services/marketplace_service.dart';
import '../../bidding/bid_model.dart';

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
  double get _fee => _subtotal * 0.01;
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

  void _submitBid() async {
    if (_isSubmitting) return;

    final bidText = _bidController.text.trim();
    if (bidText.isEmpty) return;

    double? bidPrice = double.tryParse(bidText);
    if (bidPrice == null || bidPrice <= 0) return;

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
      _loading = true;
    });

    Map<String, dynamic> latest = <String, dynamic>{};

    try {
      latest = await _marketplaceService.getListingBidContext(widget.listingId);

    final double startingPrice =
        _toDouble(
          latest.containsKey('startingPrice') ? latest['startingPrice'] : null,
        ) ??
        0.0;
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
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
              content: Text('Awaiting Admin Approval'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (nowUtc.isAfter(biddingEnd)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
              content: Text('Boli ka waqt khatam ho chuka hai.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final double minimumRequired = [startingPrice, basePrice, currentHighest]
          .reduce((a, b) => a > b ? a : b);

      if (bidPrice <= minimumRequired) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
              content: Text(
                "Boli Rs. ${_moneyFormat.format(minimumRequired)} se zyada honi chahiye!",
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (bidPrice < (minimumRequired * 0.7)) {
        bool? confirm = await _showLowBidWarning();
        if (confirm != true) return;
      }

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Boli ke liye login lazmi hai");

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
            content: Text(_mapBidError(e.code, e.message)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
            content: Text(_mapBidError('', e.toString())),
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
                        SizedBox(
                          width: double.infinity,
                          child: GlassButton(
                            label: 'Boli Lagaen (Place Bid)',
                            onPressed: (_currentBidInput <= 0 || _loading || _isSubmitting)
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

  String _mapBidError(String code, String? rawMessage) {
    final message = (rawMessage ?? '').replaceAll('Exception: ', '').trim();
    if (code == 'permission-denied' ||
        message.toLowerCase().contains('permission-denied')) {
      return 'Permission Denied: You are not allowed to place this bid.';
    }
    if (message.toLowerCase().contains('validation failed') ||
        message.toLowerCase().contains('required')) {
      return 'Validation Failed: Please enter a valid bid and try again.';
    }
    return message.isEmpty ? 'Bid failed. Please try again.' : message;
  }

  // UI Components
  Widget _buildBarkatHeader() {
    return const Column(
      children: [
        Text(
          "بِس��&ِ ا���!ِ ا�ر�}�ح��&ٰ� ِ ا�ر�}�حِ�`��&ِ",
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
            "BA-AITIMAD SELLER",
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
          _breakdownRow(
            "Subtotal:",
            "Rs. ${_moneyFormat.format(_subtotal)}",
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, thickness: 0.8, color: Color(0x22000000)),
          const SizedBox(height: 8),
          _breakdownRow(
            "Arhat Fee (1%):",
            "Rs. ${_moneyFormat.format(_fee)}",
            isRed: true,
          ),
          const SizedBox(height: 8),
          _breakdownRow(
            "Total Adaigi (Net Payable):",
            "Rs. ${_moneyFormat.format(_total)}",
            isBold: true,
          ),
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
    final double startingPrice =
        _toDouble(widget.productData['startingPrice']) ??
        _toDouble(widget.productData['basePrice']) ??
        _toDouble(widget.productData['price']) ??
        0.0;
    final double currentHighest =
        _toDouble(widget.productData['highestBid']) ?? startingPrice;
    final double reference = currentHighest > startingPrice
        ? currentHighest
        : startingPrice;

    final bool isLowSuspicious = _currentBidInput > 0 && _currentBidInput <= reference;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isLowSuspicious
            ? const Color(0xFFFFEBEE)
            : const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLowSuspicious
              ? const Color(0xFFE53935)
              : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Highest Bid: Rs. ${_moneyFormat.format(currentHighest)}',
            style: const TextStyle(
              color: Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 12,
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
          if (isLowSuspicious) ...[
            const SizedBox(height: 6),
            const Text(
              'Aap ki boli current highest se zyada honi chahiye.',
              style: TextStyle(
                color: Color(0xFFC62828),
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
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

  Future<bool?> _showLowBidWarning() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Kam Boli ka Alert!"),
        content: const Text(
          "Aapki boli market rate se kaafi kam hai. Kya aap confirm karna chahte hain?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Theek Karen"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Haan"),
          ),
        ],
      ),
    );
  }
}

