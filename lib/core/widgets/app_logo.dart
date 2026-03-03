import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.height = 42,
    this.showName = false,
    this.heroTag,
    this.textColor = Colors.white,
  });

  final double height;
  final bool showName;
  final String? heroTag;
  final Color textColor;

  Widget _buildLogoImage() {
    return Container(
      height: height,
      width: height,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFD700).withValues(alpha: 0.26),
            blurRadius: (height * 0.24).clamp(10, 28).toDouble(),
            spreadRadius: (height * 0.02).clamp(0.5, 2).toDouble(),
          ),
        ],
      ),
      child: Image.asset(
        'assets/logo.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stackTrace) {
          debugPrint(
            'AppLogo missing/opaque asset. Use transparent PNG for best branding: assets/logo.png',
          );
          return Icon(
            Icons.agriculture_rounded,
            size: height * 0.55,
            color: const Color(0xFF004D40),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLogoImage(),
        if (showName) ...[
          const SizedBox(width: 8),
          Text(
            'Digital Arhat',
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ],
    );

    if (heroTag == null) {
      return content;
    }

    return Hero(tag: heroTag!, child: content);
  }
}

