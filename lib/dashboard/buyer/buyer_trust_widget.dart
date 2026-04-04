import 'package:flutter/material.dart';

import '../../services/buyer_discipline_service.dart';
import '../../theme/app_colors.dart';

/// Displays a buyer's trust summary: completion rate, label, and strikes.
///
/// Designed to be embedded in the Account tab and listing views.
class BuyerTrustWidget extends StatelessWidget {
  const BuyerTrustWidget({
    super.key,
    required this.userData,
    this.compact = false,
  });

  /// The buyer's Firestore user data map.
  final Map<String, dynamic> userData;

  /// If true, renders a smaller single-line version (for listing cards).
  final bool compact;

  static const Color _gold = AppColors.accentGold;

  int get _won => _toInt(userData['auctionsWonCount']);
  int get _completed => _toInt(userData['auctionsCompletedCount']);
  int get _failed => _toInt(userData['auctionsFailedCount']);
  int get _strikes => _toInt(userData['strikeCount']);
  int get _rate => _won > 0
      ? ((_completed / _won) * 100).round().clamp(0, 100)
      : (_toInt(userData['completionRate']));

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  Color _rateColor() {
    if (_won == 0) return AppColors.secondaryText;
    if (_rate >= 80) return const Color(0xFF4CAF80); // green
    if (_rate >= 50) return const Color(0xFFE0A030); // amber
    return AppColors.urgencyRed;
  }

  String get _label => BuyerDisciplineService.trustLabel(
        won: _won,
        rate: _rate,
        strikes: _strikes,
      );

  IconData get _labelIcon {
    switch (_label) {
      case 'Serious Buyer':
        return Icons.verified_rounded;
      case 'Restricted':
        return Icons.block_rounded;
      default:
        return Icons.person_outline_rounded;
    }
  }

  Color get _labelColor {
    switch (_label) {
      case 'Serious Buyer':
        return _gold;
      case 'Restricted':
        return AppColors.urgencyRed;
      default:
        return AppColors.secondaryText;
    }
  }

  String get _labelUrdu {
    switch (_label) {
      case 'Serious Buyer':
        return 'سنجیدہ خریدار';
      case 'Restricted':
        return 'محدود اکاؤنٹ';
      case 'New Buyer':
        return 'نیا خریدار';
      default:
        return 'فعال خریدار';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (compact) return _buildCompact();
    return _buildFull();
  }

  Widget _buildCompact() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(_labelIcon, color: _labelColor, size: 13),
        const SizedBox(width: 4),
        Text(
          _won == 0 ? _labelUrdu : '$_labelUrdu · $_rate%',
          style: TextStyle(color: _labelColor, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _buildFull() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryText24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: _gold, size: 16),
              const SizedBox(width: 6),
              const Text(
                'خریدار اعتماد',
                style: TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              _TrustLabelChip(label: _labelUrdu, color: _labelColor, icon: _labelIcon),
            ],
          ),
          const SizedBox(height: 10),
          if (_won == 0) ...[
            const Text(
              'ابھی تک کوئی نیلامی نہیں جیتی',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _StatCell(
                    label: 'کمپلیشن ریٹ',
                    value: '$_rate%',
                    valueColor: _rateColor(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCell(
                    label: 'نیلامیاں جیتیں',
                    value: '$_won',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCell(
                    label: 'مکمل',
                    value: '$_completed',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$_won نیلامیاں جیتیں • $_completed مکمل • $_failed ناکام',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11,
              ),
            ),
          ],
          if (_strikes > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: _strikes >= 3
                      ? AppColors.urgencyRed
                      : AppColors.accentGoldAccent,
                  size: 13,
                ),
                const SizedBox(width: 5),
                Text(
                  _strikeText(),
                  style: TextStyle(
                    color: _strikes >= 3
                        ? AppColors.urgencyRed
                        : AppColors.accentGoldAccent,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _strikeText() {
    if (_strikes >= 3) {
      return 'اکاؤنٹ محدود ہے — بار بار خلاف ورزی';
    }
    if (_strikes == 2) {
      return 'اسٹرائیک ۲ از ۳ — عارضی پابندی فعال';
    }
    return 'اسٹرائیک ۱ از ۳ — تنبیہ جاری کی گئی';
  }
}

class _TrustLabelChip extends StatelessWidget {
  const _TrustLabelChip({
    required this.label,
    required this.color,
    required this.icon,
  });
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 11),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.value,
    this.valueColor = AppColors.primaryText,
  });
  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
