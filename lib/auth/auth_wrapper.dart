import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dashboard/admin/admin_dashboard.dart';
import '../dashboard/buyer/buyer_dashboard.dart';
import '../dashboard/seller/seller_dashboard.dart';
import '../splash/splash_screen.dart';
import 'auth_state.dart';
import 'verification_pending_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final user = authSnap.data;
        if (user == null) {
          return const WelcomeScreen();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = userSnap.data?.data() ?? const <String, dynamic>{};
            final role =
                (data['role'] ??
                        data['userRole'] ??
                        data['userType'] ??
                        'buyer')
                    .toString()
                    .trim()
                    .toLowerCase();

            if (role == 'admin') {
              AuthState.setSelectedRole('admin');
              return const AdminDashboard();
            }

            if (role == 'seller') {
              AuthState.setSelectedRole('seller');
              final String verificationStatus =
                  (data['verificationStatus'] ?? '')
                      .toString()
                      .trim()
                      .toLowerCase();
              final bool isVerified =
                  data['is_verified'] == true || data['isVerified'] == true;
              if (!isVerified || verificationStatus == 'pending_review') {
                return const VerificationPendingScreen();
              }
              return SellerDashboard(userData: data);
            }

            AuthState.setSelectedRole('buyer');
            return BuyerDashboard(userData: data);
          },
        );
      },
    );
  }
}
