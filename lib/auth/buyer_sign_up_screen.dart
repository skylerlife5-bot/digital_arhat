import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/pakistan_location_service.dart';
import '../dashboard/buyer/buyer_dashboard.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';

class BuyerSignUpScreen extends StatefulWidget {
  const BuyerSignUpScreen({super.key});

  @override
  State<BuyerSignUpScreen> createState() => _BuyerSignUpScreenState();
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

  int _currentStep = 0;
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;

  String? _verificationId;
  int _resendSecondsRemaining = 0;
  Timer? _resendTimer;

  bool _otpSent = false;
  bool _otpVerified = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    PakistanLocationService.instance.loadIfNeeded().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
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

  bool _validateBasicInfo() {
    final String name = _nameController.text.trim();
    final String phoneDigits = _normalizePhoneDigits(_phoneController.text);
    final String password = _passwordController.text.trim();
    final String confirmPassword = _confirmPasswordController.text.trim();

    if (name.isEmpty) {
      _showSnack('Full name is required / مکمل نام لازمی ہے');
      return false;
    }
    if (phoneDigits.isEmpty) {
      _showSnack('Mobile number is required / موبائل نمبر لازمی ہے');
      return false;
    }
    if (phoneDigits.length != 10) {
      _showSnack(
        'Enter valid 10-digit number / 10 ہندسوں والا درست نمبر درج کریں',
      );
      return false;
    }
    if (!phoneDigits.startsWith('3')) {
      _showSnack(
        'Enter valid Pakistani mobile number / درست پاکستانی موبائل نمبر درج کریں',
      );
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
    if ((_selectedCity ?? '').isEmpty) {
      _showSnack('City is required / شہر لازمی ہے');
      return false;
    }

    return true;
  }

  Future<bool> _hasDuplicatePhone(
    String normalizedPhone, {
    String? ignoreUid,
  }) async {
    final String raw92 = normalizedPhone.replaceFirst('+', '');

    final QuerySnapshot<Map<String, dynamic>> q1 = await FirebaseFirestore
        .instance
        .collection('users')
        .where('phone', isEqualTo: normalizedPhone)
        .limit(2)
        .get();

    bool hasConflict(QuerySnapshot<Map<String, dynamic>> q) => q.docs.any(
      (QueryDocumentSnapshot<Map<String, dynamic>> doc) => doc.id != ignoreUid,
    );

    if (hasConflict(q1)) return true;

    final QuerySnapshot<Map<String, dynamic>> q2 = await FirebaseFirestore
        .instance
        .collection('users')
        .where('phone', isEqualTo: raw92)
        .limit(2)
        .get();

    return hasConflict(q2);
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

    final String normalizedPhone =
        '+92${_normalizePhoneDigits(_phoneController.text)}';
    if (await _hasDuplicatePhone(normalizedPhone)) {
      _showSnack(
        'This phone number is already registered.\nیہ موبائل نمبر پہلے سے رجسٹرڈ ہے۔',
      );
      return;
    }

    setState(() => _isSendingOtp = true);
    try {
      await _authService.sendOTP(normalizedPhone, (String verificationId) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _otpSent = true;
          _otpVerified = false;
        });
      });
      if (!mounted) return;
      _startResendCountdown();
      _showSnack('OTP sent successfully / او ٹی پی کامیابی سے بھیج دی گئی');
    } catch (_) {
      _showSnack('Unable to send OTP right now / او ٹی پی بھیجنے میں مسئلہ');
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _verifyOtp() async {
    final String otp = _otpController.text.trim();
    if ((_verificationId ?? '').isEmpty) {
      _showSnack('Send OTP first / پہلے او ٹی پی بھیجیں');
      return;
    }
    if (otp.length != 6) {
      _showSnack(
        'Enter valid 6-digit OTP / درست 6 ہندسوں کی او ٹی پی درج کریں',
      );
      return;
    }

    setState(() => _isVerifyingOtp = true);
    try {
      final UserCredential? credential = await _authService.verifyOTP(
        _verificationId!,
        otp,
      );
      if (credential?.user == null) {
        _showSnack('OTP verification failed / او ٹی پی تصدیق ناکام');
        return;
      }
      if (!mounted) return;
      setState(() => _otpVerified = true);
      _showSnack('Verified / تصدیق شدہ');
    } catch (_) {
      _showSnack('Invalid OTP / غلط او ٹی پی');
    } finally {
      if (mounted) setState(() => _isVerifyingOtp = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.black87,
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

    final String normalizedDigits = _normalizePhoneDigits(
      _phoneController.text,
    );
    final String normalizedPhone = '+92$normalizedDigits';
    final DocumentReference<Map<String, dynamic>> docRef = FirebaseFirestore
        .instance
        .collection('users')
        .doc(user.uid);

    await docRef.set(<String, dynamic>{
      'role': 'buyer',
      'userRole': 'buyer',
      'userType': 'buyer',
      'phone': normalizedPhone,
      'phoneVerified': true,
      'fullName': _nameController.text.trim(),
      'province': _selectedProvince,
      'district': _selectedDistrict,
      'tehsil': _selectedTehsil,
      'city': _selectedCity,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return true;
  }

  Future<bool> _createOrUseBuyerAuth() async {
    final String email = phoneToEmail(
      _normalizePhoneDigits(_phoneController.text.trim()),
    );
    final String password = _passwordController.text.trim();
    final User? current = FirebaseAuth.instance.currentUser;

    if (current != null) {
      final Set<String> providerIds = current.providerData
          .map((UserInfo userInfo) => userInfo.providerId)
          .toSet();
      if (!providerIds.contains('password')) {
        await current.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      } else {
        await current.updatePassword(password);
      }
      return true;
    }

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        return true;
      }
      rethrow;
    }
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

    setState(() => _isSubmitting = true);

    try {
      await _createOrUseBuyerAuth();
      final User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        _showSnack('Account creation failed / اکاؤنٹ بنانے میں مسئلہ');
        return;
      }

      final String normalizedPhone =
          '+92${_normalizePhoneDigits(_phoneController.text)}';
      if (await _hasDuplicatePhone(normalizedPhone, ignoreUid: user.uid)) {
        _showSnack(
          'This phone number is already registered.\nیہ موبائل نمبر پہلے سے رجسٹرڈ ہے۔',
        );
        return;
      }

      final bool saved = await _persistBuyerProfile();
      if (!saved) {
        if (mounted) setState(() => _isSubmitting = false);
        return;
      }

      final Map<String, dynamic> buyerData = <String, dynamic>{
        'role': 'buyer',
        'userRole': 'buyer',
        'userType': 'buyer',
        'name': _nameController.text.trim(),
        'fullName': _nameController.text.trim(),
        'phone': '+92${_normalizePhoneDigits(_phoneController.text)}',
        'province': _selectedProvince,
        'district': _selectedDistrict,
        'tehsil': _selectedTehsil,
        'city': _selectedCity,
      };

      if (!mounted) return;
      await _showSuccessDialog();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BuyerDashboard(userData: buyerData),
        ),
      );
    } catch (_) {
      _showSnack(
        'Unable to create account right now / اکاؤنٹ بنانے میں مسئلہ پیش آیا',
      );
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
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.5),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
            ),
          ),
          const Expanded(child: SizedBox.shrink()),
          const Expanded(
            child: Text(
              'Buyer Sign Up / خریدار رجسٹریشن',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final PakistanLocationService locationService =
      PakistanLocationService.instance;
    final List<String> provinces = locationService.provinces;
    final List<String> districts = _selectedProvince == null
        ? <String>[]
      : locationService.districtsForProvince(_selectedProvince!);
    final List<String> tehsils = _selectedDistrict == null
        ? <String>[]
      : locationService.tehsilsForDistrict(_selectedDistrict!);
    final List<String> cities =
        (_selectedDistrict == null || _selectedTehsil == null)
        ? <String>[]
      : locationService.cityOptions(
            district: _selectedDistrict!,
            tehsil: _selectedTehsil!,
          );

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
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.all(14),
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
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 14),
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
                                          LengthLimitingTextInputFormatter(11),
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
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedProvince,
                                        dropdownColor: _greenMid,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'Province / صوبہ',
                                          hint:
                                              'Select province / صوبہ منتخب کریں',
                                          prefix: const Icon(
                                            Icons.map_outlined,
                                            color: _gold,
                                          ),
                                        ),
                                        items: provinces
                                            .map(
                                              (String province) =>
                                                  DropdownMenuItem<String>(
                                                    value: province,
                                                    child: Text(province),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: (String? value) {
                                          setState(() {
                                            _selectedProvince = value;
                                            _selectedDistrict = null;
                                            _selectedTehsil = null;
                                            _selectedCity = null;
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedDistrict,
                                        dropdownColor: _greenMid,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'District / ضلع',
                                          hint:
                                              'Select district / ضلع منتخب کریں',
                                          prefix: const Icon(
                                            Icons.location_city_rounded,
                                            color: _gold,
                                          ),
                                        ),
                                        items: districts
                                            .map(
                                              (String district) =>
                                                  DropdownMenuItem<String>(
                                                    value: district,
                                                    child: Text(district),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: _selectedProvince == null
                                            ? null
                                            : (String? value) {
                                                setState(() {
                                                  _selectedDistrict = value;
                                                  _selectedTehsil = null;
                                                  _selectedCity = null;
                                                });
                                              },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedTehsil,
                                        dropdownColor: _greenMid,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'Tehsil / تحصیل',
                                          hint:
                                              'Select tehsil / تحصیل منتخب کریں',
                                          prefix: const Icon(
                                            Icons.account_tree_outlined,
                                            color: _gold,
                                          ),
                                        ),
                                        items: tehsils
                                            .map(
                                              (String tehsil) =>
                                                  DropdownMenuItem<String>(
                                                    value: tehsil,
                                                    child: Text(tehsil),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: _selectedDistrict == null
                                            ? null
                                            : (String? value) {
                                                setState(() {
                                                  _selectedTehsil = value;
                                                  _selectedCity = null;
                                                });
                                              },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedCity,
                                        dropdownColor: _greenMid,
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                        decoration: _inputDecoration(
                                          label: 'City / شہر',
                                          hint: 'Select city / شہر منتخب کریں',
                                          prefix: const Icon(
                                            Icons.pin_drop_outlined,
                                            color: _gold,
                                          ),
                                        ),
                                        items: cities
                                            .map(
                                              (String city) =>
                                                  DropdownMenuItem<String>(
                                                    value: city,
                                                    child: Text(city),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: _selectedTehsil == null
                                            ? null
                                            : (String? value) {
                                                setState(
                                                  () => _selectedCity = value,
                                                );
                                              },
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
                                      Text(
                                        'Mobile Number / موبائل نمبر: +92${_normalizePhoneDigits(_phoneController.text)}',
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
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
                                      const SizedBox(height: 10),
                                      TextFormField(
                                        controller: _otpController,
                                        keyboardType: TextInputType.number,
                                        maxLength: 6,
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
                                          onPressed: _isVerifyingOtp
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
                                      const SizedBox(height: 10),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: _otpVerified
                                                ? Colors.greenAccent
                                                : Colors.white24,
                                          ),
                                        ),
                                        child: Text(
                                          _otpVerified
                                              ? 'Verified / تصدیق شدہ'
                                              : 'Not verified / غیر تصدیق شدہ',
                                          style: TextStyle(
                                            color: _otpVerified
                                                ? Colors.greenAccent
                                                : Colors.white70,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        height: 52,
                                        child: ElevatedButton(
                                          onPressed: _isSubmitting
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
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                        ),
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
