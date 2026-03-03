import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_wrapper.dart';
import 'admin/admin_dashboard.dart';
import 'buyer/buyer_dashboard.dart';
import 'seller/seller_dashboard.dart';

class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  static const Color _bg = Color(0xFF004D40);
  static const Color _gold = Color(0xFFFFD700);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen(label: 'Session restore ho rahi hai...');
        }

        final user = authSnap.data;
        if (user == null) {
          return const AuthWrapper();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen(label: 'Digital Arhat profile load ho rahi hai...');
            }

            if (userSnap.hasError) {
              return const _LoadingScreen(label: 'Profile sync issue... retry ho raha hai.');
            }

            final data = userSnap.data?.data() ?? <String, dynamic>{};
            final isAdmin = _isAdmin(data);
            if (isAdmin) {
              return const AdminDashboard(key: ValueKey('admin-dashboard'));
            }

            final role = _resolveUserRole(data);
            if (role == 'seller') {
              return SellerDashboard(
                key: const ValueKey('seller-dashboard'),
                userData: data,
              );
            }

            if (role == 'buyer') {
              return BuyerDashboard(
                key: const ValueKey('buyer-dashboard'),
                userData: data,
              );
            }

            return const AuthWrapper();
          },
        );
      },
    );
  }

  String _resolveUserRole(Map<String, dynamic> data) {
    return (data['userRole'] ?? data['role'] ?? data['userType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
  }

  bool _isAdmin(Map<String, dynamic> data) {
    final role = (data['userRole'] ?? data['role'] ?? data['userType'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return role == 'admin';
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RoleRouter._bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: RoleRouter._gold, strokeWidth: 3),
            const SizedBox(height: 14),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

