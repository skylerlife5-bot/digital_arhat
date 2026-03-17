import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'bid_bottom_sheet.dart';
import 'buyer_models.dart';
import 'order_status_screen.dart';
import '../../theme/app_colors.dart';

// Legacy duplicate screen: not part of canonical buyer listing-detail runtime flow.
// Canonical screen is buyer_listing_detail_screen.dart.

class ListingDetailsScreen extends StatefulWidget {
  const ListingDetailsScreen({
    super.key,
    required this.listingId,
    this.initialListing,
  });

  final String listingId;
  final BuyerListing? initialListing;

  @override
  State<ListingDetailsScreen> createState() => _ListingDetailsScreenState();
}

class _ListingDetailsScreenState extends State<ListingDetailsScreen> {
  Stream<DocumentSnapshot<Map<String, dynamic>>> _listingStream() {
    return FirebaseFirestore.instance.collection('listings').doc(widget.listingId).snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _buyerOrderStream(String buyerId) {
    return FirebaseFirestore.instance
        .collection('orders')
        .where('listingId', isEqualTo: widget.listingId)
        .where('buyerId', isEqualTo: buyerId)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final buyerId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: BuyerUiTheme.greenDark,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text('Listing Details / تفصیل', style: TextStyle(color: Colors.white)),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _listingStream(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting && widget.initialListing == null) {
                return const Center(child: CircularProgressIndicator(color: BuyerUiTheme.gold));
              }

              final doc = snapshot.data;
              if (doc == null || !doc.exists) {
                if (widget.initialListing == null) {
                  return const Center(
                    child: Text('Listing not found', style: TextStyle(color: Colors.white)),
                  );
                }
                return _buildBody(widget.initialListing!, buyerId);
              }

              final listing = BuyerListing.fromDoc(doc);
              return _buildBody(listing, buyerId);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuyerListing listing, String buyerId) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: buyerId.isEmpty ? null : _buyerOrderStream(buyerId),
      builder: (context, orderSnapshot) {
        final orderDoc = (orderSnapshot.data?.docs.isNotEmpty ?? false) ? orderSnapshot.data!.docs.first : null;
        final order = orderDoc == null ? null : BuyerOrder.fromDoc(orderDoc);

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            _DetailCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          listing.itemName,
                          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      TrustBadge(level: listing.riskLevel, score: listing.riskScore),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _line('Quantity', '${listing.quantity.toStringAsFixed(0)} ${listing.unit}'),
                  _line('Location', '${listing.province}, ${listing.district}'),
                  _line('Status', listing.isExpired ? 'Expired' : 'Live'),
                  _line(
                    'Market Avg',
                    listing.marketAveragePrice == null ? 'N/A' : 'Rs ${listing.marketAveragePrice!.toStringAsFixed(0)}',
                  ),
                  if ((listing.description ?? '').trim().isNotEmpty) _line('Description', listing.description!.trim()),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (listing.riskLevel != RiskLevel.low)
              _DetailCard(
                child: Text(
                  listing.riskLevel == RiskLevel.high
                      ? 'High risk alert: verify quantity and listing evidence before paying. / زیادہ خطرہ: ادائیگی سے پہلے تفصیل کی تصدیق کریں'
                      : 'Medium risk warning: cross-check market price and delivery terms. / درمیانی خطرہ: مارکیٹ ریٹ اور شرائط چیک کریں',
                  style: const TextStyle(color: Color(0xFFFFC107), fontWeight: FontWeight.w700),
                ),
              ),
            const SizedBox(height: 10),
            _DetailCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Privacy and Security / رازداری اور سکیورٹی',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  _securePoint('Seller phone/WhatsApp/address hidden until escrow payment.'),
                  _securePoint('Direct call/chat remains locked before payment completion.'),
                  _securePoint('Only province + district are visible before payment.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (order != null)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: BuyerUiTheme.gold, foregroundColor: Colors.black87),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => OrderStatusScreen(orderId: order.id, listingId: listing.id)),
                  );
                },
                icon: const Icon(Icons.assignment_turned_in_rounded),
                label: const Text('View Order / آرڈر دیکھیں'),
              ),
            if (order == null)
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: listing.isExpired ? Colors.grey : BuyerUiTheme.gold,
                  foregroundColor: listing.isExpired ? Colors.white70 : Colors.black87,
                ),
                onPressed: listing.isExpired || buyerId.isEmpty
                    ? null
                    : () {
                        showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => BidBottomSheet(
                            listingId: listing.id,
                            listingData: <String, dynamic>{
                              'sellerId': listing.sellerId,
                              'itemName': listing.itemName,
                              'quantity': listing.quantity,
                              'unit': listing.unit,
                            },
                          ),
                        );
                      },
                icon: const Icon(Icons.gavel_rounded),
                label: Text(listing.isExpired ? 'Bidding closed / بولی بند' : 'Place Bid / بولی لگائیں'),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _securePoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 3),
            child: Icon(Icons.lock_outline_rounded, size: 16, color: BuyerUiTheme.gold),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white70))),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BuyerUiTheme.gold.withValues(alpha: 0.35)),
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
