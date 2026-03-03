import 'package:flutter/material.dart';

import 'login_screen.dart';
import '../routes.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) => LoginScreen(
      onGoSignup: () => Navigator.pushNamed(context, Routes.signup),
      );
}

