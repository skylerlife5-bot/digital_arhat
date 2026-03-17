import 'package:flutter/material.dart';

import '../../core/seasonal_bakra_mandi_config.dart';
import '../../routes.dart';
import '../../theme/app_colors.dart';

class PostListingOptionScreen extends StatelessWidget {
  const PostListingOptionScreen({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    final bool bakraEnabled = SeasonalBakraMandiConfig.isEnabled;
    final bool bakraPostingAllowed =
        bakraEnabled && SeasonalBakraMandiConfig.allowPosting;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'پوسٹ کی قسم / Choose Post Type',
          style: TextStyle(color: AppColors.primaryText),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        children: [
          _OptionCard(
            title: 'عام منڈی پوسٹ / Regular Mandi',
            subtitle: 'Auction flow (existing rules)',
            icon: Icons.storefront_outlined,
            onTap: () {
              Navigator.of(context).pushNamed(
                Routes.sellerAddListing,
                arguments: <String, dynamic>{'userData': userData},
              );
            },
          ),
          const SizedBox(height: 12),
          _OptionCard(
            title: 'عید بکرا منڈی / Eid Bakra Mandi',
            subtitle: bakraPostingAllowed
              ? 'Fixed-price post with direct contact'
              : 'موسمی بکرا منڈی پوسٹ بند ہے',
            icon: Icons.pets_rounded,
            disabled: !bakraPostingAllowed,
            onTap: bakraPostingAllowed
                ? () {
                    Navigator.of(context).pushNamed(
                      Routes.bakraMandiPost,
                      arguments: <String, dynamic>{'userData': userData},
                    );
                  }
                : null,
          ),
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.disabled = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled ? AppColors.divider : AppColors.softGlassBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: disabled ? AppColors.secondaryText : AppColors.accentGold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: disabled
                          ? AppColors.secondaryText
                          : AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
