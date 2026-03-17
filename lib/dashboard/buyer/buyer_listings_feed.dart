import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../routes.dart';
import '../../theme/app_colors.dart';
import 'buyer_models.dart';
import 'buyer_listing_detail_screen.dart';

class BuyerListingsFeed extends StatefulWidget {
  const BuyerListingsFeed({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<BuyerListingsFeed> createState() => _BuyerListingsFeedState();
}

class _BuyerListingsFeedState extends State<BuyerListingsFeed> {
  DateTime _now = DateTime.now().toUtc();
  String _searchText = '';

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  void _startTicker() {
    Future<void>.delayed(const Duration(minutes: 1), () {
      if (!mounted) return;
      setState(() {
        _now = DateTime.now().toUtc();
      });
      _startTicker();
    });
  }

  String get _buyerName {
    final value = (widget.userData['name'] ?? '').toString().trim();
    return value.isEmpty ? 'Buyer' : value;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _liveListingsStream() {
    return FirebaseFirestore.instance
        .collection('listings')
        .where('status', isEqualTo: 'live')
        .where('expiresAt', isGreaterThan: Timestamp.fromDate(_now))
        .orderBy('expiresAt')
        .limit(100)
        .snapshots();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BuyerUiTheme.greenDark,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 12,
        title: const Text(
          'Buyer Dashboard / خریدار ڈیش بورڈ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Logout / لاگ آؤٹ',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: BuyerUiTheme.gold),
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          RefreshIndicator(
            color: BuyerUiTheme.gold,
            onRefresh: () async {
              setState(() {
                _now = DateTime.now().toUtc();
              });
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              children: [
                _HeaderCard(name: _buyerName),
                const SizedBox(height: 12),
                TextField(
                  onChanged: (value) =>
                      setState(() => _searchText = value.trim().toLowerCase()),
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search listing / تلاش',
                    hintStyle: const TextStyle(color: Colors.white70),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: Colors.white70,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: BuyerUiTheme.gold.withValues(alpha: 0.35),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: BuyerUiTheme.gold.withValues(alpha: 0.35),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: BuyerUiTheme.gold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _liveListingsStream(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: BuyerUiTheme.gold,
                          ),
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return _InfoCard(
                        title: 'Unable to load listings',
                        urdu: 'فہرست لوڈ نہیں ہو سکی',
                        icon: Icons.error_outline_rounded,
                      );
                    }

                    final docs =
                        snapshot.data?.docs ??
                        const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                    final listings = docs
                        .map(BuyerListing.fromDoc)
                        .where((listing) {
                          if (_searchText.isEmpty) return true;
                          final hay =
                              '${listing.itemName} ${listing.district} ${listing.province}'
                                  .toLowerCase();
                          return hay.contains(_searchText);
                        })
                        .toList(growable: false);

                    if (listings.isEmpty) {
                      return _InfoCard(
                        title: 'No live listings right now',
                        urdu: 'فی الحال کوئی لائیو لسٹنگ موجود نہیں',
                        icon: Icons.inventory_2_outlined,
                      );
                    }

                    return Column(
                      children: listings
                          .map(
                            (listing) => _ListingTile(
                              listing: listing,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => BuyerListingDetailScreen(
                                      listingId: listing.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                          .toList(growable: false),
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
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BuyerUiTheme.gold.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0x22D4AF37),
            child: Icon(Icons.person_outline_rounded, color: BuyerUiTheme.gold),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assalam-o-Alaikum / السلام علیکم',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: BuyerUiTheme.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Live Market / لائیو مارکیٹ',
              style: TextStyle(
                color: BuyerUiTheme.gold,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListingTile extends StatelessWidget {
  const _ListingTile({required this.listing, required this.onTap});

  final BuyerListing listing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: BuyerUiTheme.gold.withValues(alpha: 0.32)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      listing.itemName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TrustBadge(
                    level: listing.riskLevel,
                    score: listing.riskScore,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _MetaChip(
                    icon: Icons.scale_rounded,
                    label:
                        '${listing.quantity.toStringAsFixed(0)} ${listing.unit}',
                  ),
                  _MetaChip(
                    icon: Icons.location_on_outlined,
                    label: listing.locationLabel,
                  ),
                  _MetaChip(
                    icon: Icons.timer_outlined,
                    label: 'Expires: ${_timeLeft(listing.expiresAt)}',
                  ),
                ],
              ),
              if (listing.riskLevel != RiskLevel.low) ...[
                const SizedBox(height: 8),
                _WarningStrip(level: listing.riskLevel),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _timeLeft(DateTime expiresAt) {
    final diff = expiresAt.toUtc().difference(DateTime.now().toUtc());
    if (diff.isNegative) return 'Expired';
    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);
    return '${hours}h ${minutes}m';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _WarningStrip extends StatelessWidget {
  const _WarningStrip({required this.level});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) {
    final text = level == RiskLevel.high
        ? 'High risk listing, proceed carefully / یہ لسٹنگ زیادہ خطرے والی ہے'
        : 'Medium risk listing, verify details before bidding / بولی سے پہلے تفصیل چیک کریں';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF5A1E1E).withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.urdu,
    required this.icon,
  });

  final String title;
  final String urdu;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        children: [
          Icon(icon, color: BuyerUiTheme.gold, size: 30),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(urdu, style: BuyerUiTheme.urduLabelStyle(size: 15)),
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
