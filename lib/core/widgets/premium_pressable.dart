import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PremiumPressable extends StatefulWidget {
  const PremiumPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.enabled = true,
    this.pressedScale = 0.97,
    this.duration = const Duration(milliseconds: 110),
  });

  final Widget child;
  final VoidCallback onTap;
  final bool enabled;
  final double pressedScale;
  final Duration duration;

  @override
  State<PremiumPressable> createState() => _PremiumPressableState();
}

class _PremiumPressableState extends State<PremiumPressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) return;
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _handleTap() {
    if (!widget.enabled) return;
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? widget.pressedScale : 1.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setPressed(true),
      onTapUp: (_) => _setPressed(false),
      onTapCancel: () => _setPressed(false),
      onTap: _handleTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 1.0, end: scale),
        duration: widget.duration,
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Transform.scale(scale: value, child: child);
        },
        child: widget.child,
      ),
    );
  }
}

