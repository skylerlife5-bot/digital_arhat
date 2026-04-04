import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/buyer_discipline_service.dart';
import '../../theme/app_colors.dart';

/// Admin screen to review and act on buyer "failed deal" reports.
///
/// Accessible only by authenticated admin users. Each report card shows:
///  - listingId, buyerId, sellerId, reason, note, createdAt
///  - Approve (→ applies strike) or Reject (→ no action) buttons.
class AdminCompletionReportsScreen extends StatefulWidget {
  const AdminCompletionReportsScreen({super.key});

  @override
  State<AdminCompletionReportsScreen> createState() =>
      _AdminCompletionReportsScreenState();
}

class _AdminCompletionReportsScreenState
    extends State<AdminCompletionReportsScreen>
    with SingleTickerProviderStateMixin {
  static const Color _gold = AppColors.accentGold;
  static const Color _bg = Color(0xFF062517);

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'رپورٹس',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: AppColors.secondaryText,
          tabs: const [
            Tab(text: 'زیرِ التواء'),
            Tab(text: 'منظور'),
            Tab(text: 'مسترد'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ReportList(statusFilter: 'pending'),
          _ReportList(statusFilter: 'approved'),
          _ReportList(statusFilter: 'rejected'),
        ],
      ),
    );
  }
}

class _ReportList extends StatelessWidget {
  const _ReportList({required this.statusFilter});
  final String statusFilter;

  static const String _kCol = 'auction_completion_reports';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(_kCol)
          .where('status', isEqualTo: statusFilter)
          .orderBy('createdAt', descending: true)
          .limit(80)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accentGold),
          );
        }
        if (snap.hasError) {
          return Center(
            child: Text(
              'Error loading reports / رپورٹس لوڈ نہیں ہو سکیں',
              style: const TextStyle(color: AppColors.secondaryText),
            ),
          );
        }
        final docs = snap.data?.docs ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              statusFilter == 'pending'
                  ? 'کوئی زیرِ التواء رپورٹ نہیں'
                  : statusFilter == 'approved' ? 'کوئی منظور شدہ رپورٹ نہیں' : 'کوئی مسترد رپورٹ نہیں',
              style: const TextStyle(color: AppColors.secondaryText),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, ignore) => const SizedBox(height: 8),
          itemBuilder: (context, i) =>
              _ReportCard(doc: docs[i], isPending: statusFilter == 'pending'),
        );
      },
    );
  }
}

class _ReportCard extends StatefulWidget {
  const _ReportCard({required this.doc, required this.isPending});
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool isPending;

  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  bool _processing = false;

  static const Color _gold = AppColors.accentGold;

  Future<void> _review({required bool approve}) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    setState(() => _processing = true);
    try {
      await BuyerDisciplineService.reviewReport(
        reportId: widget.doc.id,
        approved: approve,
        reviewedBy: adminUid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? 'منظور — اسٹرائیک لاگو کر دی گئی'
                : 'مسترد — کوئی کارروائی نہیں ہوئی',
          ),
          backgroundColor:
              approve ? const Color(0xFF3A7D5A) : AppColors.secondaryText,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.urgencyRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final buyerId = (data['buyerId'] ?? '').toString();
    final sellerId = (data['sellerId'] ?? '').toString();
    final listingId = (data['listingId'] ?? '').toString();
    final reason = (data['reason'] ?? '').toString();
    final note = (data['note'] ?? '').toString().trim();
    final status = (data['status'] ?? 'pending').toString();
    final ts = data['createdAt'] as Timestamp?;
    final dateStr = ts != null
        ? _formatDate(ts.toDate())
        : 'Unknown date';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusBorderColor(status).withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusBadge(status: status),
              const Spacer(),
              Text(
                dateStr,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'لسٹنگ', value: listingId),
          _InfoRow(label: 'خریدار ID', value: buyerId),
          _InfoRow(label: 'بیچنے والا', value: sellerId),
          _InfoRow(label: 'وجہ', value: _humanReason(reason)),
          if (note.isNotEmpty) _InfoRow(label: 'نوٹ', value: note),
          if (data['strikeApplied'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: _StrikeAppliedChip(),
            ),
          if (widget.isPending) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _processing
                        ? null
                        : () => _review(approve: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.secondaryText,
                      side: BorderSide(
                        color: AppColors.secondaryText.withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Text('مسترد کریں'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _processing
                        ? null
                        : () => _review(approve: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.urgencyRed,
                      foregroundColor: Colors.white,
                    ),
                    child: _processing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('منظور + اسٹرائیک'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Color _statusBorderColor(String s) {
    switch (s) {
      case 'approved':
        return AppColors.urgencyRed;
      case 'rejected':
        return AppColors.secondaryText;
      default:
        return _gold;
    }
  }

  String _humanReason(String r) {
    switch (r) {
      case 'no_response':
        return 'خریدار جواب نہیں دے رہا';
      case 'refused_after_winning':
        return 'جیت کر مُکر گیا/گئی';
      case 'fake_bid':
        return 'فرضی / غیر سنجیدہ بولی';
      default:
        return r.replaceAll('_', ' ');
    }
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color bg;
    String label;
    switch (status) {
      case 'approved':
        bg = AppColors.urgencyRed;
        label = 'منظور';
      case 'rejected':
        bg = AppColors.secondaryText;
        label = 'مسترد';
      default:
        bg = AppColors.accentGold;
        label = 'زیرِ التواء';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: bg.withValues(alpha: 0.6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: bg,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _StrikeAppliedChip extends StatelessWidget {
  const _StrikeAppliedChip();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.gavel_rounded,
          color: AppColors.urgencyRed,
          size: 13,
        ),
        const SizedBox(width: 4),
        const Text(
          'اسٹرائیک لاگو',
          style: TextStyle(
            color: AppColors.urgencyRed,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
