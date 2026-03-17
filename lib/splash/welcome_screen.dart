import 'dart:math';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/phone_sign_in_screen.dart';
import '../dashboard/role_router.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _darkGreen = Color(0xFF062612);
  static const Color _royalGold = Color(0xFFD4AF37);

  late final AnimationController _bgController;
  bool _pulseUp = true;

  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  void _enterMandi() {
    final user = FirebaseAuth.instance.currentUser;
    final Widget destination = user == null
        ? const PhoneSignInScreen()
        : const RoleRouter();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 420),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (context, animation, secondaryAnimation) {
          return ColoredBox(color: _darkGreen, child: destination);
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkGreen,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _bgController,
                builder: (context, child) {
                  return CustomPaint(
                    painter: _AiGlowPainter(progress: _bgController.value),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                child: Column(
                  children: [
                    Text(
                      'Insaaf ke saath naap tol poori karo',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: _royalGold,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Imandari, bharosa aur shaffaf tijarat ka nizam',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: _pulseUp ? 1.0 : 1.05,
                        end: _pulseUp ? 1.05 : 1.0,
                      ),
                      duration: const Duration(milliseconds: 2500),
                      onEnd: () {
                        if (!mounted) return;
                        setState(() => _pulseUp = !_pulseUp);
                      },
                      builder: (context, scale, child) {
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Image.asset(
                          'assets/logo.png',
                          height: 118,
                          fit: BoxFit.contain,
                          colorBlendMode: BlendMode.dstIn,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Welcome - Jee Aya Nu',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: _royalGold,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Digital Arhat Mandi App',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: SizedBox(
                          width: double.infinity,
                          height: 58,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: _royalGold.withValues(alpha: 0.46),
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(18),
                                onTap: _enterMandi,
                                child: Center(
                                  child: Text(
                                    'Mandi Mein Shamil Hon',
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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

class _AiGlowPainter extends CustomPainter {
  const _AiGlowPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF6FE8D9).withValues(alpha: 0.12);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0xFFFFD700).withValues(alpha: 0.14);

    final points = <Offset>[];
    const rows = 4;
    const cols = 6;
    final drift = sin(progress * pi * 2) * 8;

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final dx = (size.width / (cols + 1)) * (c + 1) + (r.isEven ? drift : -drift);
        final dy = (size.height / (rows + 1)) * (r + 1);
        final offset = Offset(dx, dy);
        points.add(offset);
        canvas.drawCircle(offset, 2.4, glowPaint);
      }
    }

    for (var i = 0; i < points.length - 1; i++) {
      if (i % 2 == 0) {
        canvas.drawLine(points[i], points[i + 1], linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _AiGlowPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
