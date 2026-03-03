import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:lottie/lottie.dart';

import '../../core/constants.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../core/widgets/glass_button.dart';
import '../../models/deal_status.dart';
import '../../services/marketplace_service.dart';
import '../../services/notification_service.dart';
import '../../services/realtime_agri_rates_service.dart';
import '../../services/weather_services.dart';
import '../components/agri_rates_gold_card.dart';
import '../components/bid_dialog.dart';
import '../components/mandi_ticker_widget.dart';
import 'market_listing_card.dart';

class BuyerHomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const BuyerHomeScreen({super.key, required this.userData});

  @override
  State<BuyerHomeScreen> createState() => _BuyerHomeScreenState();
}

class _BuyerHomeScreenState extends State<BuyerHomeScreen> {
  final MarketplaceService _marketplaceService = MarketplaceService();
  final WeatherService _weatherService = WeatherService();
  final RealtimeAgriRatesService _realtimeAgriRatesService =
      RealtimeAgriRatesService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeListingsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _winnerListingsStream;

  String _searchQuery = '';
  MandiType? _selectedCategory;
  String? _currentlyPlayingUrl;

  Map<String, dynamic>? _weatherData;
  String _advisory = 'Live weather sync ho raha hai...';
  bool _isWeatherLoading = true;
  bool _weatherFailed = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _approvedWinnerSubscription;
  final Set<String> _shownWinnerNotifications = <String>{};

  @override
  void initState() {
    super.initState();
    _selectedCategory = null;
    _setupCachedStreams();
    _loadWeather();
    _listenApprovedWinnerStatus();
  }

  void _setupCachedStreams() {
    _activeListingsStream = FirebaseFirestore.instance
        .collection('listings')
        .where('isApproved', isEqualTo: true)
        .snapshots();

    final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUserId.isEmpty) {
      _winnerListingsStream = null;
      return;
    }

    _winnerListingsStream = FirebaseFirestore.instance
        .collection('listings')
        .where('winnerId', isEqualTo: currentUserId)
        .snapshots();
  }

  @override
  void dispose() {
    _approvedWinnerSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _listenApprovedWinnerStatus() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return;

    _approvedWinnerSubscription = FirebaseFirestore.instance
        .collection('listings')
        .where('buyerId', isEqualTo: uid)
        .snapshots()
        .listen((snapshot) async {
          for (final doc in snapshot.docs) {
            final map = doc.data();
            final listingStatus =
                (map['listingStatus'] ??
                        map['auctionStatus'] ??
                        map['status'] ??
                        '')
                    .toString()
                    .toLowerCase();

            if (listingStatus != 'approved_winner') continue;
            if (_shownWinnerNotifications.contains(doc.id)) continue;

            _shownWinnerNotifications.add(doc.id);
            if (!mounted) return;

            await NotificationService.showApprovedWinnerNotification();
            if (!mounted) return;
            ScaffoldMessenger.of(context).showMaterialBanner(
              MaterialBanner(
                backgroundColor: const Color(0xFF0B2F18),
                content: const Text(
                  'مبارک ہو! آپ کی بولی منظور ہو گئی ہے۔ ادائیگی کر کے اپنا مال حاصل کریں۔',
                  style: TextStyle(color: Colors.white),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                    },
                    child: const Text('Theek Hai'),
                  ),
                ],
              ),
            );
          }
        });
  }

  Future<void> _loadWeather() async {
    try {
      if (mounted) {
        setState(() {
          _isWeatherLoading = true;
          _weatherFailed = false;
        });
      }

      final districtRaw = (widget.userData['district'] ?? '').toString().trim();
      final district =
          districtRaw.isEmpty || districtRaw.toLowerCase() == 'null'
          ? 'Punjab'
          : districtRaw;

      final data = await _weatherService.getWeatherData(district);
      String advisory = 'Mausam ki maloomat dastyab nahi hain.';

      if (data['success'] == true) {
        advisory = await _weatherService.getAIAdvisory(
          data['condition'] ?? '',
          data['temp'] ?? 0,
          'Fasal',
        );
      }

      if (!mounted) return;
      setState(() {
        _weatherData = data;
        _advisory = advisory;
        _isWeatherLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _weatherData = null;
        _advisory = '';
        _isWeatherLoading = false;
        _weatherFailed = true;
      });
    }
  }

  Future<void> _playAudio(String url) async {
    try {
      if (_currentlyPlayingUrl == url) {
        await _audioPlayer.stop();
        setState(() => _currentlyPlayingUrl = null);
      } else {
        await _audioPlayer.play(UrlSource(url));
        setState(() => _currentlyPlayingUrl = url);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Audio play nahi ho saki')));
    }
  }

  Future<void> _refreshAiRatesNow() async {
    try {
      await _marketplaceService.syncPakistanMandiRates(
        forcedType: _selectedCategory,
      );
    } catch (_) {
      if (!mounted) return;
    }
  }

  Future<void> _openDealWhatsApp() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (currentUid.isEmpty) return;

    try {
      final dealSnap = await FirebaseFirestore.instance
          .collection('deals')
          .where('buyerId', isEqualTo: currentUid)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .get();

      final paidDealDoc = _firstVerifiedDeal(dealSnap.docs);

      if (paidDealDoc == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
            content: Text(
              'Chat admin payment verification ke baad enable hota hai.',
            ),
          ),
        );
        return;
      }

      final dealDoc = paidDealDoc;
      final dealData = dealDoc.data();
      final dealId = dealDoc.id;
      final sellerId = (dealData['sellerId'] ?? '').toString().trim();
      final product =
          (dealData['productName'] ?? dealData['product'] ?? 'Fasal')
              .toString()
              .trim();

      if (sellerId.isEmpty) {
        throw Exception('Seller record missing for this deal.');
      }

      final sellerSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(sellerId)
          .get();
      final sellerData = sellerSnap.data() ?? <String, dynamic>{};
      final rawPhone = (sellerData['phone'] ?? sellerData['phoneNumber'] ?? '')
          .toString();
      final waPhone = _normalizeToPlus92(rawPhone);
      if (waPhone.isEmpty) {
        throw Exception('Seller ka WhatsApp number available nahi hai.');
      }

      final message =
          'Assalam-o-Alaikum. Deal ID: $dealId ke hawalay se rabta kar raha hoon. Product: $product';
      final uri = Uri.parse(
        'https://wa.me/${waPhone.replaceAll('+', '')}?text=${Uri.encodeComponent(message)}',
      );

      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('WhatsApp open nahi ho saka.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  Query<Map<String, dynamic>> _buyerDealsQuery(String uid) {
    return FirebaseFirestore.instance
        .collection('deals')
        .where('buyerId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(10);
  }

  QueryDocumentSnapshot<Map<String, dynamic>>? _firstVerifiedDeal(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    for (final doc in docs) {
      final status = (doc.data()['paymentStatus'] ?? '')
          .toString()
          .toUpperCase();
      if (status == 'VERIFIED') {
        return doc;
      }
    }
    return null;
  }

  Future<void> _confirmDelivery(
    QueryDocumentSnapshot<Map<String, dynamic>> dealDoc,
  ) async {
    final data = dealDoc.data();
    final sellerId = (data['sellerId'] ?? '').toString().trim();
    if (sellerId.isEmpty) return;

    final dealAmountRaw =
        data['dealAmount'] ?? data['finalPrice'] ?? data['buyerTotal'] ?? 0;
    final dealAmount = dealAmountRaw is num
        ? dealAmountRaw.toDouble()
        : double.tryParse(dealAmountRaw.toString()) ?? 0.0;
    final sellerPayout = dealAmount * 0.99;

    HapticFeedback.lightImpact();
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final freshDeal = await transaction.get(dealDoc.reference);
      final fresh = freshDeal.data() ?? <String, dynamic>{};
      if (fresh['deliveryConfirmed'] == true) {
        return;
      }

      final sellerRef = FirebaseFirestore.instance
          .collection('users')
          .doc(sellerId);
      transaction.set(sellerRef, {
        'pendingBalance': FieldValue.increment(-sellerPayout),
        'availableBalance': FieldValue.increment(sellerPayout),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(dealDoc.reference, {
        'deliveryConfirmed': true,
        'paymentStatus': 'completed',
        'status': DealStatus.dealCompleted.value,
        'deliveredAt': FieldValue.serverTimestamp(),
        'sellerPayoutReleased': sellerPayout,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
        content: Text(
          'Delivery confirmed. Seller payout moved to available balance.',
        ),
      ),
    );
  }

  Widget _buildConfirmDeliveryCard() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _buyerDealsQuery(uid).snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        QueryDocumentSnapshot<Map<String, dynamic>>? deal;
        for (final doc in docs) {
          final map = doc.data();
          final payment = (map['paymentStatus'] ?? '').toString().toUpperCase();
          final confirmed = map['deliveryConfirmed'] == true;
          if (payment == 'VERIFIED' && !confirmed) {
            deal = doc;
            break;
          }
        }

        if (deal == null) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.verified_user, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Confirm Delivery / �&ا� �&� گ�Rا',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              GlassButton(
                label: 'Confirm Delivery / �&ا� �&� گ�Rا',
                onPressed: () => _confirmDelivery(deal!),
                textStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Jameel Noori Nastaliq',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _normalizeToPlus92(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('+')) {
      return digits;
    }

    if (digits.startsWith('00')) {
      return '+${digits.substring(2)}';
    }

    if (digits.startsWith('92')) {
      return '+$digits';
    }

    if (digits.startsWith('0')) {
      return '+92${digits.substring(1)}';
    }

    return '+92$digits';
  }

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);
    const darkGreen = Color(0xFF011A0A);

    return Scaffold(
      backgroundColor: darkGreen,
      floatingActionButton: CustomerSupportFab(
        userName: (widget.userData['name'] ?? '').toString(),
        mini: true,
      ),
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
              stream: _buyerDealsQuery(
                FirebaseAuth.instance.currentUser!.uid,
              ).snapshots(),
              builder: (context, snapshot) {
                final docs = snapshot.data?.docs ?? const [];
                final canChat = _firstVerifiedDeal(docs) != null;
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
      body: Column(
        children: [
          _buildSafeMandiTicker(),
          Container(
            color: darkGreen,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [Expanded(child: _buildWeatherBanner(goldColor))],
                ),
                const SizedBox(height: 10),
                AgriRatesGoldCard(
                  ratesStream: _realtimeAgriRatesService.watchRates(),
                ),
                const SizedBox(height: 15),
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildCategoryTabs(goldColor, darkGreen),
                const SizedBox(height: 10),
                _buildConfirmDeliveryCard(),
              ],
            ),
          ),
          Expanded(
            child: _BuyerListingsSection(
              stream: _activeListingsStream,
              winnerStream: _winnerListingsStream,
              searchQuery: _searchQuery,
              selectedCategory: _selectedCategory,
              currentlyPlayingUrl: _currentlyPlayingUrl,
              buyerDistrict: (widget.userData['district'] ?? 'Punjab')
                  .toString(),
              onPlayAudio: _playAudio,
              onBid: _openBidSheet,
              onRefreshAiRates: _refreshAiRatesNow,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherBanner(Color goldColor) {
    try {
      if (_weatherFailed) {
        return const SizedBox.shrink();
      }
      if (!_isWeatherLoading && _weatherData == null) {
        return const SizedBox.shrink();
      }

      final bool showWarning = _weatherData?['isRainLikely'] == true;
      final districtRaw = (widget.userData['district'] ?? '').toString().trim();
      final districtLabel =
          districtRaw.isEmpty || districtRaw.toLowerCase() == 'null'
          ? 'Lahore'
          : districtRaw;
      final String condition =
          (_weatherData?['condition'] ??
                  _weatherData?['description'] ??
                  'Clear')
              .toString();
      final String romanCondition = _romanUrduCondition(condition);
      final dynamic rawTemp = _weatherData?['temp'];
      final double? parsedTemp = rawTemp is num
          ? rawTemp.toDouble()
          : double.tryParse(rawTemp?.toString() ?? '');
      final String tempLabel = parsedTemp == null
          ? '--°C'
          : '${parsedTemp.round().toInt()}°C';
      final advisoryText = () {
        final raw = _advisory.trim();
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
                    _isWeatherLoading
                        ? '�&��س�& اپ���Rٹ ہ�� رہا ہ�...'
                        : '$romanCondition ($districtLabel)',
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
    } catch (_) {
      return const SizedBox.shrink();
    }
  }

  Widget _buildSafeMandiTicker() {
    try {
      return MandiTickerWidget(selectedType: _selectedCategory);
    } catch (e) {
      debugPrint('MANDI_TICKER_BOUNDARY_ERROR|error=$e');
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

  Widget _buildSearchBar() {
    return TextField(
      onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        hintText: 'Gandum, Kapas ya koi bhi maal dhoondein...',
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        prefixIcon: const Icon(
          Icons.search,
          color: Color(0xFFFFD700),
          size: 20,
        ),
        filled: true,
        fillColor: const Color(0xFF0B2F18).withValues(alpha: 0.66),
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide(
            color: const Color(0xFFFFD700).withValues(alpha: 0.20),
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: Color(0xFFFFD700), width: 1.5),
        ),
      ),
    );
  }

  Widget _buildCategoryTabs(Color gold, Color bg) {
    final categories = <MandiType>[...MandiType.values];

    return SizedBox(
      height: 35,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        cacheExtent: 320,
        itemCount: categories.length,
        itemBuilder: (context, index) {
          final category = categories[index];
          final bool isSelected = _selectedCategory == category;
          final label = category.label;

          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = category),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              scale: isSelected ? 1.0 : 0.96,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 18),
                decoration: BoxDecoration(
                  color: isSelected
                      ? gold
                      : Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: gold.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? bg : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openBidSheet(
    Map<String, dynamic> data,
    String listingId,
  ) async {
    Map<String, dynamic> latest = data;
    try {
      latest = await _marketplaceService.getListingBidContext(listingId);
    } catch (_) {
      latest = data;
    }

    if (!mounted) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          BidDialog(productData: latest, listingId: listingId),
    );

    if (!mounted) return;
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Boli Lagaen: kamyabi se lag gayi hai!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class _BuyerListingsSection extends StatelessWidget {
  const _BuyerListingsSection({
    required this.stream,
    required this.winnerStream,
    required this.searchQuery,
    required this.selectedCategory,
    required this.currentlyPlayingUrl,
    required this.buyerDistrict,
    required this.onPlayAudio,
    required this.onBid,
    required this.onRefreshAiRates,
  });

  final Stream<QuerySnapshot<Map<String, dynamic>>>? stream;
  final Stream<QuerySnapshot<Map<String, dynamic>>>? winnerStream;
  final String searchQuery;
  final MandiType? selectedCategory;
  final String? currentlyPlayingUrl;
  final String buyerDistrict;
  final void Function(String url) onPlayAudio;
  final void Function(Map<String, dynamic> data, String listingId) onBid;
  final Future<void> Function() onRefreshAiRates;

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);
    final listingStream = stream;
    if (listingStream == null) {
      return const Center(
        child: Text(
          'Maal dastyab nahi hai.',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: listingStream,
      builder: (context, activeSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: winnerStream,
          builder: (context, winnerSnapshot) {
            debugPrint(
              'TIMESTAMP: Buyer Stream updated at ${DateTime.now()} | state=${activeSnapshot.connectionState} | hasData=${activeSnapshot.hasData} | count=${activeSnapshot.data?.docs.length ?? 0}',
            );

            if (activeSnapshot.hasData) {
              for (final doc in activeSnapshot.data!.docs) {
                final raw = doc.data();
                final product = (raw['product'] ?? '').toString().toLowerCase();
                final marketAverage =
                    raw['market_average'] ?? raw['marketAverage'];
                debugPrint(
                  'LISTING_MARKER: id=${doc.id} product=$product marketAverage=$marketAverage price=${raw['price']}',
                );
                if (product.contains('rice')) {
                  debugPrint(
                    'RICE_MARKER: id=${doc.id} marketAverage=$marketAverage price=${raw['price']}',
                  );
                }
              }
            }

            if (activeSnapshot.hasError || winnerSnapshot.hasError) {
              final Object? streamError =
                  activeSnapshot.error ?? winnerSnapshot.error;
              final bool isPermissionDenied =
                  streamError is FirebaseException &&
                  streamError.code == 'permission-denied';

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 140),
                  Center(
                    child: Text(
                      isPermissionDenied
                          ? 'آپ کو اس ڈیٹا تک رسائی نہیں ملی۔ اپنی پرمیشن یا اکاؤنٹ رول دوبارہ چیک کریں۔'
                          : 'ڈیٹا لوڈ کرنے میں مسئلہ پیش آیا!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                ],
              );
            }
            if (activeSnapshot.connectionState == ConnectionState.waiting &&
                winnerSnapshot.connectionState == ConnectionState.waiting) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  Center(child: CircularProgressIndicator(color: goldColor)),
                ],
              );
            }

            final activeDocs = activeSnapshot.data?.docs ?? [];
            final winnerDocs = winnerSnapshot.data?.docs ?? [];

            final Map<String, QueryDocumentSnapshot<Map<String, dynamic>>>
            merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};

            for (final doc in activeDocs) {
              merged[doc.id] = doc;
            }

            for (final doc in winnerDocs) {
              final status =
                  (doc.data()['listingStatus'] ?? doc.data()['status'] ?? '')
                      .toString()
                      .toLowerCase();
              if (status == DealStatus.awaitingPayment.value ||
                  status == DealStatus.awaitingPayment.name.toLowerCase()) {
                merged[doc.id] = doc;
              }
            }

            final docs = merged.values.toList(growable: false);
            final filteredDocs = docs.where((doc) {
              final raw = doc.data();
              final bool isApproved = raw['isApproved'] == true;
              final String listingStatus =
                  (raw['listingStatus'] ?? raw['status'] ?? '')
                      .toString()
                      .toLowerCase();
              final bool isAwaitingPayment =
                  listingStatus == DealStatus.awaitingPayment.value ||
                  listingStatus ==
                      DealStatus.awaitingPayment.name.toLowerCase();
              final String product = (raw['product'] ?? '')
                  .toString()
                  .toLowerCase();
              final MandiType listingType = _resolveListingType(raw);
              return (isApproved || isAwaitingPayment) &&
                  product.contains(searchQuery) &&
                  (selectedCategory == null || listingType == selectedCategory);
            }).toList();

            if (filteredDocs.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 140),
                  Center(
                    child: Text(
                      'Maal dastyab nahi hai.',
                      style: TextStyle(color: Colors.white38),
                    ),
                  ),
                ],
              );
            }

            return RefreshIndicator(
              color: goldColor,
              onRefresh: onRefreshAiRates,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                cacheExtent: 650,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                itemCount: filteredDocs.length,
                itemBuilder: (context, index) {
                  final doc = filteredDocs[index];
                  final raw = doc.data();

                  return MarketListingCard(
                    key: ValueKey(doc.id),
                    data: raw,
                    listingId: doc.id,
                    goldColor: goldColor,
                    currentlyPlayingUrl: currentlyPlayingUrl,
                    buyerDistrict: buyerDistrict,
                    selectedMandiType: selectedCategory,
                    onPlayAudio: onPlayAudio,
                    onBid: onBid,
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  MandiType _resolveListingType(Map<String, dynamic> data) {
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
    } catch (e) {
      debugPrint('MANDI_TYPE_PARSE_ERROR|error=$e');
    }
    return MandiType.crops;
  }
}

