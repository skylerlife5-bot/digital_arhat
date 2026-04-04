import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/location_display_helper.dart';
import 'package:flutter/services.dart';

import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../services/buyer_engagement_service.dart';
import '../../theme/app_colors.dart';
import 'bid_bottom_sheet.dart';
import 'buyer_listing_detail_screen.dart';

String formatPkr(dynamic value) {
  final num n = (value is num)
      ? value
      : num.tryParse(value?.toString() ?? '') ?? 0;
  return 'Rs. ${n.toStringAsFixed(0)}';
}

class BuyerDashboardScreen extends StatefulWidget {
  const BuyerDashboardScreen({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<BuyerDashboardScreen> createState() => _BuyerDashboardScreenState();
}

class _BuyerDashboardScreenState extends State<BuyerDashboardScreen> {
  static const Color _darkGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  String _searchQuery = '';
  String _selectedProvince = 'All Pakistan';

  Timer? _ticker;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now().toUtc();
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _buyerName {
    final fullName = (widget.userData['fullName'] ?? '').toString().trim();
    if (fullName.isNotEmpty) return fullName;
    final name = (widget.userData['name'] ?? '').toString().trim();
    return name.isEmpty ? 'Buyer Marketplace' : name;
  }

  static const List<String> _marketProvinces = <String>[
    'All Pakistan',
    'Punjab',
    'Sindh',
    'KPK',
    'Balochistan',
    'Gilgit-Baltistan',
    'AJK',
  ];

  Stream<QuerySnapshot<Map<String, dynamic>>> _approvedListingsStream() {
    return FirebaseFirestore.instance
        .collection('listings')
        .where('isApproved', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(120)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _myBidsStream(String buyerId) {
    return FirebaseFirestore.instance
        .collectionGroup('bids')
        .where('buyerId', isEqualTo: buyerId)
        .orderBy('createdAt', descending: true)
        .limit(60)
        .snapshots();
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  bool _isExpired(Map<String, dynamic> listing) {
    final createdAt = _readDate(listing['createdAt']);
    if (createdAt == null) return false;
    return _now.isAfter(createdAt.add(const Duration(hours: 24)));
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await AuthService().clearPersistedSessionUid();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
  }

  Future<void> _openListingDetailSafely(
    String listingId,
    Map<String, dynamic>? listingData,
  ) async {
    // Guard against incomplete snapshots so UI fails gracefully instead of crashing.
    final id = listingId.trim();
    final data = listingData;
    if (id.isEmpty || data == null || data.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing details are not ready right now'),
        ),
      );
      return;
    }

    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              BuyerListingDetailScreen(listingId: id, initialData: data),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open listing right now')),
      );
    }
  }

  Future<void> _openBidSheetSafely(
    String listingId,
    Map<String, dynamic>? listingData,
  ) async {
    final id = listingId.trim();
    final data = listingData;
    if (id.isEmpty || data == null || data.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Listing details are not ready right now'),
        ),
      );
      return;
    }

    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => BidBottomSheet(listingId: id, listingData: data),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open bidding right now')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Mandi Market / منڈی مارکیٹ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            tooltip: 'Logout / لاگ آؤٹ',
            icon: const Icon(Icons.logout_rounded, color: _gold),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          RefreshIndicator(
            color: _gold,
            onRefresh: () async {
              setState(() {
                _now = DateTime.now().toUtc();
              });
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 18),
              children: [
                _TopBanner(name: _buyerName),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withValues(alpha: 0.26)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Search, compare, and bid on active mandi offers',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Use search and province filters to discover the right listing quickly',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.62),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 7),
                      _searchAndFilterRow(),
                      const SizedBox(height: 6),
                      const Text(
                        'Browse by province / صوبہ کے حساب سے دیکھیں',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _provinceFilter(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionTitle(
                  icon: Icons.storefront_rounded,
                  title: 'Active Mandi Listings / منڈی کی فعال آفرز',
                  subtitle:
                      'Browse live offers and compare bids with confidence',
                ),
                const SizedBox(height: 8),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _approvedListingsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(color: _gold),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return const _InfoCard(
                        icon: Icons.wifi_off_rounded,
                        title:
                            'Fresh market offers could not be refreshed right now',
                        subtitle:
                            'تازہ مارکیٹ آفرز اس وقت ریفریش نہیں ہو سکیں، براہِ کرم تھوڑی دیر بعد دوبارہ دیکھیں',
                      );
                    }

                    final source =
                        snapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final visible =
                        <QueryDocumentSnapshot<Map<String, dynamic>>>[];

                    for (final doc in source) {
                      final data = doc.data();
                      final expired = _isExpired(data);
                      if (expired) {
                        continue;
                      }

                      final status = (data['status'] ?? '')
                          .toString()
                          .toLowerCase()
                          .trim();
                      if (status != 'approved' &&
                          status != 'active' &&
                          status != 'live') {
                        continue;
                      }

                      final province = (data['province'] ?? '')
                          .toString()
                          .trim();
                      final haystack = LocationDisplayHelper.searchTextFromData(
                        data,
                      );

                      final searchMatch =
                          _searchQuery.isEmpty ||
                          haystack.contains(_searchQuery);
                      final provinceMatch =
                          _selectedProvince == 'All Pakistan' ||
                          province == _selectedProvince;

                      if (searchMatch && provinceMatch) {
                        visible.add(doc);
                      }
                    }

                    if (visible.isEmpty) {
                      final hasActiveFilters =
                          _searchQuery.isNotEmpty ||
                          _selectedProvince != 'All Pakistan';
                      return _InfoCard(
                        icon: Icons.inventory_2_outlined,
                        title: hasActiveFilters
                            ? 'No listings match your search and filters'
                            : 'No mandi listings yet',
                        subtitle: hasActiveFilters
                            ? 'تلاش اور فلٹر کے مطابق کوئی لسٹنگ نہیں ملی، فلٹر وسیع کریں یا صوبہ تبدیل کر کے دیکھیں'
                            : 'جیسے ہی فروخت کنندہ منظور شدہ آفرز شائع کریں گے، وہ یہاں نظر آئیں گی',
                      );
                    }

                    visible.sort((a, b) {
                      int featuredRank(Map<String, dynamic> d) {
                        final status = (d['promotionStatus'] ?? '')
                            .toString()
                            .toLowerCase();
                        if (status == 'active') {
                          final expires = d['promotionExpiresAt'];
                          if (expires is Timestamp &&
                              expires.toDate().isBefore(DateTime.now())) {
                            return 0;
                          }
                          return 1;
                        }
                        if (status.isNotEmpty && status != 'none') return 0;
                        final priority = (d['priorityScore'] ?? '')
                            .toString()
                            .toLowerCase();
                        return (d['featured'] == true || priority == 'high')
                            ? 1
                            : 0;
                      }

                      final featuredCompare = featuredRank(
                        b.data(),
                      ).compareTo(featuredRank(a.data()));
                      if (featuredCompare != 0) return featuredCompare;

                      DateTime readTime(Map<String, dynamic> d) {
                        DateTime? toDate(dynamic raw) {
                          if (raw is Timestamp) return raw.toDate().toUtc();
                          if (raw is DateTime) return raw.toUtc();
                          return null;
                        }

                        return toDate(d['bumpedAt']) ??
                            toDate(d['updatedAt']) ??
                            toDate(d['createdAt']) ??
                            DateTime.fromMillisecondsSinceEpoch(0).toUtc();
                      }

                      return readTime(b.data()).compareTo(readTime(a.data()));
                    });

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: visible
                          .map(
                            (doc) => _ListingCard(
                              listingId: doc.id,
                              data: doc.data(),
                              onBid: () =>
                                  _openBidSheetSafely(doc.id, doc.data()),
                              onTap: () =>
                                  _openListingDetailSafely(doc.id, doc.data()),
                            ),
                          )
                          .toList(growable: false),
                    );
                  },
                ),
                const SizedBox(height: 14),
                const _SectionTitle(
                  icon: Icons.receipt_long_rounded,
                  title: 'My Bid Activity / میری بولی سرگرمی',
                  subtitle:
                      'Track bids, accepted offers, and contact unlock progress',
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_open_rounded,
                        color: Color(0xFFE8C766),
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Accepted offers unlock seller contact automatically / قبول شدہ آفر پر رابطہ خودکار طور پر ظاہر ہوتا ہے',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
                    if (uid.isEmpty) {
                      return const _InfoCard(
                        icon: Icons.lock_outline_rounded,
                        title: 'Sign in to track bids and accepted offers',
                        subtitle:
                            'منڈی براؤز جاری رکھیں، بولیوں اور فروخت کنندہ کے جوابات دیکھنے کے لیے لاگ اِن کریں',
                      );
                    }

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _myBidsStream(uid),
                      builder: (context, bidSnapshot) {
                        if (bidSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: CircularProgressIndicator(color: _gold),
                            ),
                          );
                        }
                        if (bidSnapshot.hasError) {
                          return const _InfoCard(
                            icon: Icons.history_toggle_off_rounded,
                            title:
                                'Bid activity could not be refreshed right now',
                            subtitle:
                                'آپ کی بولی سرگرمی اس وقت ریفریش نہیں ہو سکی، براہِ کرم تھوڑی دیر بعد دوبارہ دیکھیں',
                          );
                        }

                        final docs =
                            bidSnapshot.data?.docs ??
                            const <
                              QueryDocumentSnapshot<Map<String, dynamic>>
                            >[];
                        if (docs.isEmpty) {
                          return const _InfoCard(
                            icon: Icons.gavel_rounded,
                            title: 'Your bids will appear here',
                            subtitle:
                                'مارکیٹ آفرز دیکھیں اور بولی لگائیں، آپ کی سرگرمی یہاں نظر آئے گی',
                          );
                        }

                        return Column(
                          children: docs
                              .map(
                                (doc) => _MyBidCard(
                                  key: ValueKey<String>(doc.id),
                                  bidId: doc.id,
                                  bidData: doc.data(),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchAndFilterRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: _searchField()),
        const SizedBox(width: 8),
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: _showProvinceQuickFilter,
            child: Ink(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF0A2C1C).withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold.withValues(alpha: 0.36)),
              ),
              child: const Icon(
                Icons.tune_rounded,
                color: Color(0xFFE8C766),
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showProvinceQuickFilter() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0A2C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Quick Province Filter / فوری صوبہ فلٹر',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _marketProvinces
                      .map(
                        (province) => ChoiceChip(
                          label: Text(
                            province == 'All Pakistan'
                                ? 'All Pakistan / پورا پاکستان'
                                : LocationDisplayHelper.bilingualLabel(province),
                          ),
                          selected: _selectedProvince == province,
                          backgroundColor: const Color(0xFF12402A),
                          selectedColor: _gold.withValues(alpha: 0.30),
                          side: BorderSide(
                            color: _selectedProvince == province
                                ? _gold.withValues(alpha: 0.9)
                                : Colors.white24,
                          ),
                          labelStyle: TextStyle(
                            color: _selectedProvince == province
                                ? const Color(0xFF1B1B1B)
                                : Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                          onSelected: (_) {
                            setState(() => _selectedProvince = province);
                            Navigator.of(context).pop();
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _searchField() {
    return TextField(
      style: const TextStyle(color: Colors.white),
      onChanged: (value) =>
          setState(() => _searchQuery = value.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Search mandi listings, city, or product / تلاش',
        hintStyle: const TextStyle(color: Colors.white54, fontSize: 12.8),
        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFFE8C766)),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () => setState(() => _searchQuery = ''),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white60,
                  size: 18,
                ),
                tooltip: 'Clear search',
              ),
        filled: true,
        fillColor: const Color(0xFF0A2C1C).withValues(alpha: 0.8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.28)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _gold.withValues(alpha: 0.28)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _gold),
        ),
      ),
    );
  }

  Widget _provinceFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: _marketProvinces
            .map(
              (province) => Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  label: Text(
                    province == 'All Pakistan'
                        ? 'All Pakistan / پورا پاکستان'
                        : LocationDisplayHelper.bilingualLabel(province),
                  ),
                  selected: _selectedProvince == province,
                  backgroundColor: const Color(
                    0xFF12402A,
                  ).withValues(alpha: 0.72),
                  selectedColor: _gold.withValues(alpha: 0.30),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 9),
                  side: BorderSide(
                    color: _selectedProvince == province
                        ? _gold.withValues(alpha: 0.9)
                        : Colors.white24,
                  ),
                  labelStyle: TextStyle(
                    color: _selectedProvince == province
                        ? const Color(0xFF1B1B1B)
                        : Colors.white70,
                    fontWeight: FontWeight.w700,
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedProvince = province),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _TopBanner extends StatelessWidget {
  const _TopBanner({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _BuyerDashboardScreenState._gold.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0x22D4AF37),
            child: Icon(
              Icons.person_rounded,
              color: _BuyerDashboardScreenState._gold,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Buyer Marketplace / خریدار مارکیٹ',
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Browse active offers, compare bids, and discover nearby trade',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: _BuyerDashboardScreenState._gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Live Offers',
              style: TextStyle(
                color: _BuyerDashboardScreenState._gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listingId,
    required this.data,
    required this.onTap,
    required this.onBid,
  });

  final String listingId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final VoidCallback onBid;
  static final BuyerEngagementService _engagementService =
      BuyerEngagementService();

  bool _isPromotionActive(Map<String, dynamic> map) {
    final status = (map['promotionStatus'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      final expires = map['promotionExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) {
        return false;
      }
      return true;
    }
    if (status.isNotEmpty && status != 'none') return false;
    return _isTruthy(map['featured']) ||
        _isTruthy(map['featuredAuction']) ||
        (map['priorityScore'] ?? '').toString().toLowerCase() == 'high';
  }

  @override
  Widget build(BuildContext context) {
    final item = (data['itemName'] ?? data['cropName'] ?? 'Item').toString();
    final qty = _readDouble(data['quantity']);
    final unit = (data['unit'] ?? 'kg').toString();
    final imageUrl = _firstImageUrl(data);
    final location = _locationLine(data);
    final saleType = (data['saleType'] ?? 'auction')
        .toString()
        .trim()
        .toLowerCase();
    final bool isAuction = saleType != 'fixed';
    final String sellerId = (data['sellerId'] ?? '').toString().trim();
    final rate = _readDouble(
      data['rate'] ?? data['price'] ?? data['unitPrice'],
    );
    final highestBid = _readDouble(data['highestBid']);
    final int bidsCount = _readInt(
      data['totalBids'] ?? data['bidsCount'] ?? data['bidCount'],
    );
    final int watchersCount = _readInt(data['watchersCount']);
    final priceValue = isAuction ? (highestBid > 0 ? highestBid : rate) : rate;
    final riskScore = _readInt(data['aiRiskScore'] ?? data['riskScore']);
    final urduHint = _firstUrduReason(data['aiReasonsUrdu']);
    final sellerBadge = (data['sellerBadge'] ?? '').toString().trim();
    final bool aiVerified = _isTruthy(data['isAiVerifiedSeller']);
    final bool trustedSource = _isTruthy(data['isVerifiedSource']);
    final bool adminReviewed =
        _isTruthy(data['adminVerified']) || _isTruthy(data['isAdminVerified']);
    final bool isFeatured = _isPromotionActive(data);
    final bool isHotAuction = isAuction && isFeatured;
    final DateTime? endTime = _toDate(data['endTime']);
    final bool endingSoon =
        endTime != null &&
        endTime.isAfter(DateTime.now().toUtc()) &&
        endTime.difference(DateTime.now().toUtc()).inMinutes <= 20;

    return Card(
      color: Colors.white.withValues(alpha: 0.07),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isFeatured
              ? _BuyerDashboardScreenState._gold.withValues(alpha: 0.65)
              : _BuyerDashboardScreenState._gold.withValues(alpha: 0.28),
          width: isFeatured ? 1.4 : 1.0,
        ),
      ),
      elevation: isFeatured ? 4 : 2,
      shadowColor: isFeatured
          ? _BuyerDashboardScreenState._gold.withValues(alpha: 0.30)
          : Colors.black.withValues(alpha: 0.20),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 124,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: imageUrl.isEmpty
                          ? Container(
                              decoration: const BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF1B4A34),
                                    Color(0xFF0E2F21),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    Icon(
                                      Icons.inventory_2_rounded,
                                      color: Colors.white70,
                                      size: 26,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Mandi Listing',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : Image.network(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFF1B4A34),
                                          Color(0xFF0E2F21),
                                        ],
                                      ),
                                    ),
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_not_supported_rounded,
                                      color: Colors.white70,
                                      size: 24,
                                    ),
                                  ),
                            ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (isAuction
                                      ? const Color(0xFFFF7043)
                                      : const Color(0xFF2E7D32))
                                  .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          isAuction ? 'Auction' : 'Fixed',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: _statusChip(isAuction, riskScore),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isAuction ? 'Current Bid' : 'Price',
                    style: const TextStyle(color: Colors.white60, fontSize: 11),
                  ),
                  Text(
                    formatPkr(priceValue),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isAuction
                          ? const Color(0xFFEFD88A)
                          : Colors.lightGreenAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (isAuction) ...[
                    const SizedBox(height: 4),
                    _auctionEngagementRow(
                      bidsCount: bidsCount,
                      watchersCount: watchersCount,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${qty.toStringAsFixed(0)} ${unit.trim().isEmpty ? 'unit' : unit}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (isAuction) ...[
                    _buildWatchButton(context, sellerId: sellerId),
                    const SizedBox(height: 8),
                  ],
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (isFeatured)
                        _chip(
                          Icons.star_rounded,
                          isHotAuction ? '⭐ Featured Auction' : '⭐ Featured',
                          accent: _BuyerDashboardScreenState._gold,
                        ),
                      if (isHotAuction)
                        _chip(
                          Icons.local_fire_department_rounded,
                          '🔥 HOT AUCTION',
                        ),
                      if (endingSoon)
                        _chip(
                          Icons.timer_outlined,
                          'ENDING SOON',
                          accent: AppColors.urgencyRed,
                        ),
                      if (sellerBadge.isNotEmpty)
                        _chip(Icons.verified_outlined, sellerBadge),
                      if (trustedSource)
                        _chip(Icons.verified_user_rounded, 'Trusted Source'),
                      if (aiVerified)
                        _chip(Icons.auto_awesome_rounded, 'AI Verified'),
                      if (adminReviewed)
                        _chip(Icons.shield_moon_rounded, 'Admin Reviewed'),
                      if (!trustedSource &&
                          !aiVerified &&
                          !adminReviewed &&
                          sellerBadge.isEmpty)
                        _chip(Icons.verified_rounded, 'Approved for Trade'),
                    ],
                  ),
                  if (urduHint.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _detailRow(Icons.lightbulb_outline_rounded, urduHint),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onTap,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                              color: _BuyerDashboardScreenState._gold
                                  .withValues(alpha: 0.65),
                            ),
                            foregroundColor: const Color(0xFFEFD88A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('View'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _BuyerDashboardScreenState._gold,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: onBid,
                          icon: Icon(
                            isAuction
                                ? Icons.gavel_rounded
                                : Icons.local_offer_outlined,
                            size: 17,
                          ),
                          label: Text(isAuction ? 'Place Bid' : 'Open Offer'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label, {Color? accent}) {
    final chipAccent = accent ?? Colors.white70;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: chipAccent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: chipAccent.withValues(alpha: 0.62)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipAccent),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: chipAccent, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _auctionEngagementRow({
    required int bidsCount,
    required int watchersCount,
  }) {
    final parts = <String>[];
    if (bidsCount > 0) {
      parts.add('🔥 $bidsCount bids');
    }
    if (watchersCount > 0) {
      parts.add('👁️ $watchersCount watching');
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Text(
      parts.join('   '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFFEFD88A),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildWatchButton(BuildContext context, {required String sellerId}) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && sellerId.isNotEmpty && sellerId == user.uid) {
      return const SizedBox.shrink();
    }

    if (user == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                duration: Duration(seconds: 3),
                content: Text('Login required to watch auctions'),
              ),
            );
            Navigator.of(context).pushNamed(Routes.login);
          },
          icon: const Icon(Icons.star_border_rounded, size: 18),
          label: const Text('Watch'),
        ),
      );
    }

    return StreamBuilder<bool>(
      stream: _engagementService.isListingSavedStream(listingId),
      builder: (context, snapshot) {
        if (listingId.trim().isEmpty) return const SizedBox.shrink();

        final isSaved = snapshot.data ?? false;
        return Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final saved = await _engagementService.toggleWatchlist(
                listingId: listingId,
                listingData: data,
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 2),
                  content: Text(
                    saved ? 'Watching this auction' : 'Removed from watchlist',
                  ),
                ),
              );
            },
            icon: Icon(
              isSaved ? Icons.star_rounded : Icons.star_border_rounded,
              size: 18,
              color: isSaved
                  ? const Color(0xFFEFD88A)
                  : const Color(0xFFD4AF37),
            ),
            label: Text(isSaved ? 'Watching' : 'Watch'),
          ),
        );
      },
    );
  }

  Widget _statusChip(bool isAuction, int riskScore) {
    final bool caution = riskScore >= 70;
    final String label = caution
        ? 'Review'
        : (isAuction ? 'Live Bid' : 'Ready Offer');
    final Color color = caution
        ? const Color(0xFFFFA726)
        : (isAuction ? const Color(0xFFFF7043) : const Color(0xFF66BB6A));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.white70),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  double _readDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _firstUrduReason(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first.toString().trim();
      return first;
    }
    return '';
  }

  String _locationLine(Map<String, dynamic> map) {
    return LocationDisplayHelper.locationDisplayFromData(map);
  }

  String _firstImageUrl(Map<String, dynamic> map) {
    final direct = [
      (map['thumbnailUrl'] ?? '').toString().trim(),
      (map['imageUrl'] ?? '').toString().trim(),
      (map['photoUrl'] ?? '').toString().trim(),
      (map['videoThumbnailUrl'] ?? '').toString().trim(),
    ].firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (direct.isNotEmpty) return direct;
    final imageUrls = map['imageUrls'];
    if (imageUrls is List && imageUrls.isNotEmpty) {
      return imageUrls.first.toString().trim();
    }
    return '';
  }

  DateTime? _toDate(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    return null;
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    final raw = (value ?? '').toString().trim().toLowerCase();
    return raw == 'true' || raw == '1' || raw == 'yes';
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _BuyerDashboardScreenState._gold),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MyBidCard extends StatelessWidget {
  const _MyBidCard({super.key, required this.bidId, required this.bidData});

  final String bidId;
  final Map<String, dynamic> bidData;

  @override
  Widget build(BuildContext context) {
    final listingId = (bidData['listingId'] ?? '').toString();
    final buyerId = (bidData['buyerId'] ?? '').toString();
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final base = Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _BuyerDashboardScreenState._gold.withValues(alpha: 0.26),
        ),
      ),
      child: const SizedBox.shrink(),
    );

    if (listingId.isEmpty) return base;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('listings')
          .doc(listingId)
          .snapshots(),
      builder: (context, listingSnapshot) {
        final listing =
            listingSnapshot.data?.data() ?? const <String, dynamic>{};
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: buyerId.isEmpty
              ? null
              : FirebaseFirestore.instance
                    .collection('deals')
                    .where('listingId', isEqualTo: listingId)
                    .where('buyerId', isEqualTo: buyerId)
                    .orderBy('createdAt', descending: true)
                    .limit(1)
                    .snapshots(),
          builder: (context, dealSnapshot) {
            final dealDoc = (dealSnapshot.data?.docs.isNotEmpty ?? false)
                ? dealSnapshot.data!.docs.first
                : null;
            final dealData = dealDoc?.data() ?? const <String, dynamic>{};

            final bidStatus = (bidData['status'] ?? 'pending')
                .toString()
                .toLowerCase();
            final bool thisBidAccepted = isBidAccepted(
              bidId: bidId,
              currentUserUid: currentUserUid,
              bidData: bidData,
              dealData: dealData,
              listingData: listing,
            );
            final bool contactUnlocked = isContactUnlocked(
              bidId: bidId,
              currentUserUid: currentUserUid,
              bidData: bidData,
              dealData: dealData,
              listingData: listing,
            );

            final (statusLabel, statusColor) = _statusFor(
              bidStatus: bidStatus,
              contactUnlocked: contactUnlocked,
              thisBidAccepted: thisBidAccepted,
            );

            final item =
                (bidData['productName'] ??
                        listing['itemName'] ??
                        listing['cropName'] ??
                        'Listing')
                    .toString();
            final amount = _toDouble(bidData['bidAmount']);
            final created = _dateLabel(bidData['createdAt']);
            final acceptedAmount = _toDouble(
              dealData['dealAmount'] ??
                  dealData['finalPrice'] ??
                  listing['finalPrice'] ??
                  bidData['bidAmount'],
            );
            final acceptedAtLabel = _dateLabel(
              dealData['acceptedAt'] ??
                  listing['acceptedAt'] ??
                  bidData['acceptedAt'],
              fallback: 'Accepted recently',
            );

            final sellerName =
                (dealData['sellerName'] ??
                        listing['sellerName'] ??
                        listing['ownerName'] ??
                        'Seller')
                    .toString();
            final String sellerUid =
                (dealData['sellerId'] ?? listing['sellerId'] ?? '')
                    .toString()
                    .trim();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: sellerUid.isEmpty
                  ? null
                  : FirebaseFirestore.instance
                        .collection('users')
                        .doc(sellerUid)
                        .snapshots(),
              builder: (context, sellerSnapshot) {
                final sellerProfile =
                    sellerSnapshot.data?.data() ?? const <String, dynamic>{};

                String firstPhone(
                  Map<String, dynamic> map,
                  List<String> keys,
                ) {
                  for (final key in keys) {
                    final value = (map[key] ?? '').toString().trim();
                    if (value.isNotEmpty) return value;
                  }
                  return '';
                }

                final sellerPhoneFromDealOrListing =
                    firstPhone(dealData, const <String>[
                      'sellerPhone',
                      'phone',
                      'contactPhone',
                      'sellerContact',
                    ]).isNotEmpty
                    ? firstPhone(dealData, const <String>[
                        'sellerPhone',
                        'phone',
                        'contactPhone',
                        'sellerContact',
                      ])
                    : firstPhone(listing, const <String>[
                        'sellerPhone',
                        'phone',
                        'phoneNumber',
                        'contactPhone',
                        'contact',
                        'mobile',
                        'sellerContact',
                      ]);

                final sellerPhoneFromProfile =
                    firstPhone(sellerProfile, const <String>[
                      'phone',
                      'phoneNumber',
                      'contact',
                      'mobile',
                      'contactPhone',
                      'sellerPhone',
                    ]);

                final mappedSellerPhone =
                    sellerPhoneFromDealOrListing.isNotEmpty
                    ? sellerPhoneFromDealOrListing
                    : sellerPhoneFromProfile;
                debugPrint(
                  '[AcceptBidContact] uiMappedSellerPhone=$mappedSellerPhone',
                );

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: _BuyerDashboardScreenState._gold.withValues(
                        alpha: 0.26,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: statusColor.withValues(alpha: 0.8),
                              ),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _miniChip(Icons.payments_outlined, formatPkr(amount)),
                          _miniChip(Icons.schedule_rounded, created),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _longMetaRow(
                        context: context,
                        label: 'Listing ID',
                        value: listingId,
                        allowCopy: true,
                      ),
                      if (thisBidAccepted && contactUnlocked) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF2ECC71,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(
                                0xFF2ECC71,
                              ).withValues(alpha: 0.7),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Bid Accepted / بولی قبول ہوگئی',
                                style: TextStyle(
                                  color: Color(0xFF9EF4C0),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'آپ کی بولی قبول ہوگئی',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Contact unlocked / رابطہ اَن لاک',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'براہِ راست بات کر کے ادائیگی اور ڈلیوری طے کریں',
                                style: TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Accepted Amount: ${formatPkr(acceptedAmount)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'Accepted Time: $acceptedAtLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Listing: $item',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                'Seller: $sellerName',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                              Text(
                                mappedSellerPhone.isEmpty
                                    ? 'Seller contact will appear here once available.'
                                    : 'Phone: $mappedSellerPhone',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Digital Arhat Phase-1 mein سودا براہِ راست مکمل ہوتا ہے\n'
                            'Please verify listing and seller details before finalizing the deal.\n'
                            'سودا مکمل کرنے سے پہلے چیز اور فروخت کنندہ کی تفصیل ضرور چیک کریں',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                      if (!thisBidAccepted) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Text(
                            'Seller contact appears after your bid is accepted / بولی قبول ہونے کے بعد رابطہ ظاہر ہوگا',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  (String, Color) _statusFor({
    required String bidStatus,
    required bool contactUnlocked,
    required bool thisBidAccepted,
  }) {
    if (bidStatus == 'rejected') {
      return ('Rejected / مسترد', const Color(0xFFE74C3C));
    }
    if (thisBidAccepted && contactUnlocked) {
      return ('Bid Accepted / بولی قبول ہوگئی', const Color(0xFF2ECC71));
    }
    if (thisBidAccepted) {
      return ('Accepted / قبول شدہ', const Color(0xFFFFB74D));
    }
    return ('Pending / زیر غور', const Color(0xFF90A4AE));
  }

  bool _isTrue(dynamic value) {
    if (value is bool) return value;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == 'true' || text == '1' || text == 'yes';
  }

  /// Phase-1 accepted detection supports multiple schema variants safely.
  bool isBidAccepted({
    required String bidId,
    required String currentUserUid,
    required Map<String, dynamic> bidData,
    required Map<String, dynamic> dealData,
    required Map<String, dynamic> listingData,
  }) {
    final acceptedBidId =
        (dealData['acceptedBidId'] ?? listingData['acceptedBidId'] ?? '')
            .toString()
            .trim();
    if (acceptedBidId.isNotEmpty && acceptedBidId != bidId) {
      return false;
    }

    final acceptedBuyerUid =
        (dealData['acceptedBuyerUid'] ?? listingData['acceptedBuyerUid'] ?? '')
            .toString()
            .trim();
    if (acceptedBuyerUid.isNotEmpty &&
        currentUserUid.isNotEmpty &&
        acceptedBuyerUid != currentUserUid) {
      return false;
    }

    final bidStatus = (bidData['status'] ?? '').toString().trim().toLowerCase();
    final dealStatus =
        (dealData['status'] ??
                dealData['dealStatus'] ??
                listingData['status'] ??
                listingData['listingStatus'] ??
                '')
            .toString()
            .trim()
            .toLowerCase();
    final bool bidExplicitlyAccepted =
        bidStatus == 'accepted' || bidStatus == 'bid_accepted';
    final bool acceptedMarkersMatchBid =
        acceptedBidId.isNotEmpty && acceptedBidId == bidId;
    final bool acceptedMarkersMatchBuyer =
        acceptedBuyerUid.isNotEmpty && acceptedBuyerUid == currentUserUid;
    final bool acceptedAtForThisBid =
        bidData['acceptedAt'] != null &&
        (acceptedBidId.isEmpty || acceptedBidId == bidId);
    final bool dealSignalsAcceptance =
        dealStatus == 'bid_accepted' &&
        (acceptedMarkersMatchBid ||
            acceptedMarkersMatchBuyer ||
            bidExplicitlyAccepted);

    return bidExplicitlyAccepted ||
        acceptedMarkersMatchBid ||
        acceptedMarkersMatchBuyer ||
        acceptedAtForThisBid ||
        dealSignalsAcceptance;
  }

  /// Contact is unlocked once a bid is accepted in Phase-1.
  bool isContactUnlocked({
    required String bidId,
    required String currentUserUid,
    required Map<String, dynamic> bidData,
    required Map<String, dynamic> dealData,
    required Map<String, dynamic> listingData,
  }) {
    final acceptedBidId =
        (dealData['acceptedBidId'] ?? listingData['acceptedBidId'] ?? '')
            .toString()
            .trim();
    final acceptedBuyerUid =
        (dealData['acceptedBuyerUid'] ?? listingData['acceptedBuyerUid'] ?? '')
            .toString()
            .trim();
    final bool markerMatchesBid =
        acceptedBidId.isNotEmpty && acceptedBidId == bidId;
    final bool markerMatchesBuyer =
        acceptedBuyerUid.isNotEmpty && acceptedBuyerUid == currentUserUid;
    final bool explicitUnlockForAccepted =
        (_isTrue(dealData['contactUnlocked']) ||
            _isTrue(listingData['contactUnlocked'])) &&
        (markerMatchesBid || markerMatchesBuyer);

    return explicitUnlockForAccepted ||
        isBidAccepted(
          bidId: bidId,
          currentUserUid: currentUserUid,
          bidData: bidData,
          dealData: dealData,
          listingData: listingData,
        );
  }

  Widget _miniChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _longMetaRow({
    required BuildContext context,
    required String label,
    required String value,
    bool allowCopy = false,
  }) {
    final clean = value.trim();
    return Row(
      children: [
        Icon(Icons.badge_outlined, size: 14, color: Colors.white70),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $clean',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
        if (allowCopy)
          IconButton(
            tooltip: 'Copy $label',
            iconSize: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: Colors.white70,
            onPressed: clean.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: clean));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Listing ID copied')),
                    );
                  },
            icon: const Icon(Icons.copy_rounded),
          ),
      ],
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _dateLabel(dynamic value, {String fallback = 'Recent'}) {
    if (value is Timestamp) {
      final dt = value.toDate();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (value is DateTime) {
      return '${value.day}/${value.month}/${value.year} ${value.hour}:${value.minute.toString().padLeft(2, '0')}';
    }
    return fallback;
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.24)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 30, color: _BuyerDashboardScreenState._gold),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontFamily: 'JameelNoori',
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitalBackground extends StatelessWidget {
  const _DigitalBackground();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(color: AppColors.background),
    );
  }
}
