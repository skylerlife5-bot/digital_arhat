import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../services/auth_service.dart';
import '../routes.dart';

/// Shown only when a phone-auth session exists but OTP/phone verification
/// has not yet been recorded in the user Firestore profile.
/// NOT used for seller admin-approval pending - that state is communicated
/// via a lightweight banner inside the seller dashboard.
class VerificationPendingScreen extends StatelessWidget {
  const VerificationPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
              const Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'تصدیق جاری ہے',
                  style: TextStyle(
                    fontSize: 32,
                    fontFamily: 'JameelNoori',
                    color: Color(0xFFFFD700),
                  ),
                ),
              ),
              const SizedBox(height: 15),
              const Directionality(
                textDirection: TextDirection.rtl,
                child: Text(
                  'آپ کی فراہم کردہ معلومات کی جانچ کی جا رہی ہے۔ تصدیق مکمل ہوتے ہی آپ کو اطلاع دی جائے گی۔',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontFamily: 'JameelNoori',
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 50),
              _buildStatusCard(),
              const SizedBox(height: 60),
              _buildLogoutButton(context),
            ],
          ),
        ),
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
              'Phone Verification: Pending',
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
          await AuthService().clearPersistedSessionUid();
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
          'لاگ آؤٹ کریں / Logout',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontFamily: 'JameelNoori',
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
}
