import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

class PremiumSpacing {
  PremiumSpacing._();

  static const double s1 = 8;
  static const double s1_5 = 12;
  static const double s2 = 16;
  static const double s3 = 24;

  static const double screenHorizontal = 16;
  static const double cardRadius = 14;
  static const double buttonHeight = 52;
}

class PremiumSectionHeader extends StatelessWidget {
  const PremiumSectionHeader({
    super.key,
    required this.titleUr,
    required this.titleEn,
    this.trailing,
  });

  final String titleUr;
  final String titleEn;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                titleUr,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                titleEn,
                style: const TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class PremiumSearchBar extends StatelessWidget {
  const PremiumSearchBar({
    super.key,
    required this.hintText,
    this.onTap,
    this.readOnly = false,
    this.controller,
    this.onChanged,
  });

  final String hintText;
  final VoidCallback? onTap;
  final bool readOnly;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      onChanged: onChanged,
      style: const TextStyle(
        color: AppColors.primaryText,
        fontSize: 15,
        height: 1.4,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.primaryText54,
          fontSize: 14,
        ),
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.accentGold),
        filled: true,
        fillColor: AppColors.primaryText12,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: PremiumSpacing.s2,
          vertical: PremiumSpacing.s2,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
          borderSide: BorderSide(color: AppColors.softGlassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
          borderSide: BorderSide(color: AppColors.softGlassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
          borderSide: const BorderSide(color: AppColors.accentGold),
        ),
      ),
    );
  }
}

class PremiumFilterChipRow extends StatelessWidget {
  const PremiumFilterChipRow({
    super.key,
    required this.labels,
  });

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: labels
            .map(
              (label) => Container(
                margin: const EdgeInsets.only(right: PremiumSpacing.s1),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryText10,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.softGlassBorder),
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.primaryText,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class PremiumEmptyState extends StatelessWidget {
  const PremiumEmptyState({
    super.key,
    required this.icon,
    required this.titleUr,
    required this.titleEn,
    required this.helperUr,
    required this.helperEn,
    this.primaryAction,
  });

  final IconData icon;
  final String titleUr;
  final String titleEn;
  final String helperUr;
  final String helperEn;
  final Widget? primaryAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PremiumSpacing.s2),
      decoration: BoxDecoration(
        color: AppColors.primaryText10,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.softGlassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.accentGold),
          const SizedBox(height: PremiumSpacing.s1_5),
          Text(
            titleUr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            titleEn,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: PremiumSpacing.s1_5),
          Text(
            helperUr,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            helperEn,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.primaryText54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (primaryAction != null) ...[
            const SizedBox(height: PremiumSpacing.s2),
            primaryAction!,
          ],
        ],
      ),
    );
  }
}

class PremiumStatusCard extends StatelessWidget {
  const PremiumStatusCard({
    super.key,
    required this.badgeText,
    required this.badgeColor,
    required this.titleUr,
    required this.titleEn,
    required this.descriptionUr,
    required this.descriptionEn,
    this.action,
  });

  final String badgeText;
  final Color badgeColor;
  final String titleUr;
  final String titleEn;
  final String descriptionUr;
  final String descriptionEn;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(PremiumSpacing.s2),
      decoration: BoxDecoration(
        color: AppColors.primaryText10,
        borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
        border: Border.all(color: AppColors.softGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: badgeColor.withValues(alpha: 0.55)),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                color: badgeColor,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: PremiumSpacing.s1),
          Text(
            titleUr,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            titleEn,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: PremiumSpacing.s1),
          Text(
            descriptionUr,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            descriptionEn,
            style: const TextStyle(
              color: AppColors.primaryText54,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: PremiumSpacing.s2),
            action!,
          ],
        ],
      ),
    );
  }
}

class PremiumPrimaryButton extends StatelessWidget {
  const PremiumPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: PremiumSpacing.buttonHeight,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentGold,
          foregroundColor: AppColors.ctaTextDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
          ),
        ),
        icon: Icon(icon ?? Icons.arrow_forward_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class PremiumSecondaryButton extends StatelessWidget {
  const PremiumSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: PremiumSpacing.buttonHeight,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.55)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
          ),
        ),
        icon: Icon(icon ?? Icons.person_add_alt_1_rounded, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
