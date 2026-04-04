import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/export_ready_product.dart';

class ExportReadyProductCard extends StatelessWidget {
  const ExportReadyProductCard({
    super.key,
    required this.product,
  });

  final ExportReadyProduct product;

  static const double _cardRadius = 18;
  static const double _ctaHeight = 42;

  Color _badgeBackground() {
    switch (product.readinessLevel.toLowerCase()) {
      case 'strong':
        return const Color(0xFF2A4A33).withValues(alpha: 0.55);
      case 'moderate':
        return const Color(0xFF4A3F1F).withValues(alpha: 0.55);
      default:
        return AppColors.background;
    }
  }

  String _marketsSummary() {
    final visible = product.suggestedMarkets.take(3).toList(growable: false);
    final remaining = product.suggestedMarkets.length - visible.length;
    final summary = visible.join(', ');
    return remaining > 0 ? '$summary +$remaining' : summary;
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
                product.commodity,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  height: 1.15,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _badgeBackground(),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  product.readinessLevel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
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
            'Suggested markets: ${_marketsSummary()}',
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
          Text(
            'Ideal supply format: ${product.idealSupplyFormat}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Packaging: ${product.packagingType}',
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
            product.shelfLifeNote,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.3,
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
              onPressed: () {},
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Learn More'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}