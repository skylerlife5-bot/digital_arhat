import 'dart:ui';

import 'package:flutter/material.dart';

import 'auth_state.dart';
import '../core/widgets/app_logo.dart';
import '../services/auth_service.dart';
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
  static const Color _brandDarkGreen = Color(0xFF011A0A);
  static const Color _brandGold = Color(0xFFFFD700);
  static const String _supportWhatsApp = '+92 300 0000000';

  final AuthService _authService = AuthService();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  bool _isLoading = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final phone = _authService.normalizePhone('92${_phoneController.text.trim()}');
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      await _authService.loginWithPhoneAndPassword(
        phone: phone,
        password: password,
      );
    } catch (e) {
      if (!mounted) return;
      final errorText = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorText.isEmpty ? 'Login failed. Dobara koshish karein.' : errorText)),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _goToRegister() {
    if (widget.onGoSignup != null) {
      widget.onGoSignup!.call();
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MasterSignUpScreen()),
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
    final theme = Theme.of(context);
    final selectedType = AuthState.selectedUserType;
    final selectedTypeLabel = selectedType == 'seller' ? 'Seller' : 'Buyer';

    return Scaffold(
      backgroundColor: _brandDarkGreen,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF013D20), Color(0xFF011A0A)],
              ),
            ),
          ),
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
                    children: [
                      const SizedBox(height: 12),
                      const AppLogo(height: 82, showName: false),
                      const SizedBox(height: 16),
                      Text(
                        'Sign in to Digital Arhat',
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(color: _brandGold.withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          'Selected Type: $selectedTypeLabel (Aap ne $selectedTypeLabel mode select kiya hai)',
                          style: const TextStyle(
                            color: _brandGold,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _AyatCard(),
                      const SizedBox(height: 20),
                      _GlassField(
                        child: TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            prefixIcon: Icon(Icons.phone_iphone_rounded, color: _brandGold),
                            prefixText: '+92  ',
                            prefixStyle: TextStyle(color: _brandGold, fontWeight: FontWeight.w700),
                            hintText: '3XX XXXXXXX',
                            hintStyle: TextStyle(color: Colors.white54),
                            labelText: 'Phone Number (Pakistan)',
                            labelStyle: TextStyle(color: Colors.white70),
                          ),
                          validator: (value) {
                            final normalized =
                                _authService.normalizePhone('92${(value ?? '').trim()}');
                            if (normalized.isEmpty) return 'Phone number lazmi hai';
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
                            prefixIcon: const Icon(Icons.lock_outline_rounded, color: _brandGold),
                            labelText: 'Password (Khufia Lafz)',
                            labelStyle: const TextStyle(color: Colors.white70),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _showPassword = !_showPassword),
                              icon: Icon(
                                _showPassword ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) return 'Password lazmi hai';
                            return null;
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _goToPasswordReset,
                          child: const Text(
                            'Password bhool gaye? (Forgot Password?)',
                            style: TextStyle(color: _brandGold, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _isLoading ? null : _login,
                          style: FilledButton.styleFrom(
                            backgroundColor: _brandGold,
                            foregroundColor: _brandDarkGreen,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _brandDarkGreen,
                                  ),
                                )
                              : const Text('Sign In (Dakhil Hon)'),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        children: [
                          const Text(
                            "Don't have an account?",
                            style: TextStyle(color: Colors.white70),
                          ),
                          TextButton(
                            onPressed: _goToRegister,
                            child: const Text(
                              'Register Now (Naya Account Banayein)',
                              style: TextStyle(fontWeight: FontWeight.w700, color: _brandGold),
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

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({super.key, required this.supportWhatsApp});

  final String supportWhatsApp;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  static const Color _brandDarkGreen = Color(0xFF011A0A);
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
    final normalized = _authService.normalizePhone('92${_phoneController.text.trim()}');
    if (normalized.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sahi phone number likhein.')),
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
      const SnackBar(content: Text('Dummy OTP sent: 123456')),
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
        const SnackBar(content: Text('Naya password kam az kam 6 characters ka ho.')),
      );
      return;
    }

    setState(() => _isVerifying = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    setState(() => _isVerifying = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Password reset request recorded.')),
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
        title: const Text('Password Recovery (Phone OTP)'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _GlassField(
              child: TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  prefixText: '+92  ',
                  prefixStyle: TextStyle(color: _brandGold, fontWeight: FontWeight.w700),
                  labelText: 'Phone Number (Aap ka mobile number)',
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
                    : const Text('Send OTP (OTP Bhejein)'),
              ),
            ),
            const SizedBox(height: 14),
            if (_otpSent) ...[
              _GlassField(
                child: TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    labelText: 'Enter OTP (Demo: 123456)',
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
                    labelText: 'New Password (Naya password)',
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
                      : const Text('Verify OTP (Tasdeeq Karein)'),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              'Need help? WhatsApp support: ${widget.supportWhatsApp}',
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
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: child,
        ),
      ),
    );
  }
}

class _AyatCard extends StatelessWidget {
  const _AyatCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Column(
        children: [
          Text(
            '┘ê┘Ä╪▓┘É┘å┘Å┘ê╪º ╪¿┘É╪º┘ä┘Æ┘é┘É╪│┘Æ╪╖┘Ä╪º╪│┘É ╪º┘ä┘Æ┘à┘Å╪│┘Æ╪¬┘Ä┘é┘É┘è┘à┘É',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFFFD700),
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Wazinu bil qistasul mustaqim (Aur insaaf ke saath poora tolo) - Surah Al-Isra',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _IslamicPatternPainter extends CustomPainter {
  _IslamicPatternPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const step = 60.0;
    for (double y = 0; y <= size.height + step; y += step) {
      for (double x = 0; x <= size.width + step; x += step) {
        _drawStar(canvas, Offset(x, y), 11, paint);
      }
    }
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i * 45.0) * (3.1415926535 / 180.0);
      final point = Offset(
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
  static double cos(double v) => _Trig._cos(v);
  static double sin(double v) => _Trig._sin(v);
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
      final denom = (2 * n) * (2 * n - 1);
      if (cosine) {
        term *= -x * x / denom;
      } else {
        final sDenom = (2 * n) * (2 * n + 1);
        term *= -x * x / sDenom;
      }
      sum += term;
    }
    return sum;
  }
}
