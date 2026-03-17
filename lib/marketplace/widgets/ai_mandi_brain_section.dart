import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../theme/app_colors.dart';
import '../models/ai_mandi_brain_insight.dart';
import '../screens/ai_mandi_brain_screen.dart';
import '../services/ai_mandi_brain_service.dart';

class AiMandiBrainSection extends StatefulWidget {
  const AiMandiBrainSection({
    super.key,
    required this.listings,
    required this.pulseCommodityHints,
    this.selectedCategory,
    this.accountCity,
    this.accountDistrict,
    this.accountProvince,
  });

  final List<Map<String, dynamic>> listings;
  final List<String> pulseCommodityHints;
  final MandiType? selectedCategory;
  final String? accountCity;
  final String? accountDistrict;
  final String? accountProvince;

  @override
  State<AiMandiBrainSection> createState() => _AiMandiBrainSectionState();
}

class _AiMandiBrainSectionState extends State<AiMandiBrainSection> {
  final AiMandiBrainService _service = AiMandiBrainService();

  late Future<List<AiMandiBrainInsight>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant AiMandiBrainSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final categoryChanged = oldWidget.selectedCategory != widget.selectedCategory;
    final locationChanged = oldWidget.accountCity != widget.accountCity ||
        oldWidget.accountDistrict != widget.accountDistrict ||
        oldWidget.accountProvince != widget.accountProvince;
    final listingsChanged = oldWidget.listings.length != widget.listings.length;

    if (categoryChanged || locationChanged || listingsChanged) {
      _future = _load();
    }
  }

  Future<List<AiMandiBrainInsight>> _load() {
    return _service.buildInsights(
      listings: widget.listings,
      pulseCommodityHints: widget.pulseCommodityHints,
      selectedCategory: widget.selectedCategory,
      accountCity: widget.accountCity,
      accountDistrict: widget.accountDistrict,
      accountProvince: widget.accountProvince,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AiMandiBrainInsight>>(
      future: _future,
      builder: (context, snapshot) {
        final insights = snapshot.data ?? const <AiMandiBrainInsight>[];
        final primary = insights.isNotEmpty ? insights.first : null;
        final supporting = insights.skip(1).take(2).toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Mandi Brain / اے آئی منڈی رہنمائی',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Smart market signals for today\nآج کے لیے ہوشیار منڈی اشارے',
                        style: TextStyle(
                          color: AppColors.primaryText60,
                          fontSize: 11,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (insights.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AiMandiBrainScreen(insights: insights),
                        ),
                      );
                    },
                    child: const Text('See All / سب دیکھیں'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting)
              const SizedBox(
                height: 78,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accentGold),
                ),
              )
            else if (primary == null)
              const Text(
                'Signal confidence is building. Check shortly. / سگنل کنفیڈنس بن رہا ہے، تھوڑی دیر بعد دوبارہ دیکھیں۔',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 11.2,
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF174735).withValues(alpha: 0.75),
                      const Color(0xFF0E3024).withValues(alpha: 0.72),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: const Color(0xFFE8C766).withValues(alpha: 0.42),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primary.commodity,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      primary.insight,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 11.8,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      primary.action,
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            if (supporting.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: supporting
                    .map(
                      (item) => Container(
                        constraints: const BoxConstraints(minWidth: 140, maxWidth: 290),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryText.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.secondarySurface),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.commodity,
                              style: const TextStyle(
                                color: AppColors.primaryText,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.insight,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.secondaryText,
                                fontSize: 10.8,
                                height: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        );
      },
    );
  }
}
