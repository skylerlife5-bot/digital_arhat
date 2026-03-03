import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class GlassButton extends StatefulWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.height = 54,
    this.radius = 30,
    this.textStyle,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final double height;
  final double radius;
  final TextStyle? textStyle;

  @override
  State<GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<GlassButton> {
  bool _pressed = false;

  void _handleTap() {
    final callback = widget.onPressed;
    if (callback == null || widget.loading) return;
    HapticFeedback.lightImpact();
    callback();
  }

  @override
  Widget build(BuildContext context) {
    const Color gold = Color(0xFFFFD700);
    final bool enabled = widget.onPressed != null && !widget.loading;

    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      scale: _pressed && enabled ? 0.98 : 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(widget.radius),
              onTap: enabled ? _handleTap : null,
              onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
              onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              child: Ink(
                height: widget.height,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: enabled ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: Border.all(
                    color: gold.withValues(alpha: enabled ? 0.9 : 0.45),
                    width: 1,
                  ),
                  boxShadow: enabled
                      ? [
                          BoxShadow(
                            color: gold.withValues(alpha: 0.24),
                            blurRadius: 16,
                            spreadRadius: 0.5,
                          ),
                        ]
                      : const [],
                ),
                child: Center(
                  child: widget.loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: gold,
                          ),
                        )
                      : Text(
                          widget.label,
                          style:
                              widget.textStyle ??
                              TextStyle(
                                color: enabled ? Colors.white : Colors.white54,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
