import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../deals/transaction_model.dart';
import 'custom_snack_bar.dart';
import '../../services/escrow_service.dart';

class EscrowControlPanelWidget extends StatefulWidget {
  const EscrowControlPanelWidget({
    super.key,
    required this.dealId,
    required this.adminUid,
    required this.adminRole,
    this.onActionCompleted,
    this.onActionProcessing,
  });

  final String dealId;
  final String adminUid;
  final String adminRole;
  final VoidCallback? onActionCompleted;
  final ValueChanged<bool>? onActionProcessing;

  @override
  State<EscrowControlPanelWidget> createState() => _EscrowControlPanelWidgetState();
}

class _EscrowControlPanelWidgetState extends State<EscrowControlPanelWidget> {
  final EscrowService _escrowService = EscrowService();
  final TextEditingController _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('escrow_transactions')
        .doc(widget.dealId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data == null) {
          return const SizedBox.shrink();
        }

        final state = EscrowTransactionStateX.fromWireValue((data['state'] ?? '').toString());
        final isHighRisk = data['isHighRisk'] == true;
        final note = _noteController.text.trim();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Escrow Control Panel',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text('Current State: ${state.wireValue}'),
              if (isHighRisk) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Verification Note (Required for High-Risk Release)',
                    hintText: 'Quality checked at Akbari Mandi',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (state == EscrowTransactionState.fundsLocked)
                    _actionButton(
                      label: 'Mark as In-Transit',
                      color: Colors.blue,
                      onPressed: () => _changeState(EscrowTransactionState.stockInTransit),
                    ),
                  if (state == EscrowTransactionState.stockInTransit)
                    _actionButton(
                      label: 'Verify Stock Arrival',
                      color: Colors.orange,
                      onPressed: () => _changeState(EscrowTransactionState.stockVerified),
                    ),
                  if (state == EscrowTransactionState.stockVerified)
                    _actionButton(
                      label: 'Release Funds to Seller',
                      color: Colors.green,
                      enabled: !isHighRisk || note.isNotEmpty,
                      onPressed: () => _confirmAndRelease(note),
                    ),
                  if (state != EscrowTransactionState.fundsReleased && state != EscrowTransactionState.refunded)
                    _actionButton(
                      label: 'Trigger Dispute/Refund',
                      color: Colors.red,
                      onPressed: () => _triggerRefund(note),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required Future<void> Function() onPressed,
    bool enabled = true,
  }) {
    return ElevatedButton(
      onPressed: (!_submitting && enabled) ? () => onPressed() : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
      ),
      child: _submitting
          ? const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : Text(label),
    );
  }

  Future<void> _changeState(EscrowTransactionState toState) async {
    await _performAction(
      actionLabel: 'Escrow state updated',
      action: () async {
      await _escrowService.transitionEscrowState(
        dealId: widget.dealId,
        toState: toState,
        callerUid: widget.adminUid,
        callerRole: widget.adminRole,
        verificationNote: _noteController.text.trim(),
      );
      },
    );
  }

  Future<void> _confirmAndRelease(String note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release Funds'),
        content: const Text(
          'This action is irreversible. Are you sure the kisan has delivered the stock?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm Release')),
        ],
      ),
    );

    if (confirmed != true) return;

    await _performAction(
      actionLabel: 'Funds released successfully',
      action: () async {
      await _escrowService.transitionEscrowState(
        dealId: widget.dealId,
        toState: EscrowTransactionState.fundsReleased,
        callerUid: widget.adminUid,
        callerRole: widget.adminRole,
        verificationNote: note,
      );
      },
    );
  }

  Future<void> _triggerRefund(String note) async {
    await _performAction(
      actionLabel: 'Refund completed securely',
      action: () async {
      await _escrowService.triggerDisputeRefund(
        dealId: widget.dealId,
        callerUid: widget.adminUid,
        callerRole: widget.adminRole,
        note: note,
      );
      },
    );
  }

  Future<void> _performAction({
    required String actionLabel,
    required Future<void> Function() action,
  }) async {
    if (_submitting) return;

    setState(() => _submitting = true);
    widget.onActionProcessing?.call(true);
    try {
      await action();
      if (!mounted) return;
      CustomSnackBar.success(
        context: context,
        message: actionLabel,
        transactionId: widget.dealId,
      );
      widget.onActionCompleted?.call();
    } catch (e) {
      if (!mounted) return;
      CustomSnackBar.error(
        context: context,
        message: e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      widget.onActionProcessing?.call(false);
      if (mounted) setState(() => _submitting = false);
    }
  }
}

