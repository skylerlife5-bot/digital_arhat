import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:ui';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../core/widgets/verse_card.dart';
import '../../services/weather_services.dart';
import '../../services/bidding_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/market_rate_service.dart';

// �S& Corrected Single Imports
import 'add_listing_screen.dart';
import 'seller_bids.dart';
import 'seller_listings.dart';

class SellerDashboard extends StatefulWidget {
  final Map<String, dynamic> userData;
  const SellerDashboard({super.key, required this.userData});

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  final WeatherService _weatherService = WeatherService();
  final MarketplaceService _marketplaceService = MarketplaceService();
  // ignore: unused_field
  final BiddingService _biddingService = BiddingService();

  Stream<QuerySnapshot<Map<String, dynamic>>>? _incomingBidsStream;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _bidsSubscription;
  final ScrollController _scrollController = ScrollController();
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  late Future<_WeatherViewData?> _weatherFuture;
  int _lastBidCount = -1;
  bool _widgetErrorDetected = false;
  bool _paymentBannerDismissed = false;
  bool _paymentBannerVisible = false;
  final NumberFormat _pkr = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'Rs. ',
    decimalDigits: 0,
  );

  String get _resolvedSellerId =>
      widget.userData['uid']?.toString() ??
      FirebaseAuth.instance.currentUser?.uid ??
      '';

  int _sellerBidCount(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final sellerId = _resolvedSellerId;
    if (sellerId.isEmpty) return 0;
    return docs
        .where((doc) => (doc.data()['sellerId']?.toString() ?? '') == sellerId)
        .length;
  }

  @override
  void initState() {
    super.initState();
    _installGlobalErrorGuard();
    _setupCachedStreams();
    _weatherFuture = _fetchWeatherViewData();
    _listenIncomingBids();
  }

  @override
  void dispose() {
    _bidsSubscription?.cancel();
    _scrollController.dispose();
    FlutterError.onError = _previousFlutterErrorHandler;
    super.dispose();
  }

  void _installGlobalErrorGuard() {
    _previousFlutterErrorHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _previousFlutterErrorHandler?.call(details);
      if (!mounted || _widgetErrorDetected) return;
      setState(() {
        _widgetErrorDetected = true;
      });
    };
  }

  void _setupCachedStreams() {
    final String sellerId = _resolvedSellerId;
    if (sellerId.isNotEmpty) {
      _incomingBidsStream = _marketplaceService.getSellerIncomingBidsStream(
        sellerId,
      );
    }
  }

  Future<_WeatherViewData?> _fetchWeatherViewData() async {
    try {
      final String district =
          widget.userData['district']?.toString() ?? "Lahore";
      final String crop = widget.userData['crop']?.toString() ?? "Gandum";

      final data = await _weatherService.getWeatherData(district);
      String advisory = "�&��س�& ک�R �&ع����&ات دست�Rاب � ہ�Rں ہ�Rں�";

      if ((data['success'] == true) && data.isNotEmpty) {
        advisory = await _weatherService.getAIAdvisory(
          data['condition'] ?? "Clear",
          data['temp'] ?? 25,
          crop,
        );
      }

      return _WeatherViewData(data: data, advisory: advisory, failed: false);
    } catch (_) {
      return const _WeatherViewData(data: null, advisory: '', failed: true);
    }
  }

  Future<void> _refreshWeather() async {
    if (!mounted) return;
    setState(() {
      _weatherFuture = _fetchWeatherViewData();
    });
    await _weatherFuture;
  }

  void _listenIncomingBids() {
    final stream = _incomingBidsStream;
    if (stream == null) return;

    _bidsSubscription = stream.listen(
      (snapshot) {
        if (!mounted) return;

        final int count = _sellerBidCount(snapshot.docs);
        if (_lastBidCount >= 0 && count > _lastBidCount) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5),
              behavior: SnackBarBehavior.floating,
              content: Text('Nayi boli receive hui hai!'),
            ),
          );
        }

        _lastBidCount = count;
      },
      onError: (error) {
        debugPrint(
          'SELLER_INCOMING_BIDS_ERROR|ts=${DateTime.now().toIso8601String()}|error=$error',
        );
      },
    );
  }

  Future<void> _openDealWhatsApp() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    try {
      final dealSnap = await FirebaseFirestore.instance
          .collection('deals')
          .where('sellerId', isEqualTo: currentUid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final paidDealDoc = _firstPaidDeal(dealSnap.docs);
      if (paidDealDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            content: Text('WhatsApp ایسکرو ادائیگی کے بعد فعال ہوتا ہے۔'),
          ),
        );
        return;
      }

      final dealDoc = paidDealDoc;
      final dealData = dealDoc.data();
      final dealId = dealDoc.id;
      final buyerId = (dealData['buyerId'] ?? '').toString().trim();
      final product =
          (dealData['productName'] ?? dealData['product'] ?? 'Fasal')
              .toString()
              .trim();

      if (buyerId.isEmpty) {
        throw Exception('Buyer record missing for this deal.');
      }

      final buyerSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(buyerId)
          .get();
      final buyerData = buyerSnap.data() ?? <String, dynamic>{};
      final rawPhone = (buyerData['phone'] ?? buyerData['phoneNumber'] ?? '')
          .toString();
      final waPhone = _normalizeWaPhone(rawPhone);
      if (waPhone.isEmpty) {
        throw Exception('خریدار کا WhatsApp نمبر دستیاب نہیں ہے۔');
      }

      final message =
          'السلام علیکم۔ ڈیل آئی ڈی: $dealId کے حوالے سے رابطہ کر رہا ہوں۔ پروڈکٹ: $product';
      final uri = Uri.parse(
        'https://wa.me/$waPhone?text=${Uri.encodeComponent(message)}',
      );

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            content: Text('WhatsApp کھولا نہیں جا سکا۔'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          content: Text(e.toString().replaceAll('Exception: ', '')),
        ),
      );
    }
  }

  Query<Map<String, dynamic>> _sellerDealsQuery(String uid) {
    return FirebaseFirestore.instance
        .collection('deals')
        .where('sellerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(10);
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _firstPaidDeal(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      final paymentStatus = (doc.data()['paymentStatus'] ?? '')
          .toString()
          .toUpperCase();
      if (paymentStatus == 'VERIFIED') {
        return doc;
      }
    }
    return null;
  }

  void _dismissPaymentBanner() {
    _paymentBannerDismissed = true;
    _paymentBannerVisible = false;
    ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
  }

  void _showPaymentReceivedBanner() {
    if (!mounted || _paymentBannerVisible || _paymentBannerDismissed) return;
    _paymentBannerVisible = true;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFF0E3A66),
        leading: const Icon(
          Icons.verified_rounded,
          color: Colors.lightGreenAccent,
        ),
        content: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.88, end: 1),
          duration: const Duration(milliseconds: 540),
          curve: Curves.easeOutBack,
          builder: (context, value, child) =>
              Transform.scale(scale: value, child: child),
          child: const Text(
            'Payment Received: خریدار کی ادائیگی تصدیق ہو گئی ہے۔ اب آپ اعتماد کے ساتھ مال روانہ کر سکتے ہیں۔',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _dismissPaymentBanner,
            child: const Text('Theek Hai', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  String _normalizeWaPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('+')) {
      return digits.substring(1);
    }

    if (digits.startsWith('00')) {
      return digits.substring(2);
    }

    if (digits.startsWith('92')) {
      return digits;
    }

    if (digits.startsWith('0')) {
      return '92${digits.substring(1)}';
    }

    return '92$digits';
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);
    const darkGreen = Color(0xFF011A0A);

    return Scaffold(
      backgroundColor: darkGreen,
      appBar: CustomAppBar(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        titleWidget: Image.asset(
          'assets/logo.png',
          height: 34,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        actions: [
          if ((FirebaseAuth.instance.currentUser?.uid ?? '').isNotEmpty)
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _sellerDealsQuery(
                FirebaseAuth.instance.currentUser!.uid,
              ).snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final canChat = _firstPaidDeal(docs) != null;
                if (!canChat) return const SizedBox.shrink();
                return IconButton(
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _openDealWhatsApp();
                  },
                  icon: const Icon(Icons.chat, color: Colors.amber),
                  tooltip: 'Deal WhatsApp',
                );
              },
            ),
          CustomerSupportIconAction(
            userName: (widget.userData['name'] ?? '').toString(),
          ),
        ],
      ),

      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CustomerSupportFab(
            userName: (widget.userData['name'] ?? '').toString(),
            mini: true,
          ),
          const SizedBox(height: 10),
          FloatingActionButton.extended(
            backgroundColor: goldColor,
            elevation: 10,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AddListingScreen(userData: widget.userData),
                ),
              );
            },
            icon: const Icon(
              Icons.add_shopping_cart_rounded,
              color: Colors.black,
              size: 24,
            ),
            label: const Text(
              "Maal Bechein",
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),

      body: RefreshIndicator(
        color: goldColor,
        onRefresh: _refreshWeather,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              RepaintBoundary(child: _buildWeatherCard()),
              const SizedBox(height: 15),
              const VerseCard(),
              const SizedBox(height: 12),
              _buildSellerTrustCard(),
              const SizedBox(height: 15),
              const RepaintBoundary(child: _MarketRatesTickerSection()),
              const SizedBox(height: 25),
              const Text(
                "Main Menu",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 15),

              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                children: [
                  _buildMenuCard("�&�Rرا اسٹاک", Icons.inventory_2_rounded, () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => const SellerListingsScreen(),
                      ),
                    );
                  }),
                  _buildBidsMenuCard(),
                  _buildMenuCard("�&� ���R ر�Rٹس", Icons.trending_up_rounded, () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5),
                        content: Text("ر�Rٹس اپ ���Rٹ ہ�� رہ� ہ�Rں..."),
                      ),
                    );
                  }),
                  _buildMenuCard(
                    "��ا�ٹ",
                    Icons.account_balance_wallet_rounded,
                    () {
                      _openWalletSheet();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Assalam-o-Alaikum,",
          style: TextStyle(color: Colors.white60, fontSize: 14),
        ),
        Text(
          widget.userData['fullName'] ?? "Kisan Bhai",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSellerTrustCard() {
    final sellerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sellerUid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('deals')
          .where('sellerId', isEqualTo: sellerUid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        final hasVerified = docs.any(
          (doc) =>
              (doc.data()['paymentStatus'] ?? '').toString().toUpperCase() ==
              'VERIFIED',
        );
        if (!hasVerified) return const SizedBox.shrink();

        if (!_paymentBannerDismissed && !_paymentBannerVisible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _showPaymentReceivedBanner();
          });
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0E3A66).withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.85)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.verified, color: Colors.blueAccent, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'خ��شخبر�R! خر�Rدار ک�R ر��& ا�R���&�  ک�� �&��ص��� ہ�� � ک�R ہ�� اب آپ اط�&�R� ا�  س� �&ا� ���R��R��ر کر سکت� ہ�Rں� �&ا� ک�R تصد�R� ہ��ت� ہ�R ر��& آپ ک� ��ا�ٹ �&�Rں آ جائ� گ�R�',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Jameel Noori Nastaliq',
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeatherCard() {
    try {
      if (_widgetErrorDetected) {
        return const SizedBox.shrink();
      }
      return FutureBuilder<_WeatherViewData?>(
        future: _weatherFuture,
        builder: (context, snapshot) {
          const goldColor = Color(0xFFFFD700);

          if (snapshot.connectionState == ConnectionState.waiting) {
            final String districtLabel =
                (widget.userData['district']?.toString().trim().isNotEmpty ??
                    false)
                ? widget.userData['district'].toString().trim()
                : 'Lahore';
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFB3E5FC), Color(0xFF4FC3F7)],
                ),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 38,
                    height: 38,
                    child: Lottie.asset(
                      'assets/lottie/sun.json',
                      repeat: true,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                        Icons.wb_sunny,
                        color: goldColor,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '�&��س�& اپ���Rٹ ہ�� رہا ہ�... ($districtLabel)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'درجہ حرارت: --°C',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Text(
                          '�&��س�& �&ع�&��� ک� �&طاب� ہ��',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontFamily: 'Jameel Noori',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }

          final model = snapshot.data;
          if (model == null || model.failed || model.data == null) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: const Text(
                'Mausam ki malumat mausoos nahi ho sakin',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }

          final weatherData = model.data!;
          final advisory = model.advisory;
          final bool showWarning = weatherData['isRainLikely'] == true;
          final String districtLabel =
              (widget.userData['district']?.toString().trim().isNotEmpty ??
                  false)
              ? widget.userData['district'].toString().trim()
              : 'Lahore';
          final String condition =
              (weatherData['description'] ??
                      weatherData['condition'] ??
                      'Clear')
                  .toString();
          final String romanCondition = _romanUrduCondition(condition);
          final dynamic rawTemp = weatherData['temp'];
          final double? parsedTemp = rawTemp is num
              ? rawTemp.toDouble()
              : double.tryParse(rawTemp?.toString() ?? '');
          final String tempLabel = parsedTemp == null
              ? '--°C'
              : '${parsedTemp.round().toInt()}°C';
          final advisoryText = () {
            final raw = advisory.trim();
            final hasEnglish = RegExp(r'[A-Za-z]').hasMatch(raw);
            if (raw.isEmpty || raw.toLowerCase().contains('null') || hasEnglish) {
              return showWarning
                  ? 'احت�Rاط کر�Rں�R بارش کا ا�&کا�  �&��ج��د ہ��'
                  : '�&��س�& �&ع�&��� ک� �&طاب� ہ��';
            }
            return raw;
          }();
          final gradients = _weatherGradientForTime(DateTime.now());

          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradients,
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: showWarning
                    ? Colors.redAccent.withValues(alpha: 0.7)
                    : Colors.white10,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 38,
                  height: 38,
                  child: Lottie.asset(
                    _weatherAnimationAsset(condition),
                    repeat: true,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      _weatherIconForCondition(condition),
                      color: showWarning ? Colors.redAccent : goldColor,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$romanCondition ($districtLabel)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        'درجہ حرارت: $tempLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        advisoryText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontFamily: 'Jameel Noori',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  List<Color> _weatherGradientForTime(DateTime now) {
    final hour = now.hour;
    if (hour >= 5 && hour < 16) {
      return const [Color(0xFFB3E5FC), Color(0xFF4FC3F7)];
    }
    if (hour >= 16 && hour < 24) {
      return const [Color(0xFFFF7043), Color(0xFF6A1B9A)];
    }
    return const [Color(0xFF5E35B1), Color(0xFF311B92)];
  }

  String _weatherAnimationAsset(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('rain') ||
        lower.contains('drizzle') ||
        lower.contains('storm')) {
      return 'assets/lottie/rain.json';
    }
    if (lower.contains('sun') || lower.contains('clear')) {
      return 'assets/lottie/sun.json';
    }
    return 'assets/lottie/cloudy.json';
  }

  IconData _weatherIconForCondition(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('rain') ||
        lower.contains('drizzle') ||
        lower.contains('storm')) {
      return Icons.thunderstorm;
    }
    if (lower.contains('cloud') ||
        lower.contains('overcast') ||
        lower.contains('mist')) {
      return Icons.cloud;
    }
    if (lower.contains('sun') || lower.contains('clear')) {
      return Icons.wb_sunny;
    }
    return Icons.wb_cloudy;
  }

  String _romanUrduCondition(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('rain') ||
        lower.contains('drizzle') ||
        lower.contains('storm')) {
      return 'بارش';
    }
    if (lower.contains('cloud') ||
        lower.contains('overcast') ||
        lower.contains('mist')) {
      return 'باد�';
    }
    if (lower.contains('sun') || lower.contains('clear')) {
      return 'صاف آس�&ا� ';
    }
    return 'باد�';
  }

  Widget _buildMenuCard(
    String title,
    IconData icon,
    VoidCallback onTap, {
    bool showBadge = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(
                      0xFFFFD700,
                    ).withValues(alpha: 0.1),
                    child: Icon(icon, color: const Color(0xFFFFD700)),
                  ),
                  if (showBadge)
                    const Positioned(
                      right: -1,
                      top: -1,
                      child: CircleAvatar(
                        radius: 5,
                        backgroundColor: Colors.redAccent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBidsMenuCard() {
    final stream = _incomingBidsStream;
    if (stream == null) {
      return _buildMenuCard("ب����Rاں (Bids)", Icons.gavel_rounded, () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => const SellerBidsScreen(
              listingId: "ALL",
              productName: "Tamam Faslein",
              basePrice: 0.0,
            ),
          ),
        );
      });
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final sellerCount = _sellerBidCount(snapshot.data?.docs ?? const []);
        if (snapshot.hasData) {
          debugPrint('UI REFRESHED: Bids found = $sellerCount');
        } else {
          debugPrint('UI REFRESHED: Bids found = 0');
        }
        final bool showBadge = sellerCount > 0;
        return _buildMenuCard("ب����Rاں (Bids)", Icons.gavel_rounded, () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (c) => const SellerBidsScreen(
                listingId: "ALL",
                productName: "Tamam Faslein",
                basePrice: 0.0,
              ),
            ),
          );
        }, showBadge: showBadge);
      },
    );
  }

  Future<void> _openWalletSheet() async {
    final sellerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (sellerUid.isEmpty) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF011A0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(sellerUid)
              .snapshots(),
          builder: (context, snapshot) {
            final map = snapshot.data?.data() ?? <String, dynamic>{};
            final bool isFlagged = map['isAccountFlagged'] == true;
            final pending = (map['pendingBalance'] is num)
                ? (map['pendingBalance'] as num).toDouble()
                : double.tryParse((map['pendingBalance'] ?? '0').toString()) ??
                      0.0;
            final available = (map['availableBalance'] is num)
                ? (map['availableBalance'] as num).toDouble()
                : double.tryParse(
                        (map['availableBalance'] ?? '0').toString(),
                      ) ??
                      0.0;
            final lifetime = (map['lifetimeEarnings'] is num)
                ? (map['lifetimeEarnings'] as num).toDouble()
                : double.tryParse(
                        (map['lifetimeEarnings'] ?? '0').toString(),
                      ) ??
                      0.0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seller Wallet / س�R�ر ��ا�ٹ',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontFamily: 'Jameel Noori Nastaliq',
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Pending Balance: ${_pkr.format(pending)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Available Balance: ${_pkr.format(available)}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Text(
                    'Lifetime Earnings: ${_pkr.format(lifetime)}',
                    style: const TextStyle(
                      color: Colors.lightGreenAccent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Payment History',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 170,
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('transactions')
                          .where('type', isEqualTo: 'payout')
                          .where('sellerId', isEqualTo: sellerUid)
                          .orderBy('timestamp', descending: true)
                          .limit(10)
                          .snapshots(),
                      builder: (context, txSnapshot) {
                        if (txSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          );
                        }
                        final txDocs = txSnapshot.data?.docs ?? const [];
                        if (txDocs.isEmpty) {
                          return const Center(
                            child: Text(
                              'No payout history yet.',
                              style: TextStyle(color: Colors.white60),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: txDocs.length,
                          separatorBuilder: (_, _) => const Divider(
                            color: Colors.white12,
                            height: 10,
                          ),
                          itemBuilder: (context, index) {
                            final tx = txDocs[index].data();
                            final net = (tx['amountPaid'] is num)
                                ? (tx['amountPaid'] as num).toDouble()
                                : double.tryParse(
                                        (tx['amountPaid'] ?? '0').toString(),
                                      ) ??
                                      0.0;
                            final listingId =
                                (tx['listingId'] ?? '--').toString();
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Deal: $listingId',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              trailing: Text(
                                _pkr.format(net),
                                style: const TextStyle(
                                  color: Colors.lightGreenAccent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isFlagged)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: const Text(
                        'Security Violation: Withdraw actions are locked for this account.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontFamily: 'Jameel Noori Nastaliq',
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: isFlagged
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5),
                                  content: Text('Withdraw request submitted.'),
                                ),
                              );
                              Navigator.pop(context);
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                      ),
                      icon: const Icon(Icons.account_balance_wallet_rounded),
                      label: const Text('Withdraw / ر��& � کا��Rں'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _MarketRatesTickerSection extends StatefulWidget {
  const _MarketRatesTickerSection();

  @override
  State<_MarketRatesTickerSection> createState() =>
      _MarketRatesTickerSectionState();
}

class _MarketRatesTickerSectionState extends State<_MarketRatesTickerSection> {
  final MarketRateService _rateService = MarketRateService();
  Timer? _timer;
  List<MarketRate> _rates = const [];

  @override
  void initState() {
    super.initState();
    _rates = _rateService.getLatestRates();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      final latest = _rateService.getLatestRates();
      if (!_hasRatesChanged(latest, _rates)) return;
      setState(() {
        _rates = latest;
      });
    });
  }

  bool _hasRatesChanged(List<MarketRate> latest, List<MarketRate> current) {
    if (latest.length != current.length) return true;
    for (int i = 0; i < latest.length; i++) {
      if (latest[i].cropName != current[i].cropName) return true;
      if (latest[i].currentPrice != current[i].currentPrice) return true;
      if (latest[i].change != current[i].change) return true;
      if (latest[i].trend != current[i].trend) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_rates.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 50,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _rates.length,
        separatorBuilder: (context, index) => VerticalDivider(
          color: Colors.grey.withValues(alpha: 0.25),
          indent: 10,
          endIndent: 10,
        ),
        itemBuilder: (context, index) {
          final rate = _rates[index];
          final bool isUp = rate.trend == 'up';
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rate.cropName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Color(0xFFB8860B),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Rs. ${rate.currentPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black87,
                  ),
                ),
                Icon(
                  isUp ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  color: isUp ? Colors.green : Colors.red,
                  size: 22,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _WeatherViewData {
  final Map<String, dynamic>? data;
  final String advisory;
  final bool failed;

  const _WeatherViewData({
    required this.data,
    required this.advisory,
    required this.failed,
  });
}

