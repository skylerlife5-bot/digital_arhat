import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/security_filter.dart';
import '../../core/widgets/customer_support_button.dart';
import '../../models/deal_status.dart';
import '../../routes.dart';
import '../../auth/auth_wrapper.dart';
import '../../services/admin_service.dart';
import '../../services/marketplace_service.dart';
import 'admin_payment_verification_screen.dart';
import 'admin_deal_details_screen.dart';
import 'payout_management_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MarketplaceService _marketplaceService = MarketplaceService();
  final AdminService _adminService = AdminService();
  Stream<QuerySnapshot<Map<String, dynamic>>>? _pendingListingsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _allBidsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _adminAlertsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _awaitingDealApprovalStream;
  QuerySnapshot<Map<String, dynamic>>? _awaitingDealApprovalInitialData;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingDeals =
      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
  final Set<String> _pendingDealActionListingIds = <String>{};
  late Future<_AdminStatsSnapshot> _statsFuture;
  late Future<_DealSummarySnapshot> _dealSummaryFuture;
  int _selectedTab = 0;

  static const Color navy = Color(0xFF0B1F3A);
  static const Color royalBlue = Color(0xFF002366);
  static const Color panel = Color(0xFF122B4A);
  static const Color gold = Color(0xFFFFD700);

  bool get _isInteractingWithPendingCard =>
      _pendingDealActionListingIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _setupCachedStreams();
    _statsFuture = _fetchAdminStats();
    _dealSummaryFuture = _fetchDealSummary();
  }

  void _setupCachedStreams() {
    _pendingListingsStream = _db
        .collection('listings')
        .orderBy('createdAt', descending: true)
        .snapshots();
    final awaitingApprovalQuery = _db
        .collection('listings')
        .where('listingStatus', isEqualTo: DealStatus.pendingAdminApproval.name)
        .orderBy('updatedAt', descending: true);
    _awaitingDealApprovalStream = awaitingApprovalQuery.snapshots();
    awaitingApprovalQuery.get().then((snapshot) {
      if (!mounted) return;
      setState(() {
        _awaitingDealApprovalInitialData = snapshot;
        if (!_isInteractingWithPendingCard) {
          _pendingDeals =
              List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
                snapshot.docs,
              );
        }
      });
    });
    _allBidsStream = FirebaseFirestore.instance
        .collectionGroup('bids')
        .orderBy('timestamp', descending: true)
        .snapshots();
    _adminAlertsStream = _db
        .collection('admin_alerts')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<_AdminStatsSnapshot> _fetchAdminStats() async {
    final usersSnap = await _db.collection('users').get();
    final listingsSnap = await _db.collection('listings').get();
    final dealsSnap = await _db.collection('deals').get();

    final users = usersSnap.docs;
    final listings = listingsSnap.docs;
    final deals = dealsSnap.docs;

    int pendingApprovals = 0;
    int liveListings = 0;
    double totalCommissionBase = 0;

    for (final doc in listings) {
      final data = doc.data();
      final status = _str(data, 'status').toLowerCase();

      if (status == 'pending' || !_bool(data, 'isApproved')) {
        pendingApprovals++;
      }
      if (status == 'live' || status == DealStatus.active.value) {
        liveListings++;
      }
    }

    for (final doc in deals) {
      final data = doc.data();
      final status = _str(data, 'status').toLowerCase();
      if (status == DealStatus.dealCompleted.value ||
          status == 'deal_completed' ||
          status == 'closed') {
        final amount = _num(data, 'dealAmount') > 0
            ? _num(data, 'dealAmount')
            : _num(data, 'finalPrice');
        totalCommissionBase += amount;
      }
    }

    return _AdminStatsSnapshot(
      totalUsers: users.length,
      pendingApprovals: pendingApprovals,
      liveListings: liveListings,
      totalListings: listings.length,
      netCommission: totalCommissionBase * 0.02,
    );
  }

  void _refreshAdminStats() {
    if (!mounted) return;
    setState(() {
      _statsFuture = _fetchAdminStats();
      _dealSummaryFuture = _fetchDealSummary();
    });
  }

  Future<_DealSummarySnapshot> _fetchDealSummary() async {
    final listingsSnap = await _db.collection('listings').get();
    final usersSnap = await _db
        .collection('users')
        .where('role', isEqualTo: 'seller')
        .get();

    int activeAds = 0;
    int pendingApprovals = 0;
    int pendingPayouts = 0;

    for (final doc in listingsSnap.docs) {
      final data = doc.data();
      final listingStatus = _str(
        data,
        'listingStatus',
        fallback: _str(data, 'status'),
      ).toLowerCase();
      if (listingStatus == DealStatus.active.value) {
        activeAds++;
      }
      if (listingStatus == DealStatus.pendingAdminApproval.name) {
        pendingApprovals++;
      }
    }

    try {
      final pendingWithdrawals = await _db
          .collection('withdraw_requests')
          .where('status', isEqualTo: 'pending')
          .get();
      pendingPayouts = pendingWithdrawals.docs.length;
    } catch (_) {
      for (final userDoc in usersSnap.docs) {
        final data = userDoc.data();
        final availableBalance = _num(data, 'availableBalance');
        if (availableBalance > 0) {
          pendingPayouts++;
        }
      }
    }

    return _DealSummarySnapshot(
      activeAds: activeAds,
      pendingApprovals: pendingApprovals,
      pendingPayouts: pendingPayouts,
    );
  }

  Future<void> _refreshCommandCenter() async {
    _setupCachedStreams();
    _refreshAdminStats();
    await _statsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser?.uid)
          .snapshots(),
      builder: (context, roleSnap) {
        final userData = roleSnap.data?.data() ?? <String, dynamic>{};
        final role =
            (userData['userRole'] ??
                    userData['role'] ??
                    userData['userType'] ??
                    '')
                .toString()
                .trim()
                .toLowerCase();

        if (roleSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (role != 'admin') {
          return const AuthWrapper();
        }

        return SafeArea(
          child: Scaffold(
            backgroundColor: navy,
            appBar: AppBar(
              centerTitle: true,
              title: Image.asset(
                'assets/logo.png',
                height: 34,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
              backgroundColor: navy,
              foregroundColor: Colors.white,
              actions: [
                _buildPendingApprovalsBell(),
                const CustomerSupportIconAction(),
                IconButton(
                  tooltip: 'Moderation',
                  onPressed: () {
                    Navigator.pushNamed(context, Routes.adminModeration);
                  },
                  icon: const Icon(Icons.security),
                ),
                IconButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (!context.mounted) return;
                    Navigator.of(context).pushNamedAndRemoveUntil(
                      Routes.signIn,
                      (route) => false,
                    );
                  },
                  icon: const Icon(Icons.logout),
                ),
              ],
            ),
            floatingActionButton: const CustomerSupportFab(mini: false),
            bottomNavigationBar: BottomNavigationBar(
              currentIndex: _selectedTab,
              onTap: (index) => setState(() => _selectedTab = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: royalBlue,
              selectedItemColor: Colors.amber[800],
              unselectedItemColor: Colors.white,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.analytics),
                  label: 'Analytics',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_alt),
                  label: 'Users',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.verified_user),
                  label: 'Payments',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.hourglass_top_rounded),
                  label: 'Deals / س��د�',
                ),
              ],
            ),
            body: _selectedTab == 2
                ? const AdminPaymentVerificationScreen(embedded: true)
                : _selectedTab == 3
                ? _buildAwaitingDealApprovalTab()
                : RefreshIndicator(
                    onRefresh: _refreshCommandCenter,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: _buildSelectedTab(),
                    ),
                  ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedTab() {
    if (_selectedTab == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNetArhatCommissionTopCard(),
          const SizedBox(height: 12),
          _buildVerifyPaymentsCard(),
          const SizedBox(height: 12),
          _buildPendingSettlementsCard(),
          const SizedBox(height: 12),
          _buildDealSummaryCard(),
          const SizedBox(height: 12),
          _buildLiveMetricsGrid(),
          const SizedBox(height: 16),
          _buildNeedsActionList(),
          const SizedBox(height: 16),
          _buildDealCommandQueue(),
          const SizedBox(height: 16),
          _buildRecentBidsSection(),
          const SizedBox(height: 16),
          _buildLast7DaysChart(),
        ],
      );
    }

    if (_selectedTab == 1) {
      return _buildUsersTab();
    }

    if (_selectedTab == 2) {
      return const SizedBox.shrink();
    }

    if (_selectedTab == 3) {
      return const SizedBox.shrink();
    }

    return const SizedBox.shrink();
  }

  Widget _buildAwaitingDealApprovalTab() {
    final stream = _awaitingDealApprovalStream;
    if (stream == null) {
      return const SizedBox.shrink();
    }

    return Container(
      color: navy,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        initialData: _awaitingDealApprovalInitialData,
        builder: (context, snapshot) {
          final incomingDocs = snapshot.data?.docs;
          if (incomingDocs != null) {
            _syncPendingDealsFromSnapshot(incomingDocs);
          }

          if (snapshot.connectionState == ConnectionState.waiting &&
              _pendingDeals.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          if (_pendingDeals.isEmpty) {
            return const Center(
              child: Text(
                'No deals awaiting admin approval',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            itemCount: _pendingDeals.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = _pendingDeals[index];
              final listingId = doc.id;
              final data = doc.data();
              final product = _str(data, 'product').isEmpty
                  ? _str(data, 'itemName')
                  : _str(data, 'product');
              final winnerId = _str(data, 'winnerId');
              final sellerId = _str(data, 'sellerId');
              final amount = _num(data, 'finalPrice') > 0
                  ? _num(data, 'finalPrice')
                  : _num(data, 'highestBid');
              bool approving = false;
              bool rejecting = false;

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Winner: ${winnerId.isEmpty ? '--' : winnerId}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Seller: ${sellerId.isEmpty ? '--' : sellerId}',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Text(
                      'Bid Amount: Rs. ${amount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    StatefulBuilder(
                      builder: (context, setCardState) {
                        Future<void> handleApprove() async {
                          if (approving || rejecting) return;
                          setCardState(() => approving = true);
                          await _performPendingDealAction(
                            listingId: listingId,
                            action: () => _approveDealForPayment(
                              listingId: listingId,
                              listingData: data,
                            ),
                          );
                          if (mounted) {
                            setCardState(() => approving = false);
                          }
                        }

                        Future<void> handleReject() async {
                          if (approving || rejecting) return;
                          setCardState(() => rejecting = true);
                          await _performPendingDealAction(
                            listingId: listingId,
                            action: () => _rejectDealToActive(
                              listingId: listingId,
                              listingData: data,
                            ),
                          );
                          if (mounted) {
                            setCardState(() => rejecting = false);
                          }
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: (approving || rejecting)
                                    ? null
                                    : handleApprove,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                                icon: approving
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.verified_rounded),
                                label: Text(
                                  approving ? 'Approving...' : 'Approve Deal',
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: (approving || rejecting)
                                    ? null
                                    : handleReject,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: const BorderSide(
                                    color: Colors.redAccent,
                                  ),
                                ),
                                icon: rejecting
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.redAccent,
                                        ),
                                      )
                                    : const Icon(Icons.cancel_rounded),
                                label: Text(
                                  rejecting ? 'Rejecting...' : 'Reject Deal',
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _syncPendingDealsFromSnapshot(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> incoming,
  ) {
    if (_isInteractingWithPendingCard) return;

    final incomingIds = incoming.map((doc) => doc.id).toList(growable: false);
    final currentIds = _pendingDeals
        .map((doc) => doc.id)
        .toList(growable: false);

    if (listEquals(incomingIds, currentIds)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isInteractingWithPendingCard) return;
      setState(() {
        _pendingDeals = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          incoming,
        );
      });
    });
  }

  Future<void> _performPendingDealAction({
    required String listingId,
    required Future<void> Function() action,
  }) async {
    if (_pendingDealActionListingIds.contains(listingId)) return;

    setState(() => _pendingDealActionListingIds.add(listingId));

    try {
      await action();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _pendingDeals.removeWhere((doc) => doc.id == listingId);
      });
    } finally {
      if (mounted) {
        setState(() => _pendingDealActionListingIds.remove(listingId));
      }
    }
  }

  Future<void> _approveDealForPayment({
    required String listingId,
    required Map<String, dynamic> listingData,
  }) async {
    HapticFeedback.mediumImpact();
    final buyerId = _str(
      listingData,
      'winnerId',
      fallback: _str(listingData, 'buyerId'),
    );
    final dealId = _str(listingData, 'dealId');

    final batch = _db.batch();
    final listingRef = _db.collection('listings').doc(listingId);
    batch.set(listingRef, {
      'listingStatus': DealStatus.awaitingPayment.value,
      'status': DealStatus.awaitingPayment.value,
      'auctionStatus': DealStatus.awaitingPayment.value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (dealId.isNotEmpty) {
      batch.set(_db.collection('deals').doc(dealId), {
        'status': DealStatus.awaitingPayment.value,
        'paymentStatus': DealStatus.awaitingPayment.value,
        'currentStep': 'AWAITING_PAYMENT',
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }

    if (buyerId.isNotEmpty) {
      final title = SecurityFilter.maskAll(
        'Deal Approved! Please proceed to payment.',
      );
      final body = SecurityFilter.maskAll(
        'Deal Approved! Please proceed to payment.',
      );
      batch.set(_db.collection('notifications').doc(), {
        'userId': buyerId,
        'title': title,
        'body': body,
        'type': 'DEAL_APPROVED_AWAITING_PAYMENT',
        'listingId': listingId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    await batch.commit();
  }

  Future<void> _rejectDealToActive({
    required String listingId,
    required Map<String, dynamic> listingData,
  }) async {
    HapticFeedback.mediumImpact();
    final sellerId = _str(listingData, 'sellerId');

    final batch = _db.batch();
    final listingRef = _db.collection('listings').doc(listingId);
    batch.set(listingRef, {
      'listingStatus': DealStatus.active.value,
      'status': DealStatus.active.value,
      'auctionStatus': DealStatus.active.value,
      'winnerId': null,
      'buyerId': null,
      'dealId': null,
      'finalBidId': null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (sellerId.isNotEmpty) {
      final title = SecurityFilter.maskAll(
        'Deal rejected by Admin. Your ad is now active again.',
      );
      final body = SecurityFilter.maskAll(
        'Deal rejected by Admin. Your ad is now active again.',
      );
      batch.set(_db.collection('notifications').doc(), {
        'userId': sellerId,
        'title': title,
        'body': body,
        'type': 'DEAL_REJECTED_REACTIVATED',
        'listingId': listingId,
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });
    }

    await batch.commit();
  }

  Widget _buildNetArhatCommissionTopCard() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('Admin_Earnings').doc('total_revenue').snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final netCommission = _num(data, 'totalCommissionEarned');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: gold, width: 2),
          ),
          child: Row(
            children: [
              const Icon(Icons.currency_exchange, color: gold, size: 32),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Earnings ⬢ Net Arhat Commission',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Rs. ${netCommission.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDealSummaryCard() {
    return FutureBuilder<_DealSummarySnapshot>(
      future: _dealSummaryFuture,
      builder: (context, snapshot) {
        final data = snapshot.data ?? const _DealSummarySnapshot();
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: panel,
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _summaryMetric(
                  label: 'Active Ads',
                  value: data.activeAds,
                  color: Colors.lightGreenAccent,
                ),
              ),
              Expanded(
                child: _summaryMetric(
                  label: 'Pending Approvals',
                  value: data.pendingApprovals,
                  color: gold,
                ),
              ),
              Expanded(
                child: _summaryMetric(
                  label: 'Pending Payouts',
                  value: data.pendingPayouts,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVerifyPaymentsCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .where('status', isEqualTo: 'awaiting_admin_approval')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.pushNamed(context, Routes.adminPayments),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Stack(
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified_user, color: gold, size: 30),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verify Payments',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          count > 0
                              ? '$count receipts awaiting review'
                              : 'No pending receipts',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.white70,
                      size: 30,
                    ),
                  ],
                ),
                if (count > 0)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '$count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingSettlementsCard() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .where('status', isEqualTo: 'delivered_pending_release')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PayoutManagementScreen(),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: panel,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments_rounded, color: gold, size: 30),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pending Settlements',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        count > 0
                            ? '$count deals ready for payout release'
                            : 'No payout ready deals',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                if (count > 0)
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: Colors.white70, size: 28),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _summaryMetric({
    required String label,
    required int value,
    required Color color,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLiveMetricsGrid() {
    return FutureBuilder<_AdminStatsSnapshot>(
      future: _statsFuture,
      builder: (context, snap) {
        final stats = snap.data;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.25,
          children: [
            _metricCard(
              'Total Users',
              (stats?.totalUsers ?? 0).toString(),
              Icons.groups_2,
            ),
            _metricCard(
              'Pending Approvals',
              (stats?.pendingApprovals ?? 0).toString(),
              Icons.pending_actions,
              valueColor: gold,
            ),
            _metricCard(
              'Live Listings',
              (stats?.liveListings ?? 0).toString(),
              Icons.storefront,
            ),
            _metricCard(
              'Total Listings',
              (stats?.totalListings ?? 0).toString(),
              Icons.inventory_2,
            ),
          ],
        );
      },
    );
  }

  Widget _metricCard(
    String title,
    String value,
    IconData icon, {
    Color valueColor = Colors.white,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [panel, navy]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: gold),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsActionList() {
    final stream = _pendingListingsStream;
    if (stream == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final alertStream = _adminAlertsStream;
        if (alertStream == null) {
          return const SizedBox.shrink();
        }

        final docs = (snap.data?.docs ?? []).take(3).toList();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: alertStream,
          builder: (context, alertSnap) {
            final alerts = alertSnap.data?.docs ?? const [];
            final flaggedListingIds = alerts
                .map((a) => a.data()['listingId']?.toString() ?? '')
                .where((id) => id.isNotEmpty)
                .toSet();

            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: panel,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Foran Tawajjo Chahiyen',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (docs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Maal Saf Hai!',
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  else
                    ...docs.map((doc) {
                      final data = doc.data();
                      final seller = _str(
                        data,
                        'sellerName',
                        fallback: 'Seller',
                      );
                      final city = _str(
                        data,
                        'city',
                        fallback: 'Location Pending',
                      );
                      final product = _str(data, 'product', fallback: 'Fasal');
                      final price = _num(data, 'price');
                      final imageUrl = _str(data, 'imageUrl');
                      final videoUrl = _str(data, 'videoUrl');
                      final insight = _geminiInsight(data);
                      final bool isFlagged = flaggedListingIds.contains(doc.id);

                      return Card(
                        color: Colors.white.withValues(alpha: 0.05),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isFlagged
                                ? Colors.redAccent
                                : Colors.transparent,
                            width: 1.8,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          onTap: () => _openListingDetail(doc.id, data),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: imageUrl.isNotEmpty
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    width: 52,
                                    height: 52,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      width: 52,
                                      height: 52,
                                      color: Colors.white10,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) =>
                                        Container(
                                          width: 52,
                                          height: 52,
                                          color: Colors.white10,
                                          child: const Icon(
                                            Icons.broken_image,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                        ),
                                  )
                                : Container(
                                    width: 52,
                                    height: 52,
                                    color: Colors.white10,
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      color: Colors.white54,
                                      size: 18,
                                    ),
                                  ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              if (isFlagged)
                                const Icon(
                                  Icons.flag,
                                  color: Colors.redAccent,
                                  size: 18,
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Seller: $seller',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'City: $city',
                                style: const TextStyle(
                                  color: Colors.white54,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                'Rs. ${price.toStringAsFixed(0)}',
                                style: const TextStyle(color: Colors.white70),
                              ),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.photo,
                                    size: 12,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    imageUrl.isNotEmpty ? 'Photo' : 'No Photo',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Icon(
                                    Icons.video_library,
                                    size: 12,
                                    color: Colors.white54,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    videoUrl.isNotEmpty ? 'Video' : 'No Video',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                              if (isFlagged)
                                const Text(
                                  'AI Flag',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              else if (insight.isUnusual)
                                const Text(
                                  'AI Alert: Unusual Price!',
                                  style: TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white24,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () =>
                                        _openListingDetail(doc.id, data),
                                    icon: const Icon(Icons.gavel, size: 15),
                                    label: const Text(
                                      'View Bids',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 30),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    onPressed: () =>
                                        _approveListing(doc.id, data),
                                    icon: const Icon(
                                      Icons.play_circle_fill,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Approve & Start Auction',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLast7DaysChart() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('deals')
          .orderBy('createdAt', descending: false)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final sales = List<double>.filled(7, 0);
        final commission = List<double>.filled(7, 0);
        final now = DateTime.now();

        for (final doc in docs) {
          final data = doc.data();
          final createdAt = _date(data, 'createdAt');
          if (createdAt == null) continue;

          final dayDiff = DateTime(now.year, now.month, now.day)
              .difference(
                DateTime(createdAt.year, createdAt.month, createdAt.day),
              )
              .inDays;
          if (dayDiff < 0 || dayDiff > 6) continue;

          final index = 6 - dayDiff;
          final amount = _num(data, 'dealAmount') > 0
              ? _num(data, 'dealAmount')
              : _num(data, 'finalPrice');
          sales[index] += amount;
          commission[index] += amount * 0.02;
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: SizedBox(
            height: 190,
            child: LineChart(
              LineChartData(
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(
                  show: true,
                  horizontalInterval: 1000,
                ),
                titlesData: const FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      7,
                      (i) => FlSpot(i.toDouble(), sales[i]),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: gold,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                  LineChartBarData(
                    spots: List.generate(
                      7,
                      (i) => FlSpot(i.toDouble(), commission[i]),
                    ),
                    isCurved: true,
                    curveSmoothness: 0.35,
                    color: Colors.greenAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDealCommandQueue() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('deals')
          .orderBy('createdAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Deal Command Queue',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              if (docs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No deals available yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              else
                ...docs.map((doc) {
                  final data = doc.data();
                  final product = _str(
                    data,
                    'productName',
                    fallback: _str(data, 'product', fallback: 'Deal'),
                  );
                  final escrowState = _str(
                    data,
                    'escrowState',
                    fallback: 'PENDING',
                  );
                  final amount = _num(data, 'dealAmount') > 0
                      ? _num(data, 'dealAmount')
                      : _num(data, 'finalPrice');
                  final status = _str(
                    data,
                    'paymentStatus',
                    fallback: _str(data, 'status', fallback: 'pending'),
                  );
                  final normalizedPayment = _normalizePaymentStatus(status);
                  final normalizedEscrow = _normalizeEscrowState(escrowState);
                  final isHighRisk = _bool(data, 'isHighRisk');

                  return Card(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isHighRisk ? Colors.redAccent : Colors.white12,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isHighRisk)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.redAccent),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        size: 8,
                                        color: Colors.redAccent,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'High-Risk',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Escrow: $normalizedEscrow ⬢ Payment: $normalizedPayment',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Amount: Rs. ${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.indigo,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 34),
                              ),
                              onPressed: () => _openAdminDealDetails(doc.id),
                              icon: Hero(
                                tag: 'deal-review-${doc.id}',
                                child: const Material(
                                  type: MaterialType.transparency,
                                  child: Icon(
                                    Icons.admin_panel_settings,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              label: const Text(
                                'Review & Manage',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  void _openAdminDealDetails(String dealId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 360),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: AdminDealDetailsScreen(
              dealId: dealId,
              heroTag: 'deal-review-$dealId',
            ),
          );
        },
      ),
    );
  }

  Widget _buildUsersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db.collection('users').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              dataTextStyle: const TextStyle(color: Colors.white70),
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('CNIC')),
                DataColumn(label: Text('Verified')),
              ],
              rows: docs.map((doc) {
                final data = doc.data();
                final verified = _bool(data, 'isVerified');
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        _str(
                          data,
                          'name',
                          fallback: _str(data, 'fullName', fallback: 'User'),
                        ),
                      ),
                    ),
                    DataCell(Text(_str(data, 'role', fallback: 'N/A'))),
                    DataCell(Text(_str(data, 'cnic', fallback: 'N/A'))),
                    DataCell(
                      Switch(
                        value: verified,
                        onChanged: (value) async {
                          await _db.collection('users').doc(doc.id).update({
                            'isVerified': value,
                            'verifiedAt': value
                                ? FieldValue.serverTimestamp()
                                : null,
                          });
                        },
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentBidsSection() {
    return _buildAdminPakistanMandiHubBidsPanel(title: 'Recent Bids');
  }

  Widget _buildAdminPakistanMandiHubBidsPanel({String title = 'Recent Bids'}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream:
                  _allBidsStream ??
                  FirebaseFirestore.instance
                      .collectionGroup('bids')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Text(
                      'Bids load nahi ho sakin',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final docs = snapshot.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Abhi tak koi boli nahi lagi',
                      style: TextStyle(color: Colors.white54),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: docs.length > 12 ? 12 : docs.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1, color: Colors.white12),
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final amount = _num(data, 'bidAmount');
                    final buyer = _str(data, 'buyerName', fallback: 'Kharidar');
                    final listingId = _str(data, 'listingId', fallback: '--');
                    final status = _str(data, 'status', fallback: 'pending');
                    final pakistanAverageRate = _num(data, 'aiAverageRate') > 0
                        ? _num(data, 'aiAverageRate')
                        : _num(data, 'geminiAverageRate');
                    return ListTile(
                      onTap: listingId == '--'
                          ? null
                          : () => _openListingDetail(listingId, null),
                      dense: true,
                      title: Row(
                        children: [
                          Text(
                            'Rs. ${amount.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              buyer,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Listing: $listingId ⬢ $status',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            pakistanAverageRate > 0
                                ? "Buyer's Bid vs Pakistan Average Mandi Rate: Rs. ${amount.toStringAsFixed(0)} vs Rs. ${pakistanAverageRate.toStringAsFixed(0)}"
                                : "Buyer's Bid vs Pakistan Average Mandi Rate: Rs. ${amount.toStringAsFixed(0)} vs Rate Unavailable",
                            style: const TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openListingDetail(String listingId, Map<String, dynamic>? listingData) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final product = _str(listingData, 'product', fallback: 'Fasal');
        final seller = _str(listingData, 'sellerName', fallback: 'Seller');

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.72,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product == 'Fasal' ? 'Listing Details' : product,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Seller: $seller ⬢ ID: $listingId',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Recent Bids',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _marketplaceService.getBidsStream(listingId),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        if (snapshot.hasError) {
                          return const Center(
                            child: Text(
                              'Listing bids load nahi ho sakin',
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }

                        final bids = snapshot.data?.docs ?? [];
                        if (bids.isEmpty) {
                          return const Center(
                            child: Text(
                              'Abhi tak koi boli nahi lagi',
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: bids.length,
                          separatorBuilder: (context, index) =>
                              const Divider(color: Colors.white12, height: 1),
                          itemBuilder: (context, index) {
                            final bidData = bids[index].data();
                            final amount = _num(bidData, 'bidAmount');
                            final buyer = _str(
                              bidData,
                              'buyerName',
                              fallback: 'Kharidar',
                            );
                            final bidStatus = _str(
                              bidData,
                              'status',
                              fallback: 'normal',
                            );
                            final pakistanAverageRate =
                                _num(bidData, 'aiAverageRate') > 0
                                ? _num(bidData, 'aiAverageRate')
                                : _num(bidData, 'geminiAverageRate');
                            return ListTile(
                              dense: true,
                              title: Row(
                                children: [
                                  Text(
                                    'Rs. ${amount.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      buyer,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Text(
                                pakistanAverageRate > 0
                                    ? 'Status: $bidStatus\nBuyer\'s Bid vs Pakistan Average Mandi Rate: Rs. ${amount.toStringAsFixed(0)} vs Rs. ${pakistanAverageRate.toStringAsFixed(0)}'
                                    : 'Status: $bidStatus\nBuyer\'s Bid vs Pakistan Average Mandi Rate: Rs. ${amount.toStringAsFixed(0)} vs Rate Unavailable',
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                ),
                              ),
                            );
                          },
                        );
                      },
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

  Future<void> _approveListing(
    String listingId,
    Map<String, dynamic> data, {
    BuildContext? dialogContext,
  }) async {
    await _adminService.approveListingVisibility(listingId);
    await FirebaseFirestore.instance
        .collection('listings')
        .doc(listingId)
        .update({
          'startTime': FieldValue.serverTimestamp(),
          'endTime': Timestamp.fromDate(
            DateTime.now().toUtc().add(const Duration(hours: 24)),
          ),
          'bidStartTime': FieldValue.serverTimestamp(),
          'bidExpiryTime': Timestamp.fromDate(
            DateTime.now().toUtc().add(const Duration(hours: 24)),
          ),
          'isBidForceClosed': false,
          'bidClosedAt': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });

    debugPrint(
      'TIMESTAMP: Admin Approved at ${DateTime.now()} for listingId=$listingId',
    );

    _refreshAdminStats();

    if (!mounted) return;
    if (dialogContext != null && dialogContext.mounted) {
      Navigator.pop(dialogContext);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
        content: Text('Mubarak! Maal Mandi mein Live ho gaya hai'),
      ),
    );
  }

  _AiCheck _geminiInsight(Map<String, dynamic> data) {
    final product = _str(data, 'product').toLowerCase();
    final price = _num(data, 'price');

    double? baseline;
    for (final entry in AppConstants.marketPriceByCrop.entries) {
      final key = entry.key.toLowerCase();
      if (product.contains(key) || key.contains(product)) {
        baseline = entry.value;
        break;
      }
    }

    if (baseline == null || baseline <= 0 || price <= 0) {
      return const _AiCheck(isUnusual: false, deviationPercent: 0);
    }

    final deviation = ((price - baseline) / baseline) * 100;
    return _AiCheck(
      isUnusual: deviation.abs() > 20,
      deviationPercent: deviation,
    );
  }

  String _str(Map<String, dynamic>? data, String key, {String fallback = ''}) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return fallback;
    }
    return data[key].toString();
  }

  double _num(Map<String, dynamic>? data, String key, {double fallback = 0}) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return fallback;
    }
    final value = data[key];
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? fallback;
  }

  bool _bool(Map<String, dynamic>? data, String key, {bool fallback = false}) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return fallback;
    }
    final value = data[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  DateTime? _date(Map<String, dynamic>? data, String key) {
    if (data == null || !data.containsKey(key) || data[key] == null) {
      return null;
    }
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _normalizePaymentStatus(String raw) {
    final normalized = raw.trim().toUpperCase();
    switch (normalized) {
      case 'AMANAT PENDING':
      case 'AWAITING_PAYMENT':
      case 'PENDING_ESCROW':
      case 'PENDING':
        return 'PENDING_ESCROW';
      case 'PAID_TO_ESCROW':
      case 'ESCROW_LOCKED':
        return 'ACTIVE';
      case 'COMPLETED':
      case 'VERIFIED':
      case 'FUNDS_RELEASED':
        return 'VERIFIED';
      case 'REFUNDED':
        return 'REFUNDED';
      default:
        return normalized.isEmpty ? 'PENDING_ESCROW' : normalized;
    }
  }

  String _normalizeEscrowState(String raw) {
    final normalized = raw.trim().toUpperCase();
    switch (normalized) {
      case 'PENDING':
      case 'FUNDS_LOCKED':
        return 'ACTIVE';
      case 'STOCK_IN_TRANSIT':
        return 'IN_TRANSIT';
      case 'STOCK_VERIFIED':
        return 'VERIFIED';
      case 'FUNDS_RELEASED':
        return 'RELEASED';
      case 'REFUNDED':
        return 'REFUNDED';
      default:
        return normalized.isEmpty ? 'PENDING' : normalized;
    }
  }

  Widget _buildPendingApprovalsBell() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('listings')
          .where('listingStatus', isEqualTo: DealStatus.pendingAdminApproval.name)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        final hasPending = (snapshot.data?.docs.length ?? 0) > 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              tooltip: 'Pending Approvals',
              onPressed: () => setState(() => _selectedTab = 3),
              icon: const Icon(Icons.notifications_rounded),
            ),
            if (hasPending)
              Positioned(
                right: 10,
                top: 10,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AiCheck {
  final bool isUnusual;
  final double deviationPercent;

  const _AiCheck({required this.isUnusual, required this.deviationPercent});
}

class _AdminStatsSnapshot {
  final int totalUsers;
  final int pendingApprovals;
  final int liveListings;
  final int totalListings;
  final double netCommission;

  const _AdminStatsSnapshot({
    required this.totalUsers,
    required this.pendingApprovals,
    required this.liveListings,
    required this.totalListings,
    required this.netCommission,
  });
}

class _DealSummarySnapshot {
  final int activeAds;
  final int pendingApprovals;
  final int pendingPayouts;

  const _DealSummarySnapshot({
    this.activeAds = 0,
    this.pendingApprovals = 0,
    this.pendingPayouts = 0,
  });
}

