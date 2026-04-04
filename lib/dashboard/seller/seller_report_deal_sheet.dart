import 'package:flutter/material.dart';

import '../../services/buyer_discipline_service.dart';
import '../../theme/app_colors.dart';

/// Bottom sheet that lets a seller report a buyer who did not complete a deal.
///
/// Usage:
/// ```dart
/// await showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   backgroundColor: Colors.transparent,
///   builder: (_) => SellerReportDealSheet(
///     listingId: ...,
///     buyerId: ...,
///     buyerName: ...,
///     sellerId: ...,
///     bidId: ...,
///   ),
/// );
/// ```
class SellerReportDealSheet extends StatefulWidget {
  const SellerReportDealSheet({
    super.key,
    required this.listingId,
    required this.buyerId,
    required this.buyerName,
    required this.sellerId,
    required this.bidId,
  });

  final String listingId;
  final String buyerId;
  final String buyerName;
  final String sellerId;
  final String bidId;

  @override
  State<SellerReportDealSheet> createState() => _SellerReportDealSheetState();
}

class _SellerReportDealSheetState extends State<SellerReportDealSheet> {
  static const Color _gold = AppColors.accentGold;
  static const Color _bg = AppColors.background;

  static const List<_ReasonOption> _reasons = <_ReasonOption>[
    _ReasonOption(key: 'no_response',        label: 'خریدار جواب نہیں دے رہا'),
    _ReasonOption(key: 'refused_after_winning', label: 'جیت کر مُکر گیا/گئی'),
    _ReasonOption(key: 'fake_bid',           label: 'فرضی / غیر سنجیدہ بولی'),
    _ReasonOption(key: 'other',              label: 'دوسری وجہ'),
  ];

  String? _selectedReason;
  final TextEditingController _noteCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _onSubmit() async {
    if (_selectedReason == null) {
      _snack('وجہ منتخب کریں');
      return;
    }

    setState(() => _submitting = true);
    try {
      await BuyerDisciplineService.submitCompletionReport(
        listingId: widget.listingId,
        buyerId: widget.buyerId,
        sellerId: widget.sellerId,
        bidId: widget.bidId,
        reason: _selectedReason!,
        note: _noteCtrl.text.trim(),
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'رپورٹ جائزے کے لیے جمع ہو گئی۔',
          ),
          backgroundColor: Color(0xFF3A7D5A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _snack(msg);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafe = MediaQuery.of(context).padding.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.fromLTRB(12, 0, 12, inset + bottomSafe + 12),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.urgencyRed.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.report_problem_outlined,
                    color: AppColors.urgencyRed,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'ناکام سودا رپورٹ کریں',
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.secondaryText,
                      size: 20,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Buyer: ${widget.buyerName}',
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12,
                ),
              ),
              Container(
                margin: const EdgeInsets.only(top: 6, bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.urgencyRed.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.urgencyRed.withValues(alpha: 0.35),
                  ),
                ),
                child: const Text(
                  'رپورٹ ایڈمن کے جائزے کے لیے جائے گی۔ فوری کارروائی نہیں ہوگی۔',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ),
              const Text(
                'وجہ',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              ..._reasons.map((r) => _ReasonTile(
                    option: r,
                    selected: _selectedReason == r.key,
                    onTap: () => setState(() => _selectedReason = r.key),
                  )),
              const SizedBox(height: 10),
              const Text(
                'نوٹ (اختیاری)',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteCtrl,
                maxLines: 2,
                maxLength: 200,
                cursorColor: _gold,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'اختیاری تفصیل',
                  hintStyle:
                      const TextStyle(color: AppColors.secondaryText),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  counterStyle:
                      const TextStyle(color: AppColors.secondaryText),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _gold.withValues(alpha: 0.3),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: _gold.withValues(alpha: 0.3),
                    ),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                    borderSide: BorderSide(color: _gold),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primaryText,
                        side: BorderSide(
                          color: _gold.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Text('واپس'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed:
                          (_submitting || _selectedReason == null)
                              ? null
                              : _onSubmit,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.urgencyRed,
                        foregroundColor: Colors.white,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('رپورٹ جمع کریں'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonOption {
  const _ReasonOption({required this.key, required this.label});
  final String key;
  final String label;
}

class _ReasonTile extends StatelessWidget {
  const _ReasonTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });
  final _ReasonOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const Color gold = AppColors.accentGold;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? gold.withValues(alpha: 0.12)
              : AppColors.cardSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? gold.withValues(alpha: 0.7)
                : AppColors.primaryText24,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? gold : AppColors.secondaryText,
              size: 17,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  color: selected
                      ? AppColors.primaryText
                      : AppColors.secondaryText,
                  fontWeight: selected
                      ? FontWeight.w600
                      : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
