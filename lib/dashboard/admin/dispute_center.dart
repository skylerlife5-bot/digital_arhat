import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../deals/payment_status.dart'; // Enum import
import 'admin_deal_details_screen.dart';

class DisputeCenter extends StatelessWidget {
  const DisputeCenter({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E12),
      appBar: AppBar(
        title: const Text(
          'Dispute Resolution Center',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Firestore mein enum ka name use kar ke query kar rahe hain
        stream: FirebaseFirestore.instance
            .collection('deals')
            .where('paymentStatus', isEqualTo: TransactionStatus.disputed.name)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var deal = snapshot.data!.docs[index];
              return _buildDisputeCard(context, deal);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.gavel_rounded,
            size: 80,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          const Text(
            "Sukoon hai! Koi dispute pending nahi.",
            style: TextStyle(color: Colors.white54, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildDisputeCard(BuildContext context, DocumentSnapshot deal) {
    final data = deal.data() as Map<String, dynamic>;

    return Card(
      color: Colors.white.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: const BorderSide(color: Colors.redAccent, width: 0.5),
      ),
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        iconColor: Colors.redAccent,
        collapsedIconColor: Colors.white,
        title: Text(
          data['productName'] ?? 'Ghair-maroofa Fasal',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          "Raqam: Rs. ${data['amount'] ?? '0'}",
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: Colors.white10),
                // Fixed: Null-aware operator removed from where not needed
                _infoRow("Buyer ID:", data['buyerId']?.toString() ?? 'N/A'),
                _infoRow("Seller ID:", data['sellerId']?.toString() ?? 'N/A'),
                const SizedBox(height: 15),
                const Text(
                  "SABOOT (EVIDENCE):",
                  style: TextStyle(
                    color: Colors.amber,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    _evidenceButton(Icons.image, "Photos", () {}),
                    const SizedBox(width: 10),
                    _evidenceButton(Icons.mic, "Audio Note", () {}),
                  ],
                ),

                const SizedBox(height: 20),
                const Text(
                  "ADMIN KA FAISLA:",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: _decisionButton(
                        "Refund Buyer",
                        Colors.orange,
                        () => _openAdminDealDetails(context, deal.id),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _decisionButton(
                        "Pay Seller",
                        Colors.green,
                        () => _openAdminDealDetails(context, deal.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _openAdminDealDetails(context, deal.id),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: Hero(
                      tag: 'deal-review-${deal.id}',
                      child: const Material(
                        type: MaterialType.transparency,
                        child: Icon(
                          Icons.admin_panel_settings,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    label: const Text('Open in Command Queue'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _evidenceButton(IconData icon, String label, VoidCallback onTap) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: Colors.black),
      label: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: Colors.amber,
      onPressed: onTap,
    );
  }

  Widget _decisionButton(String label, Color color, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _openAdminDealDetails(BuildContext context, String dealId) {
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
}
