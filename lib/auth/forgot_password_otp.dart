import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl_phone_field/intl_phone_field.dart';

class ForgotPasswordOtpScreen extends StatefulWidget {
  const ForgotPasswordOtpScreen({super.key});

  @override
  State<ForgotPasswordOtpScreen> createState() => _ForgotPasswordOtpScreenState();
}

enum _RecoverStep { recover, otp, reset, success }

class _ForgotPasswordOtpScreenState extends State<ForgotPasswordOtpScreen> {
  static const Color _forestTop = Color(0xFF004D40);
  static const Color _emeraldBottom = Color(0xFF00695C);
  static const Color _goldBright = Color(0xFFFFD700);

  final FirebaseAuth _auth = FirebaseAuth.instance;

  _RecoverStep _step = _RecoverStep.recover;
  bool _busy = false;

  String _phoneNumber = '+92';
  String? _verificationId;

  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  final List<TextEditingController> _otpControllers =
      List<TextEditingController>.generate(4, (_) => TextEditingController());
  final List<FocusNode> _otpNodes = List<FocusNode>.generate(4, (_) => FocusNode());

  @override
  void dispose() {
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

  Future<void> _sendOtp() async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: _phoneNumber,
        timeout: const Duration(seconds: 60),
        verificationCompleted: (credential) async {
          await _auth.signInWithCredential(credential);
          if (!mounted) return;
          setState(() => _step = _RecoverStep.reset);
        },
        verificationFailed: (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Text(error.message ?? 'Failed to send OTP.'),
            ),
          );
        },
        codeSent: (verificationId, _) {
          _verificationId = verificationId;
          if (!mounted) return;
          setState(() => _step = _RecoverStep.otp);
          Future<void>.delayed(const Duration(milliseconds: 220), () {
            if (!mounted) return;
            _otpNodes.first.requestFocus();
          });
        },
        codeAutoRetrievalTimeout: (verificationId) {
          _verificationId = verificationId;
        },
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      final chars = value.split('');
      for (int i = 0; i < chars.length && i + index < _otpControllers.length; i++) {
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
    if (code.length != 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Please enter valid 4-digit OTP.'),
        ),
      );
      return;
    }

    final verificationId = _verificationId;
    if (verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('OTP expired. Please request again.'),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _busy = true);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: code,
      );
      await _auth.signInWithCredential(credential);
      if (!mounted) return;
      setState(() => _step = _RecoverStep.reset);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(e.message ?? 'Invalid OTP.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _resetPassword() {
    final newPassword = _newPasswordController.text.trim();
    final confirmPassword = _confirmPasswordController.text.trim();

    if (newPassword.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Password should be at least 6 characters.'),
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text('Passwords do not match.'),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _step = _RecoverStep.success);
  }

  InputDecoration _fieldDecoration({required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.poppins(color: Colors.white70),
      prefixIcon: Icon(icon, color: _goldBright),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: _goldBright.withValues(alpha: 0.82), width: 0.9),
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
        Text(
          'Account Recover Karein',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Apna registered number darj karein',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        IntlPhoneField(
          initialCountryCode: 'PK',
          style: GoogleFonts.poppins(color: Colors.white),
          dropdownTextStyle: GoogleFonts.poppins(color: Colors.white),
          decoration: _fieldDecoration(
            label: 'Mobile Number',
            icon: Icons.phone_android_rounded,
          ),
          onChanged: (phone) {
            _phoneNumber = phone.completeNumber;
          },
          validator: (value) {
            final raw = value?.completeNumber.trim() ?? '';
            if (raw.length < 10) return 'Enter valid number';
            return null;
          },
        ),
        const SizedBox(height: 12),
        _GoldButton(
          label: _busy ? 'OTP bhej rahe hain...' : 'OTP Bhejein',
          onPressed: _busy ? null : _sendOtp,
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return Column(
      key: const ValueKey<String>('otp'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          '4-digit OTP darj karein',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.white70),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List<Widget>.generate(_otpControllers.length, (index) {
            return SizedBox(
              width: 58,
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
                    borderSide: const BorderSide(color: _goldBright, width: 1.2),
                  ),
                ),
                onChanged: (value) => _onOtpChanged(index, value),
              ),
            );
          }),
        ),
        const SizedBox(height: 14),
        _GoldButton(
          label: _busy ? 'Verifying...' : 'OTP Verify Karein',
          onPressed: _busy ? null : _verifyOtp,
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    return Column(
      key: const ValueKey<String>('reset'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          label: 'Password Reset Karein',
          onPressed: _resetPassword,
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey<String>('success'),
      children: [
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
            child: const Icon(Icons.check_circle_rounded, size: 62, color: _goldBright),
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
          style: GoogleFonts.poppins(color: Colors.white70),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_forestTop, _emeraldBottom],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - 90,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(26),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(26),
                          border: Border.all(
                            color: _goldBright.withValues(alpha: 0.68),
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
                              child: FadeTransition(opacity: animation, child: child),
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
            colors: [Color(0xFFEACB73), Color(0xFFD4AF37), Color(0xFFBD972A)],
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