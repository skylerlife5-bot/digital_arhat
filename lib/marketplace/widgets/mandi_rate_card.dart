import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';
import '../services/mandi_home_presenter.dart';
import '../utils/mandi_display_utils.dart';

class MandiRateCard extends StatelessWidget {
  const MandiRateCard({super.key, required this.rate});

  final LiveMandiRate rate;

  @override
  Widget build(BuildContext context) {
    final previous = rate.previousPrice;
    final hasPrevious = previous != null && previous > 0;
    final commodityKey = MandiHomePresenter.normalizeCommodityKey(
      '${rate.metadata['urduName'] ?? ''} ${rate.commodityNameUr} ${rate.commodityName} ${rate.subCategoryName}',
    );
    if (!MandiHomePresenter.isAllowlistedCommodity(commodityKey)) {
      return const SizedBox.shrink();
    }
    final row = MandiHomePresenter.buildDisplayRow(
      commodityRaw: rate.commodityName,
      urduName: '${rate.metadata['urduName'] ?? ''}'.trim().isNotEmpty
          ? '${rate.metadata['urduName']}'.trim()
          : null,
      commodityNameUr: rate.commodityNameUr.trim().isNotEmpty
          ? rate.commodityNameUr
          : null,
      city: rate.city,
      district: rate.district,
      province: rate.province,
      unitRaw: rate.unit,
      price: rate.price,
      sourceSelected: '${rate.sourceId}|${rate.sourceType}|${rate.source}',
      confidence: rate.confidenceScore,
      renderPath: MandiHomeRenderPath.card,
    );
    if (!row.isRenderable) return const SizedBox.shrink();
    debugPrint('[MandiHome] legacy_render_path_hit=false');
    final commodity = row.commodityDisplay;
    final city = row.cityDisplay;
    final priceLine = row.priceDisplay;
    final unitLine = formatUnitDisplay(rate.unit);
    final badges = <String>[
      if (rate.isLive) 'تازہ',
      rate.freshnessLabel,
      if (rate.isNearby) 'قریب',
      if (rate.isAiCleaned) 'درست شدہ',
    ].where((value) => value.trim().isNotEmpty).toSet().toList(growable: false);

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
            commodity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            city,
            maxLines: 1,
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
                  priceLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFEFD88A),
                    fontSize: 15.8,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                rate.trendSymbol,
                style: const TextStyle(
                  color: Color(0xFFEFD88A),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (unitLine.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              unitLine,
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
              'پچھلا ریٹ: ${formatLocalizedPrice(previous, MandiDisplayLanguage.urdu)}',
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
            children: badges.map(_badge).toList(growable: false),
          ),
          const Spacer(),
          Text(
            'آخری اپڈیٹ: ${getLocalizedRelativeTime(rate.lastUpdated, MandiDisplayLanguage.urdu)}',
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
            'ہم آہنگی: ${getLocalizedRelativeTime(rate.syncedAt, MandiDisplayLanguage.urdu)}',
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
