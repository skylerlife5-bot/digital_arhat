import 'dart:async';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:local_auth/local_auth.dart';

import '../core/widgets/glass_button.dart';
import '../dashboard/role_router.dart';
import '../routes.dart';
import '../services/startup_bootstrap_service.dart';
import 'forgot_password_otp.dart';

class PhoneSignInScreen extends StatefulWidget {
  const PhoneSignInScreen({super.key});

  @override
  State<PhoneSignInScreen> createState() => _PhoneSignInScreenState();
}

class _PhoneSignInScreenState extends State<PhoneSignInScreen>
    with SingleTickerProviderStateMixin {
  static const Color _forestTop = Color(0xFF004D40);
  static const Color _emeraldBottom = Color(0xFF00695C);
  static const Color _goldBright = Color(0xFFFFD700);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _passwordController = TextEditingController();
  final LocalAuthentication _localAuth = LocalAuthentication();

  AnimationController? _pulseController;

  String _phoneNumber = '+92';
  String? _verificationId;
  bool _isLoading = false;
  bool _isBiometricLoading = false;
  bool _isPasswordObscured = true;
  bool _isRedirecting = false;
  bool _offlineSnackShown = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    _pulseController?.repeat(reverse: true);

    StartupBootstrapService.instance.state.addListener(_onStartupStateChanged);
    unawaited(StartupBootstrapService.instance.start());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onStartupStateChanged();
    });
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    StartupBootstrapService.instance.state.removeListener(_onStartupStateChanged);
    _passwordController.dispose();
    super.dispose();
  }

  void _onStartupStateChanged() {
    if (!mounted) return;
    final startupState = StartupBootstrapService.instance.state.value;

    if (startupState == StartupBootstrapState.failed && !_offlineSnackShown) {
      _offlineSnackShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Working in Offline Mode'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (startupState == StartupBootstrapState.ready) {
      _maybeRedirectToRoleRouter();
    }
  }

  void _maybeRedirectToRoleRouter() {
    if (!mounted || _isRedirecting) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _isRedirecting = true;
    Navigator.of(context).pushReplacement(_buildFadeRoute(const RoleRouter()));
  }

  PageRouteBuilder<void> _buildFadeRoute(Widget child) {
    return PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 330),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (routeContext, routeAnimation, secondaryAnimation) => child,
      transitionsBuilder: (routeContext, animation, secondaryAnimation, page) {
        return FadeTransition(opacity: animation, child: page);
      },
    );
  }

  Future<void> _startPhoneSignIn() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (StartupBootstrapService.instance.state.value ==
          StartupBootstrapState.initializing) {
        await StartupBootstrapService.instance.start();
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: _phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          await FirebaseAuth.instance.signInWithCredential(credential);
          if (!mounted) return;
          _isRedirecting = true;
          Navigator.of(context).pushAndRemoveUntil(
            _buildFadeRoute(const RoleRouter()),
            (route) => false,
          );
        },
        verificationFailed: (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(error.message ?? 'Phone verification failed.'),
            ),
          );
        },
        codeSent: (verificationId, _) async {
          _verificationId = verificationId;
          if (!mounted) return;
          await _showOtpBottomSheet();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Unable to start sign in right now.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showOtpBottomSheet() async {
    String otpCode = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 14,
            right: 14,
            top: 8,
            bottom: MediaQuery.of(context).viewInsets.bottom + 14,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _goldBright.withValues(alpha: 0.8)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'OTP Darj Karein',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 5,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: '------',
                        hintStyle: GoogleFonts.poppins(color: Colors.white54),
                        counterText: '',
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: _goldBright.withValues(alpha: 0.9),
                            width: 0.9,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _goldBright, width: 1.2),
                        ),
                      ),
                      onChanged: (value) {
                        otpCode = value.trim();
                      },
                    ),
                    const SizedBox(height: 8),
                    GlassButton(
                      label: 'Verify aur Jari Rakhein',
                      onPressed: () async {
                        final verificationId = _verificationId;
                        if (verificationId == null || otpCode.length < 6) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              duration: Duration(seconds: 5),
                              content: Text('Please enter valid OTP.'),
                            ),
                          );
                          return;
                        }

                        try {
                          final credential = PhoneAuthProvider.credential(
                            verificationId: verificationId,
                            smsCode: otpCode,
                          );
                          await FirebaseAuth.instance.signInWithCredential(credential);
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          if (!mounted) return;
                          _isRedirecting = true;
                          Navigator.of(this.context).pushAndRemoveUntil(
                            _buildFadeRoute(const RoleRouter()),
                            (route) => false,
                          );
                        } on FirebaseAuthException catch (e) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 5),
                              content: Text(e.message ?? 'Invalid OTP.'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleBiometricQuickAccess() async {
    if (_isBiometricLoading || _isLoading) return;

    HapticFeedback.lightImpact();
    setState(() => _isBiometricLoading = true);

    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final supported = await _localAuth.isDeviceSupported();

      if (!canCheck || !supported) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text('Biometric authentication is unavailable.'),
          ),
        );
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate for quick secure access',
      );

      if (!mounted || !authenticated) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 5),
            content: Text(
              'Biometric verified. Sign in with phone once to enable instant access.',
            ),
          ),
        );
        return;
      }

      await _navigateToRoleDashboardFromBiometric(user);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Biometric sign in failed. Please retry.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
    }
  }

  Future<void> _navigateToRoleDashboardFromBiometric(User user) async {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final userData = userDoc.data() ?? <String, dynamic>{};

    final role =
        (userData['userRole'] ?? userData['role'] ?? userData['userType'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

    if (!mounted) return;

    if (role == 'admin') {
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.adminDashboard,
        (route) => false,
      );
      return;
    }

    if (role == 'seller' || role == 'arhat') {
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.sellerDashboard,
        (route) => false,
        arguments: userData,
      );
      return;
    }

    Navigator.of(context).pushNamedAndRemoveUntil(
      Routes.buyerDashboard,
      (route) => false,
      arguments: userData,
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: Colors.white70),
      prefixIcon: Icon(icon, color: _goldBright),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _goldBright.withValues(alpha: 0.85), width: 0.9),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _goldBright, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_forestTop, _emeraldBottom],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 108,
                              width: 108,
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _goldBright.withValues(alpha: 0.30),
                                      blurRadius: 24,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: Image.asset(
                                  'assets/logo.png',
                                  height: 96,
                                  width: 96,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Rizq Allah deta hai jise chahe be-hisaab deta hai',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'Aur woh jise chahta hai be-hisaab ata karta hai.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.poppins(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: _goldBright.withValues(alpha: 0.65),
                                      width: 1,
                                    ),
                                  ),
                                  child: Form(
                                    key: _formKey,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          'Phone Number Sign In',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          'Apne registered number se sign in karein',
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(color: Colors.white70),
                                        ),
                                        const SizedBox(height: 14),
                                        IntlPhoneField(
                                          initialCountryCode: 'PK',
                                          autovalidateMode:
                                              AutovalidateMode.onUserInteraction,
                                          style: GoogleFonts.poppins(color: Colors.white),
                                          dropdownTextStyle:
                                              GoogleFonts.poppins(color: Colors.white),
                                          decoration: _inputDecoration(
                                            label: 'Mobile Number Likhein',
                                            icon: Icons.phone_iphone_rounded,
                                          ),
                                          onChanged: (phone) {
                                            _phoneNumber = phone.completeNumber;
                                          },
                                          validator: (value) {
                                            final raw = value?.completeNumber.trim() ?? '';
                                            if (raw.length < 10) {
                                              return 'Enter valid phone number';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        TextFormField(
                                          controller: _passwordController,
                                          obscureText: _isPasswordObscured,
                                          style: GoogleFonts.poppins(color: Colors.white),
                                          decoration: _inputDecoration(
                                            label: 'Apna Password Likhein',
                                            icon: Icons.lock_outline,
                                            suffixIcon: IconButton(
                                              onPressed: () {
                                                setState(() {
                                                  _isPasswordObscured =
                                                      !_isPasswordObscured;
                                                });
                                              },
                                              icon: Icon(
                                                _isPasswordObscured
                                                    ? Icons.visibility_rounded
                                                    : Icons.visibility_off_rounded,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ),
                                          validator: (value) {
                                            if ((value ?? '').trim().isEmpty) {
                                              return 'Password required';
                                            }
                                            return null;
                                          },
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          "OTP kisi ke sath share na karein",
                                          textAlign: TextAlign.center,
                                          style: GoogleFonts.poppins(
                                            color: Colors.white70,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () {
                                              Navigator.of(context).push(
                                                PageRouteBuilder<void>(
                                                  transitionDuration:
                                                      const Duration(milliseconds: 360),
                                                  pageBuilder: (
                                                    routeContext,
                                                    routeAnimation,
                                                    secondaryAnimation,
                                                  ) =>
                                                      const ForgotPasswordOtpScreen(),
                                                  transitionsBuilder: (
                                                    routeContext,
                                                    animation,
                                                    secondaryAnimation,
                                                    child,
                                                  ) {
                                                    final slide = Tween<Offset>(
                                                      begin: const Offset(1, 0),
                                                      end: Offset.zero,
                                                    ).chain(
                                                      CurveTween(
                                                        curve: Curves.easeOutCubic,
                                                      ),
                                                    );
                                                    return SlideTransition(
                                                      position: animation.drive(slide),
                                                      child: child,
                                                    );
                                                  },
                                                ),
                                              );
                                            },
                                            child: Text(
                                              'Password Bhool Gaye?',
                                              style: GoogleFonts.poppins(
                                                color: _goldBright,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ),
                                        GlassButton(
                                          label: _isLoading
                                              ? 'Please wait...'
                                              : 'Aage Barhein',
                                          loading: _isLoading,
                                          onPressed:
                                              _isLoading ? null : _startPhoneSignIn,
                                        ),
                                        const SizedBox(height: 12),
                                        _PulsingBiometricCard(
                                          animation: _pulseController ??
                                              const AlwaysStoppedAnimation<double>(0),
                                          loading: _isBiometricLoading,
                                          onTap: _isBiometricLoading || _isLoading
                                              ? null
                                              : _handleBiometricQuickAccess,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: TextButton(
                            onPressed: () => Navigator.pushNamed(context, Routes.signup),
                            child: Text(
                              'Naya User? Sign Up Karein',
                              style: GoogleFonts.poppins(
                                color: _goldBright,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PulsingBiometricCard extends StatelessWidget {
  const _PulsingBiometricCard({
    required this.animation,
    required this.loading,
    required this.onTap,
  });

  final Animation<double> animation;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool useFaceIcon = defaultTargetPlatform == TargetPlatform.iOS;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFFFD700).withValues(alpha: 0.45 + (0.4 * t)),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFD700).withValues(alpha: 0.08 + (0.15 * t)),
                blurRadius: 5 + (8 * t),
                spreadRadius: 0.2 + (0.8 * t),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFFFFD700),
                        ),
                      )
                    else
                      Icon(
                        useFaceIcon
                            ? Icons.face_retouching_natural_rounded
                            : Icons.fingerprint_rounded,
                        color: const Color(0xFFFFD700),
                        size: 24,
                      ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Biometric ya Face ID',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFFFD700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}