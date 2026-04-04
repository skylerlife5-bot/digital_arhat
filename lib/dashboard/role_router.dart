import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/auth_state.dart';
import '../auth/auth_wrapper.dart';
import '../auth/verification_pending_screen.dart';
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

        final User? user = authSnap.data;
        if (user == null) {
          AuthState.clearSelectedRoleCache();
          debugPrint('[ROLE_ROUTER] uid=');
          debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
          return const AuthWrapper();
        }

        return FutureBuilder<_RouteDecision>(
          future: _resolveDecision(user),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const _LoadingScreen(label: 'Role resolve ho rahi hai...');
            }

            if (snap.hasError) {
              debugPrint('[ROLE_ROUTER] uid=${user.uid}');
              debugPrint('[ROLE_ROUTER] error=${snap.error}');
              debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
              return const AuthWrapper();
            }

            final _RouteDecision decision =
                snap.data ?? const _RouteDecision(route: _ResolvedRoute.fallback);

            switch (decision.route) {
              case _ResolvedRoute.admin:
                AuthState.setSelectedRole('admin');
                return const AdminDashboard(key: ValueKey('admin-dashboard'));
              case _ResolvedRoute.seller:
                AuthState.setSelectedRole('seller');
                return SellerDashboard(
                  key: const ValueKey('seller-dashboard'),
                  userData: decision.userData,
                );
              case _ResolvedRoute.user:
                AuthState.setSelectedRole('buyer');
                return BuyerDashboard(
                  key: const ValueKey('user-dashboard'),
                  userData: decision.userData,
                );
              case _ResolvedRoute.buyer:
                AuthState.setSelectedRole('buyer');
                return BuyerDashboard(
                  key: const ValueKey('buyer-dashboard'),
                  userData: decision.userData,
                );
              case _ResolvedRoute.verificationPending:
                return const VerificationPendingScreen(
                  key: ValueKey('phone-auth-unverified-block'),
                );
              case _ResolvedRoute.fallback:
                return const AuthWrapper();
            }
          },
        );
      },
    );
  }

  Future<_RouteDecision> _resolveDecision(User user) async {
    final String uid = user.uid.trim();
    debugPrint('[ROLE_ROUTER] uid=$uid');

    if (uid.isEmpty) {
      debugPrint('[ROLE_ROUTER] usersDocExists=false');
      debugPrint('[ROLE_ROUTER] users.role=');
      debugPrint('[ROLE_ROUTER] users.userRole=');
      debugPrint('[ROLE_ROUTER] users.userType=');
      debugPrint('[ROLE_ROUTER] adminsDocExists=false');
      debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
      return const _RouteDecision(route: _ResolvedRoute.fallback);
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> userSnap = await FirebaseFirestore
          .instance
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));

      final bool usersDocExists = userSnap.exists;
      final Map<String, dynamic> data = userSnap.data() ?? <String, dynamic>{};
      final String usersRole = (data['role'] ?? '').toString().trim().toLowerCase();
      final String usersUserRole =
          (data['userRole'] ?? '').toString().trim().toLowerCase();
      final String usersUserType =
          (data['userType'] ?? '').toString().trim().toLowerCase();

      debugPrint('[ROLE_ROUTER] usersDocExists=$usersDocExists');
      debugPrint('[ROLE_ROUTER] users.role=$usersRole');
      debugPrint('[ROLE_ROUTER] users.userRole=$usersUserRole');
      debugPrint('[ROLE_ROUTER] users.userType=$usersUserType');

      if (!usersDocExists) {
        debugPrint('[ROLE_ROUTER] adminsDocExists=false');
        debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
        return const _RouteDecision(route: _ResolvedRoute.fallback);
      }

      final bool isPhoneAuthSession = (user.phoneNumber ?? '').trim().isNotEmpty;
      final bool otpVerified =
          data['is_verified'] == true || data['isVerified'] == true || data['phoneVerified'] == true;
      if (isPhoneAuthSession && !otpVerified) {
        debugPrint('[ROLE_ROUTER] adminsDocExists=false');
        debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
        return _RouteDecision(route: _ResolvedRoute.verificationPending, userData: data);
      }

      // STEP C: users doc admin indicators get immediate precedence.
      if (usersRole == 'admin' || usersUserRole == 'admin' || usersUserType == 'admin') {
        debugPrint('[ROLE_ROUTER] adminsDocExists=false');
        debugPrint('[ROLE_ROUTER] resolvedRoute=admin');
        return _RouteDecision(route: _ResolvedRoute.admin, userData: data);
      }

      // STEP D: admins lookup only when users doc is not clearly admin.
      bool adminsDocExists = false;
      try {
        final DocumentSnapshot<Map<String, dynamic>> adminSnap = await FirebaseFirestore
            .instance
            .collection('admins')
            .doc(uid)
            .get()
            .timeout(const Duration(seconds: 4));
        adminsDocExists = adminSnap.exists;
        final Map<String, dynamic> adminData = adminSnap.data() ?? <String, dynamic>{};
        final bool isActive = adminData['isActive'] == true;

        debugPrint('[ROLE_ROUTER] adminsDocExists=$adminsDocExists');
        if (adminsDocExists && isActive) {
          debugPrint('[ROLE_ROUTER] resolvedRoute=admin');
          return _RouteDecision(route: _ResolvedRoute.admin, userData: data);
        }
      } catch (error) {
        debugPrint('[ROLE_ROUTER] adminsDocExists=false');
        debugPrint('[ROLE_ROUTER] error=$error');
      }

      // STEP E: normal role resolution.
      final String resolvedRole = _resolveUserRoleOrdered(data);
      if (resolvedRole == 'seller' || resolvedRole == 'arhat') {
        debugPrint('[ROLE_ROUTER] resolvedRoute=seller');
        return _RouteDecision(route: _ResolvedRoute.seller, userData: data);
      }
      if (resolvedRole == 'buyer') {
        debugPrint('[ROLE_ROUTER] resolvedRoute=buyer');
        return _RouteDecision(route: _ResolvedRoute.buyer, userData: data);
      }
      if (resolvedRole == 'user') {
        debugPrint('[ROLE_ROUTER] resolvedRoute=user');
        return _RouteDecision(route: _ResolvedRoute.user, userData: data);
      }

      // STEP F: unknown role -> safe fallback.
      debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
      return _RouteDecision(route: _ResolvedRoute.fallback, userData: data);
    } on TimeoutException catch (error) {
      debugPrint('[ROLE_ROUTER] usersDocExists=false');
      debugPrint('[ROLE_ROUTER] users.role=');
      debugPrint('[ROLE_ROUTER] users.userRole=');
      debugPrint('[ROLE_ROUTER] users.userType=');
      debugPrint('[ROLE_ROUTER] adminsDocExists=false');
      debugPrint('[ROLE_ROUTER] error=$error');
      debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
      return const _RouteDecision(route: _ResolvedRoute.fallback);
    } catch (error) {
      debugPrint('[ROLE_ROUTER] usersDocExists=false');
      debugPrint('[ROLE_ROUTER] users.role=');
      debugPrint('[ROLE_ROUTER] users.userRole=');
      debugPrint('[ROLE_ROUTER] users.userType=');
      debugPrint('[ROLE_ROUTER] adminsDocExists=false');
      debugPrint('[ROLE_ROUTER] error=$error');
      debugPrint('[ROLE_ROUTER] resolvedRoute=fallback');
      return const _RouteDecision(route: _ResolvedRoute.fallback);
    }
  }

  String _resolveUserRoleOrdered(Map<String, dynamic> data) {
    final String role = (data['role'] ?? '').toString().trim().toLowerCase();
    if (role.isNotEmpty) return role;
    final String userRole = (data['userRole'] ?? '').toString().trim().toLowerCase();
    if (userRole.isNotEmpty) return userRole;
    final String userType = (data['userType'] ?? '').toString().trim().toLowerCase();
    if (userType.isNotEmpty) return userType;
    return '';
  }
}

enum _ResolvedRoute { admin, user, seller, buyer, verificationPending, fallback }

class _RouteDecision {
  const _RouteDecision({required this.route, this.userData = const <String, dynamic>{}});

  final _ResolvedRoute route;
  final Map<String, dynamic> userData;
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
