import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/widgets/glass_button.dart';
import '../dashboard/role_router.dart';
import '../routes.dart';
import '../services/startup_bootstrap_service.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const Color _deepGreen = Color(0xFF004D40);
  static const Color _agriGold = Color(0xFFFFD54F);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRedirecting = false;
  bool _offlineSnackShown = false;

  @override
  void initState() {
    super.initState();
    StartupBootstrapService.instance.state.addListener(_onStartupStateChanged);
    unawaited(StartupBootstrapService.instance.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onStartupStateChanged();
    });
  }

  @override
  void dispose() {
    StartupBootstrapService.instance.state.removeListener(
      _onStartupStateChanged,
    );
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onStartupStateChanged() {
    if (!mounted) return;

    final startupState = StartupBootstrapService.instance.state.value;

    if (startupState == StartupBootstrapState.failed && !_offlineSnackShown) {
      _offlineSnackShown = true;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
          content: Text('Working in Offline Mode'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (startupState == StartupBootstrapState.ready) {
      _maybeRedirectToDashboard();
    }
  }

  void _maybeRedirectToDashboard() {
    if (!mounted || _isRedirecting) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _isRedirecting = true;
    Navigator.of(context).pushReplacement(_buildFadeRoute(const RoleRouter()));
  }

  PageRouteBuilder<void> _buildFadeRoute(Widget child) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 350),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) => child,
      transitionsBuilder: (context, animation, secondaryAnimation, page) {
        return FadeTransition(opacity: animation, child: page);
      },
    );
  }

  Future<void> _signIn() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      if (StartupBootstrapService.instance.state.value ==
          StartupBootstrapState.initializing) {
        await StartupBootstrapService.instance.start();
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      _isRedirecting = true;
      Navigator.of(context).pushAndRemoveUntil(
        _buildFadeRoute(const RoleRouter()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text(e.message ?? 'Sign in failed.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Unable to sign in right now.')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: _agriGold),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.09),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _agriGold.withValues(alpha: 0.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _agriGold, width: 1.6),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepGreen,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Digital Arhat',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Welcome back',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _agriGold.withValues(alpha: 0.95),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration(
                        label: 'Email',
                        icon: Icons.email_outlined,
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Email is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decoration(
                        label: 'Password',
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(
                              () => _obscurePassword = !_obscurePassword,
                            );
                          },
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return 'Password is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 22),
                    GlassButton(
                      label: 'Sign In',
                      onPressed: _isLoading ? null : _signIn,
                      loading: _isLoading,
                      height: 50,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, Routes.signup),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _agriGold,
                          side: const BorderSide(color: _agriGold),
                        ),
                        child: const Text(
                          'Sign Up',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

