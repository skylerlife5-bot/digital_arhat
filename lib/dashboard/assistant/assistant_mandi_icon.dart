import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Premium mandi-focused assistant icon with wheat symbol.
/// Wheat represents: Agriculture, Marketplace, Trust
class AssistantMandiIcon extends StatelessWidget {
  const AssistantMandiIcon({
    super.key,
    this.size = 24,
    this.padding = const EdgeInsets.all(10),
  });

  final double size;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD8B14A), Color(0xFFAA8730)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.18),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGold.withValues(alpha: 0.26),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main wheat icon (🌾)
          Icon(
            Icons.grass_rounded, // wheat/crop symbol
            color: Colors.white,
            size: size,
          ),
        ],
      ),
    );
  }
}

/// Compact version for minimal spaces (FAB, buttons).
class AssistantMandiIconCompact extends StatelessWidget {
  const AssistantMandiIconCompact({
    super.key,
    this.size = 18,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFD8B14A), Color(0xFFAA8730)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white24,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accentGold.withValues(alpha: 0.24),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.grass_rounded,
            color: Colors.white,
            size: size,
          ),
        ],
      ),
    );
  }
}
