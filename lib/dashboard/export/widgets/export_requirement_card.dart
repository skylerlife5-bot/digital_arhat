import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../models/export_requirement_guide.dart';

class ExportRequirementCard extends StatelessWidget {
  const ExportRequirementCard({
    super.key,
    required this.guide,
  });

  final ExportRequirementGuide guide;

  static const double _cardRadius = 18;
  static const double _ctaHeight = 42;

  String _certificationSummary() {
    if (guide.preferredCertifications.isEmpty) {
      return 'Preferred certifications: Buyer-specific';
    }
    final visible = guide.preferredCertifications.take(2).toList(
      growable: false,
    );
    final remaining = guide.preferredCertifications.length - visible.length;
    final summary = visible.join(', ');
    return remaining > 0
        ? 'Preferred certifications: $summary +$remaining'
        : 'Preferred certifications: $summary';
  }

  @override
  Widget build(BuildContext context) {
    final topRequirements = guide.keyRequirements.take(3).toList(growable: false);

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
          Text(
            guide.country,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: 18,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            guide.commodity,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 12),
          ...topRequirements.map(
            (requirement) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: AppColors.accentGold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      requirement,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
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
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Packaging: ${guide.packagingNotes}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background.withValues(alpha: 0.56),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.softGlassBorder.withValues(alpha: 0.85)),
            ),
            child: Text(
              guide.statusNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
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
                child: Text('View Guidance'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}