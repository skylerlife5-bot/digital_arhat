import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../bidding/bid_model.dart';
import '../../services/ai_generative_service.dart';
import '../../services/bid_eligibility_service.dart';
import '../../services/bidding_service.dart';
import '../../services/trust_safety_service.dart';
import '../../theme/app_colors.dart';

String formatPkr(dynamic value) {
  final num n = (value is num)
      ? value
      : num.tryParse(value?.toString() ?? '') ?? 0;
  return 'Rs. ${n.toStringAsFixed(0)}';
}

class BidBottomSheet extends StatefulWidget {
  const BidBottomSheet({
    super.key,
    required this.listingId,
    required this.listingData,
  });

  final String listingId;
  final Map<String, dynamic> listingData;

  @override
  State<BidBottomSheet> createState() => _BidBottomSheetState();
}

class _BidBottomSheetState extends State<BidBottomSheet> {
  static const Color _gold = AppColors.accentGold;
  static const Color _darkGreen = AppColors.background;
  static final Map<String, DateTime> _localThrottle = <String, DateTime>{};

  final BiddingService _biddingService = BiddingService();
  final MandiIntelligenceService _aiService = MandiIntelligenceService();

  final TextEditingController _bidController = TextEditingController();

  bool _submitting = false;
  bool _agreementChecked = false;

  @override
  void dispose() {
    _bidController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  String get _throttleKey => '${_uid}_${widget.listingId}';

  bool _isLocallyThrottled() {
    final last = _localThrottle[_throttleKey];
    if (last == null) return false;
    return DateTime.now().toUtc().difference(last).inSeconds < 30;
  }

  Future<bool> _isFirestoreThrottled() async {
    final threshold = Timestamp.fromDate(
      DateTime.now().toUtc().subtract(const Duration(seconds: 30)),
    );
    final snap = await FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listingId)
        .collection('bids')
        .where('buyerId', isEqualTo: _uid)
        .where('createdAt', isGreaterThan: threshold)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  double _parseAmount(String raw) {
    final cleaned = raw.replaceAll(',', '').trim();
    return double.tryParse(cleaned) ?? 0;
  }

  double _resolveListingQuantity(Map<String, dynamic> data) {
    final dynamic raw = data['quantity'] ?? data['qty'] ?? data['weight'];
    if (raw is num) return raw.toDouble();
    final text = (raw ?? '').toString();
    final match = RegExp(r'[0-9]+(?:\.[0-9]+)?').firstMatch(text);
    if (match == null) return 0;
    return double.tryParse(match.group(0) ?? '') ?? 0;
  }

  String _resolveUnit(Map<String, dynamic> data) {
    final unit = (data['unit'] ?? data['uom'] ?? '').toString().trim();
    return unit.isEmpty ? 'unit' : unit;
  }

  _BidThresholds _thresholdsFromListing(Map<String, dynamic> data) {
    final startingPrice =
        _readDouble(data['startingPrice']) > 0
            ? _readDouble(data['startingPrice'])
            : (_readDouble(data['basePrice']) > 0
                  ? _readDouble(data['basePrice'])
                  : _readDouble(data['price']));

    final currentHighest =
        _readDouble(data['highestBid']) > 0
            ? _readDouble(data['highestBid'])
            : startingPrice;

    final baseline = currentHighest > startingPrice
        ? currentHighest
        : startingPrice;

    final minimumNext = BidEligibilityService.calculateMinimumAllowedBid(data);
    final double increment =
      minimumNext > baseline ? (minimumNext - baseline) : 0.0;

    return _BidThresholds(
      startingPrice: startingPrice,
      currentHighest: currentHighest,
      minimumNext: minimumNext,
      minIncrement: increment,
    );
  }

  String _mapEligibilityMessage(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('valid bid amount')) {
      return 'Enter a valid bid amount / درست بولی رقم درج کریں';
    }
    if (lower.contains('sign in')) {
      return 'Please sign in to place a bid.\nبولی لگانے کے لیے سائن اِن کریں۔';
    }
    if (lower.contains('higher than current highest') ||
        lower.contains('maujooda boli')) {
      return 'Your bid must be higher than the current highest bid.\nآپ کی بولی موجودہ سب سے بڑی بولی سے زیادہ ہونی چاہیے۔';
    }
    if (lower.contains('at least rs.')) {
      return 'Your bid must be at least the minimum next valid amount / آپ کی بولی کم از کم اگلی درست بولی کے مطابق ہونی چاہیے';
    }
    if (lower.contains('auction has ended') || lower.contains('closed')) {
      return 'Auction is closed for bidding.\nاس آکشن میں بولی بند ہو چکی ہے۔';
    }
    return raw;
  }

  String _friendlyBidError(Object error) {
    final raw = error.toString().replaceAll('Exception: ', '').trim();
    final lower = raw.toLowerCase();

    if (lower.contains('permission-denied')) {
      return 'Could not place bid. Please try again / بولی جمع نہ ہو سکی، دوبارہ کوشش کریں';
    }

    if (lower.contains('at least rs.') || lower.contains('minimum')) {
      return 'Your bid must be at least the minimum next valid amount / آپ کی بولی کم از کم اگلی درست بولی کے مطابق ہونی چاہیے';
    }

    if (lower.contains('higher than current highest') ||
        lower.contains('maujooda boli')) {
      return 'Your bid must be higher than the current highest bid.\nآپ کی بولی موجودہ سب سے بڑی بولی سے زیادہ ہونی چاہیے۔';
    }

    if (lower.contains('valid') && lower.contains('amount')) {
      return 'Enter a valid bid amount / درست بولی رقم درج کریں';
    }

    return 'Could not place bid. Please try again / بولی جمع نہ ہو سکی، دوبارہ کوشش کریں';
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitBid() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final writePath = 'listings/${widget.listingId}/bids/{bidId}';
    debugPrint(
      '[BidFlowUI] submit_attempt currentUser=${currentUser == null ? 'null' : 'present'} uid=${currentUser?.uid ?? 'null'} listingId=${widget.listingId} writePath=$writePath',
    );

    if (currentUser == null) {
      _snack('Please sign in to place a bid.\nبولی لگانے کے لیے سائن اِن کریں۔');
      return;
    }

    final enteredText = _bidController.text.trim();
    if (enteredText.isEmpty) {
      _snack('Enter a valid bid amount / درست بولی رقم درج کریں');
      return;
    }

    final enteredBid = _parseAmount(enteredText);
    if (enteredBid <= 0) {
      _snack('Enter a valid bid amount / درست بولی رقم درج کریں');
      return;
    }

    final listingSnap = await FirebaseFirestore.instance
        .collection('listings')
        .doc(widget.listingId)
        .get();
    final latestListing = listingSnap.data() ?? widget.listingData;

    final eligibility = BidEligibilityService.evaluate(
      buyerId: currentUser.uid,
      listingData: latestListing,
      bidAmount: enteredBid,
    );
    if (!eligibility.allowed) {
      _snack(_mapEligibilityMessage(eligibility.message));
      return;
    }

    final thresholds = _thresholdsFromListing(latestListing);
    debugPrint(
      '[BidFlowUI] submit_state listingId=${widget.listingId} persistedHighest=${thresholds.currentHighest.toStringAsFixed(2)} typedInput=${enteredBid.toStringAsFixed(2)} minimumNext=${thresholds.minimumNext.toStringAsFixed(2)}',
    );
    if (enteredBid < thresholds.minimumNext) {
      _snack(
        'Your bid must be at least the minimum next valid amount / آپ کی بولی کم از کم اگلی درست بولی کے مطابق ہونی چاہیے',
      );
      return;
    }

    final qty = _resolveListingQuantity(latestListing);
    if (qty <= 0) {
      _snack('Invalid quantity for estimate.\nتخمینے کے لیے مقدار درست نہیں۔');
      return;
    }

    final estimatedTotal = enteredBid * qty;
    if (estimatedTotal <= 0 || estimatedTotal.isNaN || estimatedTotal.isInfinite) {
      _snack(
        'Could not calculate total. Please check bid and quantity.\nکل رقم کا حساب نہ ہو سکا۔ براہ کرم بولی اور مقدار چیک کریں۔',
      );
      return;
    }

    if (_isLocallyThrottled()) {
      _snack(
        'Please wait a few seconds before placing another bid.\nاگلی بولی سے پہلے چند سیکنڈ انتظار کریں۔',
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final throttled = await _isFirestoreThrottled();
      if (throttled) {
        _snack(
          'Please wait a few seconds before placing another bid.\nاگلی بولی سے پہلے چند سیکنڈ انتظار کریں۔',
        );
        return;
      }

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userData = userDoc.data() ?? const <String, dynamic>{};

      final blockStatus = TrustSafetyService.evaluateBidBlock(
        userData: userData,
      );
        if (blockStatus.isBlocked) {
        final untilText = blockStatus.blockedUntil == null
            ? ''
            : ' (${blockStatus.blockedUntil!.toLocal().toString().substring(0, 16)} تک)';
        _snack(
          '${blockStatus.reasonUr}$untilText'.trim(),
        );
        return;
      }

      final productName =
          (latestListing['itemName'] ??
                  latestListing['cropName'] ??
                  latestListing['product'] ??
                  'Product')
              .toString();

      Map<String, dynamic>? aiRisk;
      try {
        aiRisk = await _aiService.evaluateBidRisk(
          listingId: widget.listingId,
          buyerUid: currentUser.uid,
          bidRate: enteredBid,
          quantity: qty,
          unit: _resolveUnit(latestListing),
        );
      } catch (_) {
        aiRisk = null;
      }

      var bidReviewStatus = 'ok';
      var adminReviewRequired = false;
      if (aiRisk != null) {
        final action = (aiRisk['recommendedAction'] ?? 'allow')
            .toString()
            .toLowerCase();
        if (action == 'hold') {
          bidReviewStatus = 'pendingReview';
          adminReviewRequired = true;
        } else if (action == 'warn') {
          bidReviewStatus = 'warned';
        }
      }

      final bid = BidModel(
        listingId: widget.listingId,
        sellerId: (latestListing['sellerId'] ?? '').toString(),
        buyerId: currentUser.uid,
        buyerName: (userData['name'] ?? 'Buyer').toString(),
        buyerPhone: (userData['phone'] ?? '').toString(),
        productName: productName,
        bidAmount: enteredBid,
        status: 'pending',
        createdAt: DateTime.now().toUtc(),
      );

      debugPrint(
        '[BidFlowUI] payload listingId=${widget.listingId} sellerId=${bid.sellerId} buyerId=${bid.buyerId} bidAmount=${bid.bidAmount.toStringAsFixed(2)} quantity=${qty.toStringAsFixed(2)} estimatedTotal=${estimatedTotal.toStringAsFixed(2)}',
      );
      debugPrint('[BidFlowUI] service_call placeSmartBid listingId=${widget.listingId}');

      await _biddingService.placeSmartBid(
        bid: bid,
        aiMeta: <String, dynamic>{
          'aiBidRiskScore': aiRisk?['bidRiskScore'] ?? 0,
          'aiBidRiskLevel': aiRisk?['bidRiskLevel'] ?? '',
          'aiBidAdvice': aiRisk?['bidAdviceEn'] ?? '',
          'aiBidAdviceUrdu': aiRisk?['bidAdviceUrdu'] ?? '',
          'aiBidAdviceEn': aiRisk?['bidAdviceEn'] ?? '',
          'aiBidFlags': aiRisk?['bidFlags'] ?? const <dynamic>[],
          'bidReviewStatus': bidReviewStatus,
          'adminReviewRequired': adminReviewRequired,
        },
      );

      _localThrottle[_throttleKey] = DateTime.now().toUtc();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bid submitted successfully.\nبولی کامیابی سے جمع ہو گئی۔',
          ),
        ),
      );
    } catch (e) {
      final mapped = _friendlyBidError(e);
      debugPrint(
        '[BidFlowUI] submit_error currentUser=${FirebaseAuth.instance.currentUser == null ? 'null' : 'present'} uid=${FirebaseAuth.instance.currentUser?.uid ?? 'null'} listingId=${widget.listingId} writePath=$writePath finalMappedError=$mapped raw=${e.toString()}',
      );
      _snack(mapped);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, inset + bottomSafe + 56),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: _darkGreen,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _gold.withValues(alpha: 0.42)),
          ),
          child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('listings')
                .doc(widget.listingId)
                .snapshots(),
            builder: (context, snap) {
              final live = snap.data?.data() ?? widget.listingData;
              final title =
                  (live['itemName'] ?? live['cropName'] ?? live['product'] ?? 'Listing')
                      .toString()
                      .trim();
              final qty = _resolveListingQuantity(live);
              final bidValue = _parseAmount(_bidController.text);
              final estimatedTotal = (bidValue > 0 && qty > 0) ? (bidValue * qty) : 0;
              final thresholds = _thresholdsFromListing(live);

              final eligibility = BidEligibilityService.evaluate(
                buyerId: _uid,
                listingData: live,
                bidAmount: bidValue,
              );

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Place Bid / بولی لگائیں',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title.isEmpty ? 'Listing' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _bidController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      cursorColor: _gold,
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                      decoration: _decor('Bid Amount / بولی رقم').copyWith(
                        hintText: '45',
                        hintStyle: const TextStyle(color: AppColors.secondaryText),
                        prefixText: 'Rs. ',
                        prefixStyle: const TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.cardSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow(
                            'Current Highest Bid / موجودہ سب سے بڑی بولی',
                            formatPkr(thresholds.currentHighest),
                          ),
                          _infoRow(
                            'Minimum Next Bid / کم از کم اگلی بولی',
                            formatPkr(thresholds.minimumNext),
                          ),
                          _infoRow(
                            'Quantity / مقدار',
                            qty > 0 ? qty.toStringAsFixed(0) : 'N/A',
                          ),
                          _infoRow(
                            'Estimated Total / تخمینی کل رقم',
                            estimatedTotal > 0 ? formatPkr(estimatedTotal) : 'N/A',
                            isValueHighlight: true,
                          ),
                        ],
                      ),
                    ),
                    if (qty <= 0) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Invalid quantity for estimate.\nتخمینے کے لیے مقدار درست نہیں۔',
                        style: TextStyle(
                          color: AppColors.accentGoldAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    if (bidValue > 0 && !eligibility.allowed) ...[
                      const SizedBox(height: 8),
                      Text(
                        _mapEligibilityMessage(eligibility.message),
                        style: const TextStyle(
                          color: AppColors.accentGoldAccent,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    // ── Bid Agreement Checkbox ──────────────────────────────
                    InkWell(
                      onTap: () => setState(
                        () => _agreementChecked = !_agreementChecked,
                      ),
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _agreementChecked,
                            onChanged: (v) => setState(
                              () => _agreementChecked = v ?? false,
                            ),
                            activeColor: _gold,
                            checkColor: AppColors.ctaTextDark,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Text(
                                'میں سمجھتا/سمجھتی ہوں کہ یہ ایک سنجیدہ بولی ہے۔ '
                                'اگر میں جیت کر مُکر گیا/گئی تو میری کمپلیشن ریٹ کم ہو گی '
                                'اور میرا اکاؤنٹ عارضی طور پر بند ہو سکتا ہے۔',
                                style: TextStyle(
                                  color: AppColors.secondaryText,
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _submitting
                                ? null
                                : () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primaryText,
                              side: BorderSide(
                                color: _gold.withValues(alpha: 0.55),
                              ),
                            ),
                            child: const Text('Cancel / واپس'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _gold,
                              foregroundColor: AppColors.ctaTextDark,
                            ),
                            onPressed: _submitting
                                ? null
                                : (_agreementChecked ? _submitBid : null),
                            child: _submitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Place Bid / بولی لگائیں'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _decor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.secondaryText),
      filled: true,
      fillColor: AppColors.cardSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.35)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _gold),
      ),
    );
  }

  Widget _infoRow(
    String label,
    String value, {
    bool isValueHighlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isValueHighlight ? _gold : AppColors.primaryText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BidThresholds {
  const _BidThresholds({
    required this.startingPrice,
    required this.currentHighest,
    required this.minimumNext,
    required this.minIncrement,
  });

  final double startingPrice;
  final double currentHighest;
  final double minimumNext;
  final double minIncrement;
}
