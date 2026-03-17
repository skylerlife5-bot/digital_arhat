import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../chat/chat_screen.dart';
import '../../theme/app_colors.dart';
import 'buyer_models.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({
    super.key,
    required this.orderId,
    required this.listingId,
  });

  final String orderId;
  final String listingId;

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  bool _paying = false;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _orderStream() {
    return FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots();
  }

  Future<void> _mockEscrowPayment(BuyerOrder order) async {
    if (_paying) return;
    setState(() => _paying = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final listingDoc = await FirebaseFirestore.instance.collection('listings').doc(widget.listingId).get();
      final listing = listingDoc.data() ?? const <String, dynamic>{};
      final address = _buildAddressFromListing(listing);

      await FirebaseFirestore.instance.collection('orders').doc(order.id).set({
        'status': 'paid',
        'chatUnlocked': true,
        'escrowPaidAt': FieldValue.serverTimestamp(),
        'exactAddress': address,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escrow payment successful. Chat unlocked.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escrow payment failed. Please retry.')),
      );
    } finally {
      if (mounted) {
        setState(() => _paying = false);
      }
    }
  }

  String _buildAddressFromListing(Map<String, dynamic> listing) {
    final district = (listing['district'] ?? '').toString().trim();
    final province = (listing['province'] ?? '').toString().trim();
    final village = (listing['village'] ?? listing['villageArea'] ?? '').toString().trim();
    final street = (listing['address'] ?? listing['pickupAddress'] ?? '').toString().trim();

    final parts = <String>[street, village, district, province].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? 'Address will be shared by seller in chat.' : parts.join(', ');
  }

  void _openChat(BuyerOrder order) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          dealId: order.id,
          receiverId: order.sellerId,
          productName: order.itemName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: BuyerUiTheme.greenDark,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Order Status / آرڈر اسٹیٹس', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _orderStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: BuyerUiTheme.gold));
              }

              final doc = snapshot.data;
              if (doc == null || !doc.exists) {
                return const Center(
                  child: Text('Order not found', style: TextStyle(color: Colors.white)),
                );
              }

              final order = BuyerOrder.fromDoc(doc);
              if (uid.isNotEmpty && order.buyerId.isNotEmpty && order.buyerId != uid) {
                return const Center(
                  child: Text('You are not authorized for this order', style: TextStyle(color: Colors.white)),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
                children: [
                  _OrderCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.itemName,
                          style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        _line('Bid Amount', 'Rs ${order.bidAmount.toStringAsFixed(2)}'),
                        _line('Order ID', order.id),
                        _line('Status', _statusLabel(order.status)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _OrderCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Flow / مرحلہ',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _step('Seller accepted bid → pending_admin'),
                        _step('Admin approves order → approved'),
                        _step('Buyer pays escrow → paid + chatUnlocked=true'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (order.canPayEscrow)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: BuyerUiTheme.gold, foregroundColor: Colors.black87),
                      onPressed: _paying ? null : () => _mockEscrowPayment(order),
                      icon: const Icon(Icons.account_balance_wallet_rounded),
                      label: Text(_paying ? 'Processing...' : 'Pay Escrow / ایسکرو ادا کریں'),
                    ),
                  if (!order.canPayEscrow && !order.isPaid)
                    _pendingStatusCard(order.status),
                  if (order.isPaid) ...[
                    _OrderCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pickup / Delivery Address',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            (order.exactAddress ?? '').trim().isEmpty
                                ? 'Address will be shared in chat.'
                                : order.exactAddress!,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2ECC71), foregroundColor: Colors.white),
                      onPressed: order.chatUnlocked ? () => _openChat(order) : null,
                      icon: const Icon(Icons.chat_rounded),
                      label: Text(order.chatUnlocked ? 'Open Secure Chat / چیٹ کھولیں' : 'Chat locked'),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _pendingStatusCard(OrderLifecycleStatus status) {
    final message = switch (status) {
      OrderLifecycleStatus.pendingAdmin => 'Admin approval pending. Escrow payment button will appear after approval.',
      OrderLifecycleStatus.rejected => 'Order has been rejected by admin/seller.',
      OrderLifecycleStatus.cancelled => 'Order has been cancelled.',
      _ => 'Order is being processed.',
    };
    return _OrderCard(
      child: Text(message, style: const TextStyle(color: Colors.white70)),
    );
  }

  String _statusLabel(OrderLifecycleStatus status) {
    return switch (status) {
      OrderLifecycleStatus.pendingAdmin => 'pending_admin',
      OrderLifecycleStatus.approved => 'approved',
      OrderLifecycleStatus.paid => 'paid',
      OrderLifecycleStatus.rejected => 'rejected',
      OrderLifecycleStatus.cancelled => 'cancelled',
      OrderLifecycleStatus.unknown => 'unknown',
    };
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _step(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.check_circle_outline_rounded, size: 16, color: BuyerUiTheme.gold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BuyerUiTheme.gold.withValues(alpha: 0.38)),
      ),
      child: child,
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
