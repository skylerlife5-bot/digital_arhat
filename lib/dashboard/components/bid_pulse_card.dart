// File: lib/dashboard/components/bid_pulse_card.dart

import 'package:flutter/material.dart';

class BidPulseWidget extends StatefulWidget {
  final double currentBid;
  final Widget child;

  const BidPulseWidget({super.key, required this.currentBid, required this.child});

  @override
  State<BidPulseWidget> createState() => _BidPulseWidgetState();
}

class _BidPulseWidgetState extends State<BidPulseWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant BidPulseWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Agar bid price change hui toh pulse animation chalao
    if (widget.currentBid != oldWidget.currentBid) {
      _pulseController.forward().then((_) => _pulseController.reverse());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
