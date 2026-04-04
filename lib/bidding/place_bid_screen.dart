import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../config/fee_policy.dart';
import '../core/widgets/glass_button.dart';
import '../services/bidding_service.dart';
import '../bidding/bid_model.dart';
import '../dashboard/components/bid_timer.dart'; // Ensure correct path
import '../routes.dart';

class PlaceBidScreen extends StatefulWidget {
  final Map<String, dynamic> productData;
  final String docId;

  const PlaceBidScreen({
    super.key,
    required this.productData,
    required this.docId,
  });

  @override
  State<PlaceBidScreen> createState() => _PlaceBidScreenState();
}

class _PlaceBidScreenState extends State<PlaceBidScreen> {
  final _bidController = TextEditingController();
  final BiddingService _biddingService = BiddingService();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isLoading = false;
  double _calculatedCommission = 0.0;
  double _netToSeller = 0.0;
  double _currentHighestBid = 0.0;
  String? _aiNudgeMessage;
  bool _bidIsValid = false;  // Tracks if bid meets increment requirement

  static const String _verificationApproved = 'approved';
  static const String _verificationPendingReview = 'pending_review';
  static const String _verificationUnverified = 'unverified';

  @override
  void initState() {
    super.initState();
    // Fetch fresh highest bid from actual bids subcollection (not cached field)
    _initializeBidAmount();
    _bidController.addListener(_onBidChanged);
    _onBidChanged(); // Initial calculation
  }

  Future<void> _initializeBidAmount() async {
    try {
      final topBidSnap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.docId)
          .collection('bids')
          .orderBy('bidAmount', descending: true)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      final freshHighestBid = topBidSnap.docs.isNotEmpty
          ? (topBidSnap.docs.first.data()['bidAmount'] ?? 0.0).toDouble()
          : (widget.productData['basePrice'] ?? 0.0).toDouble();

      if (!mounted) return;
      setState(() {
        _currentHighestBid = freshHighestBid;
        _bidController.text = (_currentHighestBid + 20).toString();
      });
    } catch (e) {
      // Fallback to cached value if fetch fails
      if (!mounted) return;
      setState(() {
        _currentHighestBid =
            (widget.productData['highestBid'] ??
                    widget.productData['basePrice'] ??
                    0.0)
                .toDouble();
        _bidController.text = (_currentHighestBid + 20).toString();
      });
    }
  }

  void _onBidChanged() {
    final double amount = double.tryParse(_bidController.text) ?? 0.0;
    final double basePrice = (widget.productData['basePrice'] ?? 0.0)
        .toDouble();
    final double commission = FeePolicy.bidFeeActive
        ? (amount * FeePolicy.bidFeeRate)
        : 0.0;
    
    // Minimum increment validation: bid must be > current highest bid
    final bool meetsMinimum = amount > _currentHighestBid;
    
    final String nudge;
    if (amount <= _currentHighestBid) {
      nudge =
          'Jeetne ke liye Rs. ${(_currentHighestBid + 10).toStringAsFixed(0)} se zyada bid dein.';
    } else if (amount < basePrice * 1.1) {
      nudge =
          'Mashwara: Thori si zyada boli se jeetne ka chance behtar hota hai.';
    } else {
      nudge = 'Achi bid hai. Listing details verify karke confirm karein.';
    }

    if (!mounted) return;
    setState(() {
      _calculatedCommission = commission;
      _netToSeller = amount - commission;
      _aiNudgeMessage = nudge;
      _bidIsValid = meetsMinimum;
    });
  }

  void _adjustBid(int delta) {
    double current = double.tryParse(_bidController.text) ?? _currentHighestBid;
    _bidController.text = (current + delta).toString();
  }

  Future<String> _getCurrentUserBidVerificationState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _verificationUnverified;

    final userSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = userSnap.data() ?? <String, dynamic>{};

    bool truthy(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final t = (v ?? '').toString().trim().toLowerCase();
      return t == 'true' || t == '1' || t == 'yes';
    }

    final String verificationStatus =
        (data['verificationStatus'] ?? '').toString().trim().toLowerCase();

    final bool isApproved =
        truthy(data['cnicVerified']) ||
        truthy(data['isCnicVerified']) ||
        truthy(data['isCNICVerified']) ||
        verificationStatus == _verificationApproved;

    if (isApproved) return _verificationApproved;
    if (verificationStatus == _verificationPendingReview) {
      return _verificationPendingReview;
    }
    return _verificationUnverified;
  }

  Future<void> _showPendingReviewDialog() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('آپ کی تصدیق زیرِ جائزہ ہے'),
          content: const Text(
            'آپ کی معلومات کا جائزہ لیا جا رہا ہے۔ منظوری کے بعد آپ بولی لگا سکیں گے',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ٹھیک ہے'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showBidVerificationGateDialog() async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('بولی لگانے کے لیے تصدیق ضروری ہے'),
          content: const Text(
            'آپ منڈی دیکھ سکتے ہیں، لیکن پہلی بار بولی لگانے کے لیے شناخت کی تصدیق مکمل کرنا لازمی ہے',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('later'),
              child: const Text('بعد میں'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('verify'),
              child: const Text('ابھی تصدیق کریں'),
            ),
          ],
        );
      },
    );

    if (action == 'verify') {
      if (!mounted) return;
      Navigator.of(context).pushNamed(Routes.masterSignUp);
    }
  }

  Future<void> _handlePlaceBid() async {
    // Client-side validation: Check bid meets minimum increment
    if (!_bidIsValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            content: Text(
              'براہ کرم Rs. ${(_currentHighestBid + 10).toStringAsFixed(0)} سے زیادہ بولی لگائیں / Bid must be more than Rs. ${(_currentHighestBid + 10).toStringAsFixed(0)}',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      final writePath = 'listings/${widget.docId}/bids/{bidId}';
      debugPrint(
        '[BidFlowUI] submit_attempt currentUser=${user == null ? 'null' : 'present'} uid=${user?.uid ?? 'null'} listingId=${widget.docId} writePath=$writePath',
      );
      if (user == null) {
        const mapped = 'Please sign in to place a bid.';
        debugPrint(
          '[BidFlowUI] submit_blocked listingId=${widget.docId} writePath=$writePath finalMappedError=$mapped',
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

      final String verificationState =
          await _getCurrentUserBidVerificationState();
      if (verificationState == _verificationPendingReview) {
        await _showPendingReviewDialog();
        return;
      }

      if (verificationState != _verificationApproved) {
        await _showBidVerificationGateDialog();
        return;
      }

      final listingSnap = await FirebaseFirestore.instance
          .collection('listings')
          .doc(widget.docId)
          .get();
      if (!mounted) {
        return;
      }
      final listingData = listingSnap.data() ?? <String, dynamic>{};
      final bool isApproved = listingData['isApproved'] == true;
      final DateTime? startTime = (listingData['startTime'] is Timestamp)
          ? (listingData['startTime'] as Timestamp).toDate()
          : null;
      final String status = (listingData['status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (_isDealLocked(status)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Bidding locked: deal already in progress. / بولی بند ہے، سودا جاری ہے۔',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      if (!isApproved || startTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text('Admin verification pending / ایڈمن منظوری باقی ہے۔'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      double enteredBid = double.tryParse(_bidController.text) ?? 0.0;

      if (enteredBid <= _currentHighestBid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Bid must be higher than current highest. / نئی بولی زیادہ ہونی چاہیے۔',
            ),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() => _isLoading = true);

      final newBid = BidModel(
        listingId: widget.docId,
        sellerId: widget.productData['sellerId'] ?? '',
        buyerId: user.uid,
        buyerName: user.displayName ?? "Kharidar",
        buyerPhone: '',
        productName: widget.productData['product'] ?? 'Fasal',
        bidAmount: enteredBid,
        createdAt: DateTime.now(),
        status: 'pending',
      );

      await _biddingService.placeSmartBid(
        bid: newBid,
        marketPrice: (widget.productData['basePrice'] ?? 0.0).toDouble(),
      );

      await _audioPlayer.play(AssetSource('sounds/bid_success.mp3'));

      if (mounted) _showSuccessDialog();
    } catch (e) {
      final mapped = _humanizeError(e);
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        '[BidFlowUI] submit_error currentUser=${currentUser == null ? 'null' : 'present'} uid=${currentUser?.uid ?? 'null'} listingId=${widget.docId} writePath=listings/${widget.docId}/bids/{bidId} finalMappedError=$mapped raw=${e.toString()}',
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isDealLocked(String status) {
    return status == 'awaiting_admin_approval' ||
        status == 'escrow_confirmed' ||
        status == 'dispatched' ||
        status == 'delivered_pending_release' ||
        status == 'completed';
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);

    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      appBar: AppBar(
        title: Text(
          "${widget.productData['product'] ?? 'Fasal'} ki Boli",
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _biddingService.getLiveListing(widget.docId),
        builder: (context, snapshot) {
          final Map<String, dynamic> liveData =
              (snapshot.hasData && snapshot.data!.exists)
              ? ((snapshot.data!.data() as Map<String, dynamic>?) ??
                    <String, dynamic>{})
              : widget.productData;

          final bool isApproved = liveData['isApproved'] == true;
          final DateTime? startTime = (liveData['startTime'] is Timestamp)
              ? (liveData['startTime'] as Timestamp).toDate()
              : null;
          final DateTime? endTime = (liveData['endTime'] is Timestamp)
              ? (liveData['endTime'] as Timestamp).toDate()
              : null;
          final String listingStatus = (liveData['status'] ?? '')
              .toString()
              .trim()
              .toLowerCase();
          final bool isDealLocked = _isDealLocked(listingStatus);
          final double quantity = (liveData['quantity'] is num)
              ? (liveData['quantity'] as num).toDouble()
              : double.tryParse((liveData['quantity'] ?? '').toString()) ?? 0.0;
          final double enteredBid = double.tryParse(_bidController.text) ?? 0.0;
          final double totalPrice = quantity > 0
              ? (enteredBid * quantity)
              : enteredBid;

          final dynamic highestRaw =
              liveData['highestBid'] ?? liveData['basePrice'] ?? 0.0;
          if (highestRaw is num) {
            _currentHighestBid = highestRaw.toDouble();
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // ⏱️ TIMER SECTION (TOP BARA DISPLAY)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (isApproved &&
                          startTime != null &&
                          endTime != null) ...[
                        const Text(
                          "BOLI KHATAM HONE MEIN WAQT",
                          style: TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                            letterSpacing: 2,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Transform.scale(
                          scale: 1.4,
                          child: BidTimer(endTime: endTime),
                        ),
                      ] else ...[
                        const Text(
                          'Verification Pending',
                          style: TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      // �x` Kisan ka Audio Note
                      if (widget.productData['audioNoteUrl'] != null)
                        _buildAudioSection(
                          widget.productData['audioNoteUrl'],
                          goldColor,
                        ),

                      const SizedBox(height: 20),
                      _buildLiveBadge(_currentHighestBid),

                      if (quantity > 0) ...[
                        const SizedBox(height: 10),
                        _buildTotalPriceBadge(quantity, totalPrice),
                      ],

                      const SizedBox(height: 25),

                      // �S� AI NUDGE MESSAGE
                      if (!isDealLocked && _aiNudgeMessage != null)
                        _buildAiNudge(),

                      TextField(
                        controller: _bidController,
                        readOnly: isDealLocked,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: goldColor,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          prefixText: "Rs. ",
                          prefixStyle: const TextStyle(
                            color: goldColor,
                            fontSize: 22,
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: goldColor.withValues(alpha: 0.3),
                            ),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: goldColor, width: 2),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          _buildQuickButton(
                            "+50",
                            isDealLocked ? null : () => _adjustBid(50),
                            goldColor,
                          ),
                          _buildQuickButton(
                            "+100",
                            isDealLocked ? null : () => _adjustBid(100),
                            goldColor,
                          ),
                          _buildQuickButton(
                            "+500",
                            isDealLocked ? null : () => _adjustBid(500),
                            goldColor,
                          ),
                        ],
                      ),

                      const SizedBox(height: 30),
                      if (_calculatedCommission > 0)
                        _buildPriceBreakdown(goldColor),

                      const SizedBox(height: 40),
                      if (isDealLocked)
                        _buildDealLockedBadge()
                      else if (isApproved && startTime != null)
                        _buildSubmitButton(goldColor)
                      else
                        _buildVerificationPendingBadge(),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Widgets ---

  Widget _buildAiNudge() {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb, color: Colors.blueAccent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _aiNudgeMessage!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBadge(double amount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(50),
        color: Colors.greenAccent.withValues(alpha: 0.05),
      ),
      child: Column(
        children: [
          const Text(
            "AB TAK KI SAB SE BARI BOLI",
            style: TextStyle(
              color: Colors.greenAccent,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "Rs. ${amount.toInt()}",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection(String url, Color goldColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(Icons.record_voice_over, color: goldColor),
          const SizedBox(width: 15),
          const Expanded(
            child: Text(
              "Kisan ka message sunein",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => _audioPlayer.play(UrlSource(url)),
            icon: Icon(Icons.play_circle_fill, color: goldColor, size: 35),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown(Color goldColor) {
    if (!FeePolicy.bidFeeActive) {
      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
        ),
        child: const Text(
          'No platform fee is currently applied. / اس وقت کوئی پلیٹ فارم فیس لاگو نہیں۔',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Digital Arhat Fee (${(FeePolicy.bidFeeRate * 100).toStringAsFixed(0)}%):',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                "- Rs. ${_calculatedCommission.toStringAsFixed(0)}",
                style: const TextStyle(color: Colors.redAccent),
              ),
            ],
          ),
          const Divider(color: Colors.white10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Kisan ko milenge:",
                style: TextStyle(color: Colors.white70),
              ),
              Text(
                "Rs. ${_netToSeller.toStringAsFixed(0)}",
                style: TextStyle(color: goldColor, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTotalPriceBadge(double quantity, double totalPrice) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        'Total Price (${quantity.toStringAsFixed(0)} x unit): Rs. ${totalPrice.toStringAsFixed(0)}',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildQuickButton(String label, VoidCallback? onTap, Color goldColor) {
    return ActionChip(
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: goldColor,
      onPressed: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildSubmitButton(Color goldColor) {
    return GlassButton(
      label: 'Bismillah, Boli Confirm Karein',
      onPressed: (_isLoading || !_bidIsValid) ? null : _handlePlaceBid,
      loading: _isLoading,
      height: 60,
      radius: 15,
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildVerificationPendingBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_user, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Text(
            'Admin verification pending / ایڈمن منظوری باقی ہے',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDealLockedBadge() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orangeAccent),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, color: Colors.orangeAccent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bidding locked: deal is already in progress.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.orangeAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF012A10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          "Mubarak!",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          "Aapki boli kamyabi se submit ho gayi hai. / آپ کی بولی کامیابی سے جمع ہو گئی ہے۔",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          Center(
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text("Ameen", style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  String _humanizeError(Object error) {
    final message = error.toString().replaceAll('Exception: ', '').trim();
    if (message.toLowerCase().contains('permission-denied')) {
      if (FirebaseAuth.instance.currentUser == null) {
        return 'Please sign in to place a bid.';
      }
      return 'Bid could not be placed due to permission rules. Please retry.';
    }
    if (message.isEmpty) {
      return 'Bid could not be placed. Please try again. / بولی نہیں لگ سکی، دوبارہ کوشش کریں۔';
    }
    return message;
  }

  @override
  void dispose() {
    _bidController.removeListener(_onBidChanged);
    _bidController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
