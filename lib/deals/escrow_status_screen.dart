import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../deals/transaction_model.dart';

class EscrowStatusScreen extends StatefulWidget {
  const EscrowStatusScreen({
    super.key,
    required this.dealId,
    this.listingTitle,
  });

  final String dealId;
  final String? listingTitle;

  @override
  State<EscrowStatusScreen> createState() => _EscrowStatusScreenState();
}

class _EscrowStatusScreenState extends State<EscrowStatusScreen> {
  bool _deliveryConfirmed = false;
  bool _isSubmitting = false;

  Future<void> _requestReleasePayment() async {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      await FirebaseFirestore.instance.collection('deals').doc(widget.dealId).set({
        'buyerDeliveryConfirmed': true,
        'releaseRequested': true,
        'releaseRequestedBy': uid,
        'releaseRequestedAt': FieldValue.serverTimestamp(),
        'lastUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance.collection('notifications').add({
        'type': 'DEAL_ALERT',
        'dealId': widget.dealId,
        'title': 'Release Payment Request',
        'body': 'Buyer has confirmed delivery and requested escrow release.',
        'isRead': false,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Aap ki request kamyabi se submit ho gayi hai. Team payment release process karegi.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          content: Text(
            'Payment release request submit nahi ho saki. Dobara koshish karein.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Escrow Status', style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('escrow_transactions')
            .doc(widget.dealId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final stateRaw = (data['state'] ?? '').toString();
          final state = EscrowTransactionStateX.fromWireValue(stateRaw);

          final bool step1Done =
              state == EscrowTransactionState.fundsLocked ||
              state == EscrowTransactionState.stockInTransit ||
              state == EscrowTransactionState.stockVerified ||
              state == EscrowTransactionState.fundsReleased;
          final bool step2Done =
              state == EscrowTransactionState.stockInTransit ||
              state == EscrowTransactionState.stockVerified ||
              state == EscrowTransactionState.fundsReleased;
          final bool step3Done = state == EscrowTransactionState.fundsReleased;

          final bool canRelease =
              _deliveryConfirmed && step2Done && !step3Done && !_isSubmitting;

          return Stack(
            children: [
              Positioned(
                right: 14,
                top: 18,
                child: Row(
                  children: [
                    Icon(
                      Icons.verified_user,
                      color: Colors.white.withValues(alpha: 0.14),
                      size: 26,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Digital Arhat Verified',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.15),
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if ((widget.listingTitle ?? '').trim().isNotEmpty)
                      Text(
                        widget.listingTitle!,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      'Deal ID: ${widget.dealId}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    _secureBanner(),
                    const SizedBox(height: 14),
                    _stepCard(
                      index: 1,
                      title: 'Payment Deposited',
                      subtitle: 'Raqam escrow mein mehfooz tor par jama ho chuki hai.',
                      done: step1Done,
                    ),
                    _stepCard(
                      index: 2,
                      title: 'Goods in Transit',
                      subtitle: 'Samaan transit mein hai aur wasooli ka intezar hai.',
                      done: step2Done,
                    ),
                    _stepCard(
                      index: 3,
                      title: 'Payment Released to Seller',
                      subtitle: 'Wasooli ki tasdeeq ke baad raqam seller ko transfer hogi.',
                      done: step3Done,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            value: _deliveryConfirmed,
                            activeColor: const Color(0xFFFFD700),
                            contentPadding: EdgeInsets.zero,
                            onChanged: step2Done && !step3Done
                                ? (v) => setState(() => _deliveryConfirmed = v ?? false)
                                : null,
                            title: const Text(
                              'Main saman wasool hone ki tasdeeq karta/karti hoon',
                              style: TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: canRelease ? _requestReleasePayment : null,
                              icon: _isSubmitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                    )
                                  : const Icon(Icons.lock_open, color: Colors.black),
                              label: const Text(
                                'Release Payment',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFD700),
                                disabledBackgroundColor: Colors.white24,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Yeh button sirf delivery confirm hone ke baad active hoga.',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _secureBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.45)),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_rounded, color: Colors.greenAccent),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Is deal ki payment Digital Arhat Escrow se mehfooz hai.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepCard({
    required int index,
    required String title,
    required String subtitle,
    required bool done,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: done
              ? Colors.greenAccent.withValues(alpha: 0.6)
              : Colors.white12,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor:
                done ? Colors.greenAccent : Colors.white.withValues(alpha: 0.2),
            child: done
                ? const Icon(Icons.check, color: Colors.black, size: 16)
                : Text(
                    '$index',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}