import 'package:flutter/material.dart';
import 'dart:async';

import '../routes.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    this.autoNavigate = false,
    this.nextRoute = Routes.signIn,
  });

  final bool autoNavigate;
  final String nextRoute;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 3), () {
      if (!mounted || _navigated) return;
      _navigated = true;
      Navigator.pushReplacementNamed(context, '/login');
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static const Color _darkGreen = Color(0xFF004D40);
  static const Color _gold = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _darkGreen,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 150,
              width: 150,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.28),
                    blurRadius: 28,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Image.asset(
                'assets/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.agriculture_rounded,
                    size: 90,
                    color: _darkGreen,
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Digital Arhat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

