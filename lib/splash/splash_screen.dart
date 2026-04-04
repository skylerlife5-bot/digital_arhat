import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/assets.dart';
import '../core/widgets/customer_support_button.dart';
import '../routes.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  static const Color _greenDeep = Color(0xFF0B2F26);
  static const Color _greenBase = Color(0xFF0E3B2E);
  static const Color _greenMid = Color(0xFF145A41);
  static const Color _greenLift = Color(0xFF1F7A5A);

  static const Color _goldBase = Color(0xFFC9A646);
  static const Color _goldLight = Color(0xFFE4C46A);
  static const Color _goldDeep = Color(0xFFA3832A);

  static const Color _textWhite = Color(0xFFFFFFFF);
  static const Color _textSoft = Color(0xFFEAF6EE);
  static const Color _textMint = Color(0xFFB7D3C0);

  Future<void> _showHowItWorksSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        _greenMid.withValues(alpha: 0.9),
                        _greenBase.withValues(alpha: 0.93),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: _textMint.withValues(alpha: 0.25),
                    ),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const <Widget>[
                      Text(
                        'ڈیجیٹل آرہت کیسے کام کرتی ہے؟',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'JameelNoori',
                          color: _textSoft,
                          fontSize: 23,
                          height: 1.04,
                        ),
                      ),
                      SizedBox(height: 8),
                      _HowStepRow(
                        icon: Icons.fact_check_rounded,
                        text:
                            '1) فروخت کنندہ اپنی فصل یا مال کی لسٹنگ لگاتا ہے',
                      ),
                      SizedBox(height: 7),
                      _HowStepRow(
                        icon: Icons.gavel_rounded,
                        text: '2) ایڈمن لسٹنگ کو چیک کر کے منظور کرتا ہے',
                      ),
                      SizedBox(height: 7),
                      _HowStepRow(
                        icon: Icons.lock_clock_rounded,
                        text: '3) خریدار اس پر بولی لگاتے ہیں',
                      ),
                      SizedBox(height: 7),
                      _HowStepRow(
                        icon: Icons.local_shipping_rounded,
                        text: '4) فروخت کنندہ ایک بولی قبول کرتا ہے',
                      ),
                      SizedBox(height: 7),
                      _HowStepRow(
                        icon: Icons.connect_without_contact_rounded,
                        text:
                            '5) قبول ہونے کے بعد خریدار اور فروخت کنندہ کا رابطہ کھل جاتا ہے',
                      ),
                      SizedBox(height: 7),
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
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[_greenLift, _greenMid, _greenBase, _greenDeep],
              ),
            ),
            child: const SizedBox.expand(),
          ),
          Opacity(
            opacity: 0.03,
            child: CustomPaint(
              painter: _DigitalOverlayPainter(),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0.015,
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
                final bool compact = constraints.maxHeight < 760;
                final double sectionGap = compact ? 8 : 10;
                final double titleSize = compact ? 17 : 19;
                final double urduTitleSize = compact ? 24 : 28;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(14, compact ? 8 : 10, 14, 10),
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
                                SizedBox(height: compact ? 6 : 8),
                                Text(
                                  'Digital Aarhat',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.poppins(
                                    color: _textSoft,
                                    fontSize: titleSize,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                Text(
                                  'ڈیجیٹل آڑھت',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: _textWhite,
                                    fontSize: urduTitleSize,
                                    height: 1.06,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'کسان کی ترقی، پاکستان کی خوشحالی',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: _textSoft,
                                    fontSize: compact ? 19 : 21,
                                    height: 1.07,
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
                                    color: _goldLight,
                                    fontSize: compact ? 17 : 19,
                                    fontWeight: FontWeight.w700,
                                    height: 1.28,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'ناپ اور تول انصاف کے ساتھ پورا کرو',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: _textWhite,
                                    fontSize: compact ? 18 : 20,
                                    height: 1.08,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                const Text(
                                  'سورۃ الانعام 6:152',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'JameelNoori',
                                    color: _textMint,
                                    fontSize: 13,
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
                          SizedBox(height: compact ? 7 : 9),
                          const Text(
                            'پاکستان کی ڈیجیٹل منڈی',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _textMint,
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          SizedBox(height: compact ? 8 : 10),
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
        width: compact ? 116 : 130,
        height: compact ? 116 : 130,
        child: Image.asset(
          AppAssets.logoPath,
          fit: BoxFit.contain,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stackTrace) {
                return const Center(
                  child: Icon(
                    Icons.agriculture_rounded,
                    color: _textSoft,
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
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[_goldLight, _goldBase, _goldDeep],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33291D05),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
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
                foregroundColor: _greenDeep,
                shadowColor: Colors.transparent,
                minimumSize: const Size.fromHeight(49),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'منڈی دیکھیں / Explore Mandi',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  letterSpacing: 0.15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushNamed(Routes.login);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textSoft,
              side: BorderSide(color: _textMint.withValues(alpha: 0.36)),
              minimumSize: const Size.fromHeight(48),
              backgroundColor: _greenBase.withValues(alpha: 0.24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'لاگ اِن / Login',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () {
              Navigator.of(context).pushNamed(Routes.createAccount);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textSoft,
              side: BorderSide(color: _textMint.withValues(alpha: 0.36)),
              minimumSize: const Size.fromHeight(48),
              backgroundColor: _greenBase.withValues(alpha: 0.24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'اکاؤنٹ بنائیں / Create Account',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _showHowItWorksSheet,
            style: TextButton.styleFrom(
              foregroundColor: _textMint,
              minimumSize: const Size.fromHeight(32),
            ),
            child: Text(
              'یہ کیسے کام کرتی ہے؟ / How it works',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: () => CustomerSupportHelper.openWhatsAppSupport(context),
            icon: const Icon(Icons.support_agent_rounded, size: 18),
            label: const Text('مدد / Help'),
            style: FilledButton.styleFrom(
              backgroundColor: _greenMid.withValues(alpha: 0.45),
              foregroundColor: _textSoft,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(color: _textMint.withValues(alpha: 0.3)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _WelcomeScreenState._greenBase.withValues(alpha: 0.45),
            _WelcomeScreenState._greenDeep.withValues(alpha: 0.58),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: _WelcomeScreenState._textMint.withValues(alpha: 0.25),
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x17000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
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
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: _WelcomeScreenState._goldBase.withValues(alpha: 0.24),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _WelcomeScreenState._textSoft, size: 15),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              urdu,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: _WelcomeScreenState._textSoft,
                fontSize: 19,
                fontFamily: 'JameelNoori',
                height: 1.08,
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
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _WelcomeScreenState._goldBase.withValues(alpha: 0.22),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: _WelcomeScreenState._textSoft, size: 14),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontFamily: 'JameelNoori',
                color: _WelcomeScreenState._textSoft,
                fontSize: 18,
                height: 1.08,
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
      ..color = _WelcomeScreenState._textMint.withValues(alpha: 0.08)
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
      nodePaint.color = _WelcomeScreenState._goldBase.withValues(alpha: 0.12);
      canvas.drawCircle(center, 7, nodePaint);

      nodePaint.color = _WelcomeScreenState._textSoft.withValues(alpha: 0.2);
      canvas.drawCircle(center, 1.6, nodePaint);
    }

    final Paint circuitPaint = Paint()
      ..color = _WelcomeScreenState._goldDeep.withValues(alpha: 0.13)
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
