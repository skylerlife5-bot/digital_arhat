// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/pakistan_location_service.dart';
import '../dashboard/seller/add_listing_screen.dart';
import '../routes.dart';
import '../services/ai_generative_service.dart';
import '../services/auth_service.dart';
import '../theme/app_colors.dart';
import 'auth_state.dart';
import 'widgets/ai_loading_dialog.dart';

class MasterSignUpScreen extends StatefulWidget {
  const MasterSignUpScreen({super.key, this.selectedRole = 'seller'});

  final String selectedRole;

  @override
  State<MasterSignUpScreen> createState() => _MasterSignUpScreenState();
}

class _MasterSignUpScreenState extends State<MasterSignUpScreen> {
  static const Color _deepGreen = AppColors.background;
  static const Color _greenMid = AppColors.cardSurface;
  static const Color _gold = AppColors.accentGold;
  static const String _urduFont = 'Jameel Noori Nastaleeq';
  static const int _totalSteps = 6;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final AuthService _authService = AuthService();
  final MandiIntelligenceService _aiService = MandiIntelligenceService();
  final ImagePicker _imagePicker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _fatherNameController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  int _currentStep = 0;
  bool _isAiExtracting = false;
  bool _isSendingOtp = false;
  bool _isSubmitting = false;
  bool _phoneVerified = false;
  bool _livenessVerified = false;
  bool _frontCnicValidated = false;
  bool _backCnicValidated = false;
  bool _cnicNeedsReview = false;
  bool _accountCreated = false;
  bool _accountNeedsReview = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _aiInlineWarning;
  String? _completionMessage;
  String? _livenessStatusMessage;

  XFile? _cnicFront;
  XFile? _cnicBack;
  String? _verificationId;

  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;
  String? _selectedCategory;
  String _preferredLanguage = 'Urdu / اردو';
  bool _isSellerAccess = false;
  bool _roleResolved = false;
  Map<String, dynamic>? _createdUserData;

  static const List<_CategoryOption> _categories = <_CategoryOption>[
    _CategoryOption(key: 'crops', en: 'Crops', ur: 'فصلیں'),
    _CategoryOption(key: 'livestock', en: 'Livestock', ur: 'مویشی'),
    _CategoryOption(key: 'fruits', en: 'Fruits', ur: 'پھل'),
    _CategoryOption(key: 'vegetables', en: 'Vegetables', ur: 'سبزیاں'),
    _CategoryOption(key: 'milk', en: 'Milk', ur: 'دودھ'),
  ];

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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_roleResolved) return;

    final Object? args = ModalRoute.of(context)?.settings.arguments;
    final String? incomingRole = _resolveIncomingRole(
      args: args,
      fallback: widget.selectedRole,
    );

    if (incomingRole == 'seller') {
      _isSellerAccess = true;
      AuthState.setSelectedRole('seller');
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showSnack('یہ فارم صرف فروخت کنندہ کے لیے ہے');
        Navigator.of(context).maybePop();
      });
    }

    _roleResolved = true;
  }

  String? _normalizeRoleOrNull(Object? value) {
    final String r = (value ?? '').toString().trim().toLowerCase();
    if (r == 'seller') return 'seller';
    return null;
  }

  String? _resolveIncomingRole({
    required Object? args,
    required String? fallback,
  }) {
    String? fromArgs;

    if (args is String) {
      fromArgs = args;
    } else if (args is Map) {
      fromArgs = args['selectedRole']?.toString() ?? args['role']?.toString();
    }

    final String? normalizedFromArgs = _normalizeRoleOrNull(fromArgs);
    if (normalizedFromArgs != null) return normalizedFromArgs;

    final String? normalizedFallback = _normalizeRoleOrNull(fallback);
    if (normalizedFallback != null) return normalizedFallback;

    return null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _fatherNameController.dispose();
    _cnicController.dispose();
    _dobController.dispose();
    _expiryController.dispose();
    _phoneController.dispose();
    _shopNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.black87),
      );
  }

  String _resolveMimeType(String fileName) {
    final String lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

  String _formatCnicFromDigits(String value) {
    final String digits = _onlyDigits(value);
    if (digits.length != 13) return value.trim();
    return '${digits.substring(0, 5)}-${digits.substring(5, 12)}-${digits.substring(12)}';
  }

  String _maskCnic(String value) {
    final String digits = _onlyDigits(value);
    if (digits.length != 13) return '*****';
    return '${digits.substring(0, 5)}*********${digits.substring(12)}';
  }

  String _maskPhone(String value) {
    final String digits = _onlyDigits(value);
    if (digits.length < 4) return '****';
    return '*******${digits.substring(digits.length - 4)}';
  }

  String _mapFriendlyAiError(String rawMessage) {
    final String lower = rawMessage.toLowerCase();

    if (lower.contains('temporarily unavailable') ||
        lower.contains('ai-unavailable') ||
        lower.contains('unavailable') ||
        lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('quota')) {
      return 'Could not read CNIC automatically. Please review or enter details manually.\nشناختی کارڈ خودکار طور پر نہ پڑھا جا سکا۔ براہ کرم تفصیل دستی طور پر درج یا درست کریں۔';
    }

    return 'Could not read CNIC automatically. Please review or enter details manually.\nشناختی کارڈ خودکار طور پر نہ پڑھا جا سکا۔ براہ کرم تفصیل دستی طور پر درج یا درست کریں۔';
  }

  void _logStepOneDebug(String event, [Map<String, dynamic>? payload]) {
    final buffer = StringBuffer('[CNIC_STEP1] $event');
    if (payload != null && payload.isNotEmpty) {
      buffer.write(' | ${payload.toString()}');
    }
    debugPrint(buffer.toString());
  }

  Future<ImageSource?> _selectImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF133F23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (BuildContext context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.camera_alt_rounded, color: _gold),
                  title: const Text(
                    'Camera / کیمرہ',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(ImageSource.camera),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.photo_library_rounded,
                    color: _gold,
                  ),
                  title: const Text(
                    'Gallery / گیلری',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(context).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickCnicImage({required bool isFront}) async {
    final ImageSource? source = await _selectImageSource();
    if (source == null) return;

    final XFile? picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2200,
    );
    if (picked == null) return;

    setState(() {
      if (isFront) {
        _cnicFront = picked;
        _frontCnicValidated = false;
      } else {
        _cnicBack = picked;
        _backCnicValidated = false;
      }
      _accountCreated = false;
      _createdUserData = null;
      _completionMessage = null;
      _aiInlineWarning = null;
    });

    _logStepOneDebug('cnic_image_selected', <String, dynamic>{
      'side': isFront ? 'front' : 'back',
      'path': picked.path,
      'name': picked.name,
      'bytesLength': await picked.length(),
      'mimeType': _resolveMimeType(picked.name),
    });

    await _runAiExtraction(image: picked, isFront: isFront);
  }

  Future<void> _runAiExtraction({
    required XFile image,
    required bool isFront,
  }) async {
    setState(() {
      _isAiExtracting = true;
      _aiInlineWarning = null;
    });

    try {
      await _aiService.initialize();
      final Uint8List bytes = await image.readAsBytes();
      final String mimeType = _resolveMimeType(image.name);

      _logStepOneDebug('ai_extraction_request_start', <String, dynamic>{
        'side': isFront ? 'front' : 'back',
        'path': image.path,
        'name': image.name,
        'mimeType': mimeType,
        'bytesLength': bytes.length,
      });

      final CnicExtractionResult result = await _aiService
          .extractPakistaniCnicFieldsFromImage(
            imageBytes: bytes,
            mimeType: mimeType,
          );

      _logStepOneDebug('ai_extraction_response', <String, dynamic>{
        'side': isFront ? 'front' : 'back',
        'success': result.success,
        'detectedSide': result.detectedSide,
        'isCnicDocument': result.isCnicDocument,
        'confidence': result.confidence,
        'needsReview': result.needsReview,
        'errorMessage': result.errorMessage,
        'rawResponse': result.rawResponse,
      });

      if (!mounted) return;

      if (result.success) {
        final String detectedSide = result.detectedSide.trim().toLowerCase();
        final bool sideMatches = detectedSide == (isFront ? 'front' : 'back');
        if (!result.isCnicDocument || !sideMatches) {
          setState(() {
            if (isFront) {
              _frontCnicValidated = false;
            } else {
              _backCnicValidated = false;
            }
            _aiInlineWarning = !result.isCnicDocument
              ? 'Could not read CNIC clearly. Please retake the image.\nشناختی کارڈ واضح نہیں پڑھا جا سکا۔ براہ کرم دوبارہ تصویر لیں۔'
              : 'Could not read CNIC clearly. Please retake the image.\nشناختی کارڈ واضح نہیں پڑھا جا سکا۔ براہ کرم دوبارہ تصویر لیں۔';
          });

          _logStepOneDebug('ai_extraction_rejected_document_or_side', <String, dynamic>{
            'sideRequested': isFront ? 'front' : 'back',
            'detectedSide': detectedSide,
            'isCnicDocument': result.isCnicDocument,
            'reason': !result.isCnicDocument ? 'not_cnic_document' : 'side_mismatch',
          });
          return;
        }

        final String digits = _onlyDigits(result.cnicNumber);
        _logStepOneDebug('ai_extraction_parsed_values', <String, dynamic>{
          'name': result.name,
          'fatherName': result.fatherName,
          'cnicNumber': result.cnicNumber,
          'cnicDigitsLength': digits.length,
          'dateOfBirth': result.dateOfBirth,
          'expiryDate': result.expiryDate,
        });
        setState(() {
          if (result.name.trim().isNotEmpty) {
            _nameController.text = result.name.trim();
          }
          if (result.fatherName.trim().isNotEmpty) {
            _fatherNameController.text = result.fatherName.trim();
          }
          if (digits.length == 13) {
            _cnicController.text = digits;
          }
          if (result.dateOfBirth.trim().isNotEmpty) {
            _dobController.text = result.dateOfBirth.trim();
          }
          if (result.expiryDate.trim().isNotEmpty) {
            _expiryController.text = result.expiryDate.trim();
          }
          if (isFront) {
            _frontCnicValidated = true;
          } else {
            _backCnicValidated = true;
          }
          _cnicNeedsReview = _cnicNeedsReview || result.needsReview;
          _aiInlineWarning = null;
        });

        _logStepOneDebug('controllers_after_autofill', <String, dynamic>{
          'nameController': _nameController.text,
          'fatherNameController': _fatherNameController.text,
          'cnicController': _cnicController.text,
          'dobController': _dobController.text,
          'expiryController': _expiryController.text,
          'frontValidated': _frontCnicValidated,
          'backValidated': _backCnicValidated,
        });
        _showSnack(
          '${isFront ? 'Front' : 'Back'} CNIC scan complete / ${isFront ? 'فرنٹ' : 'بیک'} شناختی کارڈ اسکین مکمل',
        );
      } else {
        setState(() {
          if (isFront) {
            _frontCnicValidated = false;
          } else {
            _backCnicValidated = false;
          }
          _aiInlineWarning = _mapFriendlyAiError(result.errorMessage);
        });

        _logStepOneDebug('ai_extraction_failed_manual_fallback', <String, dynamic>{
          'side': isFront ? 'front' : 'back',
          'errorMessage': result.errorMessage,
          'mappedWarning': _aiInlineWarning,
          'rawResponse': result.rawResponse,
          'reason': 'service_returned_success_false',
        });
      }
    } catch (e) {
      setState(() {
        _aiInlineWarning =
            'Could not read CNIC automatically. Please review or enter details manually.\nشناختی کارڈ خودکار طور پر نہ پڑھا جا سکا۔ براہ کرم تفصیل دستی طور پر درج یا درست کریں۔';
      });

      _logStepOneDebug('ai_extraction_exception', <String, dynamic>{
        'side': isFront ? 'front' : 'back',
        'exception': e.toString(),
        'mappedWarning': _aiInlineWarning,
      });
    } finally {
      if (mounted) {
        setState(() => _isAiExtracting = false);
      }
    }
  }

  Future<void> _openLivenessFlow() async {
    final dynamic result = await Navigator.of(
      context,
    ).pushNamed(Routes.liveness);
    if (!mounted) return;
    final bool verified = result is Map && result['verified'] == true;
    final String message = result is Map
        ? (result['message'] ?? '').toString().trim()
        : '';
    setState(() {
      _livenessVerified = verified;
      _livenessStatusMessage = message.isEmpty
          ? (verified
                ? 'Face liveness verified / چہرہ لائیونیس کامیاب'
                : 'Liveness not completed / لائیونیس مکمل نہیں ہوئی')
          : message;
      if (!verified) {
        _accountCreated = false;
        _createdUserData = null;
        _completionMessage = null;
      }
    });
    _showSnack(_livenessStatusMessage!);
  }

  Future<bool> _hasDuplicatePhone(
    String normalizedPhone, {
    String? ignoreUid,
  }) async {
    final String raw92 = normalizedPhone.replaceFirst('+', '');
    final List<QuerySnapshot<Map<String, dynamic>>> snapshots =
        await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
          FirebaseFirestore.instance
              .collection('users')
              .where('phone', isEqualTo: normalizedPhone)
              .limit(2)
              .get(),
          FirebaseFirestore.instance
              .collection('users')
              .where('phone', isEqualTo: raw92)
              .limit(2)
              .get(),
        ]);

    for (final QuerySnapshot<Map<String, dynamic>> snapshot in snapshots) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        if (doc.id != ignoreUid) {
          return true;
        }
      }
    }
    return false;
  }

  Future<bool> _hasDuplicateCnic(String cnicDigits, {String? ignoreUid}) async {
    final String formatted = _formatCnicFromDigits(cnicDigits);
    final List<QuerySnapshot<Map<String, dynamic>>> snapshots =
        await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
          FirebaseFirestore.instance
              .collection('users')
              .where('cnicDigits', isEqualTo: cnicDigits)
              .limit(2)
              .get(),
          FirebaseFirestore.instance
              .collection('users')
              .where('cnicNumber', isEqualTo: formatted)
              .limit(2)
              .get(),
        ]);

    for (final QuerySnapshot<Map<String, dynamic>> snapshot in snapshots) {
      for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
          in snapshot.docs) {
        if (doc.id != ignoreUid) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    final String normalizedPhone = _authService.normalizePhone(
      _phoneController.text.trim(),
    );
    if (normalizedPhone.isEmpty) {
      _showSnack('Enter valid phone / درست موبائل نمبر درج کریں');
      return;
    }

    setState(() {
      _isSendingOtp = true;
      _phoneVerified = false;
      _accountCreated = false;
      _createdUserData = null;
      _completionMessage = null;
    });

    try {
      final String? ignoreUid = FirebaseAuth.instance.currentUser?.uid;
      if (await _hasDuplicatePhone(normalizedPhone, ignoreUid: ignoreUid)) {
        _showSnack(
          'Is phone number par pehle se account mojood hai / An account already exists with this phone number',
        );
        return;
      }
      await _authService.sendOTP(normalizedPhone, (String id) {
        _verificationId = id;
      });
      if (!mounted) return;
      _showSnack('OTP sent / او ٹی پی بھیج دیا گیا');
      await _showOtpInput();
    } catch (_) {
      _showSnack('OTP send failed / او ٹی پی بھیجنے میں مسئلہ');
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  Future<void> _showOtpInput() async {
    if (_verificationId == null || _verificationId!.isEmpty) {
      _showSnack('Send OTP first / پہلے او ٹی پی بھیجیں');
      return;
    }

    final TextEditingController otpController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            14,
            10,
            14,
            MediaQuery.of(sheetContext).viewInsets.bottom + 14,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _gold.withValues(alpha: 0.8)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text(
                      'Verify OTP / او ٹی پی تصدیق',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: otpController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: '------',
                        hintStyle: const TextStyle(color: Colors.white38),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: _gold.withValues(alpha: 0.55),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _gold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: _deepGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        await _verifyOtp(otpController.text.trim());
                        if (!sheetContext.mounted) return;
                        if (_phoneVerified) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                      child: const Text(
                        'Verify OTP / او ٹی پی تصدیق',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    otpController.dispose();
  }

  Future<void> _verifyOtp(String otp) async {
    if ((_verificationId ?? '').isEmpty || otp.length < 6) {
      _showSnack('Enter valid OTP / درست او ٹی پی درج کریں');
      return;
    }

    try {
      final UserCredential? credential = await _authService.verifyOTP(
        _verificationId!,
        otp,
      );
      if (credential?.user == null) {
        _showSnack('OTP verify failed / او ٹی پی تصدیق ناکام');
        return;
      }
      if (!mounted) return;
      setState(() => _phoneVerified = true);
      _showSnack('Phone verified / فون تصدیق ہوگئی');
    } catch (_) {
      _showSnack('Invalid OTP / او ٹی پی غلط ہے');
    }
  }

  bool _validateStep(int step) {
    final String name = _nameController.text.trim();
    final String fatherName = _fatherNameController.text.trim();
    final String cnicDigits = _onlyDigits(_cnicController.text.trim());
    final String dob = _dobController.text.trim();

    switch (step) {
      case 0:
        _logStepOneDebug('validation_before_continue', <String, dynamic>{
          'frontPresent': _cnicFront != null,
          'backPresent': _cnicBack != null,
          'nameFilled': name.isNotEmpty,
          'fatherFilled': fatherName.isNotEmpty,
          'cnicDigitsLength': cnicDigits.length,
          'dobFilled': dob.isNotEmpty,
          'frontValidated': _frontCnicValidated,
          'backValidated': _backCnicValidated,
          'manualFallbackReady': _isStepOneManualFallbackReady(),
        });
        if (_cnicFront == null) {
          _showSnack('Front CNIC image required / فرنٹ CNIC تصویر لازمی ہے');
          return false;
        }
        if (_cnicBack == null) {
          _showSnack('Back CNIC image required / بیک CNIC تصویر لازمی ہے');
          return false;
        }
        if (name.isEmpty) {
          _showSnack('Name required / نام لازمی ہے');
          return false;
        }
        if (fatherName.isEmpty) {
          _showSnack('Father name required / والد کا نام لازمی ہے');
          return false;
        }
        if (cnicDigits.length != 13) {
          _showSnack('CNIC must be 13 digits / CNIC کے 13 ہندسے لازمی');
          return false;
        }
        if (dob.isEmpty) {
          _showSnack('DOB required / تاریخ پیدائش لازمی ہے');
          return false;
        }
        return true;
      case 1:
        if (!_livenessVerified) {
          _showSnack('Complete liveness first / پہلے لائیونیس مکمل کریں');
          return false;
        }
        return true;
      case 2:
        if (!_phoneVerified) {
          _showSnack('Phone verification required / فون تصدیق ضروری');
          return false;
        }
        return true;
      case 3:
        if (_nameController.text.trim().isEmpty) {
          _showSnack('Full name required / مکمل نام لازمی ہے');
          return false;
        }
        if (_shopNameController.text.trim().isEmpty) {
          _showSnack(
            'Shop ya business name لازمی ہے / Shop or business name is required',
          );
          return false;
        }
        if ((_selectedCategory ?? '').isEmpty) {
          _showSnack('Select category / زمرہ منتخب کریں');
          return false;
        }
        return true;
      case 4:
        if (_selectedProvince == null ||
            _selectedDistrict == null ||
            _selectedTehsil == null ||
            _selectedCity == null) {
          _showSnack(
            'Province, district, tehsil aur city منتخب کریں / Select province, district, tehsil, and city',
          );
          return false;
        }
        final String password = _passwordController.text.trim();
        final String confirm = _confirmPasswordController.text.trim();

        if (password.isEmpty) {
          _showSnack('Password required / پاس ورڈ لازمی ہے');
          return false;
        }
        if (password.length < 8) {
          _showSnack(
            'Password kam az kam 8 characters ka ho / پاس ورڈ کم از کم 8 حروف کا ہو',
          );
          return false;
        }
        if (confirm.isEmpty) {
          _showSnack('Confirm password required / دوبارہ پاس ورڈ درج کریں');
          return false;
        }
        if (password != confirm) {
          _showSnack('Passwords match nahi karte / پاس ورڈ ایک جیسے نہیں ہیں');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    _clearAiWarningIfManualFallbackReady();
    if (!_validateStep(_currentStep)) return;
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep += 1);
    }
  }

  bool _isStepOneManualFallbackReady() {
    final String name = _nameController.text.trim();
    final String fatherName = _fatherNameController.text.trim();
    final String cnicDigits = _onlyDigits(_cnicController.text.trim());
    final String dob = _dobController.text.trim();
    return _cnicFront != null &&
        _cnicBack != null &&
        name.isNotEmpty &&
        fatherName.isNotEmpty &&
        cnicDigits.length == 13 &&
        dob.isNotEmpty;
  }

  void _clearAiWarningIfManualFallbackReady() {
    if ((_aiInlineWarning ?? '').isEmpty) return;
    if (!_isStepOneManualFallbackReady()) return;
    if (!mounted) return;
    _logStepOneDebug('manual_fallback_ready_warning_cleared', <String, dynamic>{
      'name': _nameController.text.trim(),
      'fatherName': _fatherNameController.text.trim(),
      'cnic': _cnicController.text.trim(),
      'dob': _dobController.text.trim(),
    });
    setState(() {
      _aiInlineWarning = null;
    });
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  Future<void> _createAccountForSelectedRole() async {
    if (!_validateStep(4)) return;
    const String selectedRole = 'seller';

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null || !_phoneVerified) {
      _showSnack('Phone verification required / فون تصدیق ضروری');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final String normalizedPhone = _authService.normalizePhone(
        _phoneController.text.trim(),
      );
      final String password = _passwordController.text.trim();
      final String cnicDigits = _onlyDigits(_cnicController.text.trim());
      if (await _hasDuplicatePhone(normalizedPhone, ignoreUid: user.uid)) {
        _showSnack(
          'Is phone number par pehle se account mojood hai / An account already exists with this phone number',
        );
        return;
      }
      if (await _hasDuplicateCnic(cnicDigits, ignoreUid: user.uid)) {
        _showSnack(
          'Is CNIC par pehle se account mojood hai / An account already exists with this CNIC',
        );
        return;
      }

      final bool cnicVerified =
          cnicDigits.length == 13 && _frontCnicValidated && _backCnicValidated;
      final bool isFullyVerified =
          _phoneVerified && cnicVerified && _livenessVerified;
      final bool needsManualReview = _cnicNeedsReview || !isFullyVerified;

      final String email = _authService.emailFromPhone(normalizedPhone);
      final Set<String> providerIds = user.providerData
          .map((UserInfo e) => e.providerId)
          .toSet();
      if (!providerIds.contains('password')) {
        await user.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: password),
        );
      } else {
        await user.updatePassword(password);
      }

      final Map<String, dynamic> payload = <String, dynamic>{
        'uid': user.uid,
        'role': selectedRole,
        'userRole': selectedRole,
        'userType': selectedRole,
        'name': _nameController.text.trim(),
        'fullName': _nameController.text.trim(),
        'phone': normalizedPhone,
        'password': password,
        'cnicNumber': _formatCnicFromDigits(cnicDigits),
        'cnicDigits': cnicDigits,
        'cnicName': _nameController.text.trim(),
        'fatherName': _fatherNameController.text.trim(),
        'dob': _dobController.text.trim(),
        'cnicExpiry': _expiryController.text.trim(),
        'shopName': _shopNameController.text.trim(),
        'province': _selectedProvince,
        'district': _selectedDistrict,
        'tehsil': _selectedTehsil,
        'city': _selectedCity,
        'cityVillage': _selectedCity,
        'sellerCategory': _selectedCategory,
        'preferredLanguage': _preferredLanguage,
        'phoneVerified': _phoneVerified,
        'cnicVerified': cnicVerified,
        'livenessVerified': _livenessVerified,
        'isCnicVerified': cnicVerified,
        'isFaceVerified': _livenessVerified,
        'payoutStatus': 'pending',
        'verificationStatus': needsManualReview ? 'pending_review' : 'verified',
        'is_verified': !needsManualReview && isFullyVerified,
        'isVerified': !needsManualReview && isFullyVerified,
        'isApproved': !needsManualReview && isFullyVerified,
        'reviewRequired': needsManualReview,
        'cnicFrontLocalPath': _cnicFront?.path,
        'cnicBackLocalPath': _cnicBack?.path,
        'livenessStatusMessage': _livenessStatusMessage,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      AuthState.setSelectedUserType(selectedRole);
      AuthState.setSelectedRole(selectedRole);

      if (!mounted) return;
      setState(() {
        _accountCreated = true;
        _accountNeedsReview = needsManualReview;
        _createdUserData = <String, dynamic>{...payload, 'uid': user.uid};
        _completionMessage = needsManualReview
            ? 'Seller account created and sent for review / سیلر اکاؤنٹ بن گیا اور ریویو کے لیے بھیج دیا گیا'
            : 'Seller account verified and ready / سیلر اکاؤنٹ بن گیا اور تیار ہے';
      });
      _showSnack(_completionMessage!);
    } catch (_) {
      _showSnack('Account creation failed / اکاؤنٹ بنانے میں مسئلہ');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _handleCompletionAction() {
    if (!_accountCreated) {
      _createAccountForSelectedRole();
      return;
    }

    if (_accountNeedsReview) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        Routes.verificationPending,
        (Route<dynamic> route) => false,
      );
      return;
    }

    final Map<String, dynamic> userData =
        _createdUserData ?? <String, dynamic>{'role': 'seller'};
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => AddListingScreen(userData: userData),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Widget _buildBackground() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF0A2E19),
            Color(0xFF134A29),
            Color(0xFF0A2E19),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -120,
            right: -100,
            child: _blurBlob(
              color: _gold.withValues(alpha: 0.09),
              size: const Size(260, 260),
            ),
          ),
          Positioned(
            left: -90,
            bottom: -70,
            child: _blurBlob(
              color: Colors.white.withValues(alpha: 0.04),
              size: const Size(220, 220),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    AppColors.softOverlayWhite,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blurBlob({required Color color, required Size size}) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 38, sigmaY: 38),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }

  Widget _buildAyatCard() {
    return _GlassPanel(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const <Widget>[
            Text(
              'وَتَرْزُقُ مَن تَشَاءُ بِغَيْرِ حِسَابٍ',
              style: TextStyle(
                color: _gold,
                fontSize: 20,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'اور تو جسے چاہے بے حساب رزق دیتا ہے',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontFamily: _urduFont,
                height: 1.35,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'سورۃ آل عمران 3:37',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontFamily: _urduFont,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
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
          Expanded(
            child: Text(
              'Seller Sign Up / فروخت کنندہ',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStepOne();
      case 1:
        return _buildStepTwo();
      case 2:
        return _buildStepThree();
      case 3:
        return _buildStepFour();
      case 4:
        return _buildStepFive();
      case 5:
      default:
        return _buildStepSix();
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white54),
      prefixIcon: Icon(icon, color: _gold),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.08),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.3),
      ),
    );
  }

  Widget _buildStepTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildCaptureCard({
    required String title,
    required XFile? file,
    required bool validated,
    required bool isExtracting,
    required VoidCallback onTap,
  }) {
    final String statusText;
    final Color statusColor;
    final IconData statusIcon;
    if (file == null) {
      statusText = 'Not uploaded / اپ لوڈ نہیں';
      statusColor = Colors.white54;
      statusIcon = Icons.upload_file_rounded;
    } else if (isExtracting) {
      statusText = 'Reading CNIC / شناختی کارڈ پڑھا جا رہا ہے';
      statusColor = Colors.white70;
      statusIcon = Icons.hourglass_top_rounded;
    } else if (validated) {
      statusText = 'Details extracted / تفصیل حاصل ہو گئی';
      statusColor = Colors.greenAccent;
      statusIcon = Icons.verified_rounded;
    } else {
      statusText = 'Manual entry enabled / دستی اندراج کریں';
      statusColor = _gold;
      statusIcon = Icons.edit_note_rounded;
    }

    return Expanded(
      child: InkWell(
        onTap: isExtracting ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: validated
                ? Colors.green.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: validated
                  ? Colors.greenAccent.withValues(alpha: 0.58)
                  : _gold.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                file == null ? 'Camera / Gallery' : file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: file == null ? Colors.white54 : _gold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: <Widget>[
                  Icon(statusIcon, size: 14, color: statusColor),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      statusText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11.3,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepOne() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle('Step 1: CNIC Smart Scan (AI) / شناختی کارڈ اسکین'),
          const SizedBox(height: 6),
          const Text(
            'Upload front/back CNIC. If AI cannot read, enter details manually and continue.\nCNIC فرنٹ/بیک اپ لوڈ کریں۔ اگر AI نہ پڑھے تو معلومات دستی درج کرکے آگے بڑھیں۔',
            style: TextStyle(color: Colors.white70, fontSize: 11.5, height: 1.3),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              _buildCaptureCard(
                title: 'Front CNIC / فرنٹ CNIC',
                file: _cnicFront,
                validated: _frontCnicValidated,
                isExtracting:
                    _isAiExtracting &&
                    _cnicFront != null &&
                    !_frontCnicValidated,
                onTap: () => _pickCnicImage(isFront: true),
              ),
              const SizedBox(width: 10),
              _buildCaptureCard(
                title: 'Back CNIC / بیک CNIC',
                file: _cnicBack,
                validated: _backCnicValidated,
                isExtracting:
                    _isAiExtracting && _cnicBack != null && !_backCnicValidated,
                onTap: () => _pickCnicImage(isFront: false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => _clearAiWarningIfManualFallbackReady(),
            decoration: _fieldDecoration(
              label: 'Full Name / مکمل نام',
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _fatherNameController,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => _clearAiWarningIfManualFallbackReady(),
            decoration: _fieldDecoration(
              label: 'Father Name / والد کا نام',
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _cnicController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            onChanged: (String value) {
              final String digits = _onlyDigits(value);
              if (digits != value) {
                _cnicController.value = TextEditingValue(
                  text: digits,
                  selection: TextSelection.collapsed(offset: digits.length),
                );
              }
              _clearAiWarningIfManualFallbackReady();
            },
            decoration: _fieldDecoration(
              label: 'CNIC Number (13 digits) / CNIC نمبر',
              icon: Icons.badge_outlined,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _dobController,
            style: const TextStyle(color: Colors.white),
            onChanged: (_) => _clearAiWarningIfManualFallbackReady(),
            decoration: _fieldDecoration(
              label: 'DOB / تاریخ پیدائش',
              icon: Icons.event_outlined,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _expiryController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Expiry (optional) / میعاد (اختیاری)',
              icon: Icons.event_available_outlined,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'CNIC data is used only for verification / شناخت صرف تصدیق کیلئے',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          _buildStepOneStatusBanner(),
          if ((_aiInlineWarning ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.42),
                ),
              ),
              child: Text(
                'AI could not read CNIC automatically. Please review or enter details manually.\nشناختی کارڈ خودکار طور پر نہ پڑھا جا سکا۔ براہ کرم تفصیل دستی طور پر درج یا درست کریں۔',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.5,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepOneStatusBanner() {
    final bool bothUploaded = _cnicFront != null && _cnicBack != null;
    final bool bothAiVerified = _frontCnicValidated && _backCnicValidated;
    final bool manualReady = _isStepOneManualFallbackReady();

    final String label;
    final Color tone;
    final IconData icon;

    if (_isAiExtracting) {
      label = 'Reading CNIC details / CNIC تفصیل پڑھی جا رہی ہے';
      tone = Colors.white70;
      icon = Icons.hourglass_top_rounded;
    } else if (bothAiVerified) {
      label = 'CNIC details extracted successfully / CNIC تفصیل کامیابی سے حاصل ہوگئی';
      tone = Colors.greenAccent;
      icon = Icons.verified_rounded;
    } else if (manualReady) {
      label = 'Manual details are complete. You can continue / دستی معلومات مکمل ہیں، آپ آگے بڑھ سکتے ہیں';
      tone = _gold;
      icon = Icons.check_circle_outline_rounded;
    } else if (bothUploaded) {
      label = 'Complete missing fields manually to continue / آگے بڑھنے کے لئے باقی معلومات دستی مکمل کریں';
      tone = _gold;
      icon = Icons.edit_note_rounded;
    } else {
      label = 'Upload front and back CNIC to start / شروع کرنے کے لئے فرنٹ اور بیک CNIC اپ لوڈ کریں';
      tone = Colors.white70;
      icon = Icons.upload_file_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: tone, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required bool ok,
    required String okText,
    required String pendingText,
    bool isExtracting = false,
  }) {
    final Color tone = ok
        ? Colors.green
        : isExtracting
        ? Colors.white
        : Colors.orange;
    final Color iconTone = ok
        ? Colors.greenAccent
        : isExtracting
        ? Colors.white70
        : Colors.orangeAccent;
    final IconData icon = ok
        ? Icons.verified_rounded
        : isExtracting
        ? Icons.hourglass_top_rounded
        : Icons.info_outline_rounded;
    final String label = ok
        ? okText
        : isExtracting
        ? 'Reading CNIC / شناختی کارڈ پڑھا جا رہا ہے'
        : pendingText;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: iconTone.withValues(alpha: 0.8),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: iconTone, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTwo() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle(
            'Step 2: Liveness / Face Verification / لائیونیس تصدیق',
          ),
          const SizedBox(height: 12),
          _buildStatusChip(
            ok: _livenessVerified,
            okText: 'Verified / تصدیق ہوگئی',
            pendingText: 'Not verified / تصدیق باقی ہے',
          ),
          if ((_livenessStatusMessage ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _livenessStatusMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _openLivenessFlow,
            style: OutlinedButton.styleFrom(
              foregroundColor: _gold,
              side: BorderSide(color: _gold.withValues(alpha: 0.75)),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.face_retouching_natural_rounded),
            label: const Text('Start Liveness Check / لائیونیس چیک شروع کریں'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Blink, then turn left and right in good light / اچھی روشنی میں پلک جھپکائیں پھر چہرہ بائیں اور دائیں کریں',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStepThree() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle(
            'Step 3: Phone Number + OTP Verification / فون تصدیق',
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Phone Number / موبائل نمبر',
              icon: Icons.phone_rounded,
            ),
          ),
          const SizedBox(height: 12),
          _buildStatusChip(
            ok: _phoneVerified,
            okText: 'Verified / تصدیق ہوگئی',
            pendingText: 'Unverified / غیر تصدیق شدہ',
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSendingOtp ? null : _sendOtp,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: BorderSide(color: _gold.withValues(alpha: 0.75)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: _isSendingOtp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send OTP / او ٹی پی بھیجیں'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: (_verificationId ?? '').isEmpty
                      ? null
                      : _showOtpInput,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: BorderSide(color: _gold.withValues(alpha: 0.75)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('Verify OTP / او ٹی پی تصدیق'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepFour() {
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle('Step 4: Seller Profile / فروخت کنندہ پروفائل'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Full Name / مکمل نام',
              icon: Icons.person_outline_rounded,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _shopNameController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Shop or Business Name / دکان یا کاروبار کا نام',
              icon: Icons.storefront_outlined,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Category / زمرہ',
              icon: Icons.category_rounded,
            ),
            items: _categories
                .map(
                  (_CategoryOption item) => DropdownMenuItem<String>(
                    value: item.key,
                    child: Text(
                      '${item.en} / ${item.ur}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? value) =>
                setState(() => _selectedCategory = value),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _preferredLanguage,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Preferred Language / ترجیحی زبان',
              icon: Icons.language_rounded,
            ),
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'Urdu / اردو',
                child: Text(
                  'Urdu / اردو',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              DropdownMenuItem<String>(
                value: 'English / انگریزی',
                child: Text(
                  'English / انگریزی',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
            onChanged: (String? value) {
              if (value == null) return;
              setState(() => _preferredLanguage = value);
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Verified sellers get faster approvals / تصدیق شدہ فروخت کنندہ کی منظوری جلد ہوتی ہے',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _selectedCategoryLabel() {
    final _CategoryOption? selected = _categories
        .where((e) => e.key == _selectedCategory)
        .cast<_CategoryOption?>()
        .firstWhere((e) => e != null, orElse: () => null);
    if (selected == null) return '-';
    return '${selected.en} / ${selected.ur}';
  }

  Widget _reviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              '$label:',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFive() {
    final PakistanLocationService locationService =
      PakistanLocationService.instance;
    final List<String> provinces = locationService.provinces;
    final List<String> districts = _selectedProvince == null
        ? const <String>[]
      : locationService.districtsForProvince(_selectedProvince!);
    final List<String> tehsils = _selectedDistrict == null
        ? const <String>[]
      : locationService.tehsilsForDistrict(_selectedDistrict!);
    final List<String> cities =
        (_selectedDistrict == null || _selectedTehsil == null)
        ? const <String>[]
      : locationService.cityOptions(
            district: _selectedDistrict!,
            tehsil: _selectedTehsil!,
          );

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle('Step 5: Location Information / مقام کی معلومات'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedProvince,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Province / صوبہ',
              icon: Icons.map_rounded,
            ),
            items: provinces
                .map(
                  (String item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? value) {
              setState(() {
                _selectedProvince = value;
                _selectedDistrict = null;
                _selectedTehsil = null;
                _selectedCity = null;
                _accountCreated = false;
                _createdUserData = null;
                _completionMessage = null;
              });
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedDistrict,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'District / ضلع',
              icon: Icons.location_city_rounded,
            ),
            items: districts
                .map(
                  (String item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white),
                    ),
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
                      _accountCreated = false;
                      _createdUserData = null;
                      _completionMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedTehsil,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Tehsil / تحصیل',
              icon: Icons.alt_route_rounded,
            ),
            items: tehsils
                .map(
                  (String item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: _selectedDistrict == null
                ? null
                : (String? value) {
                    setState(() {
                      _selectedTehsil = value;
                      _selectedCity = null;
                      _accountCreated = false;
                      _createdUserData = null;
                      _completionMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedCity,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'City / شہر',
              icon: Icons.location_on_rounded,
            ),
            items: cities
                .map(
                  (String item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(
                      item,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                )
                .toList(),
            onChanged: _selectedTehsil == null
                ? null
                : (String? value) {
                    setState(() {
                      _selectedCity = value;
                      _accountCreated = false;
                      _createdUserData = null;
                      _completionMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          const Text(
            'Account Password / اکاؤنٹ پاس ورڈ',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Password / پاس ورڈ',
              hint: 'At least 8 characters / کم از کم 8 حروف',
              icon: Icons.lock_outline_rounded,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Confirm Password / دوبارہ پاس ورڈ',
              hint: 'پاس ورڈ دوبارہ لکھیں',
              icon: Icons.lock_reset_rounded,
              suffixIcon: IconButton(
                onPressed: () {
                  setState(
                    () => _obscureConfirmPassword = !_obscureConfirmPassword,
                  );
                },
                icon: Icon(
                  _obscureConfirmPassword
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  color: Colors.white70,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'یہ پاس ورڈ لاگ اِن کے لیے استعمال ہوگا / This password will be used for login',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStepSix() {
    if (_accountCreated) {
      return _GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _buildStepTitle('Step 6: Completion / تکمیل'),
            const SizedBox(height: 12),
            _buildStatusChip(
              ok: !_accountNeedsReview,
              okText: 'Ready / تیار',
              pendingText: 'Under review / زیرِ جائزہ',
            ),
            const SizedBox(height: 12),
            Text(
              _completionMessage ?? '-',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _accountNeedsReview
                  ? 'Aap ka seller account review mein hai. Fake verified state save nahi ki gayi. / آپ کا سیلر اکاؤنٹ ریویو میں ہے۔ کوئی جعلی verified حالت محفوظ نہیں کی گئی۔'
                  : 'Aap ka seller account verify ho gaya hai. Ab aap اپنی پہلی listing بنا سکتے ہیں۔ / Your seller account is verified and you can create your first listing now.',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle('Step 6: Review + Completion / جائزہ اور تکمیل'),
          const SizedBox(height: 10),
          _reviewRow(
            'Name / نام',
            _nameController.text.trim().isEmpty
                ? '-'
                : _nameController.text.trim(),
          ),
          _reviewRow(
            'CNIC / شناختی کارڈ',
            _maskCnic(_cnicController.text.trim()),
          ),
          _reviewRow('Phone / فون', _maskPhone(_phoneController.text.trim())),
          _reviewRow(
            'Shop / کاروبار',
            _shopNameController.text.trim().isEmpty
                ? '-'
                : _shopNameController.text.trim(),
          ),
          _reviewRow('Province / صوبہ', _selectedProvince ?? '-'),
          _reviewRow('District / ضلع', _selectedDistrict ?? '-'),
          _reviewRow('Tehsil / تحصیل', _selectedTehsil ?? '-'),
          _reviewRow('City / شہر', _selectedCity ?? '-'),
          _reviewRow('Category / زمرہ', _selectedCategoryLabel()),
          _reviewRow(
            'Verification / تصدیق',
            _cnicNeedsReview
                ? 'Pending review / زیرِ جائزہ'
                : 'All hard checks completed / تمام سخت چیک مکمل',
          ),
          const SizedBox(height: 8),
          const Text(
            'Create account only after reviewing every detail / اکاؤنٹ بنانے سے پہلے تمام تفصیل دوبارہ دیکھ لیں',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final bool isLast = _currentStep == _totalSteps - 1;
    final String lastStepLabel = _accountCreated
        ? (_accountNeedsReview
              ? 'View Verification Status / تصدیق کی حالت دیکھیں'
              : 'Create First Listing / پہلی لسٹنگ بنائیں')
        : 'Create Account / اکاؤنٹ بنائیں';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.32))),
      ),
      child: Row(
        children: <Widget>[
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting || _isAiExtracting
                    ? null
                    : _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: BorderSide(color: _gold.withValues(alpha: 0.78)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back / واپس',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFFFC24B), Color(0xFFFFD36A)],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: (_isSubmitting || _isAiExtracting)
                    ? null
                    : (isLast ? _handleCompletionAction : _nextStep),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: _deepGreen,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isLast ? lastStepLabel : 'Continue / جاری رکھیں',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_roleResolved && !_isSellerAccess) {
      return Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: <Widget>[
            _buildBackground(),
            const SafeArea(
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: <Widget>[
          _buildBackground(),
          SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  _buildHeader(),
                  _StepProgressBar(
                    currentStep: _currentStep,
                    totalSteps: _totalSteps,
                    deepGreen: _deepGreen,
                    gold: _gold,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                    child: _buildAyatCard(),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        child: KeyedSubtree(
                          key: ValueKey<int>(_currentStep),
                          child: _buildCurrentStep(),
                        ),
                      ),
                    ),
                  ),
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
          if (_isAiExtracting)
            const AiLoadingDialog(
              message: 'Reading CNIC...\nشناختی کارڈ پڑھا جا رہا ہے...',
            ),
        ],
      ),
    );
  }
}

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
    required this.deepGreen,
    required this.gold,
  });

  final int currentStep;
  final int totalSteps;
  final Color deepGreen;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final double progress = totalSteps <= 1
        ? 0
        : (currentStep / (totalSteps - 1)).clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
      child: SizedBox(
        height: 50,
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
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
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
                    final bool active = index == currentStep;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      width: active ? 34 : 30,
                      height: active ? 34 : 30,
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
                            : deepGreen.withValues(alpha: 0.82),
                        border: Border.all(
                          color: gold,
                          width: active ? 2 : 1.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: completed ? deepGreen : Colors.white,
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

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFFFD36A).withValues(alpha: 0.45),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _CategoryOption {
  const _CategoryOption({
    required this.key,
    required this.en,
    required this.ur,
  });

  final String key;
  final String en;
  final String ur;
}
