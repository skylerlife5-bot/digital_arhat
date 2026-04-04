import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/location_display_helper.dart';
import '../core/pakistan_location_service.dart';
import '../dashboard/buyer/buyer_dashboard.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class BuyerSignUpScreen extends StatefulWidget {
  const BuyerSignUpScreen({super.key});

  @override
  State<BuyerSignUpScreen> createState() => _BuyerSignUpScreenState();
}

class _BuyerSignupFlowException implements Exception {
  const _BuyerSignupFlowException(this.userMessage);

  final String userMessage;
}

class _BuyerSignUpScreenState extends State<BuyerSignUpScreen> {
  static const Color _deepGreen = AppColors.background;
  static const Color _greenMid = AppColors.cardSurface;
  static const Color _gold = AppColors.accentGold;
  static const int _totalSteps = 3;

  final AuthService _authService = AuthService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();

  int _currentStep = 0;
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _cityText;

  String? _verificationId;
  String _phoneStateSnapshot = '';
  String? _otpRequestedPhone;
  String? _verifiedPhone;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;

  bool _otpSent = false;
  bool _otpVerified = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  int? _otpResendToken;
  String _otpStatusMessage = '';
  bool _otpStatusIsError = false;

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_handlePhoneInputChanged);
    _cityController.addListener(() {
      _cityText = _cityController.text.trim();
    });
    PakistanLocationService.instance.loadIfNeeded().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _phoneController.removeListener(_handlePhoneInputChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _cityController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  String _normalizePakistanPhoneE164(String input) =>
      _authService.normalizePhone(input);

  String _sanitizeLocalPhoneInput(String input) {
    String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('92')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length > 10) {
      digits = digits.substring(0, 10);
    }
    if (digits.isNotEmpty && !digits.startsWith('3')) {
      final int idx = digits.indexOf('3');
      if (idx >= 0) {
        digits = digits.substring(idx);
        if (digits.length > 10) {
          digits = digits.substring(0, 10);
        }
      } else {
        digits = '';
      }
    }
    return digits;
  }

  void _handlePhoneInputChanged() {
    final String current = _phoneController.text;
    final String cleaned = _sanitizeLocalPhoneInput(current);

    if (cleaned != current) {
      _phoneController.text = cleaned;
      _phoneController.selection = TextSelection.fromPosition(
        TextPosition(offset: cleaned.length),
      );
    }

    final String normalizedPhone = _normalizePakistanPhoneE164(cleaned);
    if (normalizedPhone == _phoneStateSnapshot) {
      return;
    }

    final bool hadOtpState =
        _otpSent ||
        _otpVerified ||
        (_verificationId ?? '').isNotEmpty ||
        (_otpRequestedPhone ?? '').isNotEmpty ||
        (_verifiedPhone ?? '').isNotEmpty ||
        _otpController.text.trim().isNotEmpty ||
        _otpStatusMessage.trim().isNotEmpty;

    setState(() {
      _phoneStateSnapshot = normalizedPhone;
      if (!hadOtpState) {
        return;
      }
      _clearOtpState(
        statusMessage:
            'Mobile number changed. Please send a new OTP. / موبائل نمبر تبدیل ہوگیا، نئی او ٹی پی بھیجیں',
        isError: true,
      );
    });
  }

  void _clearOtpState({
    String? statusMessage,
    bool isError = false,
    bool keepStatus = false,
  }) {
    _verificationId = null;
    _otpRequestedPhone = null;
    _verifiedPhone = null;
    _otpSent = false;
    _otpVerified = false;
    _otpResendToken = null;
    _resendTimer?.cancel();
    _resendSecondsRemaining = 0;
    _otpController.clear();
    if (keepStatus) {
      return;
    }
    _otpStatusMessage = statusMessage ?? '';
    _otpStatusIsError = statusMessage != null && statusMessage.trim().isNotEmpty
        ? isError
        : false;
  }

  void _setOtpStatus(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _otpStatusMessage = message;
      _otpStatusIsError = isError;
    });
  }

  String _formattedPhoneForDisplay() {
    final String cleanDigits = _sanitizeLocalPhoneInput(_phoneController.text);
    if (cleanDigits.length != 10) {
      return '+92 XXX XXXXXXX';
    }
    final String a = cleanDigits.substring(0, 3);
    final String b = cleanDigits.substring(3);
    return '+92 $a $b';
  }

  String _locationOptionLabel(BilingualLocationOption option) {
    return LocationDisplayHelper.bilingualLabelFromParts(
      option.labelEn,
      candidateUrdu: option.labelUr,
    );
  }

  Future<String?> _showSearchableLocationSelector({
    required String title,
    required List<BilingualLocationOption> options,
    String? selected,
  }) async {
    if (options.isEmpty) return null;
    final TextEditingController searchCtrl = TextEditingController();
    List<BilingualLocationOption> filtered = options;

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.78,
              ),
              decoration: BoxDecoration(
                color: _greenMid,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                border: Border.all(color: _gold.withValues(alpha: 0.35)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Search in English or Urdu / انگریزی یا اردو میں تلاش کریں',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchCtrl,
                        style: const TextStyle(color: Colors.white),
                        decoration: _inputDecoration(
                          label: 'Search / تلاش',
                          hint: 'e.g. Kasur / قصور',
                          prefix: const Icon(Icons.search, color: _gold),
                        ),
                        onChanged: (String value) {
                          setSheetState(() {
                            final String query = value.trim().toLowerCase();
                            filtered = options
                                .where((BilingualLocationOption option) {
                                  final String display = _locationOptionLabel(
                                    option,
                                  ).toLowerCase();
                                  return query.isEmpty ||
                                      option.labelEn.toLowerCase().contains(
                                        query,
                                      ) ||
                                      display.contains(query);
                                })
                                .toList(growable: false);
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: filtered.length,
                          separatorBuilder: (BuildContext context, int index) =>
                              Divider(
                                color: Colors.white.withValues(alpha: 0.08),
                                height: 1,
                              ),
                          itemBuilder: (BuildContext context, int index) {
                            final BilingualLocationOption item =
                                filtered[index];
                            final bool isSelected = selected == item.labelEn;
                            return ListTile(
                              dense: true,
                              onTap: () => Navigator.of(ctx).pop(item.labelEn),
                              leading: Icon(
                                isSelected
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? _gold : Colors.white54,
                                size: 18,
                              ),
                              title: Text(
                                _locationOptionLabel(item),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  height: 1.2,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildLocationSelectorField({
    required String label,
    required IconData icon,
    required String? selectedValue,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final String shown = (selectedValue ?? '').trim().isEmpty
        ? label
        : LocationDisplayHelper.bilingualLabel(selectedValue!);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: enabled
                ? _gold.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.14),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: enabled ? _gold : Colors.white30, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                shown,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white54,
                  fontSize: 13.5,
                  height: 1.2,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: enabled ? Colors.white70 : Colors.white24,
            ),
          ],
        ),
      ),
    );
  }

  void _logBuyerOtpEvent(
    String event, {
    String? normalizedPhone,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final FirebaseException? firestoreError = error is FirebaseException
        ? error
        : null;
    final FirebaseAuthException? authError = error is FirebaseAuthException
        ? error
        : null;
    final Map<String, Object?> payload = <String, Object?>{
      'flow': 'buyer_sign_up',
      'event': event,
      'normalizedPhone': normalizedPhone,
      'error': error?.toString(),
      'firebaseAuthCode': authError?.code,
      'firebaseAuthMessage': authError?.message,
      'firestoreCode': firestoreError?.code,
      'firestoreMessage': firestoreError?.message,
      ...extra,
    };
    final String firebaseCode =
        authError?.code ?? firestoreError?.code ?? 'none';
    final String firebaseMessage =
        authError?.message ?? firestoreError?.message ?? 'none';
    debugPrint(
      '[BUYER_SIGNUP][$event] code=$firebaseCode message=$firebaseMessage phone=$normalizedPhone error=$error',
    );
    developer.log(
      jsonEncode(payload),
      name: 'DigitalArhat.BuyerSignup',
      error: error,
      stackTrace: stackTrace,
    );
  }

  bool _validateBasicInfo() {
    final String name = _nameController.text.trim();
    final String phoneE164 = _normalizePakistanPhoneE164(_phoneController.text);
    final String password = _passwordController.text.trim();
    final String confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty) {
      _showSnack('Full name is required / مکمل نام لازمی ہے');
      return false;
    }
    if (phoneE164.isEmpty) {
      _showSnack('Mobile number is required / موبائل نمبر لازمی ہے');
      return false;
    }
    if (password.isEmpty) {
      _showSnack('Password is required / پاس ورڈ لازمی ہے');
      return false;
    }
    if (password.length < 8) {
      _showSnack(
        'Password must be at least 8 characters / پاس ورڈ کم از کم 8 حروف کا ہو',
      );
      return false;
    }
    if (confirmPassword.isEmpty) {
      _showSnack('Confirm password is required / دوبارہ پاس ورڈ لازمی ہے');
      return false;
    }
    if (password != confirmPassword) {
      _showSnack('Passwords do not match / پاس ورڈ ایک جیسے نہیں ہیں');
      return false;
    }

    return true;
  }

  bool _validateLocation() {
    if ((_selectedProvince ?? '').isEmpty) {
      _showSnack('Province is required / صوبہ لازمی ہے');
      return false;
    }
    if ((_selectedDistrict ?? '').isEmpty) {
      _showSnack('District is required / ضلع لازمی ہے');
      return false;
    }
    if ((_selectedTehsil ?? '').isEmpty) {
      _showSnack('Tehsil is required / تحصیل لازمی ہے');
      return false;
    }
    if ((_cityText ?? '').trim().length < 2) {
      _showSnack('City / شہر / علاقہ is required (min 2 chars)');
      return false;
    }
    return true;
  }

  Future<bool> _hasDuplicatePhone(
    String normalizedPhone, {
    String? ignoreUid,
  }) async {
    _logBuyerOtpEvent(
      'duplicate_check_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'sourcePath': 'phone_index/$normalizedPhone',
        'ignoreUid': ignoreUid,
      },
    );
    final bool duplicateExists = await _authService.isPhoneRegisteredInIndex(
      normalizedPhone,
      ignoreUid: ignoreUid,
    );
    _logBuyerOtpEvent(
      duplicateExists
          ? 'duplicate_check_duplicate_exists'
          : 'duplicate_check_not_found',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'sourcePath': 'phone_index/$normalizedPhone',
        'duplicateExists': duplicateExists,
      },
    );
    return duplicateExists;
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (!_validateBasicInfo()) return;
      setState(() => _currentStep = 1);
      return;
    }

    if (_currentStep == 1) {
      if (!_validateLocation()) return;
      setState(() => _currentStep = 2);
      return;
    }
  }

  void _previousStep() {
    if (_currentStep <= 0) return;
    setState(() => _currentStep -= 1);
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsRemaining = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsRemaining <= 1) {
        timer.cancel();
        setState(() => _resendSecondsRemaining = 0);
        return;
      }
      setState(() => _resendSecondsRemaining -= 1);
    });
  }

  Future<void> _sendOtp() async {
    if (!_validateBasicInfo()) return;

    final String normalizedPhone = _normalizePakistanPhoneE164(
      _phoneController.text,
    );
    bool duplicateExists = false;
    try {
      duplicateExists = await _hasDuplicatePhone(normalizedPhone);
    } catch (error, stackTrace) {
      _logBuyerOtpEvent(
        'duplicate_check_failed_non_blocking',
        normalizedPhone: normalizedPhone,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'nonBlocking': true,
        },
      );
      // Duplicate pre-check must never block OTP dispatch.
      // If this read fails due transient network/rules mismatch, we still allow
      // user to verify phone and rely on finalize/write-time validation.
      _setOtpStatus(
        'Pre-check skipped due to temporary validation issue. OTP sending continues. / عارضی مسئلہ کی وجہ سے ابتدائی جانچ چھوڑ دی گئی، او ٹی پی بھیجی جا رہی ہے',
        isError: false,
      );
    }

    if (duplicateExists) {
      _showSnack(
        'This phone number is already registered.\nیہ موبائل نمبر پہلے سے رجسٹرڈ ہے۔',
      );
      _setOtpStatus(
        'This phone number is already registered.\nیہ موبائل نمبر پہلے سے رجسٹرڈ ہے۔',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _clearOtpState();
    });
    _setOtpStatus(
      'Sending OTP... / او ٹی پی بھیجی جا رہی ہے...',
      isError: false,
    );
    _logBuyerOtpEvent(
      'verify_phone_number_start_requested',
      normalizedPhone: normalizedPhone,
    );

    try {
      await _authService.sendOTP(
        normalizedPhone,
        (String verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpSent = true;
            _otpRequestedPhone = normalizedPhone;
            _verifiedPhone = null;
          });
        },
        flowLabel: 'buyer_sign_up',
        forceResendingToken: _otpResendToken,
        onResendToken: (int? token) {
          if (!mounted) return;
          setState(() => _otpResendToken = token);
        },
        onVerificationFailedMessage: (String message) {
          _setOtpStatus('OTP send failed: $message', isError: true);
        },
        onAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() => _verificationId = verificationId);
        },
        onVerificationCompleted: (UserCredential credential) async {
          if (!mounted) return;
          setState(() {
            _otpVerified = true;
            _otpSent = true;
            _otpRequestedPhone = normalizedPhone;
            _verifiedPhone = normalizedPhone;
            _verificationId = null;
          });
          _otpController.clear();
          // Clear status — inline "Phone Verified" banner is the sole indicator.
          _setOtpStatus('', isError: false);
        },
      );
      if (!mounted) return;
      _startResendCountdown();
      _setOtpStatus(
        'OTP sent successfully / او ٹی پی کامیابی سے بھیج دی گئی',
        isError: false,
      );
      _logBuyerOtpEvent(
        'code_sent_callback_observed',
        normalizedPhone: normalizedPhone,
      );
      _showSnack('OTP sent successfully / او ٹی پی کامیابی سے بھیج دی گئی');
      if (mounted) {
        _otpController.clear();
      }
    } on PhoneOtpException catch (e) {
      debugPrint(
        '[OTP_DEBUG][buyer_signup] action=send_otp code=${e.code} message=${e.message} phone=$normalizedPhone',
      );
      _logBuyerOtpEvent(
        'verify_phone_number_failed_before_ui_success',
        normalizedPhone: normalizedPhone,
        error: e,
      );
      _setOtpStatus('او ٹی پی بھیجنے میں مسئلہ پیش آیا', isError: true);
      _showSnack('Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ');
    } catch (e) {
      _logBuyerOtpEvent(
        'verify_phone_number_failed_before_ui_success',
        normalizedPhone: normalizedPhone,
        error: e,
      );
      _setOtpStatus(
        'Unable to send OTP: ${e.toString()}\nاو ٹی پی بھیجنے میں مسئلہ',
        isError: true,
      );
      _showSnack('Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ');
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final String otp = _otpController.text.trim();
    final String normalizedPhone = _normalizePakistanPhoneE164(
      _phoneController.text,
    );
    if ((_verificationId ?? '').isEmpty) {
      _showSnack('Send OTP first / پہلے او ٹی پی بھیجیں');
      _setOtpStatus('Send OTP first / پہلے او ٹی پی بھیجیں', isError: true);
      return;
    }
    if ((_otpRequestedPhone ?? '').isNotEmpty &&
        _otpRequestedPhone != normalizedPhone) {
      _clearOtpState(
        statusMessage:
            'Mobile number changed. Please request a fresh OTP. / موبائل نمبر تبدیل ہوگیا، نئی او ٹی پی بھیجیں',
        isError: true,
      );
      _showSnack(
        'Mobile number changed. Please send OTP again. / موبائل نمبر تبدیل ہوگیا، دوبارہ او ٹی پی بھیجیں',
      );
      return;
    }
    if (otp.length != 6) {
      _showSnack('Enter valid 6-digit OTP');
      _setOtpStatus('Enter valid 6-digit OTP', isError: true);
      return;
    }

    setState(() => _isVerifyingOtp = true);
    _setOtpStatus(
      'Verifying OTP... / او ٹی پی کی تصدیق جاری ہے...',
      isError: false,
    );
    try {
      final UserCredential? credential = await _authService.verifyOTP(
        _verificationId!,
        otp,
        flowLabel: 'buyer_sign_up',
        phoneNumber: _phoneController.text,
      );
      if (credential?.user == null) {
        _setOtpStatus('OTP verification failed', isError: true);
        return;
      }
      if (!mounted) return;
      setState(() {
        _otpVerified = true;
        _otpSent = false;
        _verifiedPhone = normalizedPhone;
        _verificationId = null;
      });
      _otpController.clear();
      // Clear status message — the inline "Phone Verified" banner is the
      // sole success indicator; a snackbar would create a duplicate display.
      _setOtpStatus('', isError: false);
    } on PhoneOtpException catch (e) {
      debugPrint(
        '[OTP_DEBUG][buyer_signup] action=verify_otp code=${e.code} message=${e.message} phone=${_phoneController.text.trim()}',
      );
      final String friendlyMsg = _mapOtpError(e.code, e.message);
      _setOtpStatus(friendlyMsg, isError: true);
    } catch (e) {
      _setOtpStatus('Error verifying OTP', isError: true);
    } finally {
      if (mounted) setState(() => _isVerifyingOtp = false);
    }
  }

  String _mapOtpError(String code, String message) {
    final String c = code.toLowerCase();
    if (c.contains('invalid-verification-code') ||
        c.contains('invalid-credential')) {
      return 'OTP code is incorrect / او ٹی پی درست نہیں ہے';
    }
    if (c.contains('code-send-timeout')) {
      return 'OTP request timed out. Please try again';
    }
    if (c.contains('too-many-requests')) {
      return 'Too many attempts. Please wait before trying again';
    }
    if (c.contains('network')) {
      return 'Network error. Check your connection';
    }
    return message.isNotEmpty ? message : 'OTP verification failed';
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(color: Color(0xFFF6F2E8)),
          ),
          backgroundColor: const Color(0xFF1B1D21),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<bool> _persistBuyerProfile() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('Verify phone first / پہلے فون تصدیق کریں');
      return false;
    }

    final String normalizedPhone = _normalizePakistanPhoneE164(
      _phoneController.text,
    );
    if (normalizedPhone.isEmpty) {
      throw const _BuyerSignupFlowException(
        'Please enter a valid Pakistani phone number before completing signup. / سائن اپ مکمل کرنے سے پہلے درست پاکستانی موبائل نمبر درج کریں',
      );
    }
    final String province = (_selectedProvince ?? '').trim();
    final String district = (_selectedDistrict ?? '').trim();
    final String tehsil = (_selectedTehsil ?? '').trim();
    final String city = (_cityText ?? '').trim();
    final String provinceUr = LocationDisplayHelper.resolvedUrduLabel(province);
    final String districtUr = LocationDisplayHelper.resolvedUrduLabel(district);
    final String tehsilUr = LocationDisplayHelper.resolvedUrduLabel(tehsil);
    final String cityUr = LocationDisplayHelper.resolvedUrduLabel(city);
    final DocumentReference<Map<String, dynamic>> docRef = FirebaseFirestore
        .instance
        .collection('users')
        .doc(user.uid);

    _logBuyerOtpEvent(
      'finalize_profile_persist_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'otpVerified': _otpVerified,
        'authCurrentUid': user.uid,
        'usersWritePath': 'users/${user.uid}',
        'phoneIndexWritePath': 'phone_index/$normalizedPhone',
      },
    );

    try {
      await docRef.set(<String, dynamic>{
        'role': 'buyer',
        'userRole': 'buyer',
        'userType': 'buyer',
        'name': _nameController.text.trim(),
        'phone': normalizedPhone,
        'phoneVerified': true,
        'is_verified': true,
        'isVerified': true,
        'verificationStatus': 'approved',
        'isApproved': true,
        'fullName': _nameController.text.trim(),
        'password': _passwordController.text.trim(),
        'passwordHash': _authService.hashPassword(
          _passwordController.text.trim(),
        ),
        'province': province,
        'province_en': province,
        'province_ur': provinceUr,
        'district': district,
        'district_en': district,
        'district_ur': districtUr,
        'tehsil': tehsil,
        'tehsil_en': tehsil,
        'tehsil_ur': tehsilUr,
        'city': city,
        'city_text': city,
        'city_text_ur': cityUr,
        'locationDisplay': LocationDisplayHelper.locationDisplayFromData(
          <String, dynamic>{
            'province': province,
            'district': district,
            'tehsil': tehsil,
            'city': city,
          },
        ),
        'locationNodes': <String, dynamic>{
          'province': <String, String>{
            'name_en': province,
            'name_ur': provinceUr,
          },
          'district': <String, String>{
            'name_en': district,
            'name_ur': districtUr,
          },
          'tehsil': <String, String>{'name_en': tehsil, 'name_ur': tehsilUr},
          'city': <String, String>{'name_en': city, 'name_ur': cityUr},
        },
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _logBuyerOtpEvent(
        'finalize_users_write_succeeded',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'usersWritePath': 'users/${user.uid}',
          'authCurrentUid': user.uid,
        },
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[BUYER_SIGNUP][users_write_failed] error=$error stack=$stackTrace',
      );
      _logBuyerOtpEvent(
        'finalize_users_write_failed',
        normalizedPhone: normalizedPhone,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{
          'usersWritePath': 'users/${user.uid}',
          'authCurrentUid': user.uid,
        },
      );
      rethrow;
    }

    try {
      await _authService.upsertPhoneIndex(
        normalizedPhone: normalizedPhone,
        uid: user.uid,
      );
      _logBuyerOtpEvent(
        'finalize_phone_index_write_succeeded',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'phoneIndexWritePath': 'phone_index/$normalizedPhone',
          'authCurrentUid': user.uid,
        },
      );
    } catch (error, stackTrace) {
      // Phone index write is a secondary operation — users doc was already
      // written successfully.  Log the failure but do NOT rethrow; account
      // creation should still be considered successful from the user's perspective.
      debugPrint(
        '[BUYER_SIGNUP][phone_index_write_failed] error=$error stack=$stackTrace',
      );
      _logBuyerOtpEvent(
        'finalize_phone_index_write_failed_non_fatal',
        normalizedPhone: normalizedPhone,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{
          'phoneIndexWritePath': 'phone_index/$normalizedPhone',
          'authCurrentUid': user.uid,
          'nonFatal': true,
        },
      );
    }

    return true;
  }

  Future<bool> _createOrUseBuyerAuth() async {
    final String normalizedPhone = _normalizePakistanPhoneE164(
      _phoneController.text,
    );
    final String trimmedPassword = _passwordController.text.trim();
    User? current = FirebaseAuth.instance.currentUser;

    _logBuyerOtpEvent(
      'finalize_auth_binding_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'otpVerified': _otpVerified,
        'authCurrentUid': current?.uid,
        'authMode': 'phone_otp_plus_synthetic_email',
      },
    );

    if (normalizedPhone.isEmpty) {
      throw const _BuyerSignupFlowException(
        'Phone format is invalid. Please re-enter and verify OTP again. / فون فارمیٹ درست نہیں، دوبارہ درج کریں اور او ٹی پی تصدیق کریں',
      );
    }

    if (trimmedPassword.isEmpty) {
      throw const _BuyerSignupFlowException(
        'Password is required before account setup. / اکاؤنٹ سیٹ اپ سے پہلے پاس ورڈ لازمی ہے',
      );
    }

    if (current == null) {
      throw const _BuyerSignupFlowException(
        'Your verification session expired. Please verify OTP again. / آپ کا تصدیقی سیشن ختم ہوگیا، دوبارہ او ٹی پی تصدیق کریں',
      );
    }

    await current.reload();
    current = FirebaseAuth.instance.currentUser;
    if (current == null) {
      throw const _BuyerSignupFlowException(
        'Your verification session expired. Please verify OTP again. / آپ کا تصدیقی سیشن ختم ہوگیا، دوبارہ او ٹی پی تصدیق کریں',
      );
    }

    _logBuyerOtpEvent(
      'finalize_auth_password_link_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'authCurrentUid': current.uid,
        'flowLabel': 'buyer_signup',
      },
    );

    final bool passwordProviderLinked =
        await _authService.ensurePasswordProviderLinkedForCurrentUser(
          normalizedPhone: normalizedPhone,
          password: trimmedPassword,
          flowLabel: 'buyer_signup',
        );
    debugPrint(
      '[BUYER_SIGNUP] uid=${current.uid} passwordProviderLinked=$passwordProviderLinked',
    );

    if (!passwordProviderLinked) {
      _logBuyerOtpEvent(
        'finalize_auth_password_link_failed',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'authCurrentUid': current.uid,
          'flowLabel': 'buyer_signup',
        },
      );
      throw const _BuyerSignupFlowException(
        'Account setup could not complete securely. Please retry OTP verification and signup. / اکاؤنٹ سیٹ اپ محفوظ طریقے سے مکمل نہیں ہو سکا، او ٹی پی دوبارہ تصدیق کر کے سائن اپ کریں',
      );
    }

    _logBuyerOtpEvent(
      'finalize_auth_password_link_succeeded',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'authCurrentUid': current.uid,
        'authMode': 'phone_otp_plus_synthetic_email',
      },
    );

    return true;
  }

  String _friendlyFinalizeError(Object error) {
    if (error is _BuyerSignupFlowException) {
      return error.userMessage;
    }
    if (error is PhoneOtpException) {
      return _mapOtpError(error.code, error.message);
    }
    if (error is FirebaseAuthException) {
      final String c = error.code.toLowerCase();
      debugPrint(
        '[BUYER_SIGNUP][auth_error_mapping] code=${error.code} message=${error.message}',
      );
      if (c == 'email-already-in-use' || c == 'credential-already-in-use') {
        return 'This mobile number is already registered. Please log in instead. / یہ موبائل نمبر پہلے سے رجسٹرڈ ہے، براہِ کرم لاگ اِن کریں';
      }
      if (c == 'invalid-credential' || c == 'user-not-found') {
        return 'Your verification session expired. Please verify OTP again. / آپ کا تصدیقی سیشن ختم ہو گیا، دوبارہ او ٹی پی تصدیق کریں';
      }
      if (c == 'requires-recent-login') {
        return 'Please verify OTP again before finishing signup. / سائن اپ مکمل کرنے سے پہلے دوبارہ او ٹی پی تصدیق کریں';
      }
      if (c.contains('network') ||
          c == 'unavailable' ||
          c.contains('network-request-failed')) {
        return 'Network issue while creating account. Please check your connection and try again. / اکاؤنٹ بناتے وقت نیٹ ورک مسئلہ آیا، کنیکشن جانچ کر دوبارہ کوشش کریں';
      }
      if (c == 'operation-not-allowed') {
        return 'Account setup is temporarily unavailable. Please try again shortly. / اکاؤنٹ سیٹ اپ عارضی طور پر دستیاب نہیں، تھوڑی دیر بعد دوبارہ کوشش کریں';
      }
      if (c == 'operation-not-supported-in-this-environment') {
        return 'Account setup requires a valid OTP session. Please verify OTP and try again. / اکاؤنٹ سیٹ اپ کے لیے او ٹی پی سیشن ضروری ہے، تصدیق کریں';
      }
      if (c == 'weak-password') {
        return 'Please choose a stronger password. / براہِ کرم مضبوط پاس ورڈ منتخب کریں';
      }
      if (c == 'too-many-requests') {
        return 'Too many attempts. Please wait a moment and try again. / بہت زیادہ کوششیں ہوئیں، تھوڑا انتظار کریں';
      }
      if (c == 'provider-already-linked') {
        // This should be handled upstream, but just in case:
        return 'Account is already set up. Please log in instead. / اکاؤنٹ پہلے سے موجود ہے، لاگ اِن کریں';
      }
      // Fallback with code for debug visibility
      return 'Account setup error (${error.code}). Please try again. / اکاؤنٹ سیٹ اپ میں مسئلہ (${error.code})، دوبارہ کوشش کریں';
    }
    if (error is FirebaseException) {
      final String c = error.code.toLowerCase();
      debugPrint(
        '[BUYER_SIGNUP][firestore_error_mapping] code=${error.code} message=${error.message}',
      );
      if (c == 'permission-denied') {
        return 'Account save permission denied. Please contact support. / اکاؤنٹ محفوظ کرنے کی اجازت نہیں ملی، سپورٹ سے رابطہ کریں';
      }
      if (c == 'unavailable' || c.contains('network')) {
        return 'Service is temporarily unavailable. Please try again. / سروس عارضی طور پر دستیاب نہیں، دوبارہ کوشش کریں';
      }
      if (c == 'not-found') {
        return 'Account data could not be saved. Please try again. / اکاؤنٹ ڈیٹا محفوظ نہیں ہو سکا، دوبارہ کوشش کریں';
      }
      return 'Account save error (${error.code}). Please try again. / اکاؤنٹ محفوظ کرنے میں مسئلہ (${error.code})، دوبارہ کوشش کریں';
    }
    debugPrint(
      '[BUYER_SIGNUP][unknown_error] type=${error.runtimeType} error=$error',
    );
    return 'Account setup failed (${error.runtimeType}). Please try again. / اکاؤنٹ سیٹ اپ میں مسئلہ ہوا، دوبارہ کوشش کریں';
  }

  String _generateDetailedErrorLog(Object error) {
    final StringBuffer buffer = StringBuffer();
    buffer.write('ErrorType: ${error.runtimeType} | ');

    if (error is FirebaseAuthException) {
      buffer.write(
        'Firebase Auth | Code: ${error.code} | Message: ${error.message}',
      );
    } else if (error is FirebaseException) {
      buffer.write(
        'Firebase Generic | Code: ${error.code} | Message: ${error.message}',
      );
    } else if (error is _BuyerSignupFlowException) {
      buffer.write('Flow Exception | Message: ${error.userMessage}');
    } else {
      buffer.write('Unknown | Message: $error');
    }

    return buffer.toString();
  }

  Future<void> _showSuccessDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF133F23),
          title: const Text(
            'Buyer account created successfully.\nخریدار اکاؤنٹ کامیابی سے بن گیا۔',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'You are now ready to browse the market.\nاب آپ مارکیٹ دیکھ سکتے ہیں۔',
            style: TextStyle(color: Colors.white70),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Start Browsing / مارکیٹ دیکھیں',
                style: TextStyle(color: _gold),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onCompleteSignUp() async {
    if (!_validateBasicInfo()) return;
    if (!_validateLocation()) return;
    if (!_otpVerified) {
      _showSnack(
        'Verify OTP before account creation / اکاؤنٹ بنانے سے پہلے او ٹی پی تصدیق کریں',
      );
      return;
    }

    final String normalizedPhone = _normalizePakistanPhoneE164(
      _phoneController.text,
    );
    if ((_verifiedPhone ?? '').isEmpty || _verifiedPhone != normalizedPhone) {
      setState(() {
        _clearOtpState(
          statusMessage:
              'Phone verification is out of date. Please verify again. / فون تصدیق پرانی ہوگئی ہے، دوبارہ تصدیق کریں',
          isError: true,
        );
      });
      _showSnack(
        'Please verify the current mobile number again. / موجودہ موبائل نمبر دوبارہ تصدیق کریں',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    _logBuyerOtpEvent(
      'finalize_submit_tapped',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'otpVerified': _otpVerified,
        'currentStep': _currentStep,
        'usersWritePath':
            'users/${FirebaseAuth.instance.currentUser?.uid ?? 'unknown'}',
        'phoneIndexWritePath': 'phone_index/$normalizedPhone',
      },
    );

    try {
      await _createOrUseBuyerAuth();
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('Account creation failed / اکاؤنٹ بنانے میں مسئلہ');
        return;
      }

      _logBuyerOtpEvent(
        'finalize_auth_user_resolved',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'authCurrentUid': user.uid,
          'providers': user.providerData
              .map((UserInfo userInfo) => userInfo.providerId)
              .toList(),
          'otpVerified': _otpVerified,
          'usersWritePath': 'users/${user.uid}',
          'phoneIndexWritePath': 'phone_index/$normalizedPhone',
        },
      );

      await _authService.persistSessionUid(user.uid);

      try {
        final bool duplicateExists = await _hasDuplicatePhone(
          normalizedPhone,
          ignoreUid: user.uid,
        );
        if (duplicateExists) {
          _logBuyerOtpEvent(
            'finalize_duplicate_phone_detected_recovered',
            normalizedPhone: normalizedPhone,
            extra: <String, Object?>{
              'authCurrentUid': user.uid,
              'phoneIndexWritePath': 'phone_index/$normalizedPhone',
              'recoveryMode': 'continue_after_phone_verified',
            },
          );
        }
      } catch (error, stackTrace) {
        _logBuyerOtpEvent(
          'finalize_duplicate_phone_check_failed_non_fatal',
          normalizedPhone: normalizedPhone,
          error: error,
          stackTrace: stackTrace,
          extra: <String, Object?>{
            'authCurrentUid': user.uid,
            'phoneIndexWritePath': 'phone_index/$normalizedPhone',
            'nonFatal': true,
          },
        );
      }

      bool saved = await _persistBuyerProfile();
      if (!saved) {
        _logBuyerOtpEvent(
          'finalize_profile_persist_returned_false',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'authCurrentUid': user.uid,
            'usersWritePath': 'users/${user.uid}',
            'phoneIndexWritePath': 'phone_index/$normalizedPhone',
          },
        );
      }

      if (!saved) {
        _logBuyerOtpEvent(
          'finalize_profile_retry_started',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'authCurrentUid': user.uid,
            'usersWritePath': 'users/${user.uid}',
            'phoneIndexWritePath': 'phone_index/$normalizedPhone',
          },
        );
        saved = await _persistBuyerProfile();
      }

      if (!saved) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      _logBuyerOtpEvent(
        'finalize_profile_persist_completed',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'authCurrentUid': user.uid,
          'usersWritePath': 'users/${user.uid}',
          'phoneIndexWritePath': 'phone_index/$normalizedPhone',
        },
      );

      final Map<String, dynamic> buyerData = <String, dynamic>{
        'role': 'buyer',
        'userRole': 'buyer',
        'userType': 'buyer',
        'name': _nameController.text.trim(),
        'fullName': _nameController.text.trim(),
        'phone': normalizedPhone,
        'province': _selectedProvince,
        'province_en': _selectedProvince,
        'province_ur': LocationDisplayHelper.resolvedUrduLabel(
          _selectedProvince ?? '',
        ),
        'district': _selectedDistrict,
        'district_en': _selectedDistrict,
        'district_ur': LocationDisplayHelper.resolvedUrduLabel(
          _selectedDistrict ?? '',
        ),
        'tehsil': _selectedTehsil,
        'tehsil_en': _selectedTehsil,
        'tehsil_ur': LocationDisplayHelper.resolvedUrduLabel(
          _selectedTehsil ?? '',
        ),
        'city': _cityText,
        'city_text': _cityText,
        'city_text_ur': LocationDisplayHelper.resolvedUrduLabel(
          _cityText ?? '',
        ),
        'locationDisplay':
            LocationDisplayHelper.locationDisplayFromData(<String, dynamic>{
              'province': _selectedProvince,
              'district': _selectedDistrict,
              'tehsil': _selectedTehsil,
              'city': _cityText,
            }),
      };

      if (!mounted) return;
      await _showSuccessDialog();
      if (!mounted) return;
      await Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BuyerDashboard(userData: buyerData),
        ),
        (Route<dynamic> route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[BUYER_SIGNUP][finalize_failed] error=$error stack=$stackTrace errorType=${error.runtimeType}',
      );

      // Log detailed exception info with full context
      final String errorDetails = _generateDetailedErrorLog(error);
      debugPrint('[BUYER_SIGNUP] Detailed error: $errorDetails');

      final User? currentUser = FirebaseAuth.instance.currentUser;
      bool usersDocExists = false;
      String? usersDocData;
      if (currentUser != null) {
        try {
          final DocumentSnapshot<Map<String, dynamic>> snapshot =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(currentUser.uid)
                  .get();
          usersDocExists = snapshot.exists;
          if (usersDocExists) {
            usersDocData = snapshot.data().toString();
          }
        } catch (e) {
          debugPrint('[BUYER_SIGNUP] Failed to check users doc: $e');
          usersDocExists = false;
        }
      }

      _logBuyerOtpEvent(
        'finalize_submit_failed',
        normalizedPhone: normalizedPhone,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{
          'otpVerified': _otpVerified,
          'authCurrentUid': currentUser?.uid,
          'usersWritePath': currentUser == null
              ? null
              : 'users/${currentUser.uid}',
          'phoneIndexWritePath': 'phone_index/$normalizedPhone',
          'usersDocExistsAfterFailure': usersDocExists,
          'usersDocData': usersDocData,
          'errorRuntimeType': error.runtimeType.toString(),
          'errorDetails': errorDetails,
        },
      );
      _showSnack(_friendlyFinalizeError(error));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    Widget? prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: Colors.white70,
        fontSize: 15,
        fontFamily: 'JameelNoori',
      ),
      hintStyle: const TextStyle(color: Colors.white54, fontSize: 13),
      prefixIcon: prefix,
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 4),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                color: Colors.white,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 50),
            child: Text(
              'Buyer Sign Up / خریدار رجسٹریشن',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PakistanLocationService locationService =
        PakistanLocationService.instance;
    final List<BilingualLocationOption> provinces =
        locationService.provinceOptions;
    final List<BilingualLocationOption> districts = _selectedProvince == null
        ? <BilingualLocationOption>[]
        : locationService.districtOptions(_selectedProvince!);
    final List<BilingualLocationOption> tehsils = _selectedDistrict == null
        ? <BilingualLocationOption>[]
        : locationService.tehsilOptions(_selectedDistrict!);
    // City suggestions can be added here if desired, but field is now free text.

    return Scaffold(
      backgroundColor: _deepGreen,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: _BuyerBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return SingleChildScrollView(
                  padding: EdgeInsets.zero,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          _buildHeader(),
                          _BuyerStepProgressBar(
                            totalSteps: _totalSteps,
                            currentStep: _currentStep,
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  18,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _gold.withValues(alpha: 0.45),
                                    width: 1.2,
                                  ),
                                  boxShadow: <BoxShadow>[
                                    BoxShadow(
                                      color: _gold.withValues(alpha: 0.17),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    const Text(
                                      'Simple, secure buyer onboarding / آسان اور محفوظ خریدار رجسٹریشن',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12.5,
                                        height: 1.25,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    if (_currentStep == 0) ...<Widget>[
                                      const Text(
                                        'Basic Info / بنیادی معلومات',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _nameController,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'Full Name / مکمل نام',
                                          hint:
                                              'Enter full name / مکمل نام درج کریں',
                                          prefix: const Icon(
                                            Icons.person_outline_rounded,
                                            color: _gold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _phoneController,
                                        keyboardType: TextInputType.phone,
                                        inputFormatters: <TextInputFormatter>[
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                          LengthLimitingTextInputFormatter(12),
                                        ],
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'Mobile Number / موبائل نمبر',
                                          hint: '3XX XXXXXXX',
                                          prefix: const SizedBox(
                                            width: 54,
                                            child: Center(
                                              child: Text(
                                                '+92',
                                                style: TextStyle(
                                                  color: _gold,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'Password / پاس ورڈ',
                                          hint:
                                              'Minimum 8 characters / کم از کم 8 حروف',
                                          prefix: const Icon(
                                            Icons.lock_outline_rounded,
                                            color: _gold,
                                          ),
                                          suffix: IconButton(
                                            onPressed: () => setState(
                                              () => _obscurePassword =
                                                  !_obscurePassword,
                                            ),
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off_rounded
                                                  : Icons.visibility_rounded,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _confirmPasswordController,
                                        obscureText: _obscureConfirmPassword,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label:
                                              'Confirm Password / پاس ورڈ دوبارہ درج کریں',
                                          hint:
                                              'Re-enter password / پاس ورڈ دوبارہ درج کریں',
                                          prefix: const Icon(
                                            Icons.lock_reset_rounded,
                                            color: _gold,
                                          ),
                                          suffix: IconButton(
                                            onPressed: () => setState(
                                              () => _obscureConfirmPassword =
                                                  !_obscureConfirmPassword,
                                            ),
                                            icon: Icon(
                                              _obscureConfirmPassword
                                                  ? Icons.visibility_off_rounded
                                                  : Icons.visibility_rounded,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      SizedBox(
                                        height: 52,
                                        child: ElevatedButton(
                                          onPressed: _nextStep,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _gold,
                                            foregroundColor: _deepGreen,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          child: const Text(
                                            'Continue / جاری رکھیں',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ] else if (_currentStep == 1) ...<Widget>[
                                      const Text(
                                        'Location / مقام',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      _buildLocationSelectorField(
                                        label: 'Province / صوبہ',
                                        icon: Icons.map_outlined,
                                        selectedValue: _selectedProvince,
                                        onTap: () async {
                                          final String? value =
                                              await _showSearchableLocationSelector(
                                                title: 'Province / صوبہ',
                                                options: provinces,
                                                selected: _selectedProvince,
                                              );
                                          if (value == null || !mounted) return;
                                          setState(() {
                                            _selectedProvince = value;
                                            _selectedDistrict = null;
                                            _selectedTehsil = null;
                                            _cityText = null;
                                            _cityController.clear();
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      _buildLocationSelectorField(
                                        label: 'District / ضلع',
                                        icon: Icons.location_city_rounded,
                                        selectedValue: _selectedDistrict,
                                        enabled: _selectedProvince != null,
                                        onTap: () async {
                                          final String? value =
                                              await _showSearchableLocationSelector(
                                                title: 'District / ضلع',
                                                options: districts,
                                                selected: _selectedDistrict,
                                              );
                                          if (value == null || !mounted) return;
                                          setState(() {
                                            _selectedDistrict = value;
                                            _selectedTehsil = null;
                                            _cityText = null;
                                            _cityController.clear();
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      _buildLocationSelectorField(
                                        label: 'Tehsil / تحصیل',
                                        icon: Icons.account_tree_outlined,
                                        selectedValue: _selectedTehsil,
                                        enabled: _selectedDistrict != null,
                                        onTap: () async {
                                          final String? value =
                                              await _showSearchableLocationSelector(
                                                title: 'Tehsil / تحصیل',
                                                options: tehsils,
                                                selected: _selectedTehsil,
                                              );
                                          if (value == null || !mounted) return;
                                          setState(() {
                                            _selectedTehsil = value;
                                            _cityText = null;
                                            _cityController.clear();
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        enabled: _selectedTehsil != null,
                                        controller: _cityController,
                                        onChanged: (String val) {
                                          _cityText = val.trim();
                                        },
                                        decoration: _inputDecoration(
                                          label: 'City / شہر / علاقہ',
                                          hint: 'Enter city, town, or area',
                                          prefix: const Icon(
                                            Icons.location_city_rounded,
                                            color: _gold,
                                          ),
                                        ).copyWith(counterText: ''),
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        textInputAction: TextInputAction.done,
                                        maxLength: 48,
                                      ),
                                      const SizedBox(height: 18),
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: _previousStep,
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(
                                                  color: _gold.withValues(
                                                    alpha: 0.7,
                                                  ),
                                                ),
                                                foregroundColor: Colors.white,
                                                minimumSize:
                                                    const Size.fromHeight(52),
                                              ),
                                              child: const Text('Back / واپس'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: _nextStep,
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: _gold,
                                                foregroundColor: _deepGreen,
                                                minimumSize:
                                                    const Size.fromHeight(52),
                                              ),
                                              child: const Text(
                                                'Continue / جاری رکھیں',
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ] else ...<Widget>[
                                      const Text(
                                        'Phone Verification / فون تصدیق',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Mobile Number / موبائل نمبر',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Directionality(
                                        textDirection: TextDirection.ltr,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            _formattedPhoneForDisplay(),
                                            textAlign: TextAlign.left,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      if (!_otpVerified) ...<Widget>[
                                        SizedBox(
                                          height: 48,
                                          child: ElevatedButton(
                                            onPressed:
                                                (_isSendingOtp ||
                                                    _resendSecondsRemaining > 0)
                                                ? null
                                                : _sendOtp,
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: _gold,
                                              foregroundColor: _deepGreen,
                                            ),
                                            child: _isSendingOtp
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: _deepGreen,
                                                        ),
                                                  )
                                                : Text(
                                                    _otpSent
                                                        ? 'Resend OTP / دوبارہ او ٹی پی بھیجیں'
                                                        : 'Send OTP / او ٹی پی بھیجیں',
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        if (_resendSecondsRemaining > 0)
                                          Text(
                                            'Resend OTP in $_resendSecondsRemaining seconds / $_resendSecondsRemaining سیکنڈ بعد دوبارہ او ٹی پی بھیجیں',
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                      if (_otpStatusMessage.isNotEmpty &&
                                          !_otpVerified) ...<Widget>[
                                        const SizedBox(height: 10),
                                        if (_otpStatusIsError ||
                                            _otpStatusMessage.isNotEmpty)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _otpStatusIsError
                                                  ? const Color(0x33D96A6A)
                                                  : const Color(0x332B5B3A),
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: _otpStatusIsError
                                                    ? const Color(0xFFE6A0A0)
                                                    : const Color(0xFFD4AF37),
                                              ),
                                            ),
                                            child: Text(
                                              _otpStatusMessage,
                                              style: TextStyle(
                                                color: _otpStatusIsError
                                                    ? const Color(0xFFFFECEC)
                                                    : const Color(0xFFFFF5D7),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                      ],
                                      if (_otpVerified) ...<Widget>[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0x332B5B3A),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: const Color(0xFFD4AF37),
                                            ),
                                          ),
                                          child: Row(
                                            children: const <Widget>[
                                              Icon(
                                                Icons.verified_rounded,
                                                color: Color(0xFFFFF5D7),
                                                size: 20,
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  'Phone Verified / فون تصدیق شدہ',
                                                  style: TextStyle(
                                                    color: Color(0xFFFFF5D7),
                                                    fontWeight: FontWeight.w700,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ] else ...<Widget>[
                                        // OTP input and verify button are visible only before success.
                                        const SizedBox(height: 10),
                                        TextFormField(
                                          controller: _otpController,
                                          keyboardType: TextInputType.number,
                                          enabled: true,
                                          maxLength: 6,
                                          onChanged: (_) => setState(() {}),
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
                                          decoration: _inputDecoration(
                                            label:
                                                'Enter OTP / او ٹی پی درج کریں',
                                            hint: '6-digit code / 6 ہندسے',
                                            prefix: const Icon(
                                              Icons.password_rounded,
                                              color: _gold,
                                            ),
                                          ).copyWith(counterText: ''),
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: 48,
                                          child: OutlinedButton(
                                            onPressed:
                                                _isVerifyingOtp ||
                                                    !_otpSent ||
                                                    _otpController.text
                                                        .trim()
                                                        .isEmpty
                                                ? null
                                                : _verifyOtp,
                                            style: OutlinedButton.styleFrom(
                                              side: BorderSide(
                                                color: _gold.withValues(
                                                  alpha: 0.8,
                                                ),
                                              ),
                                              foregroundColor: Colors.white,
                                            ),
                                            child: _isVerifyingOtp
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child:
                                                        CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                  )
                                                : const Text(
                                                    'Verify OTP / او ٹی پی تصدیق کریں',
                                                  ),
                                          ),
                                        ),
                                      ],
                                      Row(
                                        children: <Widget>[
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: _isSubmitting
                                                  ? null
                                                  : _previousStep,
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(
                                                  color: _gold.withValues(
                                                    alpha: 0.7,
                                                  ),
                                                ),
                                                foregroundColor: Colors.white,
                                                minimumSize:
                                                    const Size.fromHeight(52),
                                              ),
                                              child: const Text('Back / واپس'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: SizedBox(
                                              height: 52,
                                              child: ElevatedButton(
                                                onPressed:
                                                    (_isSubmitting ||
                                                        !_otpVerified)
                                                    ? null
                                                    : _onCompleteSignUp,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: _gold,
                                                  foregroundColor: _deepGreen,
                                                ),
                                                child: _isSubmitting
                                                    ? const SizedBox(
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                              color: _deepGreen,
                                                            ),
                                                      )
                                                    : const Text(
                                                        'Start Browsing / مارکیٹ دیکھیں',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
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
        ],
      ),
    );
  }
}

class _BuyerStepProgressBar extends StatelessWidget {
  const _BuyerStepProgressBar({
    required this.totalSteps,
    required this.currentStep,
  });

  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);
  final int totalSteps;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final double progress = totalSteps <= 1
        ? 0
        : currentStep / (totalSteps - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: SizedBox(
        height: 46,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double lineLeft = 18;
            final double lineRight = constraints.maxWidth - 18;
            final double lineWidth = math.max(0, lineRight - lineLeft);

            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  left: lineLeft,
                  right: 18,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned(
                  left: lineLeft,
                  child: Container(
                    width: lineWidth * progress,
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFFFE082), Color(0xFFFFD700)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List<Widget>.generate(totalSteps, (int index) {
                    final bool completed = index <= currentStep;
                    return Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: completed
                            ? const LinearGradient(
                                colors: <Color>[
                                  Color(0xFFFFF3C0),
                                  Color(0xFFFFD36A),
                                ],
                              )
                            : null,
                        color: completed
                            ? null
                            : _deepGreen.withValues(alpha: 0.82),
                        border: Border.all(color: _gold, width: 1.4),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: completed ? _deepGreen : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BuyerBackground extends StatelessWidget {
  const _BuyerBackground();

  static const Color _bgDeepGreen = AppColors.background;
  static const Color _bgGreenMid = AppColors.cardSurface;
  static const Color _bgGreenTop = AppColors.background;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[_bgGreenTop, _bgGreenMid, _bgDeepGreen],
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[AppColors.softOverlayWhite, Colors.transparent],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
