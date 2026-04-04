import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth/auth_state.dart';
import 'auth/auth_wrapper.dart';
import 'auth/verification_pending_screen.dart';
import 'dashboard/admin/admin_dashboard.dart';
import 'dashboard/buyer/buyer_dashboard.dart';
import 'dashboard/seller/seller_dashboard.dart';
import 'services/admin_access_service.dart';

class AppEntry extends StatelessWidget {
  const AppEntry({super.key});

  static final AdminAccessService _adminAccessService = AdminAccessService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF011A0A),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFFFD700)),
            ),
          );
        }

        if (!snapshot.hasData) {
          AuthState.clearSelectedRoleCache();
          debugPrint('[APP_ENTRY] firebaseAuthUid=empty finalRoute=auth_wrapper');
          return const AuthWrapper();
        }

        final String uid = snapshot.data!.uid;
        debugPrint('[APP_ENTRY] firebaseAuthUid=$uid');

        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(uid).get(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF011A0A),
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              );
            }

            if (!userSnap.hasData || !userSnap.data!.exists) {
              debugPrint('[APP_ENTRY] uid=$uid usersDocMissing finalRoute=auth_wrapper');
              return const AuthWrapper();
            }

            final Map<String, dynamic> userData =
                userSnap.data!.data() ?? <String, dynamic>{};
            final String usersRoleField =
                (userData['role'] ?? '').toString().trim().toLowerCase();
            final String usersUserRoleField =
                (userData['userRole'] ?? '').toString().trim().toLowerCase();
            final String usersUserTypeField =
                (userData['userType'] ?? '').toString().trim().toLowerCase();
            final String role =
                (userData['userRole'] ?? userData['role'] ?? userData['userType'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
            final bool isApproved = userData['isApproved'] == true;

            debugPrint(
              '[APP_ENTRY] usersDocId=${userSnap.data!.id} role=$usersRoleField userRole=$usersUserRoleField userType=$usersUserTypeField resolvedUsersRole=$role',
            );

            return FutureBuilder<bool>(
              future: _adminAccessService.isAdminUser(uid),
              builder: (context, adminSnap) {
                if (adminSnap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    backgroundColor: Color(0xFF011A0A),
                    body: Center(
                      child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                    ),
                  );
                }

                final bool isAdminByService = adminSnap.data == true;
                final bool isAdminByUsersRole = role == 'admin';
                final bool isAdmin = isAdminByService || isAdminByUsersRole;
                debugPrint(
                  '[APP_ENTRY] uid=$uid adminsLookupComplete=true isAdminByService=$isAdminByService isAdminByUsersRole=$isAdminByUsersRole isAdmin=$isAdmin',
                );

                if (isAdmin) {
                  AuthState.setSelectedRole('admin');
                  debugPrint('[APP_ENTRY] uid=$uid finalRoute=admin_dashboard');
                  return const AdminDashboard();
                }

                if (role == 'buyer') {
                  AuthState.setSelectedRole('buyer');
                  debugPrint('[APP_ENTRY] uid=$uid finalRoute=buyer_dashboard');
                  return BuyerDashboard(userData: userData);
                }

                if (role == 'seller' || role == 'arhat') {
                  AuthState.setSelectedRole('seller');
                  final String verificationStatus =
                      (userData['verificationStatus'] ?? '')
                          .toString()
                          .trim()
                          .toLowerCase();
                  if (!isApproved && role == 'arhat') {
                    debugPrint('[APP_ENTRY] uid=$uid finalRoute=verification_pending');
                    return const VerificationPendingScreen();
                  }
                  debugPrint('[APP_ENTRY] uid=$uid finalRoute=seller_dashboard');
                  if (verificationStatus == 'pending_review' ||
                      verificationStatus == 'pending' ||
                      verificationStatus.isEmpty) {
                    return SellerDashboard(userData: userData);
                  }
                  return SellerDashboard(userData: userData);
                }

                debugPrint('[APP_ENTRY] uid=$uid finalRoute=auth_wrapper');
                return const AuthWrapper();
              },
            );
          },
        );
      },
    );
  }
}
