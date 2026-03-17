import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../routes.dart';

class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Dark Green theme background
      backgroundColor: const Color(0xFF011A0A),
      body: Stack(
        children: [
          // Background subtle pattern
          Opacity(
            opacity: 0.05,
            child: Container(
              decoration: const BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/images/circuit_pattern.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),

          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Animated Clock/Time Icon to show "Pending"
                  Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFFD700).withValues(alpha: 0.1),
                        ),
                        child: const Icon(
                          Icons.history_toggle_off_rounded,
                          size: 100,
                          color: Color(0xFFFFD700),
                        ),
                      )
                      .animate(onPlay: (controller) => controller.repeat())
                      .shimmer(duration: 2.seconds, color: Colors.white30)
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.05, 1.05),
                        curve: Curves.easeInOut,
                      ),

                  const SizedBox(height: 40),

                  // Urdu Title
                  const Text(
                    "تصد�R� جار�R ہ�",
                    style: TextStyle(
                      fontSize: 32,
                      fontFamily: 'Jameel Noori',
                      color: Color(0xFFFFD700),
                    ),
                  ).animate().fadeIn(duration: 800.ms).slideY(begin: 0.3),

                  const SizedBox(height: 15),

                  // Description
                  const Text(
                    "آپ ک�R فراہ�& کردہ �&ع����&ات ک�R جا� �  پ�تا� ک�R جا رہ�R ہ�� تصد�R� �&ک�&� ہ��ت� ہ�R آپ ک�� اط�اع د� د�R جائ� گ�R�",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontFamily: 'Jameel Noori',
                      height: 1.5,
                    ),
                  ).animate().fadeIn(delay: 400.ms),

                  const SizedBox(height: 50),

                  // Status Card
                  _buildStatusCard(),

                  const SizedBox(height: 60),

                  // Logout Button
                  _buildLogoutButton(context),

                  const SizedBox(height: 20),

                  // Dev Access (Discreet)
                  _buildDevButton(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFFFD700),
            ),
          ),
          SizedBox(width: 15),
          Expanded(
            child: Text(
              "Admin Verification: Pending",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 13,
                letterSpacing: 1,
              ),
            ),
          ),
        ],
      ),
    ).animate().slideX(begin: -0.1);
  }

  Widget _buildLogoutButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: () async {
          await FirebaseAuth.instance.signOut();
          if (!context.mounted) return;
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
        },
        icon: const Icon(
          Icons.logout_rounded,
          color: Colors.redAccent,
          size: 20,
        ),
        label: const Text(
          "�اگ آؤٹ کر�Rں / Logout",
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 15),
          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildDevButton(BuildContext context) {
    return Opacity(
      opacity: 0.5,
      child: TextButton(
        onPressed: () {
          Navigator.pushReplacementNamed(context, Routes.buyerDashboard);
        },
        child: const Text(
          "Continue to Dashboard (Testing)",
          style: TextStyle(
            color: Colors.white38,
            fontSize: 12,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}
