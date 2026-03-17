import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/live_mandi_rate.dart';

class MandiRatesTicker extends StatefulWidget {
  const MandiRatesTicker({super.key, required this.rates});

  final List<LiveMandiRate> rates;

  @override
  State<MandiRatesTicker> createState() => _MandiRatesTickerState();
}

class _MandiRatesTickerState extends State<MandiRatesTicker> {
  final ScrollController _controller = ScrollController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant MandiRatesTicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rates.length != widget.rates.length) {
      _restart();
    }
  }

  void _restart() {
    _timer?.cancel();
    if (_controller.hasClients) {
      _controller.jumpTo(0);
    }
    _start();
  }

  void _start() {
    _timer?.cancel();
    if (widget.rates.length < 2) return;

    _timer = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 1) return;
      final next = _controller.offset + 1.1;
      if (next >= max) {
        _controller.jumpTo(0);
      } else {
        _controller.jumpTo(next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rates.isEmpty) {
      return const SizedBox.shrink();
    }

    final mirrored = <LiveMandiRate>[...widget.rates, ...widget.rates];

    return Container(
      height: 34,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: AppColors.primaryText.withValues(alpha: 0.14),
        ),
      ),
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: mirrored.length,
        separatorBuilder: (_, index) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final rate = mirrored[index];
          final trustedPrice = getTrustedDisplayPrice(rate);
          final line =
              '${rate.commodityName} | ${rate.mandiName} | ${rate.currency} ${trustedPrice.toStringAsFixed(0)} ${rate.unit} ${rate.trendSymbol} | ${rate.lastUpdatedLabel}';
          return Center(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: const TextStyle(
                color: Color(0xFFEFD88A),
                fontSize: 11.2,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        },
      ),
    );
  }
}
