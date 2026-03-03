// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/glass_button.dart';
import '../../services/marketplace_service.dart';

class SellerListingsScreen extends StatefulWidget {
  const SellerListingsScreen({super.key});

  @override
  State<SellerListingsScreen> createState() => _SellerListingsScreenState();
}

class _SellerListingsScreenState extends State<SellerListingsScreen> {
  static const Color _deepForest = Color(0xFF1B5E20);
  static const Color _sand = Color(0xFFF6F0E5);
  static const Color _rateColor = Color(0xFF5D8C3B);
  final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en_US');
  final MarketplaceService _marketplaceService = MarketplaceService();
  final Set<String> _dispatchingListingIds = <String>{};

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  Stream<QuerySnapshot<Map<String, dynamic>>> _stockStream() {
    final sellerId = _userId;
    if (sellerId == null || sellerId.isEmpty) {
      return FirebaseFirestore.instance
          .collection('listings')
          .where('sellerId', isEqualTo: '__none__')
          .snapshots();
    }
    return _marketplaceService.getSellerListingsStream(sellerId);
  }

  double? _extractRate(Map<String, dynamic> data) {
    final dynamic raw = data['price'] ?? data['rate'] ?? data['basePrice'];
    if (raw == null) return null;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString());
  }

  double _extractQuantity(Map<String, dynamic> data) {
    final dynamic raw = data['quantity'];
    if (raw == null) return 0.0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }

  double _computeTotalValue(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    return docs.fold<double>(0.0, (runningTotal, doc) {
      final data = doc.data();
      final dynamic estimated = data['estimatedValue'];
      if (estimated is num) return runningTotal + estimated.toDouble();
      final rate = _extractRate(data) ?? 0.0;
      final qty = _extractQuantity(data);
      return runningTotal + (rate * qty);
    });
  }

  Future<void> _refreshStock() async {
    if (_userId == null) return;
    await FirebaseFirestore.instance
        .collection('listings')
        .where('sellerId', isEqualTo: _userId)
        .orderBy('createdAt', descending: true)
        .get();
    if (mounted) setState(() {});
  }

  IconData _cropIcon(String product) {
    switch (product.toLowerCase()) {
      case 'gandum':
      case 'wheat':
        return Icons.eco;
      case 'kapaas':
      case 'kapas':
      case 'chawal':
      case 'rice':
        return Icons.rice_bowl;
      case 'cotton':
        return Icons.cloud;
      case 'makai':
      case 'corn':
        return Icons.grass;
      default:
        return Icons.energy_savings_leaf;
    }
  }

  String _extractDistrict(Map<String, dynamic> data) {
    final String district = data['district']?.toString().trim() ?? '';
    if (district.isNotEmpty) return district;

    final String location = data['location']?.toString().trim() ?? '';
    if (location.isEmpty) return 'Punjab';

    final parts = location.split(',');
    if (parts.isEmpty) return 'Punjab';
    final first = parts.first.trim();
    return first.isEmpty ? 'Punjab' : first;
  }

  String _formatCurrency(double value) => _moneyFormat.format(value);

  String _formatRate(double? rate) {
    if (rate == null) return 'Waiting';
    return _moneyFormat.format(rate);
  }

  String _normalizeUnit(String rawUnit) {
    final unit = rawUnit.trim().toLowerCase();
    if (unit == 'mann' ||
        unit == 'man' ||
        unit == 'munn' ||
        unit == 'mun (40kg)' ||
        unit == 'munn (40kg)') {
      return 'Munn (40kg)';
    }
    return rawUnit;
  }

  Future<void> _showEditDialog(String docId, Map<String, dynamic> data) async {
    final quantityController = TextEditingController(
      text: data['quantity']?.toString() ?? '',
    );
    final rateController = TextEditingController(
      text: (_extractRate(data))?.toStringAsFixed(0) ?? '',
    );

    final bool? shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stock Edit Karein'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Miqdar / �&�دار'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: rateController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Rate / ��R�&ت'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (shouldSave != true) return;

    final qty = double.tryParse(quantityController.text.trim()) ?? 0;
    final price = double.tryParse(rateController.text.trim()) ?? 0;

    await FirebaseFirestore.instance.collection('listings').doc(docId).update({
      'quantity': qty,
      'price': price,
      'estimatedValue': qty * price,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Stock updated successfully')));
  }

  Future<void> _deleteStock(String docId) async {
    final bool? confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Stock'),
        content: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Kya aap ye maal mandi se hatana chahte hain?'),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await FirebaseFirestore.instance.collection('listings').doc(docId).delete();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Stock deleted')));
  }

  bool _isEscrowConfirmed(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toLowerCase();
    final listingStatus = (data['listingStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return status == 'escrow_confirmed' || listingStatus == 'escrow_confirmed';
  }

  Future<void> _markAsDispatched({
    required String listingId,
    required Map<String, dynamic> data,
  }) async {
    final carrierController = TextEditingController();
    final trackingController = TextEditingController();
    DateTime? estimatedDeliveryDate;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 14,
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Dispatch Details',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: carrierController,
                    decoration: const InputDecoration(
                      labelText: 'carrierName',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trackingController,
                    decoration: const InputDecoration(
                      labelText: 'trackingId',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: sheetContext,
                        initialDate: DateTime.now().add(const Duration(days: 2)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 45)),
                      );
                      if (picked == null) return;
                      setSheetState(() => estimatedDeliveryDate = picked);
                    },
                    icon: const Icon(Icons.calendar_today),
                    label: Text(
                      estimatedDeliveryDate == null
                          ? 'estimatedDeliveryDate'
                          : DateFormat(
                              'dd MMM yyyy',
                            ).format(estimatedDeliveryDate!),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final carrierName = carrierController.text.trim();
                        final trackingId = trackingController.text.trim();
                        if (carrierName.isEmpty ||
                            trackingId.isEmpty ||
                            estimatedDeliveryDate == null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
                              content: Text('Please fill all dispatch fields.'),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(sheetContext, {
                          'carrierName': carrierName,
                          'trackingId': trackingId,
                          'estimatedDeliveryDate': estimatedDeliveryDate,
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _deepForest,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Save & Mark as Dispatched'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    carrierController.dispose();
    trackingController.dispose();

    if (result == null) return;

    final sellerId = _userId ?? '';
    if (sellerId.isEmpty) return;

    final carrierName = (result['carrierName'] ?? '').toString();
    final trackingId = (result['trackingId'] ?? '').toString();
    final estimatedDate = result['estimatedDeliveryDate'] as DateTime;

    setState(() => _dispatchingListingIds.add(listingId));
    try {
      final dispatchDetails = <String, dynamic>{
        'carrierName': carrierName,
        'trackingId': trackingId,
        'estimatedDeliveryDate': Timestamp.fromDate(estimatedDate),
        'estimatedDeliveryLabel': DateFormat('dd MMM yyyy').format(estimatedDate),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('listings').doc(listingId).set({
        'status': 'dispatched',
        'listingStatus': 'dispatched',
        'auctionStatus': 'dispatched',
        'dispatchDetails': dispatchDetails,
        'dispatchedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final dealId = (data['dealId'] ?? '').toString().trim();
      if (dealId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('deals').doc(dealId).set({
          'status': 'dispatched',
          'currentStep': 'DISPATCHED',
          'dispatchDetails': dispatchDetails,
          'lastUpdate': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      final buyerId = (data['buyerId'] ?? data['winnerId'] ?? '').toString().trim();
      if (buyerId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': buyerId,
          'type': 'order_dispatched',
          'listingId': listingId,
          'sellerId': sellerId,
          'message':
              'Your order has been dispatched. Tracking ID: $trackingId.',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'dispatch_marked',
        'listingId': listingId,
        'sellerId': sellerId,
        'targetRole': 'admin',
        'message':
            'Seller marked listing $listingId as dispatched. Tracking ID: $trackingId.',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Listing marked as dispatched.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Dispatch update failed. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _dispatchingListingIds.remove(listingId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _sand,
      appBar: AppBar(
        title: const Text("Mera Maal (My Stock)"),
        backgroundColor: _deepForest,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stockStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _deepForest),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(context);
          }

          final listings = snapshot.data!.docs;
          final totalValue = _computeTotalValue(listings);

          return Column(
            children: [
              _buildSummaryHeader(totalValue),
              Expanded(
                child: RefreshIndicator(
                  color: _deepForest,
                  onRefresh: _refreshStock,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(14),
                    itemCount: listings.length,
                    itemBuilder: (context, index) {
                      final doc = listings[index];
                      final data = doc.data();
                      final String product =
                          data['product']?.toString() ?? 'Fasal';
                      final String district = _extractDistrict(data);
                      final String unit = _normalizeUnit(
                        data['unit']?.toString() ?? '',
                      );
                      final String status = _resolveListingStatusLabel(data);
                      final bool adminVerificationPending =
                          status ==
                          'Buyer has paid. Funds are being verified by Admin.';
                      final bool canMarkDispatched = _isEscrowConfirmed(data);
                      final bool dispatching = _dispatchingListingIds.contains(
                        doc.id,
                      );
                      final bool isSuspicious = data['isSuspicious'] == true;
                      final String imageUrl =
                          data['imageUrl']?.toString() ?? '';
                      final double? rate = _extractRate(data);
                      final String rateText = _formatRate(rate);
                      final String quantityText =
                          data['quantity']?.toString() ?? '--';
                      final IconData cropIcon = _cropIcon(product);
                      return Card(
                        key: ValueKey(doc.id),
                        elevation: 4,
                        margin: const EdgeInsets.only(bottom: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: imageUrl.isNotEmpty
                                        ? Image.network(
                                            imageUrl,
                                            width: 68,
                                            height: 68,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) =>
                                                _buildIconPlaceholder(cropIcon),
                                          )
                                        : _buildIconPlaceholder(cropIcon),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product,
                                          style: const TextStyle(
                                            color: _deepForest,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Zila / ض�ع: $district',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          'Rate / ��R�&ت',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.black54,
                                          ),
                                        ),
                                        Text(
                                          'Rs. $rateText',
                                          style: const TextStyle(
                                            color: _rateColor,
                                            fontSize: 24,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert),
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showEditDialog(doc.id, data);
                                      } else if (value == 'delete') {
                                        _deleteStock(doc.id);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'edit',
                                        child: Text('Edit'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: _metaField(
                                      labelEnUr: 'Miqdar / �&�دار',
                                      value:
                                          '$quantityText ${unit.isNotEmpty ? unit : ''}'
                                              .trim(),
                                    ),
                                  ),
                                ],
                              ),
                              if (isSuspicious) ...[
                                const SizedBox(height: 10),
                                _buildAIWarningBox(
                                  data['suspiciousReason']?.toString(),
                                ),
                              ],
                              if (adminVerificationPending) ...[
                                const SizedBox(height: 10),
                                const Text(
                                  'Buyer has paid. Funds are being verified by Admin.',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Spacer(),
                                  _buildStatusBadge(status),
                                ],
                              ),
                              if (canMarkDispatched) ...[
                                const SizedBox(height: 10),
                                GlassButton(
                                  label: 'Mark as Dispatched',
                                  onPressed: dispatching
                                      ? null
                                      : () => _markAsDispatched(
                                          listingId: doc.id,
                                          data: data,
                                        ),
                                  loading: dispatching,
                                  height: 46,
                                  radius: 12,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryHeader(double totalValue) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF0B3D2E)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Total Stock Value',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Rs. ${_formatCurrency(totalValue)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconPlaceholder(IconData icon) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: _deepForest.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: _deepForest),
    );
  }

  Widget _metaField({required String labelEnUr, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _sand,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            labelEnUr,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _deepForest,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAIWarningBox(String? reason) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              "AI Alert: ${reason ?? 'Rate check ho raha hai'}",
              style: TextStyle(
                color: Colors.red[900],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resolveListingStatusLabel(Map<String, dynamic> data) {
    final status = (data['status'] ?? '').toString().trim().toUpperCase();
    final escrowStatus = (data['escrowStatus'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    final paymentStatus = (data['paymentStatus'] ?? '')
        .toString()
        .trim()
        .toUpperCase();

    if (status == 'AWAITING_ADMIN_APPROVAL' ||
        paymentStatus == 'PENDING_VERIFICATION') {
      return 'Buyer has paid. Funds are being verified by Admin.';
    }

    if (status == 'PAYMENT_CONFIRMED' || escrowStatus == 'PAYMENT_CONFIRMED') {
      return 'PAYMENT RECEIVED';
    }
    if (escrowStatus == 'PAID_TO_ESCROW') return 'ESCROWED';
    if (escrowStatus == 'PENDING_PAYMENT') return 'AMANAT PENDING';
    if (escrowStatus == 'FUNDS_RELEASED' || escrowStatus == 'COMPLETED') {
      return 'VERIFIED';
    }
    if (status == 'AMANAT PENDING' || status == 'AWAITING_PAYMENT') {
      return 'AMANAT PENDING';
    }
    if (status == 'COMPLETED') return 'LOCKED';
    if (status == 'ACTIVE' || status == 'LIVE') return 'ACTIVE';
    if (status == 'PENDING') return 'PENDING';
    return status.isEmpty ? 'PENDING' : status;
  }

  Widget _buildStatusBadge(String status) {
    final normalized = status.trim().toUpperCase();
    final bool isActive = normalized == 'ACTIVE';
    final bool isPending =
        normalized == 'PENDING' || normalized == 'AMANAT PENDING';
    final bool isAdminVerifying =
      status == 'Buyer has paid. Funds are being verified by Admin.';
    final bool isEscrowed = normalized == 'ESCROWED';
    final bool isVerified = normalized == 'VERIFIED';
    final bool isPaymentReceived = normalized == 'PAYMENT RECEIVED';

    final Color color = isPaymentReceived
        ? Colors.green
        : isVerified
        ? Colors.green
      : isAdminVerifying
      ? Colors.orange
        : isEscrowed
        ? Colors.blue
        : isActive
        ? Colors.green
        : isPending
        ? Colors.orange
        : Colors.blueGrey;
    final Color bgColor = isPaymentReceived
        ? Colors.green.withValues(alpha: 0.12)
        : isVerified
        ? Colors.green.withValues(alpha: 0.12)
      : isAdminVerifying
      ? Colors.orange.withValues(alpha: 0.12)
        : isEscrowed
        ? Colors.blue.withValues(alpha: 0.12)
        : isActive
        ? Colors.green.withValues(alpha: 0.1)
        : isPending
        ? Colors.orange.withValues(alpha: 0.12)
        : Colors.blueGrey.withValues(alpha: 0.12);
    final String label = isAdminVerifying ? 'ADMIN VERIFICATION' : normalized;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return RefreshIndicator(
      color: _deepForest,
      onRefresh: _refreshStock,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 90),
          SvgPicture.asset('assets/images/no_stock.svg', height: 180),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'Aap ka stock abhi khali hai',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _deepForest,
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'No stock found. Add new stock to go live in mandi.',
              style: TextStyle(color: Colors.black54),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _deepForest,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Add New Stock'),
            ),
          ),
        ],
      ),
    );
  }
}

