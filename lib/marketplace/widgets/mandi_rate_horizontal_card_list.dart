import 'package:flutter/material.dart';

import '../models/live_mandi_rate.dart';
import 'mandi_rate_card.dart';

class MandiRateHorizontalCardList extends StatelessWidget {
  const MandiRateHorizontalCardList({
    super.key,
    required this.rates,
  });

  final List<LiveMandiRate> rates;

  @override
  Widget build(BuildContext context) {
    if (rates.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.11)),
        ),
        child: const Text(
          'اس وقت صاف منڈی ریٹس دستیاب نہیں ہیں۔\nچند لمحوں بعد دوبارہ دیکھیں۔',
          style: TextStyle(color: Colors.white70, fontSize: 11.5),
        ),
      );
    }

    return SizedBox(
      height: 218,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: rates.length,
        itemBuilder: (context, index) {
          return MandiRateCard(rate: rates[index]);
        },
      ),
    );
  }
}
