import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../services/auth_service.dart';
import 'auth_state.dart';
import 'signup_screen.dart';

class LoginScreen extends SignInScreen {
  const LoginScreen({
    super.key,
    super.onGoSignup,
  });
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.onGoSignup,
  });

  final VoidCallback? onGoSignup;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  static const Color _greenTop = Color(0xFF1B5E20);
  static const Color _brandGold = Color(0xFFFFD700);
  static const String _supportWhatsApp = '+92 300 0000000';

  final AuthService _authService = AuthService();
  final LocalAuthentication auth = LocalAuthentication();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _isBiometricLoading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _phoneToEmail(String phoneNumber) {
    final String digitsOnly = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    return '${digitsOnly}_phone@digitalarhat.com';
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final String normalizedPhone =
        _authService.normalizePhone('92${_phoneController.text.trim()}');
    final String email = _phoneToEmail(normalizedPhone);
    final String password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      final UserCredential credential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final User? user = credential.user;
      if (user != null) {
        await _readUserDataAfterLogin(user.uid);
      }

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } on FirebaseAuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.message ?? 'Login fail ho gaya, dobara koshish karein.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Login fail ho gaya, dobara koshish karein.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _readUserDataAfterLogin(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).get();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data access restricted hai, lekin login successful hai.'),
          ),
        );
      }
    }
  }

  Future<void> _authenticateWithBiometrics() async {
    if (_isBiometricLoading) return;

    setState(() => _isBiometricLoading = true);

    try {
      final bool canCheck = await auth.canCheckBiometrics;
      if (!canCheck) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Device biometric support nahi karta.')),
        );
        return;
      }

      final bool isAuthenticated = await auth.authenticate(
        localizedReason: 'App kholnay ke liye fingerprint scan karein',
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (isAuthenticated) {
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric fail ho gaya, dobara koshish karein.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Biometric fail ho gaya, dobara koshish karein.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isBiometricLoading = false);
      }
    }
  }

  void _goToRegister() {
    if (widget.onGoSignup != null) {
      widget.onGoSignup!.call();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SignUpScreen()),
    );
  }

  void _goToPasswordReset() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PasswordResetScreen(supportWhatsApp: _supportWhatsApp),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String selectedType = AuthState.selectedUserType;
    final String selectedTypeLabel = selectedType == 'seller' ? 'Seller' : 'Buyer';

    return Scaffold(
      backgroundColor: _greenTop,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _IslamicPatternPainter(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 48,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: <Widget>[
                        const SizedBox(height: 12),
                        Opacity(
                          opacity: 0.92,
                          child: Container(
                            height: 88,
                            width: 88,
                            color: Colors.transparent,
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/logo.png',
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Digital Arhat mein dakhil hon',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: _brandGold,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Phone aur password se secure dakhil hon',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: _brandGold.withValues(alpha: 0.52),
                            ),
                          ),
                          child: Text(
                            'Selected Type: $selectedTypeLabel',
                            style: const TextStyle(
                              color: _brandGold,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        const _VerseSection(),
                        const SizedBox(height: 20),
                        _GlassField(
                          child: TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: Icon(
                                Icons.phone_iphone_rounded,
                                color: _brandGold,
                              ),
                              prefixText: '+92  ',
                              prefixStyle: TextStyle(
                                color: _brandGold,
                                fontWeight: FontWeight.w700,
                              ),
                              hintText: '3XX XXXXXXX',
                              hintStyle: TextStyle(color: Colors.white54),
                              labelText: 'Mobile Number',
                              labelStyle: TextStyle(color: Colors.white70),
                            ),
                            validator: (String? value) {
                              final String normalized = _authService
                                  .normalizePhone('92${(value ?? '').trim()}');
                              if (normalized.isEmpty) return 'Mobile number lazmi hai';
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 14),
                        _GlassField(
                          child: TextFormField(
                            controller: _passwordController,
                            obscureText: !_showPassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                                color: _brandGold,
                              ),
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: Colors.white70),
                              suffixIcon: IconButton(
                                onPressed: () {
                                  setState(() => _showPassword = !_showPassword);
                                },
                                icon: Icon(
                                  _showPassword
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            validator: (String? value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Password lazmi hai';
                              }
                              return null;
                            },
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _goToPasswordReset,
                            child: const Text(
                              'Password bhool gaye?',
                              style: TextStyle(
                                color: _brandGold,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _PremiumGradientButton(
                          label: _isLoading ? 'Login ho raha hai...' : 'Aage Barhein',
                          onPressed: _isLoading ? null : _login,
                          isLoading: _isLoading,
                        ),
                        const SizedBox(height: 12),
                        _GlassBiometricButton(
                          label: _isBiometricLoading
                              ? 'Biometric verify ho raha hai...'
                              : 'Fingerprint se Login Karein',
                          onPressed: _isBiometricLoading
                              ? null
                              : _authenticateWithBiometrics,
                          isLoading: _isBiometricLoading,
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          alignment: WrapAlignment.center,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 4,
                          children: <Widget>[
                            const Text(
                              'Account nahi hai?',
                              style: TextStyle(color: Colors.white70),
                            ),
                            TextButton(
                              onPressed: _goToRegister,
                              child: const Text(
                                'Naya Account Banayein',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _brandGold,
                                ),
                              ),
                            ),
                          ],
                        ),
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
}

class _VerseSection extends StatelessWidget {
  const _VerseSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: const Column(
        children: <Widget>[
          Text(
            'وَتَرْزُقُ مَن تَشَاءُ بِغَيْرِ حِسَابٍ',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 30,
              fontWeight: FontWeight.w700,
              fontFamily: 'Jameel Noori',
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Aur tu jisay chahay be-hisab rizq deta hai',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _PremiumGradientButton extends StatelessWidget {
  const _PremiumGradientButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[Color(0xFFFFB300), Color(0xFFFFEB3B)],
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFFFD700).withValues(alpha: 0.34),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: Center(
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF1B5E20),
                      ),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF1B5E20),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassBiometricButton extends StatelessWidget {
  const _GlassBiometricButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.amber.withValues(alpha: 0.10),
          side: const BorderSide(color: Color(0xFFFFD700), width: 1.2),
          foregroundColor: const Color(0xFFFFD700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        icon: isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.fingerprint_rounded),
        label: Text(label),
      ),
    );
  }
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, required this.supportWhatsApp});

  final String supportWhatsApp;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  static const Color _brandDarkGreen = Color(0xFF1B5E20);
  static const Color _brandGold = Color(0xFFFFD700);

  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();

  bool _isSending = false;
  bool _isVerifying = false;
  bool _otpSent = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    final String normalized = _authService.normalizePhone('92${_phoneController.text.trim()}');
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sahi mobile number likhein.')),
      );
      return;
    }

    setState(() => _isSending = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    setState(() {
      _isSending = false;
      _otpSent = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Demo OTP bhej diya gaya: 123456')),
    );
  }

  Future<void> _verifyAndReset() async {
    if (_otpController.text.trim() != '123456') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP ghalat hai. Demo OTP 123456 use karein.')),
      );
      return;
    }
    if (_newPasswordController.text.trim().length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Naya password kam az kam 6 haroof ka ho.')),
      );
      return;
    }

    setState(() => _isVerifying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isVerifying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password reset request save ho gayi.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _brandDarkGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: _brandGold,
        title: const Text('Password Recovery OTP'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: <Widget>[
            _GlassField(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  prefixText: '+92  ',
                  prefixStyle: TextStyle(color: _brandGold, fontWeight: FontWeight.w700),
                  labelText: 'Mobile Number',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSending ? null : _sendOtp,
                style: FilledButton.styleFrom(
                  backgroundColor: _brandGold,
                  foregroundColor: _brandDarkGreen,
                ),
                child: _isSending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: _brandDarkGreen,
                        ),
                      )
                    : const Text('OTP Bhejein'),
              ),
            ),
            const SizedBox(height: 14),
            if (_otpSent) ...<Widget>[
              _GlassField(
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    labelText: 'OTP Likhein (Demo: 123456)',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _GlassField(
                child: TextField(
                  controller: _newPasswordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    labelText: 'Naya Password',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _isVerifying ? null : _verifyAndReset,
                  style: FilledButton.styleFrom(
                    backgroundColor: _brandGold,
                    foregroundColor: _brandDarkGreen,
                  ),
                  child: _isVerifying
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _brandDarkGreen,
                          ),
                        )
                      : const Text('OTP Verify Karein'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Madad ke liye WhatsApp: ${widget.supportWhatsApp}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _brandGold, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassField extends StatelessWidget {
  const _GlassField({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.55)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        ),
      ),
    );
  }
}

class _IslamicPatternPainter extends CustomPainter {
  _IslamicPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const double step = 60.0;
    for (double y = 0; y <= size.height + step; y += step) {
      for (double x = 0; x <= size.width + step; x += step) {
        _drawStar(canvas, Offset(x, y), 11, paint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final Path path = Path();
    for (int i = 0; i < 8; i++) {
      final double angle = (i * 45.0) * (3.1415926535 / 180.0);
      final Offset point = Offset(
        center.dx + radius * (i.isEven ? 1.0 : 0.45) * MathCos.cos(angle),
        center.dy + radius * (i.isEven ? 1.0 : 0.45) * MathCos.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _IslamicPatternPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class MathCos {
  static double cos(double value) => _Trig._cos(value);
  static double sin(double value) => _Trig._sin(value);
}

class _Trig {
  static double _cos(double x) {
    return _series(x, true);
  }

  static double _sin(double x) {
    return _series(x, false);
  }

  static double _series(double x, bool cosine) {
    double term = cosine ? 1 : x;
    double sum = term;
    for (int n = 1; n < 6; n++) {
      final double denom = (2 * n) * (2 * n - 1);
      if (cosine) {
        term *= -x * x / denom;
      } else {
        final double sDenom = (2 * n) * (2 * n + 1);
        term *= -x * x / sDenom;
      }
      sum += term;
    }
    return sum;
  }
}
