import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/custom_app_bar.dart';

class PayoutManagementScreen extends StatefulWidget {
  const PayoutManagementScreen({super.key});

  @override
  State<PayoutManagementScreen> createState() => _PayoutManagementScreenState();
}

class _PayoutManagementScreenState extends State<PayoutManagementScreen> {
  static const Color _navy = Color(0xFF0B1F3A);
  static const Color _royalBlue = Color(0xFF122B4A);
  static const Color _panel = Color(0xFF183B63);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final NumberFormat _pkr = NumberFormat.currency(
    locale: 'en_US',
    symbol: 'Rs. ',
    decimalDigits: 0,
  );
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _processing = <String>{};
  String _searchQuery = '';
  bool _sortHighToLow = true;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<Map<String, dynamic>> _fetchSellerProfile(String sellerId) async {
    if (sellerId.trim().isEmpty) return <String, dynamic>{};
    final doc = await _db.collection('users').doc(sellerId).get();
    return doc.data() ?? <String, dynamic>{};
  }

  Future<bool> _showReleaseDialog({
    required Map<String, dynamic> seller,
    required double total,
    required double commission,
    required double net,
  }) async {
    final bankName = (seller['bankName'] ?? '--').toString();
    final accountTitle = (seller['bankAccountTitle'] ?? '--').toString();
    final accountNo = (seller['bankAccountNumber'] ?? '--').toString();
    final iban = (seller['iban'] ?? '--').toString();
    final easyPaisa =
        (seller['easyPaisaNumber'] ?? seller['easypaisaNumber'] ?? '--')
            .toString();

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payout Release'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Total: ${_pkr.format(total)}'),
            Text('Commission (1%): ${_pkr.format(commission)}'),
            Text('Net to Seller: ${_pkr.format(net)}'),
            const SizedBox(height: 12),
            const Text(
              'Seller Bank / EasyPaisa Details',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Bank: $bankName'),
            Text('Title: $accountTitle'),
            Text('Account: $accountNo'),
            Text('IBAN: $iban'),
            Text('EasyPaisa: $easyPaisa'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Release Funds'),
          ),
        ],
      ),
    );

    return approved == true;
  }

  Future<void> _releaseFunds({
    required String listingId,
    required Map<String, dynamic> listing,
  }) async {
    if (_processing.contains(listingId)) return;

    final sellerId = (listing['sellerId'] ?? '').toString().trim();
    final buyerId =
        (listing['buyerId'] ?? listing['winnerId'] ?? '').toString().trim();
    if (sellerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), behavior: SnackBarBehavior.floating, content: Text('Seller ID is missing.')),
      );
      return;
    }

    final total = _toDouble(listing['payoutDetails']?['total']) > 0
        ? _toDouble(listing['payoutDetails']['total'])
        : (_toDouble(listing['currentPrice']) > 0
              ? _toDouble(listing['currentPrice'])
              : (_toDouble(listing['finalPrice']) > 0
                    ? _toDouble(listing['finalPrice'])
                    : _toDouble(listing['price'])));
    final commission = _toDouble(listing['payoutDetails']?['commission']) > 0
        ? _toDouble(listing['payoutDetails']['commission'])
        : (total * 0.01).toDouble();
    final net = _toDouble(listing['payoutDetails']?['sellerNet']) > 0
        ? _toDouble(listing['payoutDetails']['sellerNet'])
        : (total - commission).toDouble();

    final seller = await _fetchSellerProfile(sellerId);
    if (!mounted) return;

    final confirm = await _showReleaseDialog(
      seller: seller,
      total: total,
      commission: commission,
      net: net,
    );
    if (!confirm) return;

    setState(() => _processing.add(listingId));

    try {
      final txRef = _db.collection('transactions').doc();
      final now = FieldValue.serverTimestamp();
      final dealId = (listing['dealId'] ?? '').toString().trim();

      final batch = _db.batch();
      batch.set(_db.collection('listings').doc(listingId), {
        'status': 'completed',
        'listingStatus': 'completed',
        'auctionStatus': 'completed',
        'paymentStatus': 'completed',
        'settlementTransactionId': txRef.id,
        'payoutReleasedAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));

      if (dealId.isNotEmpty) {
        batch.set(_db.collection('deals').doc(dealId), {
          'status': 'completed',
          'paymentStatus': 'completed',
          'settlementTransactionId': txRef.id,
          'payoutReleasedAt': now,
          'lastUpdate': now,
        }, SetOptions(merge: true));
      }

      batch.set(txRef, {
        'type': 'payout',
        'sellerId': sellerId,
        'buyerId': buyerId,
        'listingId': listingId,
        'dealId': dealId,
        'amountPaid': net,
        'adminFee': commission,
        'totalAmount': total,
        'status': 'completed',
        'timestamp': now,
      });

      batch.set(_db.collection('transaction_audit').doc(), {
        'transactionId': txRef.id,
        'event': 'payout_released',
        'sellerId': sellerId,
        'listingId': listingId,
        'amountPaid': net,
        'adminFee': commission,
        'timestamp': now,
      });

      batch.set(_db.collection('users').doc(sellerId), {
        'lifetimeEarnings': FieldValue.increment(net),
        'availableBalance': FieldValue.increment(net),
        'updatedAt': now,
      }, SetOptions(merge: true));

      batch.set(
        _db
            .collection('users')
            .doc(sellerId)
            .collection('transactions')
            .doc(txRef.id),
        {
          'type': 'payout',
          'listingId': listingId,
          'dealId': dealId,
          'amountPaid': net,
          'adminFee': commission,
          'totalAmount': total,
          'timestamp': now,
        },
      );

      batch.set(_db.collection('notifications').doc(), {
        'userId': sellerId,
        'type': 'seller_payout_released',
        'listingId': listingId,
        'message':
            'Good News! Your payment of ${_pkr.format(net)} has been released to your account.',
        'isRead': false,
        'createdAt': now,
      });

      if (buyerId.isNotEmpty) {
        batch.set(_db.collection('notifications').doc(), {
          'userId': buyerId,
          'type': 'buyer_deal_closed',
          'listingId': listingId,
          'message':
              'Deal successfully closed. Thank you for using Digital Arhat!',
          'isRead': false,
          'createdAt': now,
        });
      }

      await batch.commit();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Payout released successfully: ${_pkr.format(net)} to seller.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), behavior: SnackBarBehavior.floating, content: Text('Payout release failed. Please retry.')),
      );
    } finally {
      if (mounted) {
        setState(() => _processing.remove(listingId));
      }
    }
  }

  double _resolveTotal(Map<String, dynamic> data) {
    return _toDouble(data['payoutDetails']?['total']) > 0
        ? _toDouble(data['payoutDetails']['total'])
        : (_toDouble(data['currentPrice']) > 0
              ? _toDouble(data['currentPrice'])
              : (_toDouble(data['finalPrice']) > 0
                    ? _toDouble(data['finalPrice'])
                    : _toDouble(data['price'])));
  }

  double _resolveCommission(Map<String, dynamic> data, double total) {
    return _toDouble(data['payoutDetails']?['commission']) > 0
        ? _toDouble(data['payoutDetails']['commission'])
        : (total * 0.01).toDouble();
  }

  double _resolveNet(Map<String, dynamic> data, double total, double commission) {
    return _toDouble(data['payoutDetails']?['sellerNet']) > 0
        ? _toDouble(data['payoutDetails']['sellerNet'])
        : (total - commission).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navy,
      appBar: const CustomAppBar(
        title: 'Pending Settlements',
        backgroundColor: _royalBlue,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value.trim().toLowerCase();
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by seller name or ID',
                      hintStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: _panel,
                      prefixIcon: const Icon(Icons.search, color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _sortHighToLow
                      ? 'Sorted: High to Low'
                      : 'Sorted: Low to High',
                  onPressed: () {
                    setState(() => _sortHighToLow = !_sortHighToLow);
                  },
                  icon: Icon(
                    _sortHighToLow
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _db
                  .collection('listings')
                  .where('status', isEqualTo: 'delivered_pending_release')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  );
                }

                final docs = snapshot.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No pending settlements',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                final filteredDocs = docs.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final data = doc.data();
                  final sellerName = (data['sellerName'] ?? '').toString().toLowerCase();
                  final sellerId = (data['sellerId'] ?? '').toString().toLowerCase();
                  return sellerName.contains(_searchQuery) ||
                      sellerId.contains(_searchQuery);
                }).toList();

                filteredDocs.sort((a, b) {
                  final aTotal = _resolveTotal(a.data());
                  final bTotal = _resolveTotal(b.data());
                  return _sortHighToLow
                      ? bTotal.compareTo(aTotal)
                      : aTotal.compareTo(bTotal);
                });

                if (filteredDocs.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching settlement found',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(14),
                  cacheExtent: 700,
                  itemCount: filteredDocs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data();
                    final listingId = doc.id;
                    final title =
                        (data['product'] ?? data['itemName'] ?? 'Listing')
                            .toString();
                    final sellerName = (data['sellerName'] ?? '--').toString();
                    final sellerId = (data['sellerId'] ?? '--').toString();

                    final total = _resolveTotal(data);
                    final commission = _resolveCommission(data, total);
                    final net = _resolveNet(data, total, commission);

                    final busy = _processing.contains(listingId);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _panel,
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
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Seller: $sellerName ($sellerId)',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Total Amount: ${_pkr.format(total)}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Your 1% Commission: ${_pkr.format(commission)}',
                            style: const TextStyle(color: Colors.amber),
                          ),
                          Text(
                            'Net Amount to Seller: ${_pkr.format(net)}',
                            style: const TextStyle(
                              color: Colors.lightGreenAccent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: busy
                                  ? null
                                  : () => _releaseFunds(
                                      listingId: listingId,
                                      listing: data,
                                    ),
                              icon: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.payments),
                              label: Text(
                                busy
                                    ? 'Processing...'
                                    : 'ðŸ’° Release Funds to Seller',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
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
}

