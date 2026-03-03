import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../deals/transaction_model.dart';

class EscrowTimelineWidget extends StatelessWidget {
  const EscrowTimelineWidget({
    super.key,
    required this.dealId,
  });

  final String dealId;

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('escrow_transactions')
        .doc(dealId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? <String, dynamic>{};
        final state = EscrowTransactionStateX.fromWireValue((data['state'] ?? '').toString());

        final fundsLockedAt = _parseDate(data['fundsLockedAt'] ?? data['createdAt']);
        final transitAt = _parseDate(data['stockInTransitAt']);
        final verifiedAt = _parseDate(data['stockVerifiedAt']);
        final releasedAt = _parseDate(data['fundsReleasedAt']);

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.security, color: Colors.green, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Secure Escrow',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _step(
                done: _isAtOrPast(state, EscrowTransactionState.fundsLocked),
                icon: Icons.lock,
                title: 'Payment Locked',
                timestamp: fundsLockedAt,
              ),
              _step(
                done: _isAtOrPast(state, EscrowTransactionState.stockInTransit),
                icon: Icons.local_shipping,
                title: 'Stock in Transit',
                timestamp: transitAt,
              ),
              _step(
                done: _isAtOrPast(state, EscrowTransactionState.stockVerified),
                icon: Icons.verified,
                title: 'Quality Verified by Arhat',
                timestamp: verifiedAt,
              ),
              _step(
                done: _isAtOrPast(state, EscrowTransactionState.fundsReleased),
                icon: Icons.account_balance_wallet,
                title: 'Payout Released to Seller',
                timestamp: releasedAt,
                isLast: true,
              ),
            ],
          ),
        );
      },
    );
  }

  bool _isAtOrPast(EscrowTransactionState current, EscrowTransactionState target) {
    const sequence = <EscrowTransactionState>[
      EscrowTransactionState.fundsLocked,
      EscrowTransactionState.stockInTransit,
      EscrowTransactionState.stockVerified,
      EscrowTransactionState.fundsReleased,
    ];

    final currentIndex = sequence.indexOf(current);
    final targetIndex = sequence.indexOf(target);
    if (currentIndex == -1 || targetIndex == -1) {
      return false;
    }
    return currentIndex >= targetIndex;
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  Widget _step({
    required bool done,
    required IconData icon,
    required String title,
    required DateTime? timestamp,
    bool isLast = false,
  }) {
    final color = done ? Colors.green : Colors.grey;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Icon(done ? Icons.check_circle : icon, color: color, size: 20),
            if (!isLast)
              Container(
                width: 2,
                height: 26,
                color: color.withValues(alpha: 0.5),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: done ? Colors.black87 : Colors.black54,
                  ),
                ),
                if (timestamp != null)
                  Text(
                    '${timestamp.toLocal()}',
                    style: const TextStyle(fontSize: 11, color: Colors.black54),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

