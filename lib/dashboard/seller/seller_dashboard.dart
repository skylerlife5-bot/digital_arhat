import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../routes.dart';
import '../../theme/app_colors.dart';
import 'seller_bids.dart';
import 'seller_listings.dart';

class SellerDashboard extends StatefulWidget {
  const SellerDashboard({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  static const Color _greenDark = AppColors.background;
  static const Color _gold = AppColors.accentGold;

  DateTime _lastSyncedAt = DateTime.now();
  bool _ayatExpanded = false;
  bool _secureTradingExpanded = true;

  String get _sellerUid {
    final authUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final localUid = (widget.userData['uid'] ?? '').toString().trim();
    return authUid.isNotEmpty ? authUid : localUid;
  }

  String get _sellerName {
    final raw = (widget.userData['name'] ?? '').toString().trim();
    return raw.isEmpty ? 'Seller' : raw;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sellerListingsStream() {
    if (_sellerUid.isEmpty) {
      return FirebaseFirestore.instance
          .collection('listings')
          .where('sellerId', isEqualTo: '__none__')
          .snapshots();
    }

    return FirebaseFirestore.instance
        .collection('listings')
        .where('sellerId', isEqualTo: _sellerUid)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _sellerDealsStream() {
    if (_sellerUid.isEmpty) {
      return FirebaseFirestore.instance
          .collection('deals')
          .where('sellerId', isEqualTo: '__none__')
          .snapshots();
    }

    return FirebaseFirestore.instance
        .collection('deals')
        .where('sellerId', isEqualTo: _sellerUid)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _sellerProfileStream() {
    if (_sellerUid.isEmpty) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc('__none__')
          .snapshots();
    }

    return FirebaseFirestore.instance
        .collection('users')
        .doc(_sellerUid)
        .snapshots();
  }

  Future<void> _refreshDashboard() async {
    if (_sellerUid.isNotEmpty) {
      await Future.wait([
        FirebaseFirestore.instance
            .collection('listings')
            .where('sellerId', isEqualTo: _sellerUid)
            .limit(25)
            .get(),
        FirebaseFirestore.instance
            .collection('deals')
            .where('sellerId', isEqualTo: _sellerUid)
            .limit(25)
            .get(),
        FirebaseFirestore.instance.collection('users').doc(_sellerUid).get(),
      ]);
    }

    if (!mounted) return;
    setState(() {
      _lastSyncedAt = DateTime.now();
    });
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenDark,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 12,
        title: const Text(
          'Seller Dashboard / ڈیش بورڈ',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Logout / لاگ آؤٹ',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: _gold),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _gold,
        onRefresh: _refreshDashboard,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
          children: [
            _buildGreetingCard(),
            const SizedBox(height: 10),
            _buildAyatCard(),
            const SizedBox(height: 12),
            _buildStatsRow(),
            const SizedBox(height: 8),
            _buildLastSyncedLabel(),
            const SizedBox(height: 14),
            const _SectionTitle(
              titleEn: 'Primary Actions',
              titleUr: 'بنیادی کام',
            ),
            const SizedBox(height: 10),
            _buildPrimaryActionGrid(),
            const SizedBox(height: 14),
            const _SectionTitle(
              titleEn: 'Action Center',
              titleUr: 'اہم الرٹس',
            ),
            const SizedBox(height: 8),
            _buildActionCenter(),
            const SizedBox(height: 14),
            _buildSecureTradingCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildGreetingCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _sellerProfileStream(),
      builder: (context, snapshot) {
        final profile = snapshot.data?.data() ?? const <String, dynamic>{};
        final phoneVerified =
            _readBool(profile['phoneVerified']) ||
            _readBool(profile['isPhoneVerified']);
        final videoVerified =
            _readBool(profile['videoVerified']) ||
            _readBool(profile['isFaceVerified']);
        final trusted = phoneVerified && videoVerified;

        final reasons = <String>[
          if (!videoVerified) 'Video Verification Required / ویڈیو تصدیق لازمی',
          if (!phoneVerified) 'Phone Not Verified / فون تصدیق نہیں',
        ];

        return _DashboardCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.softOverlayGold,
                    child: Icon(Icons.person_rounded, color: _gold),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Assalam-o-Alaikum / السلام علیکم',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppColors.secondaryText, fontSize: 13),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TrustBadge(isVerified: trusted),
                ],
              ),
              if (reasons.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: reasons
                      .map(
                        (message) => _SignalChip(
                          text: message,
                          color: const Color(0xFFFFB74D),
                          icon: Icons.warning_amber_rounded,
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildAyatCard() {
    return _DashboardCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _ayatExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _ayatExpanded = value;
            });
          },
          tilePadding: EdgeInsets.zero,
          collapsedIconColor: _gold,
          iconColor: _gold,
          title: const Text(
            'Motivation / رہنمائی',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
          children: const [
            Align(
              alignment: Alignment.centerRight,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'وَأَوْفُوا الْكَيْلَ وَالْمِيزَانَ بِالْقِسْطِ',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            SizedBox(height: 5),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'ناپ اور تول انصاف کے ساتھ پورا کرو',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 15,
                  fontFamily: 'JameelNoori',
                ),
              ),
            ),
            SizedBox(height: 3),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Text(
                'سورۃ الانعام 6:152',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13,
                  fontFamily: 'JameelNoori',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sellerListingsStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _StatCard(
                  titleEn: 'Active Listings',
                  titleUr: 'فعال لسٹنگز',
                  value: '—',
                  icon: Icons.storefront_rounded,
                  subtitle: 'خرابی / Error',
                );
              }
              if (!snapshot.hasData) {
                return const _StatSkeleton();
              }

              final count = snapshot.data!.docs.where((doc) {
                final status = (doc.data()['status'] ?? '')
                    .toString()
                    .toLowerCase();
                return status.isEmpty || status == 'active' || status == 'live';
              }).length;

              return _StatCard(
                titleEn: 'Active Listings',
                titleUr: 'فعال لسٹنگز',
                value: '$count',
                icon: Icons.storefront_rounded,
                subtitle: 'Realtime / براہِ راست',
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _sellerDealsStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const _StatCard(
                  titleEn: 'Pending Deals',
                  titleUr: 'زیر التواء سودے',
                  value: '—',
                  icon: Icons.pending_actions_rounded,
                  subtitle: 'خرابی / Error',
                );
              }
              if (!snapshot.hasData) {
                return const _StatSkeleton();
              }

              final pending = snapshot.data!.docs.where((doc) {
                final data = doc.data();
                final status = (data['status'] ?? '').toString().toLowerCase();
                final payment = (data['paymentStatus'] ?? '')
                    .toString()
                    .toLowerCase();
                return status.contains('pending') ||
                    payment.contains('pending');
              }).length;

              return _StatCard(
                titleEn: 'Pending Deals',
                titleUr: 'زیر التواء سودے',
                value: '$pending',
                icon: Icons.pending_actions_rounded,
                subtitle: 'Realtime / براہِ راست',
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLastSyncedLabel() {
    final label =
        '${_two(_lastSyncedAt.hour)}:${_two(_lastSyncedAt.minute)} ${_lastSyncedAt.hour >= 12 ? 'PM' : 'AM'}';
    return Text(
      'Last synced / آخری اپڈیٹ: $label',
      style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
    );
  }

  Widget _buildPrimaryActionGrid() {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.14,
      children: [
        _ActionTile(
          icon: Icons.add_business_rounded,
          titleEn: 'Add Listing',
          titleUr: 'مال بیچیں',
          semanticsLabel: 'Add Listing',
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pushNamed(
              Routes.postListingOption,
              arguments: <String, dynamic>{'userData': widget.userData},
            );
          },
        ),
        _ActionTile(
          icon: Icons.view_list_rounded,
          titleEn: 'My Listings',
          titleUr: 'میری لسٹنگز',
          semanticsLabel: 'My Listings',
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SellerListingsScreen()),
            );
          },
        ),
        _ActionTile(
          icon: Icons.gavel_rounded,
          titleEn: 'Bids',
          titleUr: 'بولیاں',
          semanticsLabel: 'Bids',
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const SellerBidsScreen(
                  listingId: 'ALL',
                  productName: 'Tamam Faslein',
                  basePrice: 0,
                ),
              ),
            );
          },
        ),
        _ActionTile(
          icon: Icons.handshake_outlined,
          titleEn: 'Deals',
          titleUr: 'سودے',
          semanticsLabel: 'Deals',
          onTap: () {
            HapticFeedback.lightImpact();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Deals screen coming soon')),
            );
          },
        ),
      ],
    );
  }

  Widget _buildActionCenter() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _sellerProfileStream(),
      builder: (context, userSnapshot) {
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _sellerListingsStream(),
          builder: (context, listingsSnapshot) {
            return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _sellerDealsStream(),
              builder: (context, dealsSnapshot) {
                if (userSnapshot.hasError ||
                    listingsSnapshot.hasError ||
                    dealsSnapshot.hasError) {
                  return _DashboardCard(
                    child: Row(
                      children: [
                        const Icon(
                          Icons.wifi_off_rounded,
                          color: AppColors.accentGoldAccent,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'آف لائن مسئلہ، دوبارہ کوشش کریں',
                            style: TextStyle(color: AppColors.primaryText),
                          ),
                        ),
                        TextButton(
                          onPressed: _refreshDashboard,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }

                if (!userSnapshot.hasData ||
                    !listingsSnapshot.hasData ||
                    !dealsSnapshot.hasData) {
                  return const _DashboardCard(child: _ActionCenterSkeleton());
                }

                final profile =
                    userSnapshot.data?.data() ?? const <String, dynamic>{};
                final listings =
                    listingsSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                final deals =
                    dealsSnapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                final alerts = <_ActionAlert>[];

                final videoVerified =
                    _readBool(profile['videoVerified']) ||
                    _readBool(profile['isFaceVerified']);
                if (!videoVerified) {
                  alerts.add(
                    const _ActionAlert(
                      title: 'Verification Video لازمی',
                      subtitle: 'ہر نئی لسٹنگ کیلئے GPS ویڈیو ضروری ہے',
                      color: Color(0xFFFFB74D),
                      icon: Icons.videocam_off_rounded,
                    ),
                  );
                }

                final hasLowPriceWarning = listings.any((doc) {
                  final data = doc.data();
                  final price =
                      _toDouble(data['price']) ?? _toDouble(data['rate']) ?? 0;
                  final market =
                      _toDouble(data['marketRate']) ??
                      _toDouble(data['market_average']) ??
                      _toDouble(data['marketAverage']) ??
                      0;
                  if (price <= 0 || market <= 0) return false;
                  return price < market * 0.65 || price > market * 1.65;
                });

                if (hasLowPriceWarning) {
                  alerts.add(
                    const _ActionAlert(
                      title: 'Low price warning / کم قیمت الرٹ',
                      subtitle: 'کچھ ریٹس مارکیٹ سے کافی مختلف ہیں',
                      color: Color(0xFFFFA726),
                      icon: Icons.trending_down_rounded,
                    ),
                  );
                }

                final suspiciousFlag =
                    _readBool(profile['suspiciousActivity']) ||
                    listings.any((doc) {
                      final data = doc.data();
                      final suspicious = _readBool(data['isSuspicious']);
                      final risk = _toDouble(data['riskScore']) ?? 0;
                      return suspicious || risk >= 70;
                    });

                if (suspiciousFlag) {
                  alerts.add(
                    const _ActionAlert(
                      title: 'Suspicious activity flag / مشکوک',
                      subtitle: 'AI نے ممکنہ فراڈ سرگرمی نشان زد کی',
                      color: Color(0xFFE53935),
                      icon: Icons.report_problem_rounded,
                    ),
                  );
                }

                final submittedDeals = deals
                    .where((doc) {
                      final data = doc.data();
                      final paymentStatus = (data['paymentStatus'] ?? '')
                          .toString()
                          .toLowerCase()
                          .trim();
                      return paymentStatus == 'payment_submitted';
                    })
                    .toList(growable: false);

                if (submittedDeals.isNotEmpty) {
                  alerts.add(
                    _ActionAlert(
                      title:
                          'Deal update received / سودا اپڈیٹ (${submittedDeals.length})',
                      subtitle:
                          'Buyer ne response diya hai, براہِ راست رابطہ کریں',
                      color: const Color(0xFF26A69A),
                      icon: Icons.local_shipping_rounded,
                    ),
                  );
                }

                if (alerts.isEmpty && submittedDeals.isEmpty) {
                  return _buildSystemStatusCard();
                }

                return _DashboardCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:
                        alerts
                            .take(3)
                            .map(
                              (alert) => Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: _ActionAlertTile(alert: alert),
                              ),
                            )
                            .toList(growable: false)
                          ..addAll(
                            submittedDeals.take(2).map((dealDoc) {
                              final deal = dealDoc.data();
                              final product =
                                  (deal['productName'] ??
                                          deal['itemName'] ??
                                          'Deal')
                                      .toString();
                              final listingId = (deal['listingId'] ?? '')
                                  .toString();
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryText.withValues(alpha: 0.06),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: AppColors.primaryText24),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: AppColors.primaryText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Text(
                                            'Deal: ',
                                            style: TextStyle(
                                              color: AppColors.secondaryText,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Expanded(
                                            child: Text(
                                              dealDoc.id,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: AppColors.secondaryText,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (listingId.isNotEmpty)
                                        Row(
                                          children: [
                                            const Text(
                                              'Listing: ',
                                              style: TextStyle(
                                                color: AppColors.secondaryText,
                                                fontSize: 12,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                listingId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: AppColors.secondaryText,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _gold,
                                            foregroundColor: AppColors.ctaTextDark,
                                          ),
                                          onPressed: () => _startDelivery(
                                            dealId: dealDoc.id,
                                            listingId: listingId,
                                          ),
                                          icon: const Icon(
                                            Icons.local_shipping_rounded,
                                          ),
                                          label: const Text(
                                            'Start Delivery / ڈیلیوری شروع کریں',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                          ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _startDelivery({
    required String dealId,
    required String listingId,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('deals').doc(dealId).set({
        'currentStep': 'DELIVERY_PENDING',
        'status': 'delivery_pending',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery step started / ڈیلیوری مرحلہ شروع ہوگیا'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start delivery right now')),
      );
    }
  }

  Widget _buildSystemStatusCard() {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'System Status / سسٹم اسٹیٹس',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          _StatusOkLine(
            text: 'All listings verified / تمام اشتہارات تصدیق شدہ ہیں',
          ),
          _StatusOkLine(text: 'No fraud alerts / کوئی فراڈ الرٹ نہیں ہے'),
          _StatusOkLine(
            text:
                'Accepted bids unlock contact / قبول شدہ بولی پر رابطہ اَن لاک ہوتا ہے',
          ),
        ],
      ),
    );
  }

  Widget _buildSecureTradingCard() {
    return _DashboardCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _secureTradingExpanded,
          onExpansionChanged: (value) {
            setState(() {
              _secureTradingExpanded = value;
            });
          },
          tilePadding: EdgeInsets.zero,
          collapsedIconColor: _gold,
          iconColor: _gold,
          leading: const Icon(Icons.shield_rounded, color: _gold),
          title: const Text(
            'Secure Trading / محفوظ تجارت',
            style: TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
          children: const [
            _SecurePoint(
              en: 'After bid acceptance, buyer and seller connect directly',
              ur: 'بولی قبول ہونے کے بعد خریدار اور فروخت کنندہ براہِ راست رابطہ کرتے ہیں',
            ),
            _SecurePoint(
              en: 'Complete deal offline after verifying listing and contact details',
              ur: 'لسٹنگ اور رابطہ کی تصدیق کے بعد براہِ راست سودا مکمل کریں',
            ),
            _SecurePoint(
              en: 'Every listing requires a verification video with GPS',
              ur: 'ہر اشتہار کے لیے GPS کے ساتھ تصدیقی ویڈیو لازمی ہے',
            ),
            _SecurePoint(
              en: 'AI system monitors fraud and suspicious activity',
              ur: 'مصنوعی ذہانت (AI) دھوکہ دہی اور مشکوک سرگرمیوں پر نظر رکھتی ہے',
            ),
          ],
        ),
      ),
    );
  }

  static bool _readBool(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  static double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.secondarySurface,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.titleEn, required this.titleUr});

  final String titleEn;
  final String titleUr;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            titleEn,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Directionality(
          textDirection: TextDirection.rtl,
          child: Text(
            titleUr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 15,
              fontFamily: 'JameelNoori',
            ),
          ),
        ),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.isVerified});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isVerified ? const Color(0xFF2E7D32) : const Color(0xFFFFB74D),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Text(
        isVerified ? 'Verified ✅' : 'Unverified ⚠️',
        style: const TextStyle(
          color: AppColors.primaryText,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({
    required this.text,
    required this.color,
    required this.icon,
  });

  final String text;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.titleEn,
    required this.titleUr,
    required this.value,
    required this.icon,
    required this.subtitle,
  });

  final String titleEn;
  final String titleUr;
  final String value;
  final IconData icon;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _SellerDashboardState._gold, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  titleEn,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            titleUr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
              fontFamily: 'JameelNoori',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _SellerDashboardState._gold,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.primaryText60, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatSkeleton extends StatelessWidget {
  const _StatSkeleton();

  @override
  Widget build(BuildContext context) {
    return const _DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonLine(width: 110, height: 14),
          SizedBox(height: 8),
          _SkeletonLine(width: 80, height: 24),
          SizedBox(height: 6),
          _SkeletonLine(width: 90, height: 11),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.titleEn,
    required this.titleUr,
    required this.semanticsLabel,
    required this.onTap,
  });

  final IconData icon;
  final String titleEn;
  final String titleUr;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: AppColors.primaryText.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _SellerDashboardState._gold.withValues(alpha: 0.4),
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 120),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 21,
                      backgroundColor: _SellerDashboardState._gold.withValues(
                        alpha: 0.20,
                      ),
                      child: Icon(icon, color: _SellerDashboardState._gold),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      titleEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Directionality(
                      textDirection: TextDirection.rtl,
                      child: Text(
                        titleUr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 13,
                          fontFamily: 'JameelNoori',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionAlert {
  const _ActionAlert({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
}

class _ActionAlertTile extends StatelessWidget {
  const _ActionAlertTile({required this.alert});

  final _ActionAlert alert;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: alert.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: alert.color.withValues(alpha: 0.52)),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(alert.icon, color: alert.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: TextStyle(
                    color: alert.color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alert.subtitle,
                  style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionCenterSkeleton extends StatelessWidget {
  const _ActionCenterSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _SkeletonLine(height: 40),
        SizedBox(height: 8),
        _SkeletonLine(height: 40),
      ],
    );
  }
}

class _StatusOkLine extends StatelessWidget {
  const _StatusOkLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF66BB6A),
              size: 17,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: AppColors.primaryText, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurePoint extends StatelessWidget {
  const _SecurePoint({required this.en, required this.ur});

  final String en;
  final String ur;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primaryText.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _SellerDashboardState._gold.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              en,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Directionality(
              textDirection: TextDirection.rtl,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Text(
                  ur,
                  style: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 14,
                    height: 1.3,
                    fontFamily: 'JameelNoori',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({this.width, required this.height});

  final double? width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}

