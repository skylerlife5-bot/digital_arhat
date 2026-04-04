import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../routes.dart';
import 'auth_service.dart';

class SessionService {
  SessionService._();

  static Future<void> logoutToLogin(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    await AuthService().clearPersistedSessionUid();
    if (!context.mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.welcome, (route) => false);
  }
}
