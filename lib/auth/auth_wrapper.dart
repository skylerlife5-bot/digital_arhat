import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../dashboard/admin/admin_dashboard.dart';
import '../dashboard/buyer/buyer_dashboard.dart';
import '../dashboard/seller/seller_dashboard.dart';
import '../services/admin_access_service.dart';
import '../services/auth_service.dart';
import '../splash/splash_screen.dart';
import 'auth_state.dart';
import 'verification_pending_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  final AuthService _authService = AuthService();
  final AdminAccessService _adminAccessService = AdminAccessService();

  Widget _buildUserRoleGate({
    required String uid,
    required bool isPhoneAuthSession,
  }) {
    debugPrint(
      '[AUTH_WRAPPER] firebaseAuthUid=${FirebaseAuth.instance.currentUser?.uid ?? ''} gateUid=$uid',
    );
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnap) {
        if (userSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!userSnap.hasData || !(userSnap.data?.exists ?? false)) {
          unawaited(_authService.clearPersistedSessionUid());
          AuthState.clearSelectedRoleCache();
          debugPrint('[AUTH_WRAPPER] uid=$uid usersDocMissing route=welcome');
          return const WelcomeScreen();
        }

        final data = userSnap.data?.data() ?? const <String, dynamic>{};
        final String usersRoleField = (data['role'] ?? '').toString().trim().toLowerCase();
        final String usersUserRoleField = (data['userRole'] ?? '').toString().trim().toLowerCase();
        final String usersUserTypeField = (data['userType'] ?? '').toString().trim().toLowerCase();
        final String userRole =
            (data['role'] ?? data['userRole'] ?? data['userType'] ?? 'buyer')
                .toString()
                .trim()
                .toLowerCase();
        debugPrint(
          '[AUTH_WRAPPER] usersDocId=${userSnap.data?.id ?? uid} role=$usersRoleField userRole=$usersUserRoleField userType=$usersUserTypeField resolvedUsersRole=$userRole',
        );
        final bool otpVerified =
            data['is_verified'] == true ||
            data['isVerified'] == true ||
            data['phoneVerified'] == true;
        if (isPhoneAuthSession && !otpVerified) {
          debugPrint('[AUTH_WRAPPER] uid=$uid finalRoute=verification_pending');
          return const VerificationPendingScreen();
        }

        return FutureBuilder<bool>(
          future: _adminAccessService.isAdminUser(uid),
          builder: (context, adminSnap) {
            if (adminSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final bool isAdmin = adminSnap.data == true;
            debugPrint(
              '[AUTH_WRAPPER] uid=$uid adminsLookupComplete=true isAdmin=$isAdmin',
            );
              // Primary: admins collection. Fallback: users doc role.
                // Fallback required when Firebase auth is null (custom login) and
              // admins/{uid} returns permission-denied.
              final bool isAdminByService = adminSnap.data == true;
              final bool isAdminByUsersRole = userRole == 'admin';
                final bool isAdmin2 = isAdminByService || isAdminByUsersRole;
              debugPrint(
                  '[AUTH_WRAPPER] uid=$uid adminsLookupComplete=true isAdminByService=$isAdminByService isAdminByUsersRole=$isAdminByUsersRole isAdmin=$isAdmin2',
              );

                if (isAdmin2) {
              AuthState.setSelectedRole('admin');
              debugPrint('[AUTH_WRAPPER] uid=$uid finalRoute=admin_dashboard');
              return const AdminDashboard();
            }

            if (userRole == 'seller' || userRole == 'arhat') {
              AuthState.setSelectedRole('seller');
              debugPrint('[AUTH_WRAPPER] uid=$uid finalRoute=seller_dashboard');
              return SellerDashboard(userData: data);
            }

            AuthState.setSelectedRole('buyer');
            debugPrint('[AUTH_WRAPPER] uid=$uid finalRoute=buyer_dashboard');
            return BuyerDashboard(userData: data);
          },
        );
      },
    );
  }

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
          AuthState.clearSelectedRoleCache();
          return FutureBuilder<String?>(
            future: _authService.getPersistedSessionUid(),
            builder: (context, sessionSnap) {
              if (sessionSnap.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              final String sessionUid = (sessionSnap.data ?? '').trim();
              if (sessionUid.isEmpty) {
                debugPrint('[AUTH_WRAPPER] firebaseAuthUid=empty persistedUid=empty route=welcome');
                return const WelcomeScreen();
              }

              debugPrint('[AUTH_WRAPPER] persistedUid=$sessionUid');

              return FutureBuilder<bool>(
                future: _authService.restoreFirebaseSessionForUid(
                  sessionUid,
                  flowLabel: 'auth_wrapper_persisted_uid',
                ),
                builder: (context, restoreSnap) {
                  if (restoreSnap.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }

                  final bool firebaseRestored = restoreSnap.data == true;
                  final String firebaseUid =
                      (FirebaseAuth.instance.currentUser?.uid ?? '').trim();
                  final bool customSessionValid =
                      firebaseRestored &&
                      firebaseUid.isNotEmpty &&
                      firebaseUid == sessionUid;
                  final bool requestAuthMismatchSuspected =
                      firebaseUid.isEmpty || firebaseUid != sessionUid;
                  debugPrint('[PROD_AUTH] currentFirebaseUid=$firebaseUid');
                  debugPrint('[PROD_AUTH] persistedUid=$sessionUid');
                  debugPrint('[PROD_AUTH] customSessionValid=$customSessionValid');
                  debugPrint(
                    '[PROD_AUTH] requestAuthMismatchSuspected=$requestAuthMismatchSuspected',
                  );
                  debugPrint('[AUTH_WRAPPER] firebaseUid=$firebaseUid');
                  debugPrint('[AUTH_WRAPPER] customSessionValid=$customSessionValid');
                  debugPrint('[AUTH_WRAPPER] firebaseRestore=$firebaseRestored');
                  if (!customSessionValid) {
                    unawaited(_authService.clearPersistedSessionUid());
                    AuthState.clearSelectedRoleCache();
                    debugPrint('[AUTH_WRAPPER] finalRoute=welcome_auth_mismatch');
                    return const WelcomeScreen();
                  }
                  debugPrint('[AUTH_WRAPPER] finalRoute=role_gate');

                  return _buildUserRoleGate(
                    uid: sessionUid,
                    isPhoneAuthSession: false,
                  );
                },
              );
            },
          );
        }

        debugPrint('[AUTH_WRAPPER] firebaseAuthUid=${user.uid} route=role_gate');
        return _buildUserRoleGate(
          uid: user.uid,
          isPhoneAuthSession: (user.phoneNumber ?? '').trim().isNotEmpty,
        );
      },
    );
  }
}
