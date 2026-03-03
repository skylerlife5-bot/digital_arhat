import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../components/escrow_control_panel_widget.dart';
import '../components/escrow_timeline_widget.dart';
import '../../services/auth_service.dart';

class AdminDealDetailsScreen extends StatefulWidget {
  const AdminDealDetailsScreen({super.key, required this.dealId, this.heroTag});

  final String dealId;
  final String? heroTag;

  @override
  State<AdminDealDetailsScreen> createState() => _AdminDealDetailsScreenState();
}

class _AdminDealDetailsScreenState extends State<AdminDealDetailsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final AuthService _authService = AuthService();
  late Future<String> _adminRoleFuture;
  bool _isActionProcessing = false;

  @override
  void initState() {
    super.initState();
    _adminRoleFuture = _authService.getCurrentAdminRole();
  }

  @override
  Widget build(BuildContext context) {
    final adminUid = _authService.currentAdminUid;

    return FutureBuilder<String>(
      future: _adminRoleFuture,
      builder: (context, roleSnap) {
        final adminRole = roleSnap.data ?? '';
        final isAdmin = adminRole == 'admin';

        if (roleSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!isAdmin || adminUid.isEmpty) {
          return const Scaffold(
            body: Center(child: Text('Access denied: Admin session required.')),
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db
              .collection('escrow_transactions')
              .doc(widget.dealId)
              .snapshots(),
          builder: (context, escrowSnap) {
            if (escrowSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final escrowData = escrowSnap.data?.data() ?? <String, dynamic>{};
            final isHighRisk = escrowData['isHighRisk'] == true;

            return Scaffold(
              appBar: AppBar(
                title: Row(
                  children: [
                    if (widget.heroTag != null)
                      Hero(
                        tag: widget.heroTag!,
                        child: const Material(
                          type: MaterialType.transparency,
                          child: Icon(Icons.admin_panel_settings),
                        ),
                      )
                    else
                      const Icon(Icons.admin_panel_settings),
                    const SizedBox(width: 8),
                    const Text('Admin Deal Details'),
                  ],
                ),
              ),
              body: Column(
                children: [
                  if (_isActionProcessing)
                    const LinearProgressIndicator(minHeight: 3),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isHighRisk) _buildSecurityAlertBanner(),
                          if (isHighRisk) const SizedBox(height: 12),
                          _buildDealSummaryCard(escrowData),
                          const SizedBox(height: 16),
                          EscrowControlPanelWidget(
                            dealId: widget.dealId,
                            adminUid: adminUid,
                            adminRole: adminRole,
                            onActionProcessing: (isRunning) {
                              if (!mounted) return;
                              setState(() => _isActionProcessing = isRunning);
                            },
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Escrow Timeline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          EscrowTimelineWidget(dealId: widget.dealId),
                          const SizedBox(height: 16),
                          const Text(
                            'System Audit Log',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildAuditLogSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSecurityAlertBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade400),
      ),
      child: const Text(
        '�a�️ AI WARNING: This deal was flagged as High-Risk during bidding. Manual stock verification and an Admin Note are REQUIRED before fund release.',
        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildDealSummaryCard(Map<String, dynamic> escrowData) {
    final amount = _toDouble(escrowData['baseAmount']);
    final buyerId = (escrowData['buyerId'] ?? 'N/A').toString();
    final sellerId = (escrowData['sellerId'] ?? 'N/A').toString();
    final state = (escrowData['state'] ?? 'N/A').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Deal ID: ${widget.dealId}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text('Escrow Amount: Rs. ${amount.toStringAsFixed(2)}'),
          Text('Current State: $state'),
          Text('Buyer: $buyerId'),
          Text('Seller: $sellerId'),
        ],
      ),
    );
  }

  Widget _buildAuditLogSection() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _db
          .collection('transaction_audit_logs')
          .where('dealId', isEqualTo: widget.dealId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Text('No audit entries yet.'),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: docs.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final data = docs[index].data();
              final adminId = (data['adminId'] ?? '').toString();
              final newState = (data['newState'] ?? '').toString();
              final note = (data['note'] ?? '').toString();
              final timestamp = data['timestamp'];
              final dateTime = timestamp is Timestamp
                  ? timestamp.toDate()
                  : null;
              final timeText = dateTime == null
                  ? 'Unknown time'
                  : TimeOfDay.fromDateTime(dateTime).format(context);

              return FutureBuilder<String>(
                future: _resolveAdminDisplayName(adminId),
                builder: (context, nameSnap) {
                  final adminName = nameSnap.data ?? adminId;
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.verified_user, size: 18),
                    title: Text(
                      'Admin $adminName marked as ${_stateLabel(newState)} at $timeText',
                    ),
                    subtitle: note.isEmpty ? null : Text('Note: $note'),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<String> _resolveAdminDisplayName(String adminId) async {
    if (adminId.isEmpty) return 'Unknown';

    try {
      final doc = await _db.collection('users').doc(adminId).get();
      final data = doc.data() ?? <String, dynamic>{};
      final name = (data['name'] ?? data['fullName'] ?? '').toString().trim();
      if (name.isNotEmpty) return name;
    } catch (_) {}

    return adminId;
  }

  String _stateLabel(String wireState) {
    switch (wireState.toUpperCase()) {
      case 'STOCK_VERIFIED':
        return 'Verified';
      case 'STOCK_IN_TRANSIT':
        return 'In-Transit';
      case 'FUNDS_RELEASED':
        return 'Funds Released';
      case 'REFUNDED':
        return 'Refunded';
      case 'DISPUTED':
        return 'Disputed';
      case 'FUNDS_LOCKED':
        return 'Funds Locked';
      default:
        return wireState;
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}

