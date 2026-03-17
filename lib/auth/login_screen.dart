import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'package:flutter/services.dart';

import '../core/assets.dart';
import '../routes.dart';
import '../services/startup_bootstrap_service.dart';

class LoginScreen extends SignInScreen {
  const LoginScreen({super.key});
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const Color _greenDark = AppColors.background;
  static const Color _gold = AppColors.accentGold;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _mobileController = TextEditingController();
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
    _mobileController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _normalizePhoneDigits(String input) {
    String digits = _digitsOnly(input);
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  String phoneToEmail(String phoneDigitsOnly) =>
      'u_92$phoneDigitsOnly@digitalarhat.app';

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
      _maybeRedirectToDashboard();
    }
  }

  void _maybeRedirectToDashboard() {
    if (!mounted || _isRedirecting) return;
    if (FirebaseAuth.instance.currentUser == null) return;

    _isRedirecting = true;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(Routes.authWrapper, (route) => false);
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

      final String digits = _normalizePhoneDigits(
        _mobileController.text.trim(),
      );
      final String email = phoneToEmail(digits);
      debugPrint('login email = $email');

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;
      _isRedirecting = true;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(Routes.authWrapper, (route) => false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(e.message ?? 'Sign in failed.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Unable to sign in right now.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required String hint,
    required IconData icon,
    Widget? prefix,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white38),
      labelStyle: const TextStyle(color: AppColors.secondaryText),
      prefixIcon: Icon(icon, color: _gold),
      prefix: prefix,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.35)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: _gold),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.urgencyRed),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: AppColors.urgencyRed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _greenDark,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: const Text(
          'لاگ ان / Login',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _DigitalBackground()),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _buildBrandHeader(),
                      const SizedBox(height: 12),
                      _buildHadithCard(),
                      const SizedBox(height: 12),
                      _buildLoginFormCard(context),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrandHeader() {
    return Column(
      children: <Widget>[
        _buildLogo(),
        const SizedBox(height: 12),
        const Text(
          'Digital Aarhat',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'ڈیجیٹل آرہت',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.primaryText,
            fontSize: 30,
            fontFamily: 'JameelNoori',
            height: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildHadithCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.45)),
          ),
          child: const Column(
            children: <Widget>[
              Text(
                'تجارت کی فضیلت',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFFFE9A6),
                  fontFamily: 'JameelNoori',
                  fontSize: 21,
                  height: 1.0,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'سچا اور امانتدار تاجر قیامت کے دن انبیاء، صدیقین اور شہداء کے ساتھ ہوگا',
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontFamily: 'JameelNoori',
                  fontSize: 18,
                  height: 1.08,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '(ترمذی 1209)',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontFamily: 'JameelNoori',
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginFormCard(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _gold.withValues(alpha: 0.5)),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _mobileController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: _fieldDecoration(
                    label: 'Mobile Number / موبائل نمبر',
                    hint: '3XX XXXXXXX',
                    icon: Icons.phone_android_rounded,
                    prefix: const Text(
                      '+92 ',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  validator: (value) {
                    final String digits = _normalizePhoneDigits(value ?? '');
                    if (digits.isEmpty) {
                      return 'موبائل نمبر درج کریں';
                    }
                    if (digits.length != 10) {
                      return '10 ہندسے ضروری ہیں';
                    }
                    if (!digits.startsWith('3')) {
                      return 'درست پاکستانی نمبر درج کریں';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  decoration: _fieldDecoration(
                    label: 'Password / پاس ورڈ',
                    hint: 'Enter password / پاس ورڈ درج کریں',
                    icon: Icons.lock_outline_rounded,
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: AppColors.secondaryText,
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
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, Routes.forgotPasswordOtp),
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: _gold,
                      textStyle: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: const Text('Forgot password? / پاس ورڈ بھول گئے؟'),
                  ),
                ),
                const SizedBox(height: 2),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _signIn,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(
                    _isLoading
                        ? 'Logging in... / لاگ ان ہو رہا ہے'
                        : 'Login / لاگ ان کریں',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, Routes.createAccount),
                    style: TextButton.styleFrom(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 4,
                      children: const <Widget>[
                        Text(
                          'New here? / نئے ہیں؟',
                          style: TextStyle(
                            color: AppColors.secondaryText,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Create Account / اکاؤنٹ بنائیں',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Align(
      alignment: Alignment.center,
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: _gold.withValues(alpha: 0.7), width: 1.2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipOval(
          child: FittedBox(
            fit: BoxFit.cover,
            child: Image.asset(
              AppAssets.logoPath,
              width: 138,
              height: 138,
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const SizedBox(
                      width: 96,
                      height: 96,
                      child: ColoredBox(
                        color: AppColors.softOverlayWhite,
                        child: Center(
                          child: Icon(
                            Icons.agriculture_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    );
                  },
            ),
          ),
        ),
      ),
    );
  }
}

class _DigitalBackground extends StatelessWidget {
  const _DigitalBackground();

  static const Color _deepGreen = AppColors.background;
  static const Color _greenMid = AppColors.cardSurface;
  static const Color _greenDark = AppColors.background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_deepGreen, _greenMid, _greenDark],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.softOverlayWhite, Colors.transparent],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ],
    );
  }
}

