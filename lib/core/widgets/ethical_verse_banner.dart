import 'package:flutter/material.dart';

import '../religious_constants.dart';

class EthicalVerseBanner extends StatelessWidget {
  const EthicalVerseBanner({
    super.key,
    this.title = 'اس�ا�&�R تجارت�R اص���',
    this.maxItems = 2,
  });

  final String title;
  final int maxItems;

  @override
  Widget build(BuildContext context) {
    final verses = ReligiousConstants.tradeEthicsVerses
        .take(maxItems.clamp(1, ReligiousConstants.tradeEthicsVerses.length))
        .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFFD700), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0F5132),
              ),
            ),
            const SizedBox(height: 8),
            ...verses.map(
              (verse) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      verse.arabic,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F5132),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      verse.urduTranslation,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      verse.reference,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

