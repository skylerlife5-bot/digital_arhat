import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../models/ai_mandi_brain_insight.dart';

class AiMandiBrainScreen extends StatelessWidget {
  const AiMandiBrainScreen({super.key, required this.insights});

  final List<AiMandiBrainInsight> insights;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Mandi Brain / اے آئی منڈی رہنمائی'),
        backgroundColor: AppColors.accentGold,
        foregroundColor: AppColors.ctaTextDark,
      ),
      body: insights.isEmpty
          ? const Center(
              child: Text(
                'Fresh insights will appear shortly. / تازہ رہنمائی جلد دستیاب ہوگی۔',
                style: TextStyle(color: AppColors.secondaryText),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
              itemCount: insights.length,
              itemBuilder: (context, index) {
                final item = insights[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondarySurface),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.commodity,
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.insight,
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.action,
                        style: const TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 11.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
