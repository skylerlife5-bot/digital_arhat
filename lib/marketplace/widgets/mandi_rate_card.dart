import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';

class MandiRateCard extends StatelessWidget {
  const MandiRateCard({super.key, required this.rate});

  final LiveMandiRate rate;

  @override
  Widget build(BuildContext context) {
    final previous = rate.previousPrice;
    final hasPrevious = previous != null && previous > 0;
    final trustedPrice = getTrustedDisplayPrice(rate);

    return Container(
      width: 236,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            const Color(0xFF0A2D1D).withValues(alpha: 0.93),
            const Color(0xFF0D3B25).withValues(alpha: 0.9),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE8C766).withValues(alpha: 0.34),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rate.commodityName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          if (rate.subCategoryName.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              rate.subCategoryName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 10.7,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Location / مقام: ${rate.mandiName} • ${rate.locationLine}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 10.6,
              height: 1.22,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${rate.currency} ${trustedPrice.toStringAsFixed(0)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEFD88A),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${rate.trendSymbol} ${rate.unit}',
                style: const TextStyle(
                  color: Color(0xFFEFD88A),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (rate.displayPriceLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              rate.displayPriceLabel,
              style: const TextStyle(
                color: Color(0xFFEFD88A),
                fontSize: 9.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (hasPrevious) ...[
            const SizedBox(height: 2),
            Text(
              'Prev: ${rate.currency} ${previous.toStringAsFixed(0)}',
              style: const TextStyle(
                color: AppColors.primaryText54,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              if (rate.isLive) _badge('Live'),
              _badge(rate.freshnessLabel),
              if (rate.isNearby) _badge('Nearby'),
              if (rate.isAiCleaned) _badge('AI Cleaned'),
            ],
          ),
          const Spacer(),
          Text(
            'Last Updated / آخری اپڈیٹ: ${rate.lastUpdatedLabel}',
            style: TextStyle(
              color: rate.isStale
                  ? AppColors.urgencyRed
                  : AppColors.secondaryText,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Synced: ${rate.syncedAtLabel}',
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 9.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.primaryText.withValues(alpha: 0.2)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 9.3,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
