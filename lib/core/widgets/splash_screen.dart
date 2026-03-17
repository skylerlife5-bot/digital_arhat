import 'package:flutter/material.dart';

import '../assets.dart';

class DigitalArhatSplashView extends StatelessWidget {
  const DigitalArhatSplashView({super.key, this.onContinue});

  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF002810),
      body: SafeArea(
        child: InkWell(
          onTap: onContinue,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF002810), Color(0xFF0A4A22)],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            child: Column(
              children: [
                const Spacer(),
                Image.asset(
                  AppAssets.splashLogoPath,
                  height: 120,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.agriculture_rounded,
                    size: 72,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Digital Arhat',
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                  ),
                ),
                const Spacer(),
                const Text(
                  'إِ� ��} ا����}�!�} �`ُحِب�ُ ا���&ُ��سِطِ�`� �}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'ب�Rشک ا��ہ ا� صاف کر� � ��ا���ں س� �&حبت کرتا ہ��',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
