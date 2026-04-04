import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/export_buyer_profile.dart';

class ExportBuyerCard extends StatelessWidget {
  const ExportBuyerCard({
    super.key,
    required this.profile,
    this.onViewBuyer,
  });

  final ExportBuyerProfile profile;
  final VoidCallback? onViewBuyer;

  static const double _cardRadius = 18;
  static const double _ctaHeight = 42;

  String _commoditySummary() {
    final visible = profile.commodities.take(2).toList(growable: false);
    final remaining = profile.commodities.length - visible.length;
    final summary = visible.join(', ');
    return remaining > 0 ? '$summary +$remaining' : summary;
  }

  String _certificationSummary() {
    if (profile.certificationsPreferred.isEmpty) {
      return 'Preferred certifications: Buyer-specific';
    }
    final visible = profile.certificationsPreferred.take(2).toList(
      growable: false,
    );
    final remaining = profile.certificationsPreferred.length - visible.length;
    final summary = visible.join(', ');
    return remaining > 0
        ? 'Preferred certifications: $summary +$remaining'
        : 'Preferred certifications: $summary';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: AppColors.softGlassBorder),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 5),
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
                profile.companyName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.15,
                ),
              ),
              if (profile.verified)
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
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${profile.country}, ${profile.city}',
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
              _MetaPill(label: profile.buyerType),
              _MetaPill(label: 'Min order ${profile.minOrder}'),
              _MetaPill(label: 'Active ${profile.lastActiveHours}h ago'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Looking for: ${_commoditySummary()}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            profile.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _certificationSummary(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
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
              onPressed: onViewBuyer ?? () {},
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('View Buyer'),
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