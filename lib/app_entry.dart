import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth/auth_wrapper.dart';
import 'dashboard/buyer/buyer_dashboard.dart';
import 'dashboard/seller/seller_dashboard.dart';
import 'auth/verification_pending_screen.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // 1. Loading State
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF011A0A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          );
        }

        // 2. Not Logged In -> Welcome Screen
        if (!snapshot.hasData) {
          return const AuthWrapper();
        }

        // 3. Logged In -> Check Firestore for Role
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF011A0A),
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              );
            }

            // User document doesn't exist yet -> return to auth
            if (!userSnap.hasData || !userSnap.data!.exists) {
              return const AuthWrapper();
            }

            // Extract User Data
            var userData = userSnap.data!.data() as Map<String, dynamic>;
            String role =
                (userData['userRole'] ??
                        userData['role'] ??
                        userData['userType'] ??
                        '')
                    .toString()
                    .trim()
                    .toLowerCase();
            bool isApproved = userData['isApproved'] ?? false;

            // 4. Role-Based Routing
            if (role == 'buyer') {
              // �S& FIX: BuyerDashboard ko userData pass kar diya aur 'const' hata diya
              return BuyerDashboard(userData: userData);
            } else if (role == 'seller' || role == 'arhat') {
              final String verificationStatus =
                  (userData['verificationStatus'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
              final bool isVerified =
                  userData['is_verified'] == true ||
                  userData['isVerified'] == true;
              if (!isApproved && role == 'arhat') {
                return const VerificationPendingScreen();
              }
              if (!isVerified || verificationStatus == 'pending_review') {
                return const VerificationPendingScreen();
              }
              return SellerDashboard(userData: userData);
            }

            return const AuthWrapper();
          },
        );
      },
    );
  }
}
