import 'package:flutter/material.dart';

import '../routes.dart';
import '../theme/app_colors.dart';

class EidMandiScreen extends StatelessWidget {
  const EidMandiScreen({super.key});

  static const List<_EidMandiAnimal> _animals = <_EidMandiAnimal>[
    _EidMandiAnimal(
      type: 'bakray',
      label: 'Bakray / بکرے',
      assetPath: 'assets/bakra_mandi/bakray.png',
      imageFit: BoxFit.cover,
      imageAlignment: Alignment(-0.08, -0.34),
      fallbackIcon: Icons.agriculture_rounded,
    ),
    _EidMandiAnimal(
      type: 'gaye',
      label: 'Gaye / گائے',
      assetPath: 'assets/bakra_mandi/gaye.png',
      imageFit: BoxFit.cover,
      imageAlignment: Alignment(0.10, -0.22),
      fallbackIcon: Icons.agriculture_rounded,
    ),
    _EidMandiAnimal(
      type: 'dumba',
      label: 'Dumba / دنبہ',
      assetPath: 'assets/bakra_mandi/dumba.png',
      imageFit: BoxFit.cover,
      imageAlignment: Alignment(0, -0.16),
      fallbackIcon: Icons.cruelty_free_rounded,
    ),
    _EidMandiAnimal(
      type: 'oont',
      label: 'Oont / اونٹ',
      assetPath: 'assets/bakra_mandi/oont.png',
      imageFit: BoxFit.cover,
      imageAlignment: Alignment(0.18, -0.18),
      fallbackIcon: Icons.terrain_rounded,
    ),
  ];

  void _openListings(BuildContext context, {String? animalType}) {
    Navigator.of(context).pushNamed(
      Routes.bakraMandiList,
      arguments: <String, dynamic>{'animalType': animalType},
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = MediaQuery.of(context).size.width < 360;
    final double ctaHeight = compact ? 36 : 40;
    final double miniCardAspectRatio = compact ? 1.42 : 1.48;
    final double miniLabelFontSize = compact ? 9.2 : 9.7;
    final EdgeInsets miniLabelPadding = EdgeInsets.fromLTRB(
      compact ? 8 : 9,
      compact ? 16 : 18,
      compact ? 8 : 9,
      compact ? 7 : 8,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E3B2E),
        foregroundColor: Colors.white,
        title: const Text(
          'عید بکرا منڈی',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Container(
          padding: EdgeInsets.fromLTRB(10, compact ? 9 : 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: <Color>[Color(0xFF194B30), Color(0xFF24563A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: AppColors.softGlassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'عید بکرا منڈی',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 17.5,
                ),
              ),
              const Text(
                'Eid Bakra Mandi',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.8,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'قربانی کے جانور خریدیں یا فروخت کریں',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.8,
                ),
              ),
              const SizedBox(height: 7),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _animals.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: miniCardAspectRatio,
                ),
                itemBuilder: (context, index) {
                  final item = _animals[index];
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.14),
                      ),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x19000000),
                          blurRadius: 8,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => _openListings(
                            context,
                            animalType: item.type,
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Positioned.fill(
                                child: Image.asset(
                                  item.assetPath,
                                  fit: item.imageFit,
                                  alignment: item.imageAlignment,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: <Color>[
                                              Colors.white.withValues(
                                                alpha: 0.16,
                                              ),
                                              Colors.white.withValues(
                                                alpha: 0.05,
                                              ),
                                            ],
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: Icon(
                                          item.fallbackIcon,
                                          color: Colors.white54,
                                          size: 28,
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
                                      colors: <Color>[
                                        Colors.black.withValues(alpha: 0.03),
                                        Colors.black.withValues(alpha: 0.00),
                                        Colors.black.withValues(alpha: 0.26),
                                        Colors.black.withValues(alpha: 0.64),
                                      ],
                                      stops: const <double>[0, 0.38, 0.68, 1],
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  padding: miniLabelPadding,
                                  alignment: Alignment.bottomCenter,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: <Color>[
                                        Colors.black.withValues(alpha: 0.08),
                                        Colors.black.withValues(alpha: 0.24),
                                      ],
                                    ),
                                  ),
                                  child: Text(
                                    item.label,
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: miniLabelFontSize + 1,
                                      fontWeight: FontWeight.w700,
                                      height: 1.1,
                                      letterSpacing: 0.3,
                                      shadows: const <Shadow>[
                                        Shadow(
                                          color: Color(0x80000000),
                                          blurRadius: 6,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                height: ctaHeight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: AppColors.ctaTextDark,
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => _openListings(context),
                  icon: const Icon(Icons.visibility_rounded, size: 18),
                  label: const Text(
                    'جانور دیکھیں / Explore Animals',
                    style: TextStyle(fontSize: 12.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EidMandiAnimal {
  const _EidMandiAnimal({
    required this.type,
    required this.label,
    required this.assetPath,
    required this.imageFit,
    required this.imageAlignment,
    required this.fallbackIcon,
  });

  final String type;
  final String label;
  final String assetPath;
  final BoxFit imageFit;
  final Alignment imageAlignment;
  final IconData fallbackIcon;
}