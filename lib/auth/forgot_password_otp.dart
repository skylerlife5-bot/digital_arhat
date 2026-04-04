import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class ForgotPasswordOtpScreen extends StatefulWidget {
  const ForgotPasswordOtpScreen({super.key});

  @override
  State<ForgotPasswordOtpScreen> createState() =>
      _ForgotPasswordOtpScreenState();
}

enum _RecoverStep { recover, otp, reset, success }

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
  static const Color _forestTop = AppColors.background;
  static const Color _forestMid = AppColors.cardSurface;
  static const Color _emeraldBottom = AppColors.divider;
  static const Color _goldBright = AppColors.accentGold;

  final AuthService _authService = AuthService();

  _RecoverStep _step = _RecoverStep.recover;
  bool _busy = false;

  String? _verificationId;
  String? _normalizedPhone;
  User? _verifiedUser;
  bool _otpVerified = false;
  String _statusMessage = '';
  bool _statusIsError = false;
  final TextEditingController _phoneController = TextEditingController();

  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  final List<TextEditingController> _otpControllers =
      List<TextEditingController>.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List<FocusNode>.generate(
    6,
    (_) => FocusNode(),
  );

  @override
  void dispose() {
    _phoneController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (final controller in _otpControllers) {
      controller.dispose();
    }
    for (final node in _otpNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _setStatus(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _statusMessage = message;
      _statusIsError = isError;
    });
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(duration: const Duration(seconds: 5), content: Text(message)),
      );
  }

  Future<void> _sendOtp() async {
    final String normalizedPhone = _authService.normalizePhone(
      _phoneController.text,
    );
    if (normalizedPhone.isEmpty) {
      _setStatus(AuthService.pakistanPhoneValidationMessage, isError: true);
      _showSnack('براہ کرم درست پاکستانی موبائل نمبر درج کریں');
      return;
    }
    _normalizedPhone = normalizedPhone;

    for (final TextEditingController controller in _otpControllers) {
      controller.clear();
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _busy = true;
      _verificationId = null;
      _otpVerified = false;
      _verifiedUser = null;
    });
    _setStatus('Sending OTP... / او ٹی پی بھیجی جا رہی ہے...', isError: false);

    try {
      await _authService.sendPasswordResetOtpToPhone(
        phone: normalizedPhone,
        flowLabel: 'forgot_password',
        onCodeSent: (String verificationId) {
          _verificationId = verificationId;
          if (!mounted) return;
          _setStatus(
            'OTP sent successfully / او ٹی پی کامیابی سے بھیج دی گئی',
            isError: false,
          );
          setState(() => _step = _RecoverStep.otp);
          Future<void>.delayed(const Duration(milliseconds: 220), () {
            if (!mounted) return;
            _otpNodes.first.requestFocus();
          });
        },
        onAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
          _setStatus(
            'OTP timeout reached. You can still verify the received code. / او ٹی پی ٹائم آؤٹ ہوگیا، موصولہ کوڈ سے تصدیق جاری رکھیں',
            isError: false,
          );
        },
        onVerificationFailed: (FirebaseAuthException error) {
          _setStatus(
            'Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ',
            isError: true,
          );
          _showSnack(error.message ?? 'Failed to send OTP.');
        },
        onVerificationCompleted: (UserCredential credential) async {
          if (!mounted) return;
          _verifiedUser = credential.user;
          _otpVerified = credential.user != null;
          _setStatus(
            'Phone auto-verified / فون خودکار طور پر تصدیق ہوگیا',
            isError: false,
          );
          setState(() => _step = _RecoverStep.reset);
        },
      );
    } on PhoneOtpException catch (error) {
      debugPrint(
        '[OTP_DEBUG][forgot_password] action=send_otp code=${error.code} message=${error.message} phone=${_normalizedPhone ?? _phoneController.text.trim()}',
      );
      if (error.code == 'account-not-found') {
        _setStatus(
          'No account found for this phone number / اس نمبر پر کوئی اکاؤنٹ موجود نہیں',
          isError: true,
        );
        _showSnack('No account found for this phone number.');
      } else {
        _setStatus(
          'Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ',
          isError: true,
        );
        _showSnack(error.message);
      }
    } on FirebaseException {
      _setStatus(
        'Unable to validate account right now / اکاؤنٹ کی جانچ اس وقت ممکن نہیں',
        isError: true,
      );
      _showSnack('Unable to validate account right now. Please try again.');
    } catch (_) {
      _setStatus(
        'Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ',
        isError: true,
      );
      _showSnack('Unable to send OTP right now. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.split('');
      for (
        int i = 0;
        i < chars.length && i + index < _otpControllers.length;
        i++
      ) {
        _otpControllers[index + i].text = chars[i];
      }
    }

    if (value.isNotEmpty && index < _otpNodes.length - 1) {
      _otpNodes[index + 1].requestFocus();
    }

    if (value.isEmpty && index > 0) {
      _otpNodes[index - 1].requestFocus();
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length != 6) {
      _setStatus(
        'Please enter all 6 digits / براہ کرم تمام 6 ہندسے درج کریں',
        isError: true,
      );
      _showSnack('Please enter 6-digit OTP.');
      return;
    }

    final verificationId = _verificationId;
    if (verificationId == null) {
      _setStatus(
        'OTP expired. Please request again. / او ٹی پی ایکسپائر ہوگئی، دوبارہ درخواست دیں',
        isError: true,
      );
      _showSnack('OTP expired. Please request again.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    _setStatus(
      'Verifying OTP... / او ٹی پی کی تصدیق جاری ہے...',
      isError: false,
    );

    try {
      final UserCredential? credential = await _authService.verifyOTP(
        verificationId,
        code,
        flowLabel: 'forgot_password',
        phoneNumber: _normalizedPhone,
      );
      _verifiedUser = credential?.user;
      _otpVerified = credential?.user != null;
      if (!mounted) return;
      _setStatus('Verified / تصدیق شدہ', isError: false);
      setState(() => _step = _RecoverStep.reset);
    } on PhoneOtpException catch (e) {
      debugPrint(
        '[OTP_DEBUG][forgot_password] action=verify_otp code=${e.code} message=${e.message} phone=${_normalizedPhone ?? _phoneController.text.trim()}',
      );
      _setStatus(
        _mapOtpError(e.code, e.message),
        isError: true,
      );
      _showSnack('OTP verification failed.');
    } catch (e) {
      _setStatus(
        'Unexpected error verifying OTP / او ٹی پی میں غیر متوقع خرابی',
        isError: true,
      );
      _showSnack('Error verifying OTP.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _mapOtpError(String code, String message) {
    final String c = code.toLowerCase();
    if (c.contains('invalid-verification-code') || c.contains('invalid-credential')) {
      return 'The OTP code is incorrect / او ٹی پی کوڈ غلط ہے';
    }
    if (c.contains('code-send-timeout')) {
      return 'OTP request timed out. Please try again / او ٹی پی میں تاخیر، دوبارہ کوشش کریں';
    }
    if (c.contains('too-many-requests')) {
      return 'Too many attempts. Please wait and try again / بہت سی کوششیں ہو گئیں، انتظار کریں';
    }
    if (c.contains('network')) {
      return 'Network error. Check your internet / انٹرنیٹ میں مسئلہ ہے';
    }
    return message.isNotEmpty ? message : 'OTP verification failed / او ٹی پی تصدیق ناکام';

  }

  Future<void> _resetPassword() async {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.length < 6) {
      _setStatus('Password should be at least 6 characters.', isError: true);
      _showSnack('Password should be at least 6 characters.');
      return;
    }

    if (newPassword != confirmPassword) {
      _setStatus('Passwords do not match.', isError: true);
      _showSnack('Passwords do not match.');
      return;
    }

    final String normalizedPhone =
        _normalizedPhone ?? _authService.normalizePhone(_phoneController.text);
    final String code = _otpControllers
        .map((TextEditingController c) => c.text)
        .join();
    if (!_otpVerified && _verifiedUser == null) {
      _setStatus(
        'Verify OTP before resetting password / پاس ورڈ ری سیٹ کرنے سے پہلے او ٹی پی تصدیق کریں',
        isError: true,
      );
      _showSnack('Verify OTP before resetting password.');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    _setStatus(
      'Resetting password... / پاس ورڈ ری سیٹ ہو رہا ہے...',
      isError: false,
    );

    try {
      await _authService.resetPasswordWithOtp(
        phone: normalizedPhone,
        verificationId: _verificationId,
        smsCode: code.length == 6 ? code : null,
        newPassword: newPassword,
        verifiedUser: _verifiedUser ?? FirebaseAuth.instance.currentUser,
      );
      _setStatus(
        'Password updated successfully / پاس ورڈ کامیابی سے اپڈیٹ ہوگیا',
        isError: false,
      );
      if (!mounted) return;
      setState(() => _step = _RecoverStep.success);
    } catch (e) {
      _setStatus(
        'Unable to reset password right now / پاس ورڈ ری سیٹ نہیں ہو سکا',
        isError: true,
      );
      _showSnack(e.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Widget _buildStatusBanner() {
    if (_statusMessage.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _statusIsError
            ? const Color(0x33D96A6A)
            : const Color(0x332B5B3A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _statusIsError
              ? const Color(0xFFE6A0A0)
              : const Color(0xFFD4AF37),
        ),
      ),
      child: Text(
        _statusMessage,
        style: TextStyle(
          color: _statusIsError
              ? const Color(0xFFFFECEC)
              : const Color(0xFFFFF5D7),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: AppColors.secondaryText),
      prefixIcon: Icon(icon, color: _goldBright),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: _goldBright.withValues(alpha: 0.82),
          width: 0.9,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: _goldBright, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    );
  }

  Widget _buildRecoverStep() {
    return Column(
      key: const ValueKey<String>('recover'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusBanner(),
        Text(
          'پاس ورڈ واپس کریں',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontFamily: 'JameelNoori',
            height: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'اپنا رجسٹرڈ موبائل نمبر درج کریں، ہم OTP بھیج دیں گے',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.secondaryText,
            fontSize: 17,
            fontFamily: 'JameelNoori',
            height: 1.1,
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
            LengthLimitingTextInputFormatter(13),
          ],
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
          decoration: _fieldDecoration(
            label: 'Mobile Number / موبائل نمبر',
            icon: Icons.phone_android_rounded,
          ).copyWith(hintText: '03001234567 | 3001234567 | +923001234567'),
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: _busy ? 'OTP بھیجا جا رہا ہے...' : 'OTP بھیجیں / Send OTP',
          onPressed: _busy ? null : _sendOtp,
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(
              foregroundColor: _goldBright,
              textStyle: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('واپس لاگ اِن کریں / Back to Login'),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey<String>('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusBanner(),
        Text(
          'OTP Verification',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '6-digit OTP darj karein',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 16),
        Row(
          children: List<Widget>.generate(_otpControllers.length, (index) {
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: index == 0 ? 0 : 3.0,
                  right: index == _otpControllers.length - 1 ? 0 : 3.0,
                ),
                child: TextField(
                  controller: _otpControllers[index],
                  focusNode: _otpNodes[index],
                  autofocus: index == 0,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 1,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: _goldBright.withValues(alpha: 0.82),
                        width: 0.9,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: _goldBright,
                        width: 1.2,
                      ),
                    ),
                  ),
                  onChanged: (value) => _onOtpChanged(index, value),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: _busy ? 'Verifying...' : 'OTP Verify Karein',
          onPressed:
              _busy ||
                  _otpControllers.any(
                    (TextEditingController c) => c.text.trim().isEmpty,
                  )
              ? null
              : _verifyOtp,
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    return Column(
      key: const ValueKey<String>('reset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusBanner(),
        Text(
          'Password Reset',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newPasswordController,
          obscureText: true,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _fieldDecoration(
            label: 'Naya Password',
            icon: Icons.lock_reset,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: true,
          style: GoogleFonts.poppins(color: Colors.white),
          decoration: _fieldDecoration(
            label: 'Confirm Password',
            icon: Icons.lock_outline,
          ),
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: _busy ? 'Updating Password...' : 'Password Reset Karein',
          onPressed: _busy || !_otpVerified ? null : _resetPassword,
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey<String>('success'),
      children: [
        _buildStatusBanner(),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.7, end: 1),
          duration: const Duration(milliseconds: 650),
          curve: Curves.elasticOut,
          builder: (context, value, child) {
            return Transform(
              transform: Matrix4.diagonal3Values(value, value, 1),
              alignment: Alignment.center,
              child: child,
            );
          },
          child: Container(
            height: 94,
            width: 94,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.13),
              border: Border.all(color: _goldBright, width: 1.2),
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 62,
              color: _goldBright,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Password Update Ho Gaya',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Ab aap naya password use karke sign in kar sakte hain.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: AppColors.secondaryText),
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: 'Sign In Par Wapas Jayein',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _RecoverStep.recover:
        return _buildRecoverStep();
      case _RecoverStep.otp:
        return _buildOtpStep();
      case _RecoverStep.reset:
        return _buildResetStep();
      case _RecoverStep.success:
        return _buildSuccessStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[_forestTop, _forestMid, _emeraldBottom],
              ),
            ),
            child: SizedBox.expand(),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[AppColors.softOverlayWhite, Colors.transparent],
              ),
            ),
            child: SizedBox.expand(),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height - 90,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.20),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _goldBright.withValues(alpha: 0.40),
                              width: 1,
                            ),
                          ),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 360),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              final offsetTween = Tween<Offset>(
                                begin: const Offset(0.15, 0),
                                end: Offset.zero,
                              );
                              return SlideTransition(
                                position: animation.drive(offsetTween),
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              );
                            },
                            child: _buildCurrentStep(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldButton extends StatefulWidget {
  const _GoldButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_GoldButton> createState() => _GoldButtonState();
}

class _GoldButtonState extends State<_GoldButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: enabled ? widget.onPressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        transform: Matrix4.diagonal3Values(
          _pressed ? 0.98 : 1,
          _pressed ? 0.98 : 1,
          1,
        ),
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFEACB73),
              AppColors.accentGold,
              Color(0xFFBD972A),
            ],
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    offset: Offset(0, _pressed ? 2 : 5),
                    blurRadius: _pressed ? 4 : 9,
                  ),
                ]
              : const [],
        ),
        child: Center(
          child: Text(
            widget.label,
            style: GoogleFonts.poppins(
              color: enabled ? const Color(0xFF083D34) : Colors.black45,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
