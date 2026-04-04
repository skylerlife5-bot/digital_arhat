import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'aarhat_assistant_sheet.dart';
import 'assistant_mandi_icon.dart';

/// Premium floating entry point for the Aarhat Assistant.
/// Uses mandi-focused icon (wheat + sparkle + gold gradient).
/// Compact, refined, and feels lightweight while premium.
class AarhatAssistantFab extends StatelessWidget {
  const AarhatAssistantFab({
    super.key,
    required this.userData,
  });

  final Map<String, dynamic> userData;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'aarhat_assistant_fab',
      tooltip: 'آڑھت اسسٹنٹ',
      backgroundColor: AppColors.accentGold,
      foregroundColor: AppColors.ctaTextDark,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onPressed: () => AarhatAssistantSheet.show(context, userData: userData),
      icon: const AssistantMandiIconCompact(size: 18),
      label: const Text(
        'مددگار',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
