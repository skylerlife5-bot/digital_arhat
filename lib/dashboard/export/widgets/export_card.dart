import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/export_opportunity.dart';

class ExportCard extends StatelessWidget {
  const ExportCard({
    super.key,
    required this.opportunity,
    this.onViewDetails,
    this.compact = false,
  });

  final ExportOpportunity opportunity;
  final VoidCallback? onViewDetails;
  final bool compact;

  static const double _cardRadius = 18;
  static const double _ctaHeight = 42;
  static const double _compactMinHeight = 248;

  String _certificationsSummary() {
    final certs = opportunity.certificationsRequired;
    if (certs.isEmpty) return 'Certifications: Not specified';

    final visible = certs.take(2).toList(growable: false);
    final remaining = certs.length - visible.length;
    final base = visible.join(', ');
    if (remaining > 0) {
      return 'Certifications: $base +$remaining';
    }
    return 'Certifications: $base';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 300 : null,
      constraints: compact
          ? const BoxConstraints(minHeight: _compactMinHeight)
          : null,
      margin: EdgeInsets.only(bottom: compact ? 0 : 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: compact
            ? AppColors.cardSurface.withValues(alpha: 0.96)
            : AppColors.cardSurface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(
          color: compact
              ? AppColors.accentGold.withValues(alpha: 0.24)
              : AppColors.softGlassBorder,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: compact ? 0.14 : 0.08),
            blurRadius: compact ? 18 : 14,
            offset: Offset(0, compact ? 7 : 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                opportunity.commodity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.15,
                ),
              ),
              if (opportunity.verified)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A4A33).withValues(alpha: 0.50),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Verified',
                    style: TextStyle(
                      color: AppColors.accentGold,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            opportunity.city == null || opportunity.city!.trim().isEmpty
                ? opportunity.country
                : '${opportunity.country}, ${opportunity.city}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _MetaPill(label: opportunity.buyerType),
              _MetaPill(label: 'MOQ ${opportunity.demand}'),
              _MetaPill(label: 'Updated ${opportunity.freshnessHours}h ago'),
            ],
          ),
          const SizedBox(height: 10),
          if ((opportunity.priceHint ?? '').isNotEmpty)
            Text(
              opportunity.priceHint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                height: 1.3,
              ),
            ),
          if (!compact) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _certificationsSummary(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
          if (compact) const Spacer(),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: _ctaHeight,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentGold,
                side: const BorderSide(color: AppColors.accentGold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              onPressed: onViewDetails ?? () {},
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('View Details'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}
