// ignore_for_file: deprecated_member_use

import 'dart:math' as math;
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/location_display_helper.dart';
import '../core/pakistan_location_service.dart';
import '../dashboard/seller/seller_dashboard.dart';
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
  static const int _totalSteps = 3;

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
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  final TextEditingController _otpController = TextEditingController();

  int _currentStep = 0;
  bool _isAiExtracting = false;
  bool _isSendingOtp = false;
  bool _isSubmitting = false;
  bool _phoneVerified = false;
  bool _frontCnicValidated = false;
  bool _backCnicValidated = false;
  bool _cnicNeedsReview = false;
  bool _accountCreated = false;
  bool _accountNeedsReview = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isVerifyingOtp = false;
  bool _isManualEditEnabled = false;
  String? _aiInlineWarning;
  String? _completionMessage;
  String? _otpStatusMessage;
  bool _otpStatusIsError = false;
  String? _stepInlineError;
  String? _otpInlineError;
  String? _passwordInlineError;
  String? _confirmPasswordInlineError;
  String? _locationInlineError;

  XFile? _cnicFront;
  XFile? _cnicBack;
  String? _verificationId;
  int? _resendToken;
  int _otpResendSeconds = 0;
  Timer? _otpResendTimer;

  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;
  String? _cityText;
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
    _cityController.addListener(() {
      _cityText = _cityController.text.trim();
      _selectedCity = _cityText;
    });
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
    _cityController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _otpController.dispose();
    _otpResendTimer?.cancel();
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

  /// Returns a clean +92 3XX XXXXXXX display string.
  /// Input may be raw digits or any mixed format from the controller.
  String _formatPhoneForDisplay(String input) {
    String digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    // Strip leading country code variants
    if (digits.startsWith('0092')) digits = digits.substring(4);
    if (digits.startsWith('92') && digits.length > 10) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length > 10) digits = digits.substring(0, 10);
    if (digits.length != 10) return '+92 XXX XXXXXXX';
    return '+92 ${digits.substring(0, 3)} ${digits.substring(3)}';
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

  String _normalizeExtractedNameValue(
    String raw, {
    bool allowFatherKeywords = false,
  }) {
    String value = raw.trim();
    if (value.isEmpty) return '';

    value = value.replaceAll(RegExp(r'\s+'), ' ');
    value = value.replaceFirst(
      RegExp(r'^(name|full\s*name)\s*[:\-]?\s*', caseSensitive: false),
      '',
    );
    value = value.replaceFirst(
      RegExp(
        r'^(father\s*name|husband\s*name|s/o|d/o|w/o)\s*[:\-]?\s*',
        caseSensitive: false,
      ),
      '',
    );

    final String lower = value.toLowerCase();
    final bool hasDate = RegExp(r'\b\d{2}[./-]\d{2}[./-]\d{4}\b').hasMatch(value);
    final bool hasCnicDigits = RegExp(r'\b\d{13}\b').hasMatch(value);
    final bool fatherKeywordPresent = RegExp(
      r'(father|husband|s/o|d/o|w/o)',
      caseSensitive: false,
    ).hasMatch(lower);

    if (hasDate || hasCnicDigits) {
      return '';
    }
    if (!allowFatherKeywords && fatherKeywordPresent) {
      return '';
    }
    if (allowFatherKeywords && value.length < 3) {
      return '';
    }
    return value;
  }

  String _normalizeExtractedDateValue(String raw) {
    final String value = raw.trim();
    if (!RegExp(r'^\d{2}[./-]\d{2}[./-]\d{4}$').hasMatch(value)) {
      return '';
    }
    return value.replaceAll('.', '-').replaceAll('/', '-');
  }

  void _assignExtractedField({
    required String targetField,
    required TextEditingController controller,
    required String value,
    required String side,
  }) {
    final String trimmedValue = value.trim();
    if (trimmedValue.isEmpty) {
      _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
        'targetField': targetField,
        'side': side,
        'reason': 'empty_value',
      });
      return;
    }

    controller.text = trimmedValue;
    _logStepOneDebug('ocr_assignment_applied', <String, dynamic>{
      'targetField': targetField,
      'side': side,
      'assignedValue': trimmedValue,
    });
  }

  void _applyCnicExtractionToControllers(
    CnicExtractionResult result, {
    required bool isFront,
  }) {
    final String side = isFront ? 'front' : 'back';
    final bool allowSensitiveAutofill =
        !result.needsReview && result.confidence.toLowerCase() != 'low';
    final String normalizedName = _normalizeExtractedNameValue(result.name);
    final String normalizedFatherName = _normalizeExtractedNameValue(
      result.fatherName,
      allowFatherKeywords: true,
    );
    final String normalizedDob = _normalizeExtractedDateValue(
      result.dateOfBirth,
    );
    final String normalizedExpiry = _normalizeExtractedDateValue(
      result.expiryDate,
    );
    final String normalizedCnicDigits = _onlyDigits(result.cnicNumber);

    _logStepOneDebug('ocr_mapping_inputs', <String, dynamic>{
      'side': side,
      'parsedFullName': result.name,
      'parsedFatherName': result.fatherName,
      'parsedCnicNumber': result.cnicNumber,
      'parsedDob': result.dateOfBirth,
      'parsedExpiry': result.expiryDate,
      'normalizedFullName': normalizedName,
      'normalizedFatherName': normalizedFatherName,
      'normalizedDob': normalizedDob,
      'normalizedExpiry': normalizedExpiry,
      'normalizedCnicDigits': normalizedCnicDigits,
      'confidence': result.confidence,
      'needsReview': result.needsReview,
      'allowSensitiveAutofill': allowSensitiveAutofill,
    });

    if (normalizedCnicDigits.length == 13) {
      _assignExtractedField(
        targetField: 'cnicNumber',
        controller: _cnicController,
        value: normalizedCnicDigits,
        side: side,
      );
    } else {
      _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
        'targetField': 'cnicNumber',
        'side': side,
        'reason': 'invalid_cnic_pattern',
        'parsedValue': result.cnicNumber,
      });
    }

    if (!allowSensitiveAutofill) {
      _logStepOneDebug('ocr_assignment_guarded_low_confidence', <String, dynamic>{
        'side': side,
        'reason': 'needs_review_or_low_confidence',
      });
      return;
    }

    if (isFront) {
      if (normalizedName.isNotEmpty) {
        _assignExtractedField(
          targetField: 'fullName',
          controller: _nameController,
          value: normalizedName,
          side: side,
        );
      }

      if (normalizedFatherName.isNotEmpty &&
          normalizedFatherName.toLowerCase() != normalizedName.toLowerCase()) {
        _assignExtractedField(
          targetField: 'fatherName',
          controller: _fatherNameController,
          value: normalizedFatherName,
          side: side,
        );
      } else {
        _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
          'targetField': 'fatherName',
          'side': side,
          'reason': normalizedFatherName.isEmpty
              ? 'empty_or_invalid_father_name'
              : 'matches_full_name',
        });
      }

      if (normalizedDob.isNotEmpty) {
        _assignExtractedField(
          targetField: 'dob',
          controller: _dobController,
          value: normalizedDob,
          side: side,
        );
      }
    } else {
      _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
        'targetField': 'fullName',
        'side': side,
        'reason': 'back_side_does_not_overwrite_name_fields',
      });
      _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
        'targetField': 'fatherName',
        'side': side,
        'reason': 'back_side_does_not_overwrite_name_fields',
      });
      _logStepOneDebug('ocr_assignment_skipped', <String, dynamic>{
        'targetField': 'dob',
        'side': side,
        'reason': 'back_side_does_not_overwrite_dob',
      });
    }

    if (normalizedExpiry.isNotEmpty) {
      _assignExtractedField(
        targetField: 'expiry',
        controller: _expiryController,
        value: normalizedExpiry,
        side: side,
      );
    }
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

    debugPrint(
      '[CNIC] ${isFront ? 'front' : 'back'}_image_path=${picked.path}',
    );
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

      debugPrint(
        '[CNIC] extraction_started side=${isFront ? 'front' : 'back'}',
      );
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
            imagePath: image.path,
            mimeType: mimeType,
            expectedSide: isFront ? 'front' : 'back',
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
        'pipeline': result.pipeline,
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

          _logStepOneDebug(
            'ai_extraction_rejected_document_or_side',
            <String, dynamic>{
              'sideRequested': isFront ? 'front' : 'back',
              'detectedSide': detectedSide,
              'isCnicDocument': result.isCnicDocument,
              'reason': !result.isCnicDocument
                  ? 'not_cnic_document'
                  : 'side_mismatch',
            },
          );
          return;
        }

        final String digits = _onlyDigits(result.cnicNumber);
        debugPrint('[CNIC] parsed_name=${result.name}');
        debugPrint('[CNIC] parsed_father_name=${result.fatherName}');
        debugPrint('[CNIC] parsed_cnic=${result.cnicNumber}');
        debugPrint('[CNIC] parsed_dob=${result.dateOfBirth}');
        debugPrint('[CNIC] parsed_expiry=${result.expiryDate}');
        _logStepOneDebug('ai_extraction_parsed_values', <String, dynamic>{
          'name': result.name,
          'fatherName': result.fatherName,
          'cnicNumber': result.cnicNumber,
          'cnicDigitsLength': digits.length,
          'dateOfBirth': result.dateOfBirth,
          'expiryDate': result.expiryDate,
        });
        setState(() {
          _applyCnicExtractionToControllers(result, isFront: isFront);
          if (isFront) {
            _frontCnicValidated = true;
          } else {
            _backCnicValidated = true;
          }
          _cnicNeedsReview = _cnicNeedsReview || result.needsReview;
          _aiInlineWarning = null;
        });

        final bool finalAutofillSuccess =
            _nameController.text.trim().isNotEmpty ||
            _fatherNameController.text.trim().isNotEmpty ||
            _cnicController.text.trim().isNotEmpty ||
            _dobController.text.trim().isNotEmpty ||
            _expiryController.text.trim().isNotEmpty;
        debugPrint('[CNIC] final_autofill_success=$finalAutofillSuccess');
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

        debugPrint(
          '[CNIC] ERROR stage=autofill code=SERVICE_RETURNED_FAILURE message=${result.errorMessage}',
        );
        debugPrint('[CNIC] final_autofill_success=false');
        _logStepOneDebug(
          'ai_extraction_failed_manual_fallback',
          <String, dynamic>{
            'side': isFront ? 'front' : 'back',
            'errorMessage': result.errorMessage,
            'mappedWarning': _aiInlineWarning,
            'rawResponse': result.rawResponse,
            'reason': 'service_returned_success_false',
          },
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _aiInlineWarning =
              'Could not read CNIC automatically. Please review or enter details manually.\nشناختی کارڈ خودکار طور پر نہ پڑھا جا سکا۔ براہ کرم تفصیل دستی طور پر درج یا درست کریں۔';
        });
      }

      debugPrint(
        '[CNIC] ERROR stage=autofill code=EXCEPTION message=${e.toString()}',
      );
      debugPrint('[CNIC] final_autofill_success=false');
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

  Future<bool> _hasDuplicatePhone(
    String normalizedPhone, {
    String? ignoreUid,
  }) async {
    return _authService.isPhoneRegisteredInIndex(
      normalizedPhone,
      ignoreUid: ignoreUid,
    );
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
      _verificationId = null;
      _otpController.clear();
      _otpInlineError = null;
      _accountCreated = false;
      _createdUserData = null;
      _completionMessage = null;
      _otpStatusMessage = 'Sending OTP... / او ٹی پی بھیجی جا رہی ہے...';
      _otpStatusIsError = false;
    });

    try {
      final String? ignoreUid = FirebaseAuth.instance.currentUser?.uid;
      final bool duplicateExists = await _hasDuplicatePhone(
        normalizedPhone,
        ignoreUid: ignoreUid,
      );
      if (duplicateExists) {
        if (mounted) {
          setState(() {
            _otpStatusMessage =
                'This phone number is already registered / اس نمبر پر پہلے سے اکاؤنٹ موجود ہے';
            _otpStatusIsError = true;
          });
        }
        _showSnack(
          'Is phone number par pehle se account mojood hai / An account already exists with this phone number',
        );
        return;
      }
      await _authService.sendOTP(
        normalizedPhone,
        (String id) {
          if (!mounted) return;
          setState(() {
            _verificationId = id;
            _otpStatusMessage =
                'OTP sent successfully / او ٹی پی کامیابی سے بھیج دی گئی';
            _otpStatusIsError = false;
          });
          _startOtpResendTimer();
        },
        flowLabel: 'seller_sign_up',
        forceResendingToken: _resendToken,
        onResendToken: (int? token) {
          if (!mounted) return;
          setState(() => _resendToken = token);
        },
        onVerificationFailed: (FirebaseAuthException error) {
          if (!mounted) return;
          setState(() {
            final String msg = (error.message ?? '').trim();
            _otpStatusMessage = msg.isEmpty
                ? 'انٹرنیٹ مسئلہ ہے / Network issue'
                : '$msg / او ٹی پی بھیجنے میں مسئلہ';
            _otpStatusIsError = true;
          });
        },
        onVerificationFailedMessage: (String message) {
          if (!mounted) return;
          setState(() {
            _otpStatusMessage = '$message / او ٹی پی بھیجنے میں مسئلہ';
            _otpStatusIsError = true;
          });
        },
        onAutoRetrievalTimeout: (String verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _otpStatusMessage =
                'OTP timeout reached. You can still verify the received code. / او ٹی پی ٹائم آؤٹ ہوگیا، موصولہ کوڈ سے تصدیق جاری رکھیں';
            _otpStatusIsError = false;
          });
        },
        onVerificationCompleted: (UserCredential credential) async {
          if (!mounted) return;
          setState(() {
            _phoneVerified = credential.user != null;
            _otpStatusMessage =
                'Phone auto-verified / فون خودکار طور پر تصدیق ہوگیا';
            _otpStatusIsError = false;
            _otpInlineError = null;
          });
        },
      );
      if (!mounted) return;
      _showSnack('OTP sent / او ٹی پی بھیج دیا گیا');
    } on FirebaseException catch (error) {
      if (mounted) {
        setState(() {
          _otpStatusMessage = _friendlySubmitError(error.code, error.message);
          _otpStatusIsError = true;
        });
      }
      _showSnack(_friendlySubmitError(error.code, error.message));
    } on PhoneOtpException catch (error) {
      debugPrint(
        '[OTP_DEBUG][seller_signup] action=send_otp code=${error.code} message=${error.message} phone=${_maskPhone(_phoneController.text)}',
      );
      if (mounted) {
        setState(() {
          _otpStatusMessage = error.message;
          _otpStatusIsError = true;
        });
      }
      _showSnack(error.message);
    } catch (error) {
      if (mounted) {
        setState(() {
          _otpStatusMessage =
              'Unexpected validation error before OTP / او ٹی پی سے پہلے غیر متوقع مسئلہ';
          _otpStatusIsError = true;
        });
      }
      _showSnack('Validation failed before OTP / او ٹی پی سے پہلے مسئلہ');
    } finally {
      if (mounted) {
        setState(() => _isSendingOtp = false);
      }
    }
  }

  void _startOtpResendTimer() {
    _otpResendTimer?.cancel();
    setState(() => _otpResendSeconds = 45);
    _otpResendTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_otpResendSeconds <= 1) {
        timer.cancel();
        setState(() => _otpResendSeconds = 0);
        return;
      }
      setState(() => _otpResendSeconds -= 1);
    });
  }

  Future<void> _verifyOtp(String otp) async {
    if ((_verificationId ?? '').isEmpty || otp.length < 6) {
      setState(() => _otpInlineError = 'درست 6 ہندسوں کی او ٹی پی درج کریں');
      _showSnack('Enter valid 6-digit OTP');
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isVerifyingOtp = true;
          _otpStatusMessage = 'Verifying OTP... / او ٹی پی کی تصدیق جاری ہے...';
          _otpStatusIsError = false;
          _otpInlineError = null;
        });
      }
      final UserCredential? credential = await _authService.verifyOTP(
        _verificationId!,
        otp,
        flowLabel: 'seller_sign_up',
        phoneNumber: _phoneController.text,
      );
      if (credential?.user == null) {
        if (mounted) {
          setState(() {
            _otpStatusMessage =
                'OTP verification failed / او ٹی پی تصدیق ناکام';
            _otpStatusIsError = true;
            _otpInlineError = 'تصدیق ناکام، دوبارہ کوشش کریں';
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _otpStatusMessage = 'Verified / تصدیق شدہ';
        _otpStatusIsError = false;
        _otpInlineError = null;
      });
      _showSnack('Phone verified / فون تصدیق ہوگئی');
    } on PhoneOtpException catch (error) {
      debugPrint(
        '[OTP_DEBUG][seller_signup] action=verify_otp code=${error.code} message=${error.message} phone=${_maskPhone(_phoneController.text)}',
      );
      if (mounted) {
        final String errorMessage = _mapOtpError(error.code, error.message);
        setState(() {
          _otpStatusMessage = errorMessage;
          _otpStatusIsError = true;
          _otpInlineError = 'او ٹی پی درست نہیں ہے';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _otpStatusMessage = 'Unexpected error verifying OTP';
          _otpStatusIsError = true;
          _otpInlineError = 'او ٹی پی درست نہیں ہے';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isVerifyingOtp = false);
      }
    }
  }

  String _mapOtpError(String code, String message) {
    final String c = code.toLowerCase();
    if (c.contains('invalid-verification-code') ||
        c.contains('invalid-credential')) {
      return 'OTP code is incorrect / او ٹی پی کوڈ غلط ہے';
    }
    if (c.contains('code-send-timeout')) {
      return 'OTP request timed out. Please try again';
    }
    if (c.contains('network')) {
      return 'Network error. Please check your connection';
    }
    if (c.contains('too-many-requests')) {
      return 'Too many attempts. Please wait before trying again';
    }
    return message.isNotEmpty ? message : 'OTP verification failed';
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
          setState(() => _stepInlineError = 'فرنٹ CNIC تصویر لازمی ہے');
          return false;
        }
        if (_cnicBack == null) {
          setState(() => _stepInlineError = 'بیک CNIC تصویر لازمی ہے');
          return false;
        }
        if (name.isEmpty) {
          setState(() => _stepInlineError = 'نام لازمی ہے');
          return false;
        }
        if (fatherName.isEmpty) {
          setState(() => _stepInlineError = 'والد کا نام لازمی ہے');
          return false;
        }
        if (cnicDigits.length != 13) {
          setState(() => _stepInlineError = 'CNIC کے 13 ہندسے لازمی ہیں');
          return false;
        }
        setState(() => _stepInlineError = null);
        return true;
      case 1:
        if (!_phoneVerified) {
          setState(() => _otpInlineError = 'پہلے OTP تصدیق مکمل کریں');
          return false;
        }
        final String password = _passwordController.text.trim();
        final String confirm = _confirmPasswordController.text.trim();
        if (password.length < 8) {
          setState(
            () =>
                _passwordInlineError = 'پاس ورڈ کم از کم 8 حروف کا ہونا چاہیے',
          );
          return false;
        }
        if (password != confirm) {
          setState(
            () => _confirmPasswordInlineError = 'پاس ورڈ ایک جیسے نہیں ہیں',
          );
          return false;
        }
        setState(() {
          _otpInlineError = null;
          _passwordInlineError = null;
          _confirmPasswordInlineError = null;
        });
        return true;
      case 2:
        if (_shopNameController.text.trim().isEmpty) {
          setState(
            () => _locationInlineError = 'دکان یا کاروبار کا نام لازمی ہے',
          );
          return false;
        }
        if ((_selectedCategory ?? '').isEmpty) {
          setState(() => _locationInlineError = 'زمرہ منتخب کریں');
          return false;
        }
        if (_selectedProvince == null ||
            _selectedDistrict == null ||
            _selectedTehsil == null ||
            (_cityText ?? '').trim().length < 2) {
          setState(() => _locationInlineError = 'ضلع منتخب کریں');
          return false;
        }
        setState(() => _locationInlineError = null);
        return true;
      default:
        return true;
    }
  }

  void _nextStep() {
    _clearAiWarningIfManualFallbackReady();
    if (!_validateStep(_currentStep)) return;

    // Prevent step progression if current step data is incomplete
    if (_currentStep == 0 && _stepInlineError != null) return;
    if (_currentStep == 1 && _otpInlineError != null) return;
    if (_currentStep == 2 && _locationInlineError != null) return;

    if (_currentStep < _totalSteps - 1) {
      setState(() {
        _currentStep += 1;
        // Clear inline errors when moving to next step
        _stepInlineError = null;
        _otpInlineError = null;
        _passwordInlineError = null;
        _confirmPasswordInlineError = null;
        _locationInlineError = null;
      });
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
    // Prevent going backwards after phone verification to protect data integrity
    if (_currentStep == 2 && _phoneVerified) {
      _showSnack('Cannot go back after OTP verification');
      return;
    }

    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  Future<void> _createAccountForSelectedRole() async {
    if (!_validateStep(2)) return;
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
      final String cnicDigits = _onlyDigits(_cnicController.text.trim());
      if (await _hasDuplicatePhone(normalizedPhone, ignoreUid: user.uid)) {
        _showSnack('یہ نمبر پہلے سے رجسٹرڈ ہے');
        return;
      }
      if (await _hasDuplicateCnic(cnicDigits, ignoreUid: user.uid)) {
        _showSnack('یہ CNIC پہلے سے رجسٹرڈ ہے');
        return;
      }

      final bool cnicVerified =
          cnicDigits.length == 13 && _frontCnicValidated && _backCnicValidated;
      final bool isFullyVerified = _phoneVerified && cnicVerified;
      const bool needsManualReview = true;
      final String province = (_selectedProvince ?? '').trim();
      final String district = (_selectedDistrict ?? '').trim();
      final String tehsil = (_selectedTehsil ?? '').trim();
      final String city = (_cityText ?? _selectedCity ?? '').trim();
      final String provinceUr = LocationDisplayHelper.resolvedUrduLabel(
        province,
      );
      final String districtUr = LocationDisplayHelper.resolvedUrduLabel(
        district,
      );
      final String tehsilUr = LocationDisplayHelper.resolvedUrduLabel(tehsil);
      final String cityUr = LocationDisplayHelper.resolvedUrduLabel(city);

      final Map<String, dynamic> payload = <String, dynamic>{
        'uid': user.uid,
        'role': selectedRole,
        'userRole': selectedRole,
        'userType': selectedRole,
        'name': _nameController.text.trim(),
        'fullName': _nameController.text.trim(),
        'phone': normalizedPhone,
        'password': _passwordController.text.trim(),
        'passwordHash': _authService.hashPassword(
          _passwordController.text.trim(),
        ),
        'cnicNumber': _formatCnicFromDigits(cnicDigits),
        'cnicDigits': cnicDigits,
        'cnicName': _nameController.text.trim(),
        'fatherName': _fatherNameController.text.trim(),
        'dob': _dobController.text.trim(),
        'cnicExpiry': _expiryController.text.trim(),
        'shopName': _shopNameController.text.trim(),
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
        'cityVillage': city,
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
        'sellerCategory': _selectedCategory,
        'preferredLanguage': _preferredLanguage,
        'phoneVerified': _phoneVerified,
        'cnicVerified': cnicVerified,
        'livenessVerified': false,
        'isCnicVerified': cnicVerified,
        'isFaceVerified': false,
        'payoutStatus': 'pending',
        'verificationStatus': 'pending',
        'is_verified': isFullyVerified,
        'isVerified': isFullyVerified,
        'isApproved': false,
        'reviewRequired': true,
        'cnicFrontLocalPath': _cnicFront?.path,
        'cnicBackLocalPath': _cnicBack?.path,
        'livenessStatusMessage': 'skipped_in_3_step_signup',
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      await _authService.upsertPhoneIndex(
        normalizedPhone: normalizedPhone,
        uid: user.uid,
      );

      final bool passwordProviderLinked =
          await _authService.ensurePasswordProviderLinkedForCurrentUser(
            normalizedPhone: normalizedPhone,
            password: _passwordController.text.trim(),
            flowLabel: 'seller_signup',
          );
      debugPrint(
        '[SELLER_SIGNUP] uid=${user.uid} passwordProviderLinked=$passwordProviderLinked',
      );

      await _authService.persistSessionUid(user.uid);

      AuthState.setSelectedUserType(selectedRole);
      AuthState.setSelectedRole(selectedRole);

      if (!mounted) return;
      setState(() {
        _accountCreated = true;
        _accountNeedsReview = needsManualReview;
        _createdUserData = <String, dynamic>{...payload, 'uid': user.uid};
        _completionMessage =
            'Seller account created successfully / سیلر اکاؤنٹ کامیابی سے بن گیا ہے';
      });
      _showSnack(_completionMessage!);
      _navigateAfterSignupSuccess();
    } on FirebaseException catch (error) {
      _showSnack(_friendlySubmitError(error.code, error.message));
    } catch (error) {
      _showSnack(
        'کچھ مسئلہ ہوا، دوبارہ کوشش کریں / Something went wrong, try again',
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String _friendlySubmitError(String code, String? message) {
    final String c = code.toLowerCase();
    if (c.contains('invalid-verification-code') ||
        c.contains('invalid-credential')) {
      return 'OTP درست نہیں ہے / OTP is incorrect';
    }
    if (c.contains('network') || c == 'unavailable') {
      return 'انٹرنیٹ مسئلہ ہے / Network issue';
    }
    if (c.contains('email-already-in-use')) {
      return 'یہ ای میل پہلے سے استعمال ہو رہی ہے / This email is already in use';
    }
    if (c.contains('phone') && c.contains('already')) {
      return 'یہ نمبر پہلے سے رجسٹرڈ ہے / This phone is already registered';
    }
    if (c.contains('cnic') && c.contains('already')) {
      return 'یہ CNIC پہلے سے رجسٹرڈ ہے / This CNIC is already registered';
    }
    if (c == 'email-already-in-use') {
      return 'This email is already in use / یہ ای میل پہلے سے استعمال ہو رہی ہے';
    }
    final String cleanMessage = (message ?? '').trim();
    if (cleanMessage.isNotEmpty) {
      return '$cleanMessage\nکچھ مسئلہ ہوا، دوبارہ کوشش کریں / Something went wrong, try again';
    }
    return 'کچھ مسئلہ ہوا، دوبارہ کوشش کریں / Something went wrong, try again';
  }

  void _navigateAfterSignupSuccess() {
    if (!mounted) return;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      final Map<String, dynamic> userData =
          _createdUserData ?? <String, dynamic>{'role': 'seller'};
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => SellerDashboard(userData: userData),
        ),
        (Route<dynamic> route) => false,
      );
    });
  }

  void _handleCompletionAction() {
    if (!_accountCreated) {
      _createAccountForSelectedRole();
      return;
    }

    final Map<String, dynamic> userData =
        _createdUserData ?? <String, dynamic>{'role': 'seller'};
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => SellerDashboard(userData: userData),
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: const Row(
          children: <Widget>[
            Icon(Icons.auto_awesome_rounded, color: _gold, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'اپنا کاروبار اعتماد کے ساتھ شروع کریں',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontFamily: _urduFont,
                  fontWeight: FontWeight.w600,
                ),
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
          Expanded(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Seller Registration / فروخت کنندہ رجسٹریشن',
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.2,
                  ),
                ),
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
      default:
        return _buildStepThree();
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

    final IconData heroIcon = validated
        ? Icons.verified_user_rounded
        : file == null
        ? Icons.contact_page_rounded
        : Icons.document_scanner_rounded;
    final String helperText = file == null
        ? 'Upload clear image / واضح تصویر اپ لوڈ کریں'
        : validated
        ? 'Ready for review / تصدیق کے لیے تیار'
        : 'Check details below / نیچے تفصیل چیک کریں';

    return Expanded(
      child: InkWell(
        onTap: isExtracting ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.all(14),
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
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: validated
                          ? Colors.green.withValues(alpha: 0.16)
                          : _gold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: validated
                            ? Colors.greenAccent.withValues(alpha: 0.5)
                            : _gold.withValues(alpha: 0.36),
                      ),
                    ),
                    child: Icon(heroIcon, color: validated ? Colors.greenAccent : _gold),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          file == null
                              ? Icons.add_photo_alternate_outlined
                              : Icons.refresh_rounded,
                          size: 12,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          file == null ? 'Upload' : 'Replace',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                helperText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10.8,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                file == null ? 'Camera / Gallery' : file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: file == null ? Colors.white54 : _gold,
                  fontSize: 11,
                  fontWeight: file == null ? FontWeight.w500 : FontWeight.w700,
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
          _buildStepTitle('شناختی کارڈ / CNIC Scan'),
          const SizedBox(height: 6),
          const Text(
            'Front اور back CNIC کی واضح تصاویر اپ لوڈ کریں تاکہ تفصیل محفوظ طریقے سے بھر سکے',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                setState(() => _isManualEditEnabled = !_isManualEditEnabled);
              },
              icon: Icon(
                _isManualEditEnabled
                    ? Icons.check_circle_outline_rounded
                    : Icons.edit_note_rounded,
                color: _gold,
                size: 16,
              ),
              label: Text(
                _isManualEditEnabled ? 'Manual edit on' : 'Manual edit',
                style: const TextStyle(color: _gold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white),
            readOnly: !_isManualEditEnabled,
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
            readOnly: !_isManualEditEnabled,
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
            readOnly: !_isManualEditEnabled,
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
            readOnly: !_isManualEditEnabled,
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
            readOnly: !_isManualEditEnabled,
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
          if ((_stepInlineError ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _stepInlineError!,
              style: const TextStyle(color: Color(0xFFFFD9D9), fontSize: 12),
            ),
          ],
          if ((_aiInlineWarning ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gold.withValues(alpha: 0.42)),
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
      label =
          'CNIC details extracted successfully / CNIC تفصیل کامیابی سے حاصل ہوگئی';
      tone = Colors.greenAccent;
      icon = Icons.verified_rounded;
    } else if (manualReady) {
      label =
          'Manual details are complete. You can continue / دستی معلومات مکمل ہیں، آپ آگے بڑھ سکتے ہیں';
      tone = _gold;
      icon = Icons.check_circle_outline_rounded;
    } else if (bothUploaded) {
      label =
          'Complete missing fields manually to continue / آگے بڑھنے کے لئے باقی معلومات دستی مکمل کریں';
      tone = _gold;
      icon = Icons.edit_note_rounded;
    } else {
      label =
          'Upload front and back CNIC to start / شروع کرنے کے لئے فرنٹ اور بیک CNIC اپ لوڈ کریں';
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
        border: Border.all(color: iconTone.withValues(alpha: 0.8)),
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
          _buildStepTitle('نمبر تصدیق اور پاس ورڈ / OTP + Password'),
          const SizedBox(height: 10),
          if (!_phoneVerified)
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              style: const TextStyle(color: Colors.white),
              decoration: _fieldDecoration(
                label: 'Phone Number / موبائل نمبر',
                icon: Icons.phone_rounded,
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _gold.withValues(alpha: 0.45)),
              ),
              child: Text(
                'فون نمبر تصدیق شدہ: ${_formatPhoneForDisplay(_phoneController.text.trim())}',
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 12),
          _buildStatusChip(
            ok: _phoneVerified,
            okText: 'Verified / تصدیق ہوگئی',
            pendingText: 'Unverified / غیر تصدیق شدہ',
          ),
          if ((_otpStatusMessage ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: _otpStatusIsError
                    ? const Color(0x33D96A6A)
                    : const Color(0x332B5B3A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _otpStatusIsError
                      ? const Color(0xFFE6A0A0)
                      : const Color(0xFFD4AF37),
                ),
              ),
              child: Text(
                _otpStatusMessage!,
                style: TextStyle(
                  color: _otpStatusIsError
                      ? const Color(0xFFFFECEC)
                      : const Color(0xFFFFF5D7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
                  onPressed:
                      (_verificationId ?? '').isEmpty ||
                          _isVerifyingOtp ||
                          _otpController.text.trim().length != 6
                      ? null
                      : () => _verifyOtp(_otpController.text.trim()),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: BorderSide(color: _gold.withValues(alpha: 0.75)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: _isVerifyingOtp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Verify OTP / او ٹی پی تصدیق'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            autofillHints: const <String>[AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            maxLength: 6,
            style: const TextStyle(
              color: Colors.white,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w700,
            ),
            decoration: _fieldDecoration(
              label: 'OTP Code / او ٹی پی کوڈ',
              icon: Icons.password_rounded,
              hint: '6-digit code',
            ).copyWith(counterText: ''),
            onChanged: (String value) {
              final String digits = _onlyDigits(value);
              if (digits != value) {
                _otpController.value = TextEditingValue(
                  text: digits,
                  selection: TextSelection.collapsed(offset: digits.length),
                );
              }
              if (_otpInlineError != null && digits.length == 6) {
                setState(() => _otpInlineError = null);
              }
            },
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              Text(
                _otpResendSeconds > 0
                    ? 'Resend in $_otpResendSeconds s'
                    : 'OTP نہ ملا؟',
                style: const TextStyle(color: Colors.white70, fontSize: 11.5),
              ),
              const Spacer(),
              TextButton(
                onPressed: (_otpResendSeconds > 0 || _isSendingOtp)
                    ? null
                    : _sendOtp,
                child: const Text('Resend OTP / دوبارہ بھیجیں'),
              ),
            ],
          ),
          if ((_otpInlineError ?? '').isNotEmpty) ...<Widget>[
            Text(
              _otpInlineError!,
              style: const TextStyle(color: Color(0xFFFFD9D9), fontSize: 12),
            ),
            const SizedBox(height: 8),
          ],
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
            onChanged: (String value) {
              if (_passwordInlineError != null && value.trim().length >= 8) {
                setState(() => _passwordInlineError = null);
              }
            },
          ),
          if ((_passwordInlineError ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              _passwordInlineError!,
              style: const TextStyle(color: Color(0xFFFFD9D9), fontSize: 12),
            ),
          ],
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
            onChanged: (String value) {
              if (_confirmPasswordInlineError != null &&
                  value.trim() == _passwordController.text.trim()) {
                setState(() => _confirmPasswordInlineError = null);
              }
            },
          ),
          if ((_confirmPasswordInlineError ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              _confirmPasswordInlineError!,
              style: const TextStyle(color: Color(0xFFFFD9D9), fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'OTP تصدیق مکمل ہوتے ہی آپ اگلے مرحلے پر جا سکتے ہیں',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
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
            void runFilter(String query) {
              final String q = query.trim().toLowerCase();
              setSheetState(() {
                if (q.isEmpty) {
                  filtered = options;
                } else {
                  filtered = options
                      .where((BilingualLocationOption item) {
                        final String en = item.labelEn.toLowerCase();
                        final String ur = item.labelUr.toLowerCase();
                        final String code = item.code.toLowerCase();
                        return en.contains(q) ||
                            ur.contains(q) ||
                            code.contains(q);
                      })
                      .toList(growable: false);
                }
              });
            }

            return SafeArea(
              child: Container(
                margin: const EdgeInsets.only(top: 80),
                decoration: BoxDecoration(
                  color: const Color(0xFF103A29),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(18),
                  ),
                  border: Border.all(color: _gold.withValues(alpha: 0.30)),
                ),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: TextField(
                        controller: searchCtrl,
                        onChanged: runFilter,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Search / تلاش کریں',
                          hintStyle: const TextStyle(color: Colors.white60),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _gold,
                          ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.08),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _gold.withValues(alpha: 0.45),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: _gold.withValues(alpha: 0.45),
                            ),
                          ),
                          focusedBorder: const OutlineInputBorder(
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                            borderSide: BorderSide(color: _gold),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            Divider(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.06),
                            ),
                        itemBuilder: (BuildContext context, int index) {
                          final BilingualLocationOption item = filtered[index];
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
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _gold.withValues(alpha: 0.55)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, color: enabled ? _gold : Colors.white30, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                shown,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white54,
                  fontSize: 13,
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

  Widget _buildStepThree() {
    final PakistanLocationService locationService =
        PakistanLocationService.instance;
    final List<BilingualLocationOption> provinces =
        locationService.provinceOptions;
    final List<BilingualLocationOption> districts = _selectedProvince == null
        ? const <BilingualLocationOption>[]
        : locationService.districtOptions(_selectedProvince!);
    final List<BilingualLocationOption> tehsils = _selectedDistrict == null
        ? const <BilingualLocationOption>[]
        : locationService.tehsilOptions(_selectedDistrict!);
    final List<BilingualLocationOption> cities =
        (_selectedDistrict == null || _selectedTehsil == null)
        ? const <BilingualLocationOption>[]
        : locationService.cityOptionsLocalized(
            district: _selectedDistrict!,
            tehsil: _selectedTehsil!,
          );

    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildStepTitle('کاروبار اور مقام / Business + Location'),
          const SizedBox(height: 10),
          TextFormField(
            controller: _shopNameController,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Shop name / دکان یا کاروبار کا نام',
              icon: Icons.storefront_outlined,
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategory,
            isExpanded: true,
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
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (String? value) =>
                setState(() => _selectedCategory = value),
          ),
          const SizedBox(height: 10),
          _buildLocationSelectorField(
            label: 'Province / صوبہ',
            icon: Icons.map_rounded,
            selectedValue: _selectedProvince,
            onTap: () async {
              final String? value = await _showSearchableLocationSelector(
                title: 'Province / صوبہ',
                options: provinces,
                selected: _selectedProvince,
              );
              if (value == null || !mounted) return;
              setState(() {
                _selectedProvince = value;
                _selectedDistrict = null;
                _selectedTehsil = null;
                _selectedCity = null;
                _cityText = null;
                _cityController.clear();
              });
            },
          ),
          const SizedBox(height: 10),
          _buildLocationSelectorField(
            label: 'District / ضلع',
            icon: Icons.location_city_rounded,
            selectedValue: _selectedDistrict,
            enabled: _selectedProvince != null,
            onTap: () async {
              final String? value = await _showSearchableLocationSelector(
                title: 'District / ضلع',
                options: districts,
                selected: _selectedDistrict,
              );
              if (value == null || !mounted) return;
              setState(() {
                _selectedDistrict = value;
                _selectedTehsil = null;
                _selectedCity = null;
                _cityText = null;
                _cityController.clear();
              });
            },
          ),
          const SizedBox(height: 10),
          _buildLocationSelectorField(
            label: 'Tehsil / تحصیل',
            icon: Icons.alt_route_rounded,
            selectedValue: _selectedTehsil,
            enabled: _selectedDistrict != null,
            onTap: () async {
              final String? value = await _showSearchableLocationSelector(
                title: 'Tehsil / تحصیل',
                options: tehsils,
                selected: _selectedTehsil,
              );
              if (value == null || !mounted) return;
              setState(() {
                _selectedTehsil = value;
                _selectedCity = null;
                _cityText = null;
                _cityController.clear();
              });
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            enabled: _selectedTehsil != null,
            controller: _cityController,
            onChanged: (val) => setState(() {
              _cityText = val.trim();
              _selectedCity = _cityText;
            }),
            decoration: _fieldDecoration(
              label: 'City / شہر / علاقہ',
              icon: Icons.location_city_rounded,
              hint: 'Enter city, town, or area',
            ),
            style: const TextStyle(color: Colors.white),
            textInputAction: TextInputAction.done,
            maxLength: 48,
            validator: (value) {
              if ((value ?? '').trim().length < 2) {
                return 'City / شہر / علاقہ is required';
              }
              return null;
            },
          ),
          if (cities.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: cities
                  .take(6)
                  .map(
                    (BilingualLocationOption item) => ActionChip(
                      label: Text(item.bilingualLabel),
                      onPressed: () {
                        setState(() {
                          _selectedCity = item.labelEn;
                          _cityText = item.labelEn;
                          _cityController.text = item.labelEn;
                          _cityController.selection = TextSelection.collapsed(
                            offset: item.labelEn.length,
                          );
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          if ((_locationInlineError ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _locationInlineError!,
              style: const TextStyle(color: Color(0xFFFFD9D9), fontSize: 12),
            ),
          ],
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
            isExpanded: true,
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
            isExpanded: true,
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
    final List<BilingualLocationOption> provinces =
        locationService.provinceOptions;
    final List<BilingualLocationOption> districts = _selectedProvince == null
        ? const <BilingualLocationOption>[]
        : locationService.districtOptions(_selectedProvince!);
    final List<BilingualLocationOption> tehsils = _selectedDistrict == null
        ? const <BilingualLocationOption>[]
        : locationService.tehsilOptions(_selectedDistrict!);
    final List<BilingualLocationOption> cities =
        (_selectedDistrict == null || _selectedTehsil == null)
        ? const <BilingualLocationOption>[]
        : locationService.cityOptionsLocalized(
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
            isExpanded: true,
            initialValue: _selectedProvince,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Province / صوبہ',
              icon: Icons.map_rounded,
            ),
            items: provinces
                .map(
                  (BilingualLocationOption item) => DropdownMenuItem<String>(
                    value: item.labelEn,
                    child: Text(
                      item.bilingualLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                _cityText = null;
                _cityController.clear();
                _accountCreated = false;
                _createdUserData = null;
                _completionMessage = null;
              });
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedDistrict,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'District / ضلع',
              icon: Icons.location_city_rounded,
            ),
            items: districts
                .map(
                  (BilingualLocationOption item) => DropdownMenuItem<String>(
                    value: item.labelEn,
                    child: Text(
                      item.bilingualLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      _cityText = null;
                      _cityController.clear();
                      _accountCreated = false;
                      _createdUserData = null;
                      _completionMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _selectedTehsil,
            dropdownColor: _greenMid,
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'Tehsil / تحصیل',
              icon: Icons.alt_route_rounded,
            ),
            items: tehsils
                .map(
                  (BilingualLocationOption item) => DropdownMenuItem<String>(
                    value: item.labelEn,
                    child: Text(
                      item.bilingualLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
                      _cityText = null;
                      _cityController.clear();
                      _accountCreated = false;
                      _createdUserData = null;
                      _completionMessage = null;
                    });
                  },
          ),
          const SizedBox(height: 10),
          TextFormField(
            enabled: _selectedTehsil != null,
            controller: _cityController,
            onChanged: (String value) {
              setState(() {
                _selectedCity = value.trim();
                _cityText = value.trim();
                _accountCreated = false;
                _createdUserData = null;
                _completionMessage = null;
              });
            },
            style: const TextStyle(color: Colors.white),
            decoration: _fieldDecoration(
              label: 'City / شہر / علاقہ',
              icon: Icons.location_on_rounded,
              hint: 'Enter city, town, or area',
            ),
            maxLength: 48,
            validator: (value) {
              if ((value ?? '').trim().length < 2) {
                return 'City / شہر / علاقہ is required';
              }
              return null;
            },
          ),
          if (cities.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: cities
                  .take(6)
                  .map(
                    (BilingualLocationOption item) => ActionChip(
                      label: Text(item.bilingualLabel),
                      onPressed: () {
                        setState(() {
                          _selectedCity = item.labelEn;
                          _cityText = item.labelEn;
                          _cityController.text = item.labelEn;
                          _cityController.selection = TextSelection.collapsed(
                            offset: item.labelEn.length,
                          );
                        });
                      },
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
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
          _reviewRow('City / شہر', (_cityText ?? _selectedCity ?? '-')),
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

  bool _isCurrentStepValid() {
    switch (_currentStep) {
      case 0:
        final String name = _nameController.text.trim();
        final String fatherName = _fatherNameController.text.trim();
        final String cnicDigits = _onlyDigits(_cnicController.text.trim());
        final String dob = _dobController.text.trim();
        return (_cnicFront != null &&
            _cnicBack != null &&
            name.isNotEmpty &&
            fatherName.isNotEmpty &&
            cnicDigits.length == 13 &&
            dob.isNotEmpty);
      case 1:
        return _phoneVerified &&
            _passwordController.text.trim().length >= 8 &&
            _passwordController.text.trim() ==
                _confirmPasswordController.text.trim();
      case 2:
        return _shopNameController.text.trim().isNotEmpty &&
            (_selectedCategory ?? '').isNotEmpty &&
            _selectedProvince != null &&
            _selectedDistrict != null &&
            _selectedTehsil != null &&
            (_cityText ?? '').trim().length >= 2;
      default:
        return true;
    }
  }

  Widget _buildBottomControls() {
    final bool isLast = _currentStep == _totalSteps - 1;
    final bool currentStepValid = _isCurrentStepValid();
    final bool canProceed =
        currentStepValid && !_isSubmitting && !_isAiExtracting;
    final String continueLabel = _currentStep == 0
        ? 'Continue / جاری رکھیں'
        : _currentStep == 1
        ? 'Continue / جاری رکھیں'
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
                gradient: LinearGradient(
                  colors: canProceed
                      ? const <Color>[Color(0xFFFFC24B), Color(0xFFFFD36A)]
                      : <Color>[
                          Colors.grey.withValues(alpha: 0.5),
                          Colors.grey.withValues(alpha: 0.4),
                        ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: canProceed
                    ? <BoxShadow>[
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: ElevatedButton(
                onPressed: canProceed
                    ? (isLast ? _handleCompletionAction : _nextStep)
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: canProceed ? _deepGreen : Colors.grey,
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
                        continueLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: canProceed ? _deepGreen : Colors.grey,
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.34),
                        ),
                      ),
                      child: Text(
                        'مرحلہ ${_currentStep + 1} از $_totalSteps',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
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
