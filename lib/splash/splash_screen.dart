import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/assets.dart';
import '../core/widgets/customer_support_button.dart';
import '../routes.dart';
import '../theme/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.autoNavigate = false,
    this.nextRoute = Routes.welcome,
  });

  final bool autoNavigate;
  final String nextRoute;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;
  bool _fadeIn = false;
  Timer? _timer;

  static const Color _baseGreen = AppColors.background;
  static const Color _midGreen = AppColors.cardSurface;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _fadeIn = true);
    });
    if (widget.autoNavigate) {
      _timer = Timer(const Duration(seconds: 2), () {
        if (!mounted || _navigated) return;
        _navigated = true;
        Navigator.pushReplacementNamed(context, widget.nextRoute);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          _buildBackground(),
          Center(
            child: AnimatedOpacity(
              opacity: _fadeIn ? 1 : 0,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOut,
              child: SizedBox(
                width: 122,
                height: 122,
                child: Image.asset(
                  AppAssets.logoPath,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.agriculture_rounded,
                      color: AppColors.primaryText,
                      size: 44,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[_baseGreen, _baseGreen, _midGreen],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const Color _baseGreen = AppColors.background;
  static const Color _warmGold = AppColors.accentGold;
  static const Color _warmGoldLight = AppColors.primaryText;
  Future<void> _showHowItWorksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.divider,
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[
                      Text(
                        'ڈیجیٹل آرہت کیسے کام کرتی ہے؟',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'JameelNoori',
                          color: AppColors.primaryText,
                          fontSize: 24,
                          height: 1.0,
                        ),
                      ),
                      SizedBox(height: 10),
                      _HowStepRow(
                        icon: Icons.fact_check_rounded,
                        text:
                            '1) فروخت کنندہ اپنی فصل یا مال کی لسٹنگ لگاتا ہے',
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.gavel_rounded,
                        text: '2) ایڈمن لسٹنگ کو چیک کر کے منظور کرتا ہے',
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.lock_clock_rounded,
                        text: '3) خریدار اس پر بولی لگاتے ہیں',
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.local_shipping_rounded,
                        text: '4) فروخت کنندہ ایک بولی قبول کرتا ہے',
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.connect_without_contact_rounded,
                        text:
                            '5) قبول ہونے کے بعد خریدار اور فروخت کنندہ کا رابطہ کھل جاتا ہے',
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.handshake_rounded,
                        text: '6) سودا آف لائن مکمل کیا جاتا ہے',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  _baseGreen,
                  const Color(0xFF062517),
                  const Color(0xFF082B1C),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Opacity(
            opacity: 0.02,
            child: CustomPaint(
              painter: _DigitalOverlayPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.02,
              child: Image.asset(
                'assets/images/circuit_pattern.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool compact = constraints.maxHeight < 700;
                final double sectionGap = compact ? 10 : 12;
                final double titleSize = compact ? 18 : 20;
                final double urduTitleSize = compact ? 26 : 30;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(14, compact ? 10 : 12, 14, 12),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 500),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _PanelCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                _buildLogo(compact: compact),
                                SizedBox(height: compact ? 8 : 10),
                                Text(
                                  'Digital Aarhat',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: AppColors.primaryText,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  'ڈیجیٹل آڑھت',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: AppColors.primaryText,
                                    fontSize: urduTitleSize,
                                    height: 1.02,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'کسان کی ترقی، پاکستان کی خوشحالی',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: AppColors.primaryText,
                                    fontSize: compact ? 20 : 22,
                                    height: 1.02,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          _PanelCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                Text(
                                  'وَأَوْفُوا الْكَيْلَ وَالْمِيزَانَ بِالْقِسْطِ',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: AppColors.accentGold,
                                    fontSize: compact ? 18 : 20,
                                    fontWeight: FontWeight.w700,
                                    height: 1.28,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'ناپ اور تول انصاف کے ساتھ پورا کرو',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: AppColors.primaryText,
                                    fontSize: compact ? 19 : 21,
                                    height: 1.04,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'سورۃ الانعام 6:152',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: AppColors.secondaryText,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: sectionGap),
                          const _PanelCard(
                            child: Column(
                              children: <Widget>[
                                _TrustRow(
                                  icon: Icons.rule_rounded,
                                  urdu: 'ایڈمن ہر لسٹنگ پہلے چیک کرتا ہے',
                                ),
                                SizedBox(height: 8),
                                _TrustRow(
                                  icon: Icons.account_balance_wallet_rounded,
                                  urdu: 'بولی منظور ہونے کے بعد رابطہ کھلتا ہے',
                                ),
                                SizedBox(height: 8),
                                _TrustRow(
                                  icon: Icons.lock_outline_rounded,
                                  urdu: 'محفوظ اور شفاف خرید و فروخت',
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 10),
                          const Text(
                            'پاکستان کی ڈیجیٹل منڈی',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: compact ? 10 : 12),
                          _buildActions(context),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogo({required bool compact}) {
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: compact ? 120 : 136,
        height: compact ? 120 : 136,
        child: Image.asset(
          AppAssets.logoPath,
          fit: BoxFit.contain,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return const Center(
                  child: Icon(
                    Icons.agriculture_rounded,
                    color: AppColors.primaryText,
                    size: 38,
                  ),
                );
              },
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[_warmGold, _warmGoldLight],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(
                  Routes.buyerDashboard,
                  arguments: const <String, dynamic>{},
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: AppColors.ctaTextDark,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'منڈی دیکھیں / Explore Mandi',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushNamed(Routes.login);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(color: AppColors.divider),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'لاگ اِن / Login',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushNamed(Routes.createAccount);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(color: AppColors.divider),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'اکاؤنٹ بنائیں / Create Account',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _showHowItWorksSheet,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              minimumSize: const Size.fromHeight(36),
            ),
            child: Text(
              'یہ کیسے کام کرتی ہے؟ / How it works',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () => CustomerSupportHelper.openWhatsAppSupport(context),
            icon: const Icon(Icons.support_agent_rounded, size: 18),
            label: const Text('مدد / Help'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.divider,
              foregroundColor: AppColors.primaryText,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.softGlassBorder.withValues(alpha: 0.62),
        ),
      ),
      child: child,
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.icon, required this.urdu});

  final IconData icon;
  final String urdu;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryText, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              urdu,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 20,
                fontFamily: 'JameelNoori',
                height: 1.05,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowStepRow extends StatelessWidget {
  const _HowStepRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryText, size: 15),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JameelNoori',
                color: AppColors.primaryText,
                fontSize: 19,
                height: 1.04,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DigitalOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()
      ..color = AppColors.primaryText.withValues(alpha: 0.05)
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    const double spacing = 28;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final Paint nodePaint = Paint()..style = PaintingStyle.fill;

    final List<Offset> nodes = <Offset>[
      Offset(size.width * 0.15, size.height * 0.20),
      Offset(size.width * 0.78, size.height * 0.18),
      Offset(size.width * 0.30, size.height * 0.52),
      Offset(size.width * 0.66, size.height * 0.60),
      Offset(size.width * 0.48, size.height * 0.78),
    ];

    for (int i = 0; i < nodes.length; i++) {
      final Offset center = nodes[i];
      nodePaint.color = AppColors.accentGold.withValues(alpha: 0.09);
      canvas.drawCircle(center, 7, nodePaint);

      nodePaint.color = AppColors.primaryText.withValues(alpha: 0.18);
      canvas.drawCircle(center, 1.6, nodePaint);
    }

    final Paint circuitPaint = Paint()
      ..color = AppColors.accentGold.withValues(alpha: 0.06)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final Path p = Path()
      ..moveTo(size.width * 0.08, size.height * 0.28)
      ..lineTo(size.width * 0.26, size.height * 0.28)
      ..lineTo(size.width * 0.26, size.height * 0.40)
      ..lineTo(size.width * 0.40, size.height * 0.40)
      ..moveTo(size.width * 0.62, size.height * 0.64)
      ..lineTo(size.width * 0.82, size.height * 0.64)
      ..lineTo(size.width * 0.82, size.height * 0.76);

    canvas.drawPath(p, circuitPaint);
  }

  @override
  bool shouldRepaint(covariant _DigitalOverlayPainter oldDelegate) => false;
}
