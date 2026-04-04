import 'package:flutter/material.dart';

import '../../routes.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';

class BakraMandiEntryScreen extends StatefulWidget {
  const BakraMandiEntryScreen({super.key, this.initialAnimalType});

  final String? initialAnimalType;

  @override
  State<BakraMandiEntryScreen> createState() => _BakraMandiEntryScreenState();
}

class _BakraMandiEntryScreenState extends State<BakraMandiEntryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final AnalyticsService _analytics = AnalyticsService();

  static const List<_AnimalType> _animals = <_AnimalType>[
    _AnimalType(
      'bakray',
      'بکرے / Bakray',
      Icons.pets_rounded,
      'assets/bakra_mandi/bakray.png',
    ),
    _AnimalType(
      'gaye',
      'گائے / Gaye',
      Icons.agriculture_rounded,
      'assets/bakra_mandi/gaye.png',
    ),
    _AnimalType(
      'dumba',
      'دنبہ / Dumba',
      Icons.cruelty_free_rounded,
      'assets/bakra_mandi/dumba.png',
    ),
    _AnimalType(
      'oont',
      'اونٹ / Oont',
      Icons.terrain_rounded,
      'assets/bakra_mandi/oont.png',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialAnimalType ?? '';
    Future<void>.microtask(() {
      _analytics.logEvent(
        event: 'bakra_mandi_entry_open',
        data: <String, dynamic>{
          'initialAnimalType': widget.initialAnimalType ?? 'all',
        },
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openListings({String? animalType}) {
    Navigator.of(context).pushNamed(
      Routes.bakraMandiList,
      arguments: <String, dynamic>{
        'animalType': animalType,
        'query': _searchController.text.trim(),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'بکرا منڈی',
          style: TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                SizedBox(
                  height: 160,
                  width: double.infinity,
                  child: Image.asset(
                    'assets/bakra_mandi/bakray.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: AppColors.cardSurface,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.pets_rounded,
                        size: 56,
                        color: AppColors.accentGold,
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.12),
                          Colors.black.withValues(alpha: 0.56),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'قربانی کے جانور ایک نظر میں',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Browse Bakray, Gaye, Dumba aur Oont with direct seller contact',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            style: const TextStyle(color: AppColors.primaryText),
            decoration: InputDecoration(
              hintText: 'جانور تلاش کریں / Search animal',
              hintStyle: const TextStyle(color: AppColors.secondaryText),
              prefixIcon: const Icon(Icons.search_rounded),
              filled: true,
              fillColor: AppColors.cardSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
            ),
          ),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.08,
            ),
            itemCount: _animals.length,
            itemBuilder: (context, index) {
              final animal = _animals[index];
              return FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.cardSurface,
                  foregroundColor: AppColors.primaryText,
                  side: const BorderSide(color: AppColors.softGlassBorder),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => _openListings(animalType: animal.value),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.asset(
                              animal.assetPath,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: AppColors.cardSurface,
                                alignment: Alignment.center,
                                child: Icon(
                                  animal.icon,
                                  color: AppColors.accentGold,
                                  size: 40,
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.06),
                                      Colors.black.withValues(alpha: 0.45),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 8,
                              left: 8,
                              child: Icon(
                                animal.icon,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      animal.label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: AppColors.accentGold),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ادائیگی سے پہلے جانور خود دیکھ لیں',
                    style: TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: FilledButton.icon(
            onPressed: _openListings,
            icon: const Icon(Icons.search_rounded),
            label: const Text('جانور دیکھیں / Explore Animals'),
          ),
        ),
      ),
    );
  }
}

class _AnimalType {
  const _AnimalType(this.value, this.label, this.icon, this.assetPath);

  final String value;
  final String label;
  final IconData icon;
  final String assetPath;
}
