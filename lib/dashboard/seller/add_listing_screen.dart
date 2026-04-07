import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../core/location_display_helper.dart';
import '../../core/mandi_unit_mapper.dart';
import '../../core/market_hierarchy.dart';
import '../../config/promotion_payment_config.dart';
import '../../services/ai_generative_service.dart';
import '../../services/layer2_market_intelligence_service.dart';
import '../../services/auth_service.dart';
import '../../services/marketplace_service.dart';
import '../components/audio_recorder_widget.dart';
import 'gemini_voice_helper.dart';
import '../../theme/app_colors.dart';
import 'components/featured_listing_payment_modal.dart';

class FraudPrecheckResult {
  const FraudPrecheckResult({
    required this.riskScore,
    required this.flags,
    required this.status,
  });

  final int riskScore;
  final List<String> flags;
  final String status;
}

class _VoiceApplyPlan {
  const _VoiceApplyPlan({
    required this.applied,
    required this.suggestions,
    required this.recognized,
  });

  final Map<String, dynamic> applied;
  final Map<String, String> suggestions;
  final Map<String, String> recognized;
}

class _LocationLeaf {
  const _LocationLeaf({
    required this.id,
    required this.nameEn,
    required this.nameUr,
  });

  final String id;
  final String nameEn;
  final String nameUr;
}

class _TehsilNode {
  const _TehsilNode({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.cities,
  });

  final String id;
  final String nameEn;
  final String nameUr;
  final List<_LocationLeaf> cities;
}

class _DistrictNode {
  const _DistrictNode({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.tehsils,
  });

  final String id;
  final String nameEn;
  final String nameUr;
  final List<_TehsilNode> tehsils;
}

class _ProvinceNode {
  const _ProvinceNode({
    required this.id,
    required this.nameEn,
    required this.nameUr,
    required this.districts,
  });

  final String id;
  final String nameEn;
  final String nameUr;
  final List<_DistrictNode> districts;
}

class AddListingScreen extends StatefulWidget {
  const AddListingScreen({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  static const Color _gold = AppColors.accentGold;
  static const Color _darkGreenStart = AppColors.background;
  static const Color _darkGreenMid = AppColors.background;
  static const Color _darkGreenEnd = AppColors.cardSurface;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final AuthService _authService = AuthService();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final MandiIntelligenceService _intelligenceService =
      MandiIntelligenceService();
  final Layer2MarketIntelligenceService _layer2Service =
      Layer2MarketIntelligenceService();
  final stt.SpeechToText _speechToText = stt.SpeechToText();

  MandiType _selectedMandiType = MandiType.crops;
  String _selectedCategoryOptionId = 'crops';
  String? _selectedProduct;
  String? _selectedRiceVariety;
  UnitType _selectedUnitType = UnitType.kg;
  final String _selectedCountry = MarketHierarchy.pakistanCountry;
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _localAreaController = TextEditingController();
  final TextEditingController _villageController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();

  final TextEditingController _districtAutocompleteController =
      TextEditingController();

  List<XFile> _images = <XFile>[];
  XFile? _trustPhoto;
  double? _trustPhotoLat;
  double? _trustPhotoLng;
  DateTime? _trustPhotoCapturedAt;
  String? _trustPhotoTag;
  int? _trustPhotoFileSize;
  XFile? _video;
  VideoPlayerController? _videoController;
  String? _recordedAudioPath;

  double? _videoLat;
  double? _videoLng;
  DateTime? _videoCapturedAt;
  String? _videoTag;
  int? _videoFileSize;
  int? _videoDurationSeconds;

  String? _verificationInlineError;

  bool _isSubmitting = false;
  bool _approvalCheckInProgress = true;
  bool _approvalLocked = false;
  String _approvalLockMessage =
      'آپ کی سیلر منظوری زیرِ جائزہ ہے۔ منظوری کے بعد ہی آپ لسٹنگ پوسٹ کر سکیں گے۔';
  bool _isVoiceAssistLoading = false;
  bool _isVoiceListening = false;
  bool _isMediaUploading = false;
  double _mediaUploadProgress = 0;
  bool _isLoadingMarket = false;
  bool _featuredListing = false;
  FeaturedListingPaymentData? _featuredPaymentData;
  String _selectedSaleType = 'auction';

  double? _marketAverage;
  double? _recommendedPrice;
  double? _priceDeviationPercent;
  String _sellerPriceInsight = '';
  bool _isLocationAssetReady = false;
  List<_ProvinceNode> _locationAssetProvinces = const <_ProvinceNode>[];
  Map<String, String> _voiceAssistSuggestions = const <String, String>{};

  final Map<String, String> _provinceUrduByEn = <String, String>{};
  final Map<String, String> _districtUrduByEn = <String, String>{};
  final Map<String, String> _tehsilUrduByEn = <String, String>{};
  final Map<String, String> _cityUrduByEn = <String, String>{};

  FraudPrecheckResult _fraudPrecheck = const FraudPrecheckResult(
    riskScore: 0,
    flags: <String>[],
    status: 'Low Risk',
  );
  String _lastSubmitGateLogSignature = '';

  Map<String, String> get _districtToProvince {
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      final map = <String, String>{};
      for (final province in _locationAssetProvinces) {
        for (final district in province.districts) {
          map[district.nameEn.toLowerCase()] = province.nameEn;
        }
      }
      return map;
    }

    final map = <String, String>{};
    for (final entry in AppConstants.pakistanLocations.entries) {
      for (final district in entry.value) {
        map[district.toLowerCase()] = entry.key;
      }
    }
    return map;
  }

  List<String> get _allDistricts {
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      final set = <String>{};
      for (final province in _locationAssetProvinces) {
        for (final district in province.districts) {
          if (district.nameEn.trim().isNotEmpty) {
            set.add(district.nameEn.trim());
          }
        }
      }
      final all = set.toList()..sort();
      return all;
    }

    final set = <String>{};
    for (final districts in AppConstants.pakistanLocations.values) {
      set.addAll(districts);
    }
    final all = set.toList()..sort();
    return all;
  }

  List<String> get _provinceOptions {
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      return _locationAssetProvinces.map((e) => e.nameEn).toList();
    }
    return PakistanLocationHierarchy.provinces;
  }

  List<String> get _districtOptions {
    final province = (_selectedProvince ?? '').trim();
    if (province.isEmpty) return const <String>[];

    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      final match = _locationAssetProvinces.where(
        (p) => p.nameEn.toLowerCase() == province.toLowerCase(),
      );
      if (match.isNotEmpty) {
        final districts = match.first.districts
            .map((e) => e.nameEn)
            .toList(growable: false);
        return districts;
      }
    }

    return PakistanLocationHierarchy.districtsForProvince(province);
  }

  List<String> get _tehsilOptions {
    final district = (_selectedDistrict ?? '').trim();
    if (district.isEmpty) return const <String>[];

    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final districtNode in province.districts) {
          if (districtNode.nameEn.toLowerCase() == district.toLowerCase()) {
            return districtNode.tehsils
                .map((e) => e.nameEn)
                .toList(growable: false);
          }
        }
      }
    }

    return PakistanLocationHierarchy.tehsilsForDistrict(district);
  }

  List<String> get _cityOptions {
    final district = (_selectedDistrict ?? '').trim();
    final tehsil = (_selectedTehsil ?? '').trim();
    if (district.isEmpty || tehsil.isEmpty) return const <String>[];
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final districtNode in province.districts) {
          if (districtNode.nameEn.toLowerCase() != district.toLowerCase()) {
            continue;
          }
          for (final tehsilNode in districtNode.tehsils) {
            if (tehsilNode.nameEn.toLowerCase() != tehsil.toLowerCase()) {
              continue;
            }
            final cities = tehsilNode.cities
                .map((e) => e.nameEn.trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false);
            return cities;
          }
        }
      }
    }

    return PakistanLocationHierarchy.citiesForTehsil(
      district: district,
      tehsil: tehsil,
    ).where((e) => e.trim().isNotEmpty).toList(growable: false);
  }

  List<String> get _productOptions =>
      CategoryConstants.itemsForCategoryId(_selectedCategoryOptionId);

  List<String> get _categoryOptions => MarketHierarchy.listingCategories
      .map((option) => option.bilingualLabel)
      .toList(growable: false);

  String get _selectedCategoryDisplay =>
      MarketHierarchy.listingCategoryLabelForId(_selectedCategoryOptionId);

  String get _selectedCategoryId => _selectedCategoryOptionId;

  String get _selectedCategoryLabel =>
      MarketHierarchy.listingCategoryLabelForId(_selectedCategoryOptionId);

  String get _selectedSubcategoryId =>
      MarketHierarchy.subcategoryIdFromProduct(_selectedProduct ?? '');

  String get _selectedSubcategoryLabel =>
      MarketHierarchy.subcategoryDisplayFromProduct(_selectedProduct ?? '');

  List<UnitType> get _allowedUnits => MandiUnitMapper.resolve(
    categoryId: _selectedCategoryOptionId,
    fallbackType: _selectedMandiType,
    subcategoryLabel: _selectedProduct,
  ).allowedUnits;

  bool get _isLivestock => _selectedMandiType == MandiType.livestock;
  bool get _isMilk => _selectedMandiType == MandiType.milk;
  bool get _isRiceCropSelected {
    final value = (_selectedProduct ?? '').toLowerCase();
    return value.contains('rice crop (paddy)') || value.contains('دھان');
  }

  bool get _isProcessedRiceSelected {
    final value = (_selectedProduct ?? '').toLowerCase();
    return value.contains('processed rice') || value.contains('چاول');
  }

  List<String> get _riceVarietyOptions {
    if (_isRiceCropSelected) {
      return const <String>[
        'Super Basmati (Paddy) / سپر باسمتی دھان',
        'IRRI-6 (Paddy) / اری-6 دھان',
        'IRRI-9 (Paddy) / اری-9 دھان',
        'PK-386 (Paddy) / پی کے-386 دھان',
        'KSK-133 (Paddy) / کے ایس کے-133 دھان',
        'Hybrid Paddy / ہائبرڈ دھان',
      ];
    }
    return const <String>[
      'Super Basmati Rice / سپر باسمتی چاول',
      '1121 Basmati Rice / 1121 باسمتی چاول',
      '1509 Basmati Rice / 1509 باسمتی چاول',
      'IRRI-6 Rice / اری-6 چاول',
      'IRRI-9 Rice / اری-9 چاول',
      'Sella Rice / سیلا چاول',
      'Brown Rice / براؤن چاول',
      'Broken Rice / ٹوٹا چاول',
    ];
  }

  double get _numericPrice =>
      double.tryParse(_priceController.text.trim()) ?? 0;
  double get _numericQuantity =>
      double.tryParse(_quantityController.text.trim()) ?? 0;
  double get _numericWeight =>
      double.tryParse(_weightController.text.trim()) ?? 0;

  double get _valueBaseQuantity =>
      _isLivestock ? _numericWeight : _numericQuantity;

  double get _totalValue => _numericPrice * _valueBaseQuantity;

  String get _mappedDescriptionForPayload {
    final base = _descriptionController.text.trim();
    final variety = (_selectedRiceVariety ?? '').trim();
    if (variety.isEmpty) return base;
    return base.isEmpty
        ? 'Rice Variety: $variety'
        : 'Rice Variety: $variety\n$base';
  }

  MarketCategoryOption? _listingCategoryFromLabel(String selected) {
    return MarketHierarchy.listingCategoryFromLabel(selected);
  }

  bool get _hasRequiredTrustPhoto {
    // Keep trust requirement aligned with what seller sees in UI:
    // selected trust photo + GPS coordinates.
    return _trustPhoto != null &&
        _trustPhotoLat != null &&
        _trustPhotoLng != null;
  }

  List<String> _submitDisabledReasons() {
    final List<String> reasons = <String>[];
    if (_isSubmitting) reasons.add('isSubmitting');
    if (_approvalCheckInProgress) reasons.add('approvalCheckInProgress');
    if (_approvalLocked) reasons.add('approvalLocked');
    if (!_hasRequiredTrustPhoto) reasons.add('missingTrustPhotoOrGps');
    if (_hardFraudBlock) reasons.add('hardFraudBlock');
    return reasons;
  }

  void _logSubmitGateStatus(String source) {
    final String signature = [
      _trustPhoto != null ? '1' : '0',
      _trustPhotoLat != null ? '1' : '0',
      _trustPhotoLng != null ? '1' : '0',
      _trustPhotoCapturedAt != null ? '1' : '0',
      _isSubmitting ? '1' : '0',
      _isMediaUploading ? '1' : '0',
      _approvalCheckInProgress ? '1' : '0',
      _approvalLocked ? '1' : '0',
      _hardFraudBlock ? '1' : '0',
      _hasRequiredTrustPhoto ? '1' : '0',
      _hasAllRequiredForSubmit ? '1' : '0',
      _submitDisabledReasons().join(','),
    ].join('|');
    if (signature == _lastSubmitGateLogSignature) {
      return;
    }
    _lastSubmitGateLogSignature = signature;

    debugPrint(
      '[ADD_LISTING_GATE][$source] trustPhotoFilePresent=${_trustPhoto != null} gpsPresent=${_trustPhotoLat != null && _trustPhotoLng != null} latitude=${_trustPhotoLat?.toStringAsFixed(6) ?? 'null'} longitude=${_trustPhotoLng?.toStringAsFixed(6) ?? 'null'} uploadFlag=$_isMediaUploading isSubmitting=$_isSubmitting approvalCheckInProgress=$_approvalCheckInProgress approvalLocked=$_approvalLocked hardFraudBlock=$_hardFraudBlock hasRequiredTrustPhoto=$_hasRequiredTrustPhoto hasAllRequiredForSubmit=$_hasAllRequiredForSubmit disabledReasons=${_submitDisabledReasons().join(',')}',
    );
  }

  List<XFile> get _allListingImages {
    final files = <XFile>[];
    if (_trustPhoto != null) {
      files.add(_trustPhoto!);
    }
    files.addAll(_images);
    return files;
  }

  bool get _hardFraudBlock {
    return _fraudPrecheck.riskScore > 85 && !_hasRequiredTrustPhoto;
  }

  String get _sellerDocUid => (widget.userData['uid'] ?? '').toString().trim();

  Future<void> _logAuthSnapshot(
    String stage, {
    required String finalDecision,
    required String reason,
  }) async {
    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    final String localSessionUid =
        (await _authService.getPersistedSessionUid() ?? '').trim();
    debugPrint(
      '[AddListingAuth] stage=$stage '
      'firebaseUid=${firebaseUid.isEmpty ? 'null' : firebaseUid} '
      'localSessionUid=${localSessionUid.isEmpty ? 'null' : localSessionUid} '
      'sellerDocUid=${_sellerDocUid.isEmpty ? 'null' : _sellerDocUid} '
      'finalDecision=$finalDecision '
      'reason=$reason',
    );
  }

  Future<bool> _ensureListingAuthSession(String stage) async {
    final String firebaseUid = (FirebaseAuth.instance.currentUser?.uid ?? '')
        .trim();
    if (firebaseUid.isNotEmpty) {
      await _logAuthSnapshot(
        '${stage}_auth_present',
        finalDecision: 'inspect',
        reason: 'firebase_session_already_present',
      );
      return true;
    }

    final bool restored = await _authService.restoreFirebaseSessionForUserData(
      widget.userData,
      flowLabel: 'add_listing_$stage',
    );
    await _logAuthSnapshot(
      '${stage}_after_restore',
      finalDecision: restored ? 'inspect' : 'pending',
      reason: restored
          ? 'firebase_session_restored'
          : 'firebase_session_restore_failed',
    );
    return restored;
  }

  bool get _hasAllRequiredForSubmit {
    // Keep button state lightweight; full validation still runs inside _submitListing.
    return !_isSubmitting &&
        !_approvalCheckInProgress &&
        !_approvalLocked &&
        _hasRequiredTrustPhoto &&
        !_hardFraudBlock;
  }

  @override
  void initState() {
    super.initState();
    _selectedUnitType = MandiUnitMapper.resolve(
      categoryId: _selectedCategoryOptionId,
      fallbackType: _selectedMandiType,
      subcategoryLabel: _selectedProduct,
    ).defaultUnit;

    final listeners = <TextEditingController>[
      _priceController,
      _quantityController,
      _weightController,
      _cityController,
      _localAreaController,
      _descriptionController,
      _villageController,
      _breedController,
      _ageController,
      _fatController,
    ];
    for (final c in listeners) {
      c.addListener(_onFormChange);
    }
    _fraudPrecheck = _runFraudPrecheck();
    unawaited(
      _logAuthSnapshot(
        'screen_open',
        finalDecision: 'inspect',
        reason: 'screen_initialized',
      ),
    );
    unawaited(_ensureListingAuthSession('screen_open'));
    unawaited(_loadPakistanLocationsAsset());
    unawaited(_enforceSellerApprovalPolicy());
  }

  Future<void> _enforceSellerApprovalPolicy() async {
    await _ensureListingAuthSession('approval_check');
    final User? user = FirebaseAuth.instance.currentUser;
    final String firebaseUid = (user?.uid ?? '').trim();
    if (firebaseUid.isEmpty) {
      await _logAuthSnapshot(
        'approval_check_blocked',
        finalDecision: 'block',
        reason: 'firebase_auth_session_missing',
      );
      if (!mounted) return;
      setState(() {
        _approvalCheckInProgress = false;
        _approvalLocked = true;
        _approvalLockMessage =
            'لاگ اِن ضروری ہے۔ براہِ کرم دوبارہ سائن اِن کریں تاکہ لسٹنگ پوسٹ ہو سکے۔';
      });
      return;
    }

    if (_sellerDocUid.isNotEmpty && _sellerDocUid != firebaseUid) {
      await _logAuthSnapshot(
        'approval_check_blocked',
        finalDecision: 'block',
        reason: 'seller_doc_uid_mismatch_firebase_uid',
      );
      if (!mounted) return;
      setState(() {
        _approvalCheckInProgress = false;
        _approvalLocked = true;
        _approvalLockMessage =
            'سیشن میں تضاد ہے۔ براہِ کرم دوبارہ سائن اِن کریں۔';
      });
      return;
    }

    final String sellerDocUid = firebaseUid;

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(sellerDocUid)
              .get();

      final Map<String, dynamic> profile = <String, dynamic>{
        ...widget.userData,
        ...(snap.data() ?? const <String, dynamic>{}),
      };

      final String verificationStatus = (profile['verificationStatus'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final bool approved =
          profile['isApproved'] == true ||
          verificationStatus == 'approved' ||
          verificationStatus == 'verified';
      final bool suspended = profile['isSuspended'] == true;
      final bool restricted = profile['listingRestricted'] == true;

      String message = _approvalLockMessage;
      bool locked = !approved;

      if (suspended) {
        locked = true;
        message =
            'آپ کا اکاؤنٹ عارضی طور پر معطل ہے۔ براہِ کرم ایڈمن سپورٹ سے رابطہ کریں۔';
      } else if (restricted) {
        locked = true;
        message =
            'آپ کی لسٹنگ رسائی محدود ہے۔ براہِ کرم ایڈمن سے منظوری کے بعد دوبارہ کوشش کریں۔';
      } else if (verificationStatus == 'rejected') {
        locked = true;
        message =
            'آپ کی سیلر تصدیق مسترد ہوئی ہے۔ پروفائل درست کر کے دوبارہ جائزہ کے لیے بھیجیں۔';
      } else if (!approved) {
        message =
            'آپ کی سیلر منظوری زیرِ جائزہ ہے۔ منظوری کے بعد ہی آپ لسٹنگ پوسٹ کر سکیں گے۔';
      }

      if (!mounted) return;
      setState(() {
        _approvalCheckInProgress = false;
        _approvalLocked = locked;
        _approvalLockMessage = message;
      });
      await _logAuthSnapshot(
        'approval_check_complete',
        finalDecision: locked ? 'block' : 'allow',
        reason: locked ? 'seller_not_approved' : 'seller_approved',
      );
    } catch (_) {
      await _logAuthSnapshot(
        'approval_check_failed',
        finalDecision: 'block',
        reason: 'approval_doc_read_failed',
      );
      if (!mounted) return;
      setState(() {
        _approvalCheckInProgress = false;
        _approvalLocked = true;
        _approvalLockMessage =
            'سیلر منظوری کی تصدیق اس وقت ممکن نہیں۔ انٹرنیٹ چیک کر کے دوبارہ کوشش کریں۔';
      });
    }
  }

  @override
  void dispose() {
    // Remove _onFormChange listeners before disposal to satisfy
    // ChangeNotifier debug assertions and prevent use-after-dispose.
    _priceController.removeListener(_onFormChange);
    _quantityController.removeListener(_onFormChange);
    _weightController.removeListener(_onFormChange);
    _cityController.removeListener(_onFormChange);
    _localAreaController.removeListener(_onFormChange);
    _villageController.removeListener(_onFormChange);
    _descriptionController.removeListener(_onFormChange);
    _breedController.removeListener(_onFormChange);
    _ageController.removeListener(_onFormChange);
    _fatController.removeListener(_onFormChange);
    _priceController.dispose();
    _quantityController.dispose();
    _weightController.dispose();
    _cityController.dispose();
    _localAreaController.dispose();
    _villageController.dispose();
    _descriptionController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _fatController.dispose();
    _districtAutocompleteController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _onFormChange() {
    if (!mounted) return;
    setState(() {
      _fraudPrecheck = _runFraudPrecheck();
      _logSubmitGateStatus('form_change');
    });
  }

  String _formatDecimalForField(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  String _normalizeVoiceToken(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool get _isAuctionSale => _selectedSaleType == 'auction';

  static const List<String> _voiceAuctionTerms = <String>[
    'auction',
    'boli',
    'بولی',
    'bid',
    'bidding',
  ];

  static const List<String> _voiceFixedTerms = <String>[
    'fixed price',
    'fixed rate',
    'direct price',
    'seedhi qeemat',
    'seedha rate',
    'سیدھی قیمت',
  ];

  String? _detectSaleTypeFromVoice(String transcript) {
    final normalized = _normalizeVoiceToken(transcript);
    if (normalized.isEmpty) return null;

    final hasAuction = _voiceAuctionTerms.any(
      (term) => _voiceTokenContains(normalized, term),
    );
    final hasFixed = _voiceFixedTerms.any(
      (term) => _voiceTokenContains(normalized, term),
    );

    if (hasFixed && !hasAuction) return 'fixed';
    if (hasAuction && !hasFixed) return 'auction';
    return null;
  }

  bool _voiceTokenMatches(String raw, String candidate) {
    final a = _normalizeVoiceToken(raw);
    final b = _normalizeVoiceToken(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    return a == b;
  }

  bool _voiceTokenContains(String raw, String candidate) {
    final a = _normalizeVoiceToken(raw);
    final b = _normalizeVoiceToken(candidate);
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b || a.contains(b) || b.contains(a)) return true;
    final compactA = a.replaceAll(' ', '');
    final compactB = b.replaceAll(' ', '');
    return compactA.contains(compactB) || compactB.contains(compactA);
  }

  static const Map<String, List<String>> _voiceLocationAliases =
      <String, List<String>>{
        'Lahore': <String>['lahore', 'لاہور'],
        'Kasur': <String>['kasur', 'قصور'],
        'Faisalabad': <String>['faisalabad', 'فیصل آباد', 'فیصلاباد'],
        'Karachi': <String>['karachi', 'کراچی'],
        'Multan': <String>['multan', 'ملتان'],
        'Gujranwala': <String>['gujranwala', 'گوجرانوالہ'],
        'Sahiwal': <String>['sahiwal', 'ساہیوال'],
        'Okara': <String>['okara', 'اوکاڑہ'],
        'Sheikhupura': <String>['sheikhupura', 'شیخوپورہ'],
        'Punjab': <String>['punjab', 'پنجاب'],
        'Sindh': <String>['sindh', 'سندھ'],
        'Khyber Pakhtunkhwa (KPK)': <String>[
          'kpk',
          'kp',
          'khyber pakhtunkhwa',
          'خیبر پختونخوا',
          'پختونخوا',
        ],
        'Balochistan': <String>['balochistan', 'بلوچستان'],
      };

  List<String> _locationSearchTerms(String option) {
    final label = _locationOptionLabel(option);
    final terms = <String>{
      option.trim(),
      label.trim(),
      ..._splitBilingual(option).map((e) => e.trim()),
      ..._splitBilingual(label).map((e) => e.trim()),
      ...(_voiceLocationAliases[option] ?? const <String>[]),
    }..removeWhere((e) => e.isEmpty);
    final list = terms.toList()..sort((a, b) => b.length.compareTo(a.length));
    return list;
  }

  String? _safeMatchLocationOption(String raw, List<String> options) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in options) {
      for (final term in _locationSearchTerms(option)) {
        if (_voiceTokenMatches(value, term) ||
            _voiceTokenContains(value, term)) {
          return option;
        }
      }
    }
    return null;
  }

  String? _findBestTranscriptLocationOption(
    String transcript,
    List<String> options,
  ) {
    final source = transcript.trim();
    if (source.isEmpty) return null;

    String? bestOption;
    var bestScore = 0;
    for (final option in options) {
      for (final term in _locationSearchTerms(option)) {
        final normalizedTerm = _normalizeVoiceToken(term).replaceAll(' ', '');
        if (normalizedTerm.isEmpty) continue;
        if (_voiceTokenContains(source, term) &&
            normalizedTerm.length > bestScore) {
          bestScore = normalizedTerm.length;
          bestOption = option;
        }
      }
    }
    return bestOption;
  }

  List<String> _cityOptionsForSelection({
    required String district,
    required String tehsil,
  }) {
    final safeDistrict = district.trim();
    final safeTehsil = tehsil.trim();
    if (safeDistrict.isEmpty || safeTehsil.isEmpty) {
      return const <String>[];
    }

    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final districtNode in province.districts) {
          if (districtNode.nameEn.toLowerCase() != safeDistrict.toLowerCase()) {
            continue;
          }
          for (final tehsilNode in districtNode.tehsils) {
            if (tehsilNode.nameEn.toLowerCase() != safeTehsil.toLowerCase()) {
              continue;
            }
            final cities = tehsilNode.cities
                .map((e) => e.nameEn.trim())
                .where((e) => e.isNotEmpty)
                .toList(growable: false);
            return cities;
          }
        }
      }
    }

    return PakistanLocationHierarchy.citiesForTehsil(
      district: safeDistrict,
      tehsil: safeTehsil,
    ).where((e) => e.trim().isNotEmpty).toList(growable: false);
  }

  bool _isDistinctLocalArea(
    String value, {
    String province = '',
    String district = '',
    String tehsil = '',
  }) {
    final local = value.trim();
    if (local.isEmpty) return false;
    return !_voiceTokenContains(local, province) &&
        !_voiceTokenContains(local, district) &&
        !_voiceTokenContains(local, tehsil);
  }

  Map<String, String> _resolveTranscriptLocation({
    required String transcript,
    required GeminiVoiceDraft draft,
  }) {
    final result = <String, String>{};

    var province =
        _safeMatchLocationOption(draft.province, _provinceOptions) ??
        _findBestTranscriptLocationOption(transcript, _provinceOptions);
    if ((province ?? '').isNotEmpty) {
      result['province'] = province!;
    }

    final districtPool = (province ?? '').isNotEmpty
        ? _districtOptionsForProvince(province!)
        : _allDistricts;
    var district =
        _safeMatchLocationOption(draft.district, districtPool) ??
        _findBestTranscriptLocationOption(transcript, districtPool);

    if ((district ?? '').isEmpty && transcript.trim().isNotEmpty) {
      for (final token in _extractLocationTokens(transcript)) {
        final hit = _resolveVoiceLocation(token);
        if ((hit['district'] ?? '').isNotEmpty) {
          district = hit['district']!.trim();
          province ??= hit['province']?.trim();
          break;
        }
      }
    }

    if ((district ?? '').isNotEmpty) {
      result['district'] = district!;
      province ??= _findProvinceForDistrict(district);
      if ((province ?? '').isNotEmpty) {
        result['province'] = province!;
      }
    }

    final tehsilPool = (district ?? '').isNotEmpty
        ? _tehsilOptionsForDistrict(district!)
        : const <String>[];
    var tehsil =
        _safeMatchLocationOption(draft.tehsil, tehsilPool) ??
        _findBestTranscriptLocationOption(transcript, tehsilPool);
    if ((tehsil ?? '').isEmpty && tehsilPool.length == 1) {
      tehsil = tehsilPool.first;
    }
    if ((tehsil ?? '').isNotEmpty) {
      result['tehsil'] = tehsil!;
    }

    final cityPool = (district ?? '').isNotEmpty && (tehsil ?? '').isNotEmpty
        ? _cityOptionsForSelection(district: district!, tehsil: tehsil!)
        : const <String>[];
    final matchedLocalArea =
        _safeMatchLocationOption(draft.localArea, cityPool) ??
        _findBestTranscriptLocationOption(transcript, cityPool);
    if ((matchedLocalArea ?? '').isNotEmpty &&
        _isDistinctLocalArea(
          matchedLocalArea!,
          province: result['province'] ?? '',
          district: result['district'] ?? '',
          tehsil: result['tehsil'] ?? '',
        )) {
      result['localArea'] = matchedLocalArea;
    } else if (_isDistinctLocalArea(
      draft.localArea,
      province: result['province'] ?? '',
      district: result['district'] ?? '',
      tehsil: result['tehsil'] ?? '',
    )) {
      result['localArea'] = draft.localArea.trim();
    }

    return result;
  }

  String? _safeMatchOption(
    String raw,
    List<String> options, {
    String Function(String)? labelBuilder,
  }) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in options) {
      final label = labelBuilder?.call(option) ?? option;
      if (_voiceTokenMatches(value, option) ||
          _voiceTokenMatches(value, label)) {
        return option;
      }
      final parts = _splitBilingual(label);
      if (_voiceTokenMatches(value, parts[0]) ||
          _voiceTokenMatches(value, parts[1])) {
        return option;
      }
    }
    return null;
  }

  MarketCategoryOption? _safeMatchCategory(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in MarketHierarchy.listingCategories) {
      if (_voiceTokenMatches(value, option.id) ||
          _voiceTokenMatches(value, option.labelEn) ||
          _voiceTokenMatches(value, option.labelUr) ||
          _voiceTokenMatches(value, option.bilingualLabel)) {
        return option;
      }
    }
    return null;
  }

  UnitType? _safeMatchUnit(String raw, List<UnitType> options) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    for (final option in options) {
      final aliases = <String>[
        option.wireValue,
        option.urduLabel,
        switch (option) {
          UnitType.mann => 'man',
          UnitType.kg => 'kilo',
          UnitType.litre => 'liter',
          UnitType.perHead => 'per head',
          UnitType.peti => 'peti',
        },
      ];
      for (final alias in aliases) {
        if (_voiceTokenMatches(value, alias)) {
          return option;
        }
      }
    }
    return null;
  }

  // Alias -> exact in-app taxonomy subcategory label (source of truth).
  static const Map<String, String> _voiceAliasToTaxonomySubcategory =
      <String, String>{
        'aalu': 'Potato / آلو',
        'aloo': 'Potato / آلو',
        'alu': 'Potato / آلو',
        'potato': 'Potato / آلو',
        'آلو': 'Potato / آلو',
        'pyaz': 'Onion / پیاز',
        'onion': 'Onion / پیاز',
        'پیاز': 'Onion / پیاز',
        'tamatar': 'Tomato / ٹماٹر',
        'tomato': 'Tomato / ٹماٹر',
        'ٹماٹر': 'Tomato / ٹماٹر',
        'shimla mirch': 'Capsicum / شملہ مرچ',
        'capsicum': 'Capsicum / شملہ مرچ',
        'شملہ مرچ': 'Capsicum / شملہ مرچ',
        'mirch': 'Chili / مرچ',
        'chili': 'Chili / مرچ',
        'مرچ': 'Chili / مرچ',
        'gandum': 'Wheat / گندم',
        'gehun': 'Wheat / گندم',
        'wheat': 'Wheat / گندم',
        'گندم': 'Wheat / گندم',
        'chawal': 'Processed Rice / چاول',
        'rice': 'Processed Rice / چاول',
        'چاول': 'Processed Rice / چاول',
        'dhan': 'Rice Crop (Paddy) / دھان',
        'paddy': 'Rice Crop (Paddy) / دھان',
        'دھان': 'Rice Crop (Paddy) / دھان',
        'broiler': 'Broiler / برائلر',
        'برائلر': 'Broiler / برائلر',
        'desi chicken': 'Desi Chicken / دیسی مرغی',
        'دیسی مرغی': 'Desi Chicken / دیسی مرغی',
        'bakra': 'Goat / بکری',
        'goat': 'Goat / بکری',
        'بکرا': 'Goat / بکری',
        'بکری': 'Goat / بکری',
      };

  ({MarketCategoryOption? category, String? subcategory})
  _findTaxonomyMatchFromTranscript(String transcript) {
    final normalizedTranscript = _normalizeVoiceToken(transcript);
    if (normalizedTranscript.isEmpty) {
      return (category: null, subcategory: null);
    }

    final categoryById = <String, MarketCategoryOption>{
      for (final c in MarketHierarchy.listingCategories) c.id: c,
    };

    MarketCategoryOption? matchedCategory;
    String? matchedSubcategory;

    final aliasKeys = _voiceAliasToTaxonomySubcategory.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final alias in aliasKeys) {
      final aliasNorm = _normalizeVoiceToken(alias);
      if (aliasNorm.isEmpty || !normalizedTranscript.contains(aliasNorm)) {
        continue;
      }
      final targetSubLabel = _voiceAliasToTaxonomySubcategory[alias] ?? '';
      if (targetSubLabel.isEmpty) continue;

      for (final category in MarketHierarchy.listingCategories) {
        final options = CategoryConstants.itemsForCategoryId(category.id);
        final safe = _safeMatchOption(targetSubLabel, options);
        if (safe != null) {
          matchedCategory = categoryById[category.id];
          matchedSubcategory = safe;
          return (category: matchedCategory, subcategory: matchedSubcategory);
        }
      }
    }

    // Backup: direct spoken match against existing in-app options.
    var bestScore = 0;
    for (final category in MarketHierarchy.listingCategories) {
      final options = CategoryConstants.itemsForCategoryId(category.id);
      for (final option in options) {
        final parts = _splitBilingual(option);
        final candidates = <String>[option, parts[0], parts[1]];
        for (final candidate in candidates) {
          final norm = _normalizeVoiceToken(candidate);
          if (norm.isEmpty) continue;
          if (normalizedTranscript.contains(norm) && norm.length > bestScore) {
            bestScore = norm.length;
            matchedCategory = categoryById[category.id];
            matchedSubcategory = option;
          }
        }
      }
    }

    return (category: matchedCategory, subcategory: matchedSubcategory);
  }

  static const Set<String> _descriptionHintKeywords = <String>{
    'fresh',
    'quality',
    'achi',
    'zabardast',
    'delivery',
    'available',
    'ready',
    'behtareen',
    'maal',
    'seedha',
    'direct',
    'mandi',
  };

  static const Set<String> _descriptionFillerWords = <String>{
    'mein',
    'main',
    'ma',
    'se',
    'ka',
    'ki',
    'ke',
    'wala',
    'wali',
    'walay',
    'waliyan',
    'from',
    'ye',
    'yeh',
    'tha',
    'the',
    'hain',
  };

  String _extractDescriptionCandidateWindow(String source) {
    final normalized = GeminiVoiceHelper.normalizeVoiceText(source);
    if (normalized.isEmpty) return '';

    final tokens = normalized
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (tokens.isEmpty) return '';

    var hitIndex = -1;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final matched = _descriptionHintKeywords.any(
        (keyword) =>
            token == keyword ||
            token.contains(keyword) ||
            keyword.contains(token),
      );
      if (matched) {
        hitIndex = i;
        break;
      }
    }

    if (hitIndex < 0) {
      return normalized;
    }

    final start = hitIndex - 2 < 0 ? 0 : hitIndex - 2;
    final end = hitIndex + 2 >= tokens.length
        ? tokens.length - 1
        : hitIndex + 2;
    return tokens.sublist(start, end + 1).join(' ');
  }

  Set<String> _allLocationTermsForDescription() {
    final terms = <String>{};

    for (final province in _provinceOptions) {
      terms.add(province);
      terms.add(_locationOptionLabel(province));
      terms.addAll(_splitBilingual(_locationOptionLabel(province)));
      terms.addAll(_voiceLocationAliases[province] ?? const <String>[]);
    }

    for (final district in _allDistricts) {
      terms.add(district);
      terms.add(_locationOptionLabel(district));
      terms.addAll(_splitBilingual(_locationOptionLabel(district)));
      terms.addAll(_voiceLocationAliases[district] ?? const <String>[]);
    }

    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final district in province.districts) {
          for (final tehsil in district.tehsils) {
            terms.add(tehsil.nameEn);
            terms.add(_locationOptionLabel(tehsil.nameEn));
            terms.addAll(_splitBilingual(_locationOptionLabel(tehsil.nameEn)));
            terms.addAll(
              _voiceLocationAliases[tehsil.nameEn] ?? const <String>[],
            );
          }
        }
      }
    } else {
      for (final district in _allDistricts) {
        for (final tehsil in PakistanLocationHierarchy.tehsilsForDistrict(
          district,
        )) {
          terms.add(tehsil);
          terms.add(_locationOptionLabel(tehsil));
          terms.addAll(_splitBilingual(_locationOptionLabel(tehsil)));
          terms.addAll(_voiceLocationAliases[tehsil] ?? const <String>[]);
        }
      }
    }

    return terms
      ..removeWhere((term) => term.trim().isEmpty)
      ..addAll(<String>[
        'punjab',
        'sindh',
        'kpk',
        'balochistan',
        'lahore',
        'kasur',
        'faisalabad',
      ]);
  }

  Set<String> _allCategoryTermsForDescription() {
    final terms = <String>{};

    for (final category in MarketHierarchy.listingCategories) {
      terms.add(category.id);
      terms.add(category.labelEn);
      terms.add(category.labelUr);
      terms.add(category.bilingualLabel);
      terms.addAll(_splitBilingual(category.bilingualLabel));
      terms.addAll(CategoryConstants.itemsForCategoryId(category.id));
      for (final option in CategoryConstants.itemsForCategoryId(category.id)) {
        terms.addAll(_splitBilingual(option));
      }
    }

    terms.addAll(_voiceAliasToTaxonomySubcategory.keys);
    terms.addAll(_voiceAliasToTaxonomySubcategory.values);

    return terms..removeWhere((term) => term.trim().isEmpty);
  }

  String _stripDescriptionTerms(String input, Set<String> stripTerms) {
    var desc = input;
    final sortedTerms = stripTerms.toList()
      ..sort((a, b) => b.trim().length.compareTo(a.trim().length));

    for (final term in sortedTerms) {
      for (final token in _splitBilingual(term)) {
        final normalizedToken = GeminiVoiceHelper.normalizeVoiceText(token);
        if (normalizedToken.isEmpty) continue;
        desc = desc.replaceAll(
          RegExp(
            r'\b' + RegExp.escape(normalizedToken) + r'\b',
            caseSensitive: false,
          ),
          ' ',
        );
      }
    }

    return desc;
  }

  String _compactDescription(String input) {
    final rawTokens = input
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .split(' ')
        .where((token) => token.trim().isNotEmpty)
        .toList(growable: false);
    if (rawTokens.isEmpty) return '';

    final output = <String>[];
    for (final token in rawTokens) {
      if (_descriptionFillerWords.contains(token)) {
        continue;
      }
      if (output.isNotEmpty && output.last == token) {
        continue;
      }
      output.add(token);
    }

    if (output.isEmpty) return '';
    if (output.length == 1 && output.first == 'hai') return '';
    return output.join(' ').trim();
  }

  String _finalDescriptionSafetyPass(String input, Set<String> safetyTerms) {
    var desc = input;

    desc = desc.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\b'), ' ');
    desc = _stripDescriptionTerms(desc, safetyTerms);
    desc = desc.replaceAll(
      RegExp(
        r'\b(kilo|kg|kilogram|mann|man|maund|litre|liter|ltr|peti|crate)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    desc = desc.replaceAll(
      RegExp(r'\b(rupay|rupee|rupees|rs\.?|pkr|روپے)\b', caseSensitive: false),
      ' ',
    );

    return _compactDescription(desc);
  }

  String _cleanVoiceDescription({
    required String source,
    required String quantity,
    required String unit,
    required String price,
    required String category,
    required String subcategory,
    required String province,
    required String district,
    required String tehsil,
    required String localArea,
  }) {
    final normalized = GeminiVoiceHelper.normalizeVoiceText(source);
    if (normalized.isEmpty) return '';

    final rawCandidate = _extractDescriptionCandidateWindow(normalized);
    debugPrint('[VoiceListing] raw_description_candidate=$rawCandidate');

    var desc = rawCandidate;
    desc = desc.replaceAll(RegExp(r'\b\d+(?:[.,]\d+)?\b'), ' ');
    desc = desc.replaceAll(
      RegExp(
        r'\b(kilo|kg|kilogram|mann|man|maund|litre|liter|ltr|peti|crate)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    desc = desc.replaceAll(
      RegExp(r'\b(rupay|rupee|rupees|rs\.?|pkr|روپے)\b', caseSensitive: false),
      ' ',
    );

    final numericFragments = <String>{
      quantity.trim(),
      quantity.replaceAll(RegExp(r'\s+'), ''),
      price.trim(),
      price.replaceAll(RegExp(r'\s+'), ''),
      ...quantity.split(RegExp(r'\s+')),
      ...price.split(RegExp(r'\s+')),
    }..removeWhere((value) => value.trim().isEmpty);
    for (final fragment in numericFragments) {
      desc = desc.replaceAll(
        RegExp(
          r'\b' + RegExp.escape(fragment.trim()) + r'\b',
          caseSensitive: false,
        ),
        ' ',
      );
    }

    final stripTerms = <String>{
      unit.trim(),
      category.trim(),
      ..._splitBilingual(category),
      subcategory.trim(),
      ..._splitBilingual(subcategory),
      province.trim(),
      district.trim(),
      tehsil.trim(),
      localArea.trim(),
      ..._voiceLocationAliases[province] ?? const <String>[],
      ..._voiceLocationAliases[district] ?? const <String>[],
      ..._voiceLocationAliases[tehsil] ?? const <String>[],
      ..._voiceLocationAliases[localArea] ?? const <String>[],
      ..._allLocationTermsForDescription(),
      ..._allCategoryTermsForDescription(),
    }..removeWhere((term) => term.trim().isEmpty);

    desc = _stripDescriptionTerms(desc, stripTerms);
    desc = _compactDescription(desc);

    final finalSafetyTerms = <String>{
      province,
      district,
      tehsil,
      localArea,
      category,
      subcategory,
      ..._allLocationTermsForDescription(),
      ..._allCategoryTermsForDescription(),
    }..removeWhere((term) => term.trim().isEmpty);
    final cleaned = _finalDescriptionSafetyPass(desc, finalSafetyTerms);

    debugPrint('[VoiceListing] cleaned_description_final=$cleaned');
    debugPrint('[VoiceListing] description_length=${cleaned.length}');

    return cleaned;
  }

  List<String> _districtOptionsForProvince(String province) {
    final p = province.trim();
    if (p.isEmpty) return const <String>[];
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      final match = _locationAssetProvinces.where(
        (e) => e.nameEn.toLowerCase() == p.toLowerCase(),
      );
      if (match.isNotEmpty) {
        return match.first.districts
            .map((e) => e.nameEn)
            .toList(growable: false);
      }
    }
    return PakistanLocationHierarchy.districtsForProvince(p);
  }

  List<String> _tehsilOptionsForDistrict(String district) {
    final d = district.trim();
    if (d.isEmpty) return const <String>[];
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final districtNode in province.districts) {
          if (districtNode.nameEn.toLowerCase() == d.toLowerCase()) {
            return districtNode.tehsils
                .map((e) => e.nameEn)
                .toList(growable: false);
          }
        }
      }
    }
    return PakistanLocationHierarchy.tehsilsForDistrict(d);
  }

  /// Returns the province name for a given district, searching loaded asset
  /// first, then AppConstants.pakistanLocations.
  String? _findProvinceForDistrict(String district) {
    final dLower = district.trim().toLowerCase();
    if (dLower.isEmpty) return null;

    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        for (final d in province.districts) {
          if (d.nameEn.toLowerCase() == dLower) return province.nameEn;
        }
      }
    }

    for (final entry in AppConstants.pakistanLocations.entries) {
      for (final d in entry.value) {
        if (d.toLowerCase() == dLower) return entry.key;
      }
    }
    return null;
  }

  /// Resolves a location token (city / district / province alias) to
  /// {province?, district?, tehsil?} using the app's existing location data.
  Map<String, String> _resolveVoiceLocation(String token) {
    final raw = token.trim();
    final lower = raw.toLowerCase();
    if (lower.isEmpty) return const {};
    final result = <String, String>{};

    // 1. Try loaded JSON asset (most complete data)
    if (_isLocationAssetReady && _locationAssetProvinces.isNotEmpty) {
      for (final province in _locationAssetProvinces) {
        if (_voiceTokenMatches(raw, province.nameEn) ||
            _voiceTokenContains(raw, province.nameEn) ||
            _voiceTokenMatches(raw, _locationOptionLabel(province.nameEn)) ||
            _voiceTokenContains(raw, _locationOptionLabel(province.nameEn))) {
          result['province'] = province.nameEn;
          return result;
        }
        for (final district in province.districts) {
          if (_voiceTokenMatches(raw, district.nameEn) ||
              _voiceTokenContains(raw, district.nameEn) ||
              _voiceTokenMatches(raw, _locationOptionLabel(district.nameEn)) ||
              _voiceTokenContains(raw, _locationOptionLabel(district.nameEn))) {
            result['province'] = province.nameEn;
            result['district'] = district.nameEn;
            return result;
          }
          for (final tehsil in district.tehsils) {
            if (_voiceTokenMatches(raw, tehsil.nameEn) ||
                _voiceTokenContains(raw, tehsil.nameEn) ||
                _voiceTokenMatches(raw, _locationOptionLabel(tehsil.nameEn)) ||
                _voiceTokenContains(raw, _locationOptionLabel(tehsil.nameEn))) {
              result['province'] = province.nameEn;
              result['district'] = district.nameEn;
              result['tehsil'] = tehsil.nameEn;
              return result;
            }
          }
        }
      }
    }

    // 2. Fall back to AppConstants + PakistanLocationHierarchy static data
    for (final entry in AppConstants.pakistanLocations.entries) {
      for (final district in entry.value) {
        if (_voiceTokenMatches(raw, district) ||
            _voiceTokenContains(raw, district) ||
            _voiceTokenMatches(raw, _locationOptionLabel(district)) ||
            _voiceTokenContains(raw, _locationOptionLabel(district))) {
          result['province'] = entry.key;
          result['district'] = district;
          // Try to get tehsils for this district
          final tehsils = PakistanLocationHierarchy.tehsilsForDistrict(
            district,
          );
          if (tehsils.length == 1) result['tehsil'] = tehsils.first;
          return result;
        }
        final tehsils = PakistanLocationHierarchy.tehsilsForDistrict(district);
        for (final tehsil in tehsils) {
          if (_voiceTokenMatches(raw, tehsil) ||
              _voiceTokenContains(raw, tehsil) ||
              _voiceTokenMatches(raw, _locationOptionLabel(tehsil)) ||
              _voiceTokenContains(raw, _locationOptionLabel(tehsil))) {
            result['province'] = entry.key;
            result['district'] = district;
            result['tehsil'] = tehsil;
            return result;
          }
        }
      }
    }

    // 3. Province alias matching
    const provinceAliasMap = <String, String>{
      'punjab': 'Punjab',
      'sindh': 'Sindh',
      'balochistan': 'Balochistan',
      'kpk': 'Khyber Pakhtunkhwa (KPK)',
      'kp': 'Khyber Pakhtunkhwa (KPK)',
      'khyber': 'Khyber Pakhtunkhwa (KPK)',
      'gilgit': 'Gilgit-Baltistan',
      'gb': 'Gilgit-Baltistan',
      'ajk': 'Azad Jammu & Kashmir (AJK)',
      'kashmir': 'Azad Jammu & Kashmir (AJK)',
    };
    if (provinceAliasMap.containsKey(lower)) {
      result['province'] = provinceAliasMap[lower]!;
    }

    return result;
  }

  Future<String?> _captureVoiceTranscriptFromMic() async {
    debugPrint('[VoiceListing] button_tapped');

    try {
      final ValueNotifier<String> transcriptNotifier = ValueNotifier<String>(
        '',
      );
      final List<String> finalChunks = <String>[];
      String currentPartial = '';
      bool stopRequested = false;

      String buildTranscript() {
        final parts = <String>[...finalChunks];
        final partial = currentPartial.trim();
        if (partial.isNotEmpty) {
          parts.add(partial);
        }
        return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      }

      Future<void> startListening({String? localeId}) async {
        try {
          await _speechToText.listen(
            localeId: localeId,
            listenFor: const Duration(seconds: 60),
            pauseFor: const Duration(seconds: 5),
            listenOptions: stt.SpeechListenOptions(
              listenMode: stt.ListenMode.dictation,
              partialResults: true,
              cancelOnError: false,
            ),
            onResult: (result) {
              final words = result.recognizedWords.trim();
              currentPartial = words;
              if (result.finalResult && words.isNotEmpty) {
                if (finalChunks.isEmpty || finalChunks.last != words) {
                  finalChunks.add(words);
                }
                currentPartial = '';
              }
              transcriptNotifier.value = buildTranscript();
            },
          );
        } catch (e) {
          debugPrint('[VoiceListing] ERROR stage=listen_start message=$e');
          if (localeId != null) {
            await startListening();
          }
        }
      }

      final ready = await _speechToText.initialize(
        onError: (error) {
          debugPrint(
            '[VoiceListing] ERROR stage=speech_initialize message=${error.errorMsg}',
          );
        },
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            debugPrint('[VoiceListing] recording_finished');
            if (!stopRequested && _isVoiceListening) {
              unawaited(startListening(localeId: 'ur_PK'));
            }
          }
        },
      );

      if (!ready) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Microphone permission ya speech service unavailable. Manual form use karein.',
              ),
            ),
          );
        }
        transcriptNotifier.dispose();
        return null;
      }

      setState(() {
        _isVoiceListening = true;
      });
      debugPrint('[VoiceListing] recording_started');
      await startListening(localeId: 'ur_PK');

      if (!mounted) {
        await _speechToText.stop();
        transcriptNotifier.dispose();
        return null;
      }

      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: _darkGreenMid,
            title: const Text(
              'Sunte Hain... / سن رہے ہیں...',
              style: TextStyle(color: AppColors.primaryText),
            ),
            content: ValueListenableBuilder<String>(
              valueListenable: transcriptNotifier,
              builder: (context, value, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Boliye, phir Stop dabayein.\nبولیے، پھر اسٹاپ دبائیں۔',
                      style: TextStyle(
                        color: AppColors.primaryText.withValues(alpha: 0.86),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primaryText.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primaryText.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        value.trim().isEmpty ? '...' : value,
                        style: const TextStyle(color: AppColors.primaryText),
                      ),
                    ),
                  ],
                );
              },
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop('manual'),
                child: const Text(
                  'Manual Edit',
                  style: TextStyle(color: AppColors.primaryText),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(dialogContext).pop('stop'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: AppColors.ctaTextDark,
                ),
                child: const Text('Stop'),
              ),
            ],
          );
        },
      );

      stopRequested = true;
      final pending = currentPartial.trim();
      if (pending.isNotEmpty) {
        if (finalChunks.isEmpty || finalChunks.last != pending) {
          finalChunks.add(pending);
        }
      }
      await _speechToText.stop();
      final transcript = buildTranscript();
      transcriptNotifier.dispose();
      debugPrint('[VOICE] transcript_final=$transcript');
      debugPrint('[VOICE] FINAL TRANSCRIPT = $transcript');

      if (mounted) {
        setState(() {
          _isVoiceListening = false;
        });
      }

      if (action != 'stop') {
        debugPrint('[VoiceListing] manual_edit_selected');
        return null;
      }

      if (transcript.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Transcript empty. Please speak clearly and try again.',
            ),
          ),
        );
        return null;
      }
      return transcript;
    } catch (e) {
      debugPrint('[VoiceListing] ERROR stage=speech_flow message=$e');
      if (mounted) {
        setState(() {
          _isVoiceListening = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voice recording fail hui. Manual form abhi bhi available hai.',
            ),
          ),
        );
      }
      return null;
    }
  }

  _VoiceApplyPlan _buildVoiceApplyPlan(
    GeminiVoiceDraft draft, {
    String transcript = '',
  }) {
    final normalizedTranscript = _normalizeVoiceToken(transcript);
    debugPrint('[VoiceListing] normalized_transcript=$normalizedTranscript');

    final applied = <String, dynamic>{};
    final suggestions = <String, String>{};
    final recognized = <String, String>{
      if (draft.category.trim().isNotEmpty) 'category': draft.category.trim(),
      if (draft.subcategory.trim().isNotEmpty)
        'subcategory': draft.subcategory.trim(),
      if (draft.quantity.trim().isNotEmpty) 'quantity': draft.quantity.trim(),
      if (draft.unit.trim().isNotEmpty) 'unit': draft.unit.trim(),
      if (draft.price.trim().isNotEmpty) 'price': draft.price.trim(),
      if (draft.province.trim().isNotEmpty) 'province': draft.province.trim(),
      if (draft.district.trim().isNotEmpty) 'district': draft.district.trim(),
      if (draft.tehsil.trim().isNotEmpty) 'tehsil': draft.tehsil.trim(),
      if (draft.localArea.trim().isNotEmpty)
        'localArea': draft.localArea.trim(),
      if (draft.description.trim().isNotEmpty)
        'description': draft.description.trim(),
    };

    final detectedSaleType = _detectSaleTypeFromVoice(transcript);
    if ((detectedSaleType ?? '').isNotEmpty) {
      applied['saleType'] = detectedSaleType;
      recognized['saleType'] = detectedSaleType == 'fixed'
          ? 'Fixed Price / سیدھی قیمت'
          : 'Auction / بولی';
      debugPrint('[VoiceListing] matched_sale_type=$detectedSaleType');
    }

    // ── CATEGORY: try Gemini/fallback output first, then taxonomy transcript match ─────
    var category = _safeMatchCategory(draft.category);

    final taxonomyMatch = transcript.trim().isEmpty
        ? (
            category: null as MarketCategoryOption?,
            subcategory: null as String?,
          )
        : _findTaxonomyMatchFromTranscript(transcript);

    if (category == null && taxonomyMatch.category != null) {
      category = taxonomyMatch.category;
    }
    if (category != null) {
      applied['category'] = category;
      debugPrint(
        '[VoiceListing] matched_category=${category.id}|${category.bilingualLabel}',
      );
    } else if (draft.category.trim().isNotEmpty) {
      suggestions['category'] = draft.category.trim();
      debugPrint('[VoiceListing] skipped_field=category reason=no_exact_match');
      debugPrint('[VoiceListing] matched_category=none');
    } else {
      debugPrint('[VoiceListing] matched_category=none');
    }

    // ── SUBCATEGORY: use Gemini/fallback label, then keyword scan ─────────
    final targetCategoryId =
        (applied['category'] as MarketCategoryOption?)?.id ??
        _selectedCategoryOptionId;
    var subcategoryMatch = _safeMatchOption(
      draft.subcategory,
      CategoryConstants.itemsForCategoryId(targetCategoryId),
    );
    if (subcategoryMatch == null && taxonomyMatch.subcategory != null) {
      subcategoryMatch = _safeMatchOption(
        taxonomyMatch.subcategory!,
        CategoryConstants.itemsForCategoryId(targetCategoryId),
      );
    }
    if (subcategoryMatch != null) {
      applied['subcategory'] = subcategoryMatch;
      debugPrint('[VoiceListing] matched_subcategory=$subcategoryMatch');
    } else if (draft.subcategory.trim().isNotEmpty) {
      suggestions['subcategory'] = draft.subcategory.trim();
      debugPrint(
        '[VoiceListing] skipped_field=subcategory reason=no_exact_match',
      );
      debugPrint('[VoiceListing] matched_subcategory=none');
    } else {
      debugPrint('[VoiceListing] matched_subcategory=none');
    }

    final parsedQty = GeminiVoiceHelper.parsePositiveNumber(draft.quantity);
    if (parsedQty != null) {
      applied['quantity'] = _formatDecimalForField(parsedQty);
    } else if (draft.quantity.trim().isNotEmpty) {
      suggestions['quantity'] = draft.quantity.trim();
      debugPrint(
        '[VoiceListing] skipped_field=quantity reason=invalid_numeric',
      );
    }

    String? mergedPriceTokens;
    if (transcript.trim().isEmpty) {
      debugPrint('[VoiceListing] merged_price_tokens=none');
    } else {
      mergedPriceTokens = GeminiVoiceHelper.extractMergedPriceTokens(
        transcript,
      );
    }
    final parsedPrice = GeminiVoiceHelper.parsePositiveNumber(
      (mergedPriceTokens ?? '').trim().isNotEmpty
          ? mergedPriceTokens!
          : draft.price,
    );
    debugPrint(
      '[VoiceListing] parsed_price=${parsedPrice != null ? _formatDecimalForField(parsedPrice) : 'none'}',
    );
    if (parsedPrice != null) {
      applied['price'] = _formatDecimalForField(parsedPrice);
    } else if (draft.price.trim().isNotEmpty) {
      suggestions['price'] = draft.price.trim();
      debugPrint('[VoiceListing] skipped_field=price reason=invalid_numeric');
    }

    final categoryForUnit =
        (applied['category'] as MarketCategoryOption?)?.id ??
        _selectedCategoryOptionId;
    final mandiForUnit =
        (applied['category'] as MarketCategoryOption?)?.mandiType ??
        _selectedMandiType;
    final subcategoryForUnit =
        (applied['subcategory'] as String?) ?? _selectedProduct;
    final allowedUnits = MandiUnitMapper.resolve(
      categoryId: categoryForUnit,
      fallbackType: mandiForUnit,
      subcategoryLabel: subcategoryForUnit,
    ).allowedUnits;
    final matchedUnit = _safeMatchUnit(draft.unit, allowedUnits);
    if (matchedUnit != null) {
      applied['unit'] = matchedUnit;
    } else if (draft.unit.trim().isNotEmpty) {
      suggestions['unit'] = draft.unit.trim();
      debugPrint('[VoiceListing] skipped_field=unit reason=no_exact_match');
    }

    // ── PROVINCE: try draft value, then smart location from transcript ────
    final resolvedLocation = _resolveTranscriptLocation(
      transcript: transcript,
      draft: draft,
    );
    final provinceMatch = resolvedLocation['province'];
    if (provinceMatch != null) {
      applied['province'] = provinceMatch;
      debugPrint('[VoiceListing] matched_province=$provinceMatch');
    } else if (draft.province.trim().isNotEmpty) {
      suggestions['province'] = draft.province.trim();
      debugPrint('[VoiceListing] skipped_field=province reason=no_exact_match');
      debugPrint('[VoiceListing] matched_province=none');
    } else {
      debugPrint('[VoiceListing] matched_province=none');
    }

    // ── DISTRICT ─────────────────────────────────────────────────────────
    // Prefer smart district resolved from transcript if available
    final districtInput = resolvedLocation['district'] ?? draft.district.trim();
    final districtMatch = (districtInput).trim().isEmpty ? null : districtInput;
    if (districtMatch != null) {
      applied['district'] = districtMatch;
      final inferredProvince = _findProvinceForDistrict(districtMatch);
      if ((applied['province'] as String? ?? '').isEmpty &&
          (inferredProvince ?? '').trim().isNotEmpty) {
        applied['province'] = inferredProvince!.trim();
        debugPrint(
          '[VoiceListing] matched_province=${inferredProvince.trim()}',
        );
      }
      debugPrint('[VoiceListing] matched_district=$districtMatch');
    } else if (districtInput.isNotEmpty) {
      suggestions['district'] = districtInput;
      debugPrint('[VoiceListing] skipped_field=district reason=no_exact_match');
      debugPrint('[VoiceListing] matched_district=none');
    } else {
      debugPrint('[VoiceListing] matched_district=none');
    }

    // ── TEHSIL ────────────────────────────────────────────────────────────
    final tehsilInput = resolvedLocation['tehsil'] ?? draft.tehsil.trim();
    final tehsilMatch = tehsilInput.trim().isEmpty ? null : tehsilInput;
    if (tehsilMatch != null) {
      applied['tehsil'] = tehsilMatch;
      debugPrint('[VoiceListing] matched_tehsil=$tehsilMatch');
    } else if (tehsilInput.isNotEmpty) {
      suggestions['tehsil'] = tehsilInput;
      debugPrint('[VoiceListing] skipped_field=tehsil reason=no_exact_match');
      debugPrint('[VoiceListing] matched_tehsil=none');
    } else {
      debugPrint('[VoiceListing] matched_tehsil=none');
    }

    // ── LOCAL AREA ────────────────────────────────────────────────────────
    // If localArea is a district name, it was already set above as district;
    // still keep a friendly localArea text for display.
    final localAreaMatch = resolvedLocation['localArea'];
    if ((localAreaMatch ?? '').trim().isNotEmpty) {
      applied['localArea'] = localAreaMatch!.trim();
      debugPrint('[VoiceListing] matched_local_area=${localAreaMatch.trim()}');
    } else if (draft.localArea.trim().isNotEmpty) {
      applied['localArea'] = draft.localArea.trim();
      debugPrint('[VoiceListing] matched_local_area=${draft.localArea.trim()}');
    } else if ((applied['district'] as String? ?? '').isNotEmpty) {
      applied['localArea'] = applied['district'] as String;
      debugPrint('[VoiceListing] matched_local_area=${applied['district']}');
    } else {
      debugPrint('[VoiceListing] matched_local_area=none');
    }

    final cleanedDescription = _cleanVoiceDescription(
      source: draft.description.trim().isNotEmpty
          ? draft.description.trim()
          : transcript.trim(),
      quantity: (applied['quantity'] ?? draft.quantity).toString(),
      unit: (applied['unit'] as UnitType?)?.wireValue ?? draft.unit,
      price: (applied['price'] ?? draft.price).toString(),
      category:
          (applied['category'] as MarketCategoryOption?)?.bilingualLabel ??
          draft.category,
      subcategory: (applied['subcategory'] ?? draft.subcategory).toString(),
      province: (applied['province'] ?? draft.province).toString(),
      district: (applied['district'] ?? draft.district).toString(),
      tehsil: (applied['tehsil'] ?? draft.tehsil).toString(),
      localArea: (applied['localArea'] ?? draft.localArea).toString(),
    );
    debugPrint('[VoiceListing] cleaned_description=$cleanedDescription');
    if (cleanedDescription.isNotEmpty) {
      applied['description'] = cleanedDescription;
    }

    // ── POPULATE recognized map with all resolved fields ─────────────────
    if ((applied['category'] as MarketCategoryOption?) != null) {
      final cat = applied['category'] as MarketCategoryOption;
      recognized['category'] = cat.bilingualLabel;
    }
    if ((applied['subcategory'] as String? ?? '').isNotEmpty) {
      recognized['subcategory'] = applied['subcategory'] as String;
    }
    if ((applied['province'] as String? ?? '').isNotEmpty) {
      recognized['province'] = applied['province'] as String;
    }
    if ((applied['district'] as String? ?? '').isNotEmpty) {
      recognized['district'] = applied['district'] as String;
    }
    if ((applied['tehsil'] as String? ?? '').isNotEmpty) {
      recognized['tehsil'] = applied['tehsil'] as String;
    }

    return _VoiceApplyPlan(
      applied: applied,
      suggestions: suggestions,
      recognized: recognized,
    );
  }

  /// Extracts candidate location tokens (1–3 words each) from a transcript
  /// for reverse lookup against the location database.
  List<String> _extractLocationTokens(String transcript) {
    final words = transcript
        .replaceAll(RegExp(r'[,.،]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final tokens = <String>{};
    for (var i = 0; i < words.length; i++) {
      tokens.add(words[i]);
      if (i + 1 < words.length) tokens.add('${words[i]} ${words[i + 1]}');
      if (i + 2 < words.length) {
        tokens.add('${words[i]} ${words[i + 1]} ${words[i + 2]}');
      }
    }
    return tokens.toList();
  }

  Future<String?> _showVoiceApplyDialog({required _VoiceApplyPlan plan}) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _darkGreenMid,
          title: const Text(
            'Yeh details samjhi gayi hain / یہ تفصیلات سمجھی گئی ہیں',
            style: TextStyle(color: AppColors.primaryText),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                // ── Guided summary ─────────────────────────────────────
                _buildVoiceGuidanceText(plan),
                const SizedBox(height: 6),
                if (plan.recognized.isEmpty)
                  Text(
                    'Koi detail samajh nahi aayi. Dobara bolen ya manual edit karein.',
                    style: TextStyle(
                      color: AppColors.primaryText.withValues(alpha: 0.9),
                    ),
                  )
                else
                  ...plan.recognized.entries.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_fieldLabel(row.key)}: ${row.value}',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ),
                if (plan.suggestions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    'Yeh fields baaki hain / These need manual input:',
                    style: TextStyle(
                      color: AppColors.primaryText.withValues(alpha: 0.82),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: plan.suggestions.entries
                        .map(
                          (entry) => Chip(
                            backgroundColor: AppColors.primaryText.withValues(
                              alpha: 0.08,
                            ),
                            side: BorderSide(
                              color: AppColors.primaryText.withValues(
                                alpha: 0.22,
                              ),
                            ),
                            label: Text(
                              '${entry.key}: ${entry.value}',
                              style: const TextStyle(
                                color: AppColors.primaryText,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('retry'),
              child: const Text(
                'Dobara Bolen',
                style: TextStyle(color: AppColors.primaryText),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('manual'),
              child: const Text(
                'Khud Edit Karun',
                style: TextStyle(color: AppColors.primaryText),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop('apply'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: AppColors.ctaTextDark,
              ),
              child: const Text('Haan (Apply)'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runVoiceAssist() async {
    if (_isSubmitting || _isVoiceAssistLoading) return;

    final transcript = await _captureVoiceTranscriptFromMic();
    if (!mounted) return;
    if (transcript == null || transcript.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transcript empty. Dobara bolen.')),
      );
      return;
    }

    setState(() {
      _isVoiceAssistLoading = true;
    });

    try {
      GeminiVoiceDraft draft;
      try {
        debugPrint('[VOICE] gemini_started');
        draft = await GeminiVoiceHelper.extractDraft(
          ai: _intelligenceService,
          transcript: transcript,
        );
        debugPrint('[VOICE] gemini_response=${draft.rawResponse}');
        if (draft.usedFallback) {
          debugPrint('[VOICE] fallback_success');
        }
      } catch (e) {
        debugPrint('[VOICE] gemini_failed=$e');
        debugPrint('[VoiceListing] ERROR stage=gemini_extract message=$e');
        rethrow;
      }

      debugPrint('[VoiceListing] apply_started');
      final plan = _buildVoiceApplyPlan(draft, transcript: transcript);

      if (!mounted) return;
      final action = await _showVoiceApplyDialog(plan: plan);

      if (!mounted) return;
      if (action == 'retry') {
        debugPrint('[VoiceListing] retry_selected');
        setState(() {
          _isVoiceAssistLoading = false;
        });
        await _runVoiceAssist();
        return;
      }

      if (action == 'apply') {
        var changed = false;

        final matchedCategory =
            plan.applied['category'] as MarketCategoryOption?;
        final matchedSubcategory = plan.applied['subcategory'] as String?;
        final matchedUnit = plan.applied['unit'] as UnitType?;
        final matchedSaleType = plan.applied['saleType'] as String?;

        setState(() {
          if (matchedCategory != null) {
            _selectedCategoryOptionId = matchedCategory.id;
            _selectedMandiType = matchedCategory.mandiType;
            _selectedProduct = null;
            _selectedRiceVariety = null;
            _selectedUnitType = MandiUnitMapper.resolve(
              categoryId: matchedCategory.id,
              fallbackType: matchedCategory.mandiType,
              subcategoryLabel: null,
            ).defaultUnit;
            changed = true;
            debugPrint('[VoiceListing] applied_field=category');
          }

          if ((matchedSubcategory ?? '').trim().isNotEmpty) {
            _selectedProduct = matchedSubcategory;
            if (!_isRiceCropSelected && !_isProcessedRiceSelected) {
              _selectedRiceVariety = null;
            }
            if (matchedUnit == null) {
              _selectedUnitType = MandiUnitMapper.resolve(
                categoryId: _selectedCategoryOptionId,
                fallbackType: _selectedMandiType,
                subcategoryLabel: matchedSubcategory,
              ).defaultUnit;
            }
            changed = true;
            debugPrint('[VoiceListing] applied_field=subcategory');
          }

          if (matchedUnit != null) {
            _selectedUnitType = matchedUnit;
            changed = true;
            debugPrint('[VoiceListing] applied_field=unit');
          }

          if (matchedSaleType == 'auction' || matchedSaleType == 'fixed') {
            _selectedSaleType = matchedSaleType!;
            changed = true;
            debugPrint(
              '[VoiceListing] applied_field=saleType value=$matchedSaleType',
            );
          }

          if ((plan.applied['province'] ?? '').toString().trim().isNotEmpty) {
            _selectedProvince = plan.applied['province'] as String;
            _selectedDistrict = null;
            _selectedTehsil = null;
            _selectedCity = null;
            _cityController.clear();
            changed = true;
            debugPrint('[VoiceListing] applied_field=province');
          }

          if ((plan.applied['district'] ?? '').toString().trim().isNotEmpty) {
            _selectedDistrict = plan.applied['district'] as String;
            _districtAutocompleteController.text = _selectedDistrict!;
            _selectedTehsil = null;
            _selectedCity = null;
            _cityController.clear();
            changed = true;
            debugPrint('[VoiceListing] applied_field=district');
          }

          if ((plan.applied['tehsil'] ?? '').toString().trim().isNotEmpty) {
            _selectedTehsil = plan.applied['tehsil'] as String;
            _selectedCity = null;
            _cityController.clear();
            changed = true;
            debugPrint('[VoiceListing] applied_field=tehsil');
          }

          if ((plan.applied['quantity'] ?? '').toString().trim().isNotEmpty) {
            _quantityController.text = (plan.applied['quantity'] as String)
                .trim();
            changed = true;
            debugPrint('[VoiceListing] applied_field=quantity');
            debugPrint(
              '[VOICE] field_applied_quantity=${_quantityController.text.trim()}',
            );
          }

          if ((plan.applied['price'] ?? '').toString().trim().isNotEmpty) {
            _priceController.text = (plan.applied['price'] as String).trim();
            changed = true;
            debugPrint('[VoiceListing] applied_field=price');
            debugPrint(
              '[VOICE] field_applied_price=${_priceController.text.trim()}',
            );
          }

          if ((plan.applied['localArea'] ?? '').toString().trim().isNotEmpty) {
            final mergedVillage = (plan.applied['localArea'] as String).trim();
            _localAreaController.text = mergedVillage;
            _villageController.text = mergedVillage;
            changed = true;
            debugPrint('[VoiceListing] applied_field=localArea');
          }

          if ((plan.applied['description'] ?? '')
              .toString()
              .trim()
              .isNotEmpty) {
            _descriptionController.text =
                (plan.applied['description'] as String).trim();
            changed = true;
            debugPrint('[VoiceListing] applied_field=description');
          }

          _fraudPrecheck = _runFraudPrecheck();
          _voiceAssistSuggestions = plan.suggestions;
        });

        if (changed) {
          unawaited(_refreshMarketIntelligence());
          debugPrint('[VoiceListing] confirm_applied');
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Voice details applied safely. Unmatched fields remain for manual review.',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'No safe fields recognized. Manual edit karein ya dobara bolen.',
              ),
            ),
          );
        }
      } else {
        debugPrint('[VoiceListing] manual_edit_selected');
        setState(() {
          _voiceAssistSuggestions = plan.suggestions;
        });
      }
    } catch (e) {
      debugPrint('[VoiceListing] ERROR stage=voice_assist_final message=$e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gemini unavailable. Please try again. Error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isVoiceAssistLoading = false;
        });
      }
    }
  }

  /// Builds guided text shown on the confirmation dialog explaining what
  /// was understood and what's still missing.
  Widget _buildVoiceGuidanceText(_VoiceApplyPlan plan) {
    final lines = <String>[];
    final applied = plan.applied;

    // What was understood
    final catOption = applied['category'] as MarketCategoryOption?;
    if (catOption != null) {
      lines.add('✅ Category samjhi gayi: ${catOption.bilingualLabel}');
    }
    final sub = (applied['subcategory'] as String? ?? '').trim();
    if (sub.isNotEmpty) lines.add('✅ Cheez samjhi gayi: $sub');
    if ((applied['quantity'] as String? ?? '').isNotEmpty &&
        (applied['price'] as String? ?? '').isNotEmpty) {
      lines.add('✅ Miqdar / Qeemat samjhi gayi');
    } else if ((applied['quantity'] as String? ?? '').isNotEmpty) {
      lines.add('✅ Miqdar samjhi gayi');
    } else if ((applied['price'] as String? ?? '').isNotEmpty) {
      lines.add('✅ Qeemat samjhi gayi');
    }
    final province = (applied['province'] as String? ?? '').trim();
    final district = (applied['district'] as String? ?? '').trim();
    final tehsil = (applied['tehsil'] as String? ?? '').trim();
    if (province.isNotEmpty || district.isNotEmpty) {
      final loc = [
        if (district.isNotEmpty) district,
        if (province.isNotEmpty) province,
      ].join(', ');
      lines.add('✅ Jagah samjhi gayi: $loc');
    }

    // What's still needed (critical gaps)
    if (catOption == null) {
      lines.add('⚠️ Category nahi samji – dobara bolen ya khud chunain');
    }
    if ((applied['quantity'] as String? ?? '').isEmpty) {
      lines.add('⚠️ Miqdar nahi mili – jaise "50 mann"');
    }
    if ((applied['price'] as String? ?? '').isEmpty) {
      lines.add('⚠️ Qeemat nahi mili – jaise "3600 rupay"');
    }
    if (province.isEmpty && district.isEmpty) {
      lines.add('⚠️ Jagah nahi mili – shahir ya zila batayen');
    } else if (province.isNotEmpty && district.isNotEmpty && tehsil.isEmpty) {
      lines.add('ℹ️ Tehsil optional hai – baad mein bhar saktay hain');
    }

    final saleType = (applied['saleType'] as String? ?? '').trim();
    if (saleType == 'fixed') {
      lines.add('✅ Sale type: Fixed Price / سیدھی قیمت');
    } else if (saleType == 'auction') {
      lines.add('✅ Sale type: Auction / بولی');
    }

    if (lines.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        ...lines.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              l,
              style: TextStyle(
                color: l.startsWith('✅')
                    ? const Color(0xFF8FCA74)
                    : AppColors.primaryText.withValues(alpha: 0.85),
                fontSize: 12.5,
              ),
            ),
          ),
        ),
        const Divider(color: Colors.white24, height: 14),
      ],
    );
  }

  /// Human-readable field label for the confirmation dialog.
  String _fieldLabel(String key) {
    switch (key) {
      case 'category':
        return 'Category';
      case 'subcategory':
        return 'Cheez / Item';
      case 'quantity':
        return 'Miqdar';
      case 'unit':
        return 'Unit';
      case 'price':
        return 'Qeemat (Rs)';
      case 'province':
        return 'Suba';
      case 'district':
        return 'Zila';
      case 'tehsil':
        return 'Tehsil';
      case 'localArea':
        return 'Illaqa';
      case 'description':
        return 'Tafseelaat';
      case 'saleType':
        return 'Sale Type / فروخت کی قسم';
      default:
        return key;
    }
  }

  Widget _buildVoiceAssistCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_isVoiceListening) ...<Widget>[
            const _VoiceListeningPulse(),
            const SizedBox(height: 10),
          ],
          ElevatedButton.icon(
            onPressed:
                (_isSubmitting || _isVoiceAssistLoading || _isVoiceListening)
                ? null
                : _runVoiceAssist,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: AppColors.ctaTextDark,
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: _isVoiceAssistLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.mic_none_rounded),
            label: const Text(
              '🎤 Bol Ke Listing Banao',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (_isVoiceAssistLoading) ...<Widget>[
            const SizedBox(height: 8),
            const _VoiceProcessingShimmer(),
          ],
          const SizedBox(height: 6),
          Text(
            'Bolain, hum details samajh kar form bhar denge',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.78),
              fontSize: 12,
            ),
          ),
          if (_voiceAssistSuggestions.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _voiceAssistSuggestions.entries
                  .map(
                    (entry) => Chip(
                      backgroundColor: AppColors.primaryText.withValues(
                        alpha: 0.08,
                      ),
                      side: BorderSide(
                        color: AppColors.primaryText.withValues(alpha: 0.2),
                      ),
                      label: Text(
                        '${entry.key}: ${entry.value}',
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _loadPakistanLocationsAsset() async {
    try {
      final rawJson = await rootBundle.loadString(
        'assets/data/pakistan_locations.json',
      );
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return;

      final provincesRaw = decoded['provinces'];
      if (provincesRaw is! List) return;

      final provinces = <_ProvinceNode>[];
      final provinceUrdu = <String, String>{};
      final districtUrdu = <String, String>{};
      final tehsilUrdu = <String, String>{};
      final cityUrdu = <String, String>{};

      for (final provinceItem in provincesRaw) {
        if (provinceItem is! Map) continue;

        final provinceMap = provinceItem.cast<String, dynamic>();
        final provinceEn = (provinceMap['name_en'] ?? '').toString().trim();
        if (provinceEn.isEmpty) continue;

        final provinceUr = (provinceMap['name_ur'] ?? '').toString().trim();
        provinceUrdu[provinceEn] = provinceUr;

        final districtsRaw = provinceMap['districts'];
        final districts = <_DistrictNode>[];

        if (districtsRaw is List) {
          for (final districtItem in districtsRaw) {
            if (districtItem is! Map) continue;
            final districtMap = districtItem.cast<String, dynamic>();
            final districtEn = (districtMap['name_en'] ?? '').toString().trim();
            if (districtEn.isEmpty) continue;

            final districtUr = (districtMap['name_ur'] ?? '').toString().trim();
            districtUrdu[districtEn] = districtUr;

            final tehsilsRaw = districtMap['tehsils'];
            final tehsils = <_TehsilNode>[];

            if (tehsilsRaw is List) {
              for (final tehsilItem in tehsilsRaw) {
                if (tehsilItem is! Map) continue;
                final tehsilMap = tehsilItem.cast<String, dynamic>();
                final tehsilEn = (tehsilMap['name_en'] ?? '').toString().trim();
                if (tehsilEn.isEmpty) continue;

                final tehsilUr = (tehsilMap['name_ur'] ?? '').toString().trim();
                tehsilUrdu[tehsilEn] = tehsilUr;

                final cities = <_LocationLeaf>[];
                final citiesRaw = tehsilMap['cities'];
                if (citiesRaw is List) {
                  for (final cityItem in citiesRaw) {
                    if (cityItem is! Map) continue;
                    final cityMap = cityItem.cast<String, dynamic>();
                    final cityEn = (cityMap['name_en'] ?? '').toString().trim();
                    if (cityEn.isEmpty) continue;
                    final cityUr = (cityMap['name_ur'] ?? '').toString().trim();
                    cityUrdu[cityEn] = cityUr;
                    cities.add(
                      _LocationLeaf(
                        id: (cityMap['id'] ?? cityEn)
                            .toString()
                            .trim()
                            .toLowerCase(),
                        nameEn: cityEn,
                        nameUr: cityUr,
                      ),
                    );
                  }
                }

                tehsils.add(
                  _TehsilNode(
                    id: (tehsilMap['id'] ?? tehsilEn)
                        .toString()
                        .trim()
                        .toLowerCase(),
                    nameEn: tehsilEn,
                    nameUr: tehsilUr,
                    cities: cities,
                  ),
                );
              }
            }

            districts.add(
              _DistrictNode(
                id: (districtMap['id'] ?? districtEn)
                    .toString()
                    .trim()
                    .toLowerCase(),
                nameEn: districtEn,
                nameUr: districtUr,
                tehsils: tehsils,
              ),
            );
          }
        }

        provinces.add(
          _ProvinceNode(
            id: (provinceMap['id'] ?? provinceEn)
                .toString()
                .trim()
                .toLowerCase(),
            nameEn: provinceEn,
            nameUr: provinceUr,
            districts: districts,
          ),
        );
      }

      if (!mounted || provinces.isEmpty) return;
      setState(() {
        _locationAssetProvinces = provinces;
        _provinceUrduByEn
          ..clear()
          ..addAll(provinceUrdu);
        _districtUrduByEn
          ..clear()
          ..addAll(districtUrdu);
        _tehsilUrduByEn
          ..clear()
          ..addAll(tehsilUrdu);
        _cityUrduByEn
          ..clear()
          ..addAll(cityUrdu);
        _isLocationAssetReady = true;
      });
    } catch (_) {
      // Keep existing constant-based hierarchy as fallback.
    }
  }

  String _locationOptionLabel(String option) {
    final trimmed = option.trim();
    if (trimmed.isEmpty) return option;

    final urdu =
        (_provinceUrduByEn[trimmed] ??
                _districtUrduByEn[trimmed] ??
                _tehsilUrduByEn[trimmed] ??
                _cityUrduByEn[trimmed] ??
                PakistanLocationHierarchy.urduLabelForLocation(trimmed))
            .trim();
    return LocationDisplayHelper.bilingualLabelFromParts(
      trimmed,
      candidateUrdu: urdu,
    );
  }

  String _resolveCityForPayload() {
    final typedCity = _cityController.text.trim();
    if (typedCity.isNotEmpty) {
      return typedCity;
    }
    return (_selectedCity ?? '').trim();
  }

  String _resolveTehsilForPayload(String resolvedCity) {
    final tehsil = (_selectedTehsil ?? '').trim();
    return tehsil;
  }

  String _resolveDistrictForPayload(String resolvedTehsil) {
    final district = (_selectedDistrict ?? '').trim();
    return district;
  }

  String _resolveProvinceForPayload(String resolvedDistrict) {
    final province = (_selectedProvince ?? '').trim();
    return province;
  }

  String _composeLocationEnglish({
    required String city,
    required String tehsil,
    required String district,
  }) {
    final parts = <String>[
      city.trim(),
      tehsil.trim(),
      district.trim(),
    ].where((e) => e.isNotEmpty).toList(growable: false);
    return parts.join(', ');
  }

  String _composeLocationUrdu({
    required String city,
    required String tehsil,
    required String district,
  }) {
    final parts = <String>[
      _locationUrduPart(city),
      _locationUrduPart(tehsil),
      _locationUrduPart(district),
    ].where((e) => e.isNotEmpty).toList(growable: false);
    return parts.join('، ');
  }

  String _locationUrduPart(String english) {
    final String en = english.trim();
    if (en.isEmpty) return '';
    return LocationDisplayHelper.resolvedUrduLabel(
      en,
      candidateUrdu:
          _provinceUrduByEn[en] ??
          _districtUrduByEn[en] ??
          _tehsilUrduByEn[en] ??
          _cityUrduByEn[en],
    );
  }

  FraudPrecheckResult _runFraudPrecheck() {
    var risk = 0;
    final flags = <String>[];

    final price = _numericPrice;
    final marketAvg = _marketAverage;
    if (marketAvg != null && marketAvg > 0 && price > 0) {
      final deviation = (price - marketAvg).abs() / marketAvg;
      if (deviation > 0.35) {
        risk += 35;
        flags.add('price_anomaly');
      }
    }

    final description = _descriptionController.text.trim().toLowerCase();
    if (description.length < 20) {
      risk += 15;
      flags.add('thin_description');
    }

    const blockedKeywords = <String>[
      'whatsapp',
      'call',
      '03',
      '+92',
      'link',
      'urgent',
      'cheap',
    ];
    if (blockedKeywords.any(description.contains)) {
      risk += 25;
      flags.add('external_contact');
    }

    final hasAudio = (_recordedAudioPath ?? '').trim().isNotEmpty;
    if (!_hasRequiredTrustPhoto && _images.isEmpty && !hasAudio) {
      risk += 10;
      flags.add('low_evidence');
    }

    final province = (_selectedProvince ?? '').trim();
    final district = (_selectedDistrict ?? '').trim();
    if (province.isNotEmpty && district.isNotEmpty) {
      final districtList = _isLocationAssetReady
          ? _districtOptions
          : (AppConstants.pakistanLocations[province] ?? const <String>[]);
      final match = districtList
          .map((e) => e.toLowerCase())
          .contains(district.toLowerCase());
      if (!match) {
        risk += 20;
        flags.add('location_mismatch');
      }
    }

    if (risk > 100) risk = 100;
    if (risk < 0) risk = 0;

    final status = risk <= 30
        ? 'Low Risk'
        : risk <= 60
        ? 'Medium Risk'
        : 'High Risk (Review)';

    return FraudPrecheckResult(riskScore: risk, flags: flags, status: status);
  }

  Future<Position?> _captureLocationForVideo() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      setState(() {
        _verificationInlineError =
            'Location required for trusted listing verification / معتبر لسٹنگ کی تصدیق کے لیے لوکیشن ضروری ہے';
      });
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _verificationInlineError =
            'Please enable GPS and allow location access / براہِ کرم GPS آن کریں اور لوکیشن اجازت دیں';
      });
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 8),
        ),
      );
    } catch (_) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) return lastKnown;
      setState(() {
        _verificationInlineError =
            'Could not read GPS location. Move outdoors and retry / GPS لوکیشن نہیں ملی، کھلی جگہ جا کر دوبارہ کوشش کریں';
      });
      return null;
    }
  }

  Future<void> _captureTrustPhoto() async {
    setState(() {
      _verificationInlineError = null;
    });

    final preflightLocation = await _captureLocationForVideo();
    if (preflightLocation == null) return;

    XFile? image;
    try {
      image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Please allow camera and location access / براہِ کرم کیمرہ اور لوکیشن اجازت دیں';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Unable to open camera. Please retry / کیمرہ نہیں کھل سکا، دوبارہ کوشش کریں';
      });
      return;
    }

    if (image == null) return;

    try {
      final file = File(image.path);
      final fileSize = await file.length();
      final position = await _captureLocationForVideo();
      if (position == null) return;
      if (!mounted) return;
      setState(() {
        _trustPhoto = image;
        _trustPhotoLat = position.latitude;
        _trustPhotoLng = position.longitude;
        _trustPhotoCapturedAt = DateTime.now().toUtc();
        _trustPhotoTag = image!.path.split(Platform.pathSeparator).last;
        _trustPhotoFileSize = fileSize;
        _verificationInlineError = null;
        _fraudPrecheck = _runFraudPrecheck();
        _logSubmitGateStatus('trust_photo_captured');
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Trust photo could not be captured. Please retry / ٹرسٹ تصویر محفوظ نہیں ہو سکی، دوبارہ کوشش کریں';
      });
    }
  }

  bool get _showVerificationRecoveryActions {
    final message = (_verificationInlineError ?? '').toLowerCase();
    return message.contains('gps') ||
        message.contains('location') ||
        message.contains('اجازت') ||
        message.contains('permission');
  }

  Future<void> _recordVerificationVideo() async {
    setState(() {
      _verificationInlineError = null;
    });

    final preflightLocation = await _captureLocationForVideo();
    if (preflightLocation == null) return;

    XFile? picked;
    try {
      picked = await _picker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(seconds: 15),
      );
    } on PlatformException catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Please allow camera and location access / براہِ کرم کیمرہ اور لوکیشن اجازت دیں';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Unable to open camera. Please retry / کیمرہ نہیں کھل سکا، دوبارہ کوشش کریں';
      });
      return;
    }

    if (picked == null) return;
    final pickedVideo = picked;

    final file = File(pickedVideo.path);
    final fileSize = await file.length();

    VideoPlayerController? nextController;
    try {
      nextController = VideoPlayerController.file(file);
      await nextController.initialize();
      final durationSeconds = nextController.value.duration.inSeconds;

      if (durationSeconds < 5 || durationSeconds > 15) {
        await nextController.dispose();
        if (!mounted) return;
        setState(() {
          _verificationInlineError =
              'Verification video must be 5-15 seconds / ویڈیو 5-15 سیکنڈ ہونی چاہیے';
          _video = null;
          _videoController = null;
          _videoDurationSeconds = null;
          _videoLat = null;
          _videoLng = null;
          _videoCapturedAt = null;
          _videoTag = null;
          _videoFileSize = null;
        });
        return;
      }

      final position = await _captureLocationForVideo();
      if (position == null) {
        await nextController.dispose();
        if (!mounted) return;
        setState(() {
          _verificationInlineError =
              'GPS must be enabled for verification / تصدیق کے لیے GPS آن ہونا ضروری ہے';
          _video = null;
          _videoController = null;
          _videoDurationSeconds = null;
          _videoLat = null;
          _videoLng = null;
          _videoCapturedAt = null;
          _videoTag = null;
          _videoFileSize = null;
        });
        return;
      }

      final old = _videoController;
      if (!mounted) {
        await nextController.dispose();
        return;
      }

      setState(() {
        _video = pickedVideo;
        _videoController = nextController;
        _videoDurationSeconds = durationSeconds;
        _videoLat = position.latitude;
        _videoLng = position.longitude;
        _videoCapturedAt = DateTime.now().toUtc();
        _videoTag = pickedVideo.path.split(Platform.pathSeparator).last;
        _videoFileSize = fileSize;
        _verificationInlineError = null;
      });
      await old?.dispose();
    } catch (_) {
      await nextController?.dispose();
      if (!mounted) return;
      setState(() {
        _verificationInlineError =
            'Unable to record verification video / تصدیقی ویڈیو ریکارڈ نہیں ہو سکی';
      });
    }
  }

  Future<void> _pickImage() async {
    if (_images.length >= 3) return;

    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image == null) return;

    if (!mounted) return;
    setState(() {
      _images = <XFile>[..._images, image].take(3).toList();
      _fraudPrecheck = _runFraudPrecheck();
    });
  }

  Future<void> _refreshMarketIntelligence() async {
    final product = (_selectedProduct ?? '').trim();
    if (product.isEmpty) return;

    setState(() {
      _isLoadingMarket = true;
    });

    final normalizedUnitType = MandiUnitMapper.normalizeUnitType(
      rawUnit: _selectedUnitType.wireValue,
      categoryId: _selectedCategoryOptionId,
      fallbackType: _selectedMandiType,
      subcategoryLabel: _selectedProduct,
    );

    try {
      final result = await _intelligenceService.fetchMandiAverageRateWithMeta(
        product,
        province: _selectedProvince,
        district: _selectedDistrict,
      );
      final sellerSuggestion = await _layer2Service.buildSellerPriceSuggestion(
        itemName: product,
        enteredPrice: _numericPrice,
        province: _selectedProvince,
        district: _selectedDistrict,
        quantity: _numericQuantity > 0 ? _numericQuantity : null,
        unit: normalizedUnitType.wireValue,
      );
      if (!mounted) return;
      setState(() {
        _marketAverage = result.rate;
        _recommendedPrice = sellerSuggestion.recommendedPrice > 0
            ? sellerSuggestion.recommendedPrice
            : null;
        _priceDeviationPercent = sellerSuggestion.marketAverage > 0
            ? sellerSuggestion.priceDeviationPercent
            : null;
        _sellerPriceInsight = sellerSuggestion.message;
        _isLoadingMarket = false;
        _fraudPrecheck = _runFraudPrecheck();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _marketAverage = null;
        _recommendedPrice = null;
        _priceDeviationPercent = null;
        _sellerPriceInsight = 'Price insight unavailable.';
        _isLoadingMarket = false;
        _fraudPrecheck = _runFraudPrecheck();
      });
    }
  }

  Future<void> _submitListing() async {
    debugPrint('[AddListingUI] submit_tap');
    if (_isSubmitting) {
      debugPrint('[AddListingUI] submit_blocked_already_submitting');
      return;
    }

    if (_approvalCheckInProgress) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Seller approval status is still loading / سیلر منظوری کی حالت ابھی لوڈ ہو رہی ہے',
          ),
        ),
      );
      return;
    }

    if (_approvalLocked) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_approvalLockMessage)));
      return;
    }

    FocusScope.of(context).unfocus();

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      debugPrint('[AddListingUI] form_validation_failed');
      return;
    }
    debugPrint('[AddListingUI] form_validation_pass');

    if ((_isRiceCropSelected || _isProcessedRiceSelected) &&
        (_selectedRiceVariety ?? '').trim().isEmpty) {
      debugPrint('[AddListingUI] variety_required');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Variety is required / قسم لازمی ہے')),
      );
      return;
    }

    if (!_hasRequiredTrustPhoto) {
      debugPrint('[AddListingUI] trust_photo_missing');
      setState(() {
        _verificationInlineError =
            'Capture trust photo with GPS before posting / پوسٹ کرنے سے پہلے GPS کے ساتھ ٹرسٹ تصویر لیں';
        _fraudPrecheck = _runFraudPrecheck();
      });
      return;
    }

    if (_hardFraudBlock) {
      debugPrint('[AddListingUI] hard_fraud_block');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'High risk listing blocked / ہائی رسک لسٹنگ بلاک ہوگئی۔ کم از کم 1 تصویر اور درست ویڈیو شامل کریں۔',
          ),
        ),
      );
      return;
    }

    await _logAuthSnapshot(
      'submit_tap',
      finalDecision: 'inspect',
      reason: 'submit_pressed',
    );
    await _ensureListingAuthSession('submit_tap');

    final user = FirebaseAuth.instance.currentUser;
    final String localSessionUid =
        (await _authService.getPersistedSessionUid() ?? '').trim();
    final String firebaseUid = (user?.uid ?? '').trim();
    if (firebaseUid.isEmpty) {
      await _logAuthSnapshot(
        'submit_decision',
        finalDecision: 'block',
        reason: 'firebase_auth_session_missing_for_submit',
      );
      debugPrint(
        '[AddListingUI] submit_blocked missing_firebase_auth '
        'firebaseUid=null '
        'localSessionUid=${localSessionUid.isEmpty ? 'null' : localSessionUid} '
        'sellerDocUid=${_sellerDocUid.isEmpty ? 'null' : _sellerDocUid}',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login required / لاگ اِن ضروری ہے')),
      );
      return;
    }
    if (_sellerDocUid.isNotEmpty && _sellerDocUid != firebaseUid) {
      await _logAuthSnapshot(
        'submit_decision',
        finalDecision: 'block',
        reason: 'firebase_uid_mismatch_seller_doc_uid',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session mismatch. Please sign in again / سیشن دوبارہ شروع کریں',
          ),
        ),
      );
      return;
    }
    if (localSessionUid.isNotEmpty &&
        _sellerDocUid.isNotEmpty &&
        localSessionUid != _sellerDocUid) {
      await _logAuthSnapshot(
        'submit_decision',
        finalDecision: 'block',
        reason: 'local_session_uid_mismatch_seller_doc_uid',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Session mismatch. Please sign in again / سیشن دوبارہ شروع کریں',
          ),
        ),
      );
      return;
    }
    await _logAuthSnapshot(
      'submit_decision',
      finalDecision: 'allow',
      reason: 'firebase_uid_resolved_for_submit',
    );
    final String submitSellerUid = firebaseUid;
    debugPrint(
      '[AddListingUI] submit_identity_resolved '
      'firebaseUid=$firebaseUid '
      'localSessionUid=${localSessionUid.isEmpty ? 'null' : localSessionUid} '
      'sellerDocUid=${_sellerDocUid.isEmpty ? 'null' : _sellerDocUid} '
      'finalResolvedUid=$submitSellerUid '
      'source=firebase_auth',
    );

    setState(() {
      _isSubmitting = true;
      _isMediaUploading = true;
      _mediaUploadProgress = 0;
    });
    debugPrint(
      '[AddListingUI] media_upload_start images=${_allListingImages.length}',
    );

    final bool requestedFeaturedListing = _featuredListing;

    // CRITICAL: Featured listing requires valid payment data
    if (requestedFeaturedListing && _featuredPaymentData == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Featured listing ke liye payment zaroori hai / نمایاں لسٹنگ کے لیے ادائیگی ضروری ہے',
          ),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 4),
        ),
      );
      setState(() {
        _isSubmitting = false;
        _isMediaUploading = false;
      });
      return;
    }

    // Validate payment data if featured is requested
    if (requestedFeaturedListing && _featuredPaymentData != null) {
      if (!_featuredPaymentData!.isComplete) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment details incomplete. Varify payment method, reference, and proof / ادائیگی کی تفصیلات نامکمل ہیں',
            ),
            backgroundColor: Colors.redAccent,
            duration: Duration(seconds: 4),
          ),
        );
        setState(() {
          _isSubmitting = false;
          _isMediaUploading = false;
        });
        return;
      }
    }

    final bool promotionRequested = requestedFeaturedListing;
    final String promotionType = requestedFeaturedListing
        ? 'featured_listing'
        : 'none';
    final int promotionCost = requestedFeaturedListing
        ? PromotionPaymentConfig.featuredListingFee
        : 0;
    final String? featuredRequestTimestamp = requestedFeaturedListing
        ? DateTime.now().toUtc().toIso8601String()
        : null;

    final String resolvedCity = _resolveCityForPayload();
    if (resolvedCity.length < 2) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('City required / شہر منتخب کریں')),
      );
      setState(() {
        _isSubmitting = false;
        _isMediaUploading = false;
      });
      return;
    }
    final String resolvedTehsil = _resolveTehsilForPayload(resolvedCity);
    final String resolvedDistrict = _resolveDistrictForPayload(resolvedTehsil);
    final String resolvedProvince = _resolveProvinceForPayload(
      resolvedDistrict,
    );
    final String resolvedProvinceUr = _locationUrduPart(resolvedProvince);
    final String resolvedDistrictUr = _locationUrduPart(resolvedDistrict);
    final String resolvedTehsilUr = _locationUrduPart(resolvedTehsil);
    final String resolvedCityUr = _locationUrduPart(resolvedCity);
    final String locationEn = _composeLocationEnglish(
      city: resolvedCity,
      tehsil: resolvedTehsil,
      district: resolvedDistrict,
    );
    final String locationUr = _composeLocationUrdu(
      city: resolvedCity,
      tehsil: resolvedTehsil,
      district: resolvedDistrict,
    );
    final String resolvedVillage = _villageController.text.trim().isNotEmpty
        ? _villageController.text.trim()
        : _localAreaController.text.trim();

    final normalizedUnitType = MandiUnitMapper.normalizeUnitType(
      rawUnit: _selectedUnitType.wireValue,
      categoryId: _selectedCategoryOptionId,
      fallbackType: _selectedMandiType,
      subcategoryLabel: _selectedProduct,
    );

    final listingData = <String, dynamic>{
      'sellerId': submitSellerUid,
      'sellerName':
          (widget.userData['name'] ?? widget.userData['fullName'] ?? '')
              .toString(),
      'mandiType': _selectedMandiType.wireValue,
      'category': _selectedCategoryId,
      'categoryLabel': _selectedCategoryLabel,
      'legacyCategory': _selectedMandiType.wireValue,
      'subcategory': _selectedSubcategoryId,
      'subcategoryLabel': _selectedSubcategoryLabel,
      'product': _selectedProduct,
      'quantity': _numericQuantity,
      'unit': normalizedUnitType.wireValue,
      'unitType': normalizedUnitType.wireValue,
      'price': _numericPrice,
      'description': _mappedDescriptionForPayload,
      'country': _selectedCountry,
      'province': resolvedProvince,
      'province_en': resolvedProvince,
      'province_ur': resolvedProvinceUr,
      'district': resolvedDistrict,
      'district_en': resolvedDistrict,
      'district_ur': resolvedDistrictUr,
      'tehsil': resolvedTehsil,
      'tehsil_en': resolvedTehsil,
      'tehsil_ur': resolvedTehsilUr,
      'city': resolvedCity,
      'city_text': resolvedCity,
      'city_text_ur': resolvedCityUr,
      'village': resolvedVillage,
      'location': locationEn,
      'locationUr': locationUr,
      'locationDisplay':
          LocationDisplayHelper.locationDisplayFromData(<String, dynamic>{
            'province': resolvedProvince,
            'district': resolvedDistrict,
            'tehsil': resolvedTehsil,
            'city': resolvedCity,
            'location': locationEn,
            'locationUr': locationUr,
          }),
      'locationNodes': <String, dynamic>{
        'province': <String, String>{
          'name_en': resolvedProvince,
          'name_ur': resolvedProvinceUr,
        },
        'district': <String, String>{
          'name_en': resolvedDistrict,
          'name_ur': resolvedDistrictUr,
        },
        'tehsil': <String, String>{
          'name_en': resolvedTehsil,
          'name_ur': resolvedTehsilUr,
        },
        'city': <String, String>{
          'name_en': resolvedCity,
          'name_ur': resolvedCityUr,
        },
      },
      'locationData': <String, dynamic>{
        'country': _selectedCountry,
        'province': resolvedProvince,
        'district': resolvedDistrict,
        'tehsil': resolvedTehsil,
        'city': resolvedCity,
        'village': resolvedVillage,
        'provinceObj': <String, String>{
          'name_en': resolvedProvince,
          'name_ur': resolvedProvinceUr,
        },
        'districtObj': <String, String>{
          'name_en': resolvedDistrict,
          'name_ur': resolvedDistrictUr,
        },
        'tehsilObj': <String, String>{
          'name_en': resolvedTehsil,
          'name_ur': resolvedTehsilUr,
        },
        'cityObj': <String, String>{
          'name_en': resolvedCity,
          'name_ur': resolvedCityUr,
        },
      },
      'saleType': _selectedSaleType,
      'isAuction': _isAuctionSale,
      'featured': false,
      'featuredAuction': false,
      'priorityScore': 'normal',
      'featuredCost': promotionCost,
      'promotionType': promotionType,
      'promotionStatus': promotionRequested ? 'pending_payment_review' : 'none',
      'promotionRequestedAt': featuredRequestTimestamp ?? '',
      'promotionPaymentRequired': promotionRequested,
      'promotionRequestedFeaturedListing': requestedFeaturedListing,
      'promotionRequestedFeaturedAuction': false,
      'paymentMethod': requestedFeaturedListing && _featuredPaymentData != null
          ? _featuredPaymentData!.paymentMethod
          : null,
      'paymentRef': requestedFeaturedListing && _featuredPaymentData != null
          ? _featuredPaymentData!.paymentRef
          : null,
      'paymentProofFileName':
          requestedFeaturedListing &&
              _featuredPaymentData != null &&
              _featuredPaymentData!.proofImage != null
          ? _featuredPaymentData!.proofImage!.name
          : null,
      'promotionPaymentSubmittedAt': promotionRequested
          ? DateTime.now().toUtc().toIso8601String()
          : null,
      'isFeaturedRequested': requestedFeaturedListing,
      'featuredFee': requestedFeaturedListing
          ? PromotionPaymentConfig.featuredListingFee
          : null,
      'featuredStatus': requestedFeaturedListing ? 'pending' : null,
      'featuredRequestedAt': featuredRequestTimestamp,
      'isSeasonalQurbani':
          _selectedMandiType == MandiType.livestock &&
          SeasonalMarketRules.isQurbaniSeason &&
          SeasonalMarketRules.isQurbaniEligibleProduct(_selectedProduct ?? ''),
      'seasonalTags':
          _selectedMandiType == MandiType.livestock &&
              SeasonalMarketRules.isQurbaniSeason &&
              SeasonalMarketRules.isQurbaniEligibleProduct(
                _selectedProduct ?? '',
              )
          ? const <String>['qurbani']
          : const <String>[],
      'weight': _weightController.text.trim(),
      'breed': _breedController.text.trim(),
      'age': _ageController.text.trim(),
      'fatPercentage': _fatController.text.trim(),
      'images': _allListingImages.map((e) => e.path).toList(),
      'video': _video?.path ?? '',
      'audioPath': _recordedAudioPath ?? '',
      'verificationGeo': <String, dynamic>{
        'lat': _trustPhotoLat ?? _videoLat,
        'lng': _trustPhotoLng ?? _videoLng,
      },
      'verificationCapturedAt': _trustPhotoCapturedAt ?? _videoCapturedAt,
      'verificationVideoTag': _videoTag,
      'verificationVideoMeta': <String, dynamic>{
        'lat': _videoLat,
        'lng': _videoLng,
        'capturedAt': _videoCapturedAt?.toIso8601String(),
        'tag': _videoTag,
        'fileSize': _videoFileSize,
        'durationSeconds': _videoDurationSeconds,
      },
      'verificationTrustPhotoMeta': <String, dynamic>{
        'lat': _trustPhotoLat,
        'lng': _trustPhotoLng,
        'capturedAt': _trustPhotoCapturedAt?.toIso8601String(),
        'tag': _trustPhotoTag,
        'fileSize': _trustPhotoFileSize,
      },
      'fraudPrecheck': <String, dynamic>{
        'riskScore': _fraudPrecheck.riskScore,
        'flags': _fraudPrecheck.flags,
        'status': _fraudPrecheck.status,
      },
      'estimatedValue': _marketAverage ?? 0,
      'isVerifiedSource': true,
    };

    debugPrint(
      '[AddListingUI] payload_assembled '
      'product=${listingData['product']} '
      'price=${listingData['price']} '
      'quantity=${listingData['quantity']} '
      'province=${listingData['province']} '
      'district=${listingData['district']} '
      'village=${listingData['village']}',
    );

    final mediaFiles = <String, dynamic>{
      'images': _allListingImages,
      'video': _video,
      'audioPath': _recordedAudioPath,
      'paymentProofImage':
          requestedFeaturedListing &&
              _featuredPaymentData != null &&
              _featuredPaymentData!.proofImage != null
          ? _featuredPaymentData!.proofImage
          : null,
    };

    try {
      final String status;
      developer.log(
        '[AddListingUI] submission_start uid=$submitSellerUid authStatus=authenticated',
      );
      developer.log('[AddListingUI] payload_keys=${listingData.keys.toList()}');
      developer.log(
        '[AddListingUI] using_createListingSecure_path uid=$submitSellerUid',
      );
      status = await _marketplaceService.createListingSecure(
        listingData,
        mediaFiles,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _mediaUploadProgress = progress.clamp(0.0, 1.0);
          });
        },
      );
      developer.log('[AddListingUI] submission_success status=$status');

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isMediaUploading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Listing submitted / لسٹنگ جمع ہوگئی۔ Status: $status'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      debugPrint(
        '[AddListingUI] submit_error_caught type=${error.runtimeType} message=$error',
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isMediaUploading = false;
      });
      final errorMsg = error.toString();
      debugPrint('[AddListingUI] error_msg=$errorMsg');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Submit failed. Please wait a moment and try again.\n'
            'لسٹنگ جمع نہیں ہو سکی، براہ کرم تھوڑی دیر بعد دوبارہ کوشش کریں',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration(
    String label, {
    String? hint,
    String? helperText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      filled: true,
      fillColor: AppColors.primaryText.withValues(alpha: 0.08),
      hintStyle: TextStyle(
        color: AppColors.primaryText.withValues(alpha: 0.65),
      ),
      labelStyle: TextStyle(
        color: AppColors.primaryText.withValues(alpha: 0.95),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: AppColors.primaryText.withValues(alpha: 0.22),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.urgencyRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.urgencyRed, width: 1.3),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: AppColors.primaryText.withValues(alpha: 0.2),
            ),
            gradient: LinearGradient(
              colors: <Color>[
                AppColors.primaryText.withValues(alpha: 0.13),
                AppColors.primaryText.withValues(alpha: 0.07),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildCollapsedSupportCard({
    required String title,
    required String subtitle,
    required Widget child,
    bool initiallyExpanded = false,
  }) {
    return _glassCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          initiallyExpanded: initiallyExpanded,
          iconColor: _gold,
          collapsedIconColor: _gold,
          title: Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          children: <Widget>[child],
        ),
      ),
    );
  }

  Widget _buildResponsiveFields({required Widget first, Widget? second}) {
    if (second == null) return first;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[first, const SizedBox(height: 12), second],
          );
        }
        return Row(
          children: <Widget>[
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }

  List<String> _splitBilingual(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <String>['', ''];
    final parts = trimmed.split('/');
    if (parts.length < 2) return <String>[trimmed, ''];
    return <String>[parts.first.trim(), parts.sublist(1).join('/').trim()];
  }

  Widget _bilingualLabel(
    String text, {
    Color enColor = AppColors.primaryText,
    Color urColor = AppColors.secondaryText,
    FontWeight enWeight = FontWeight.w600,
    double enSize = 14,
    double urSize = 12,
  }) {
    final parts = _splitBilingual(text);
    final en = parts[0];
    final ur = parts[1];
    if (ur.isEmpty) {
      return Text(
        en,
        style: TextStyle(
          color: enColor,
          fontWeight: enWeight,
          fontSize: enSize,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          en,
          style: TextStyle(
            color: enColor,
            fontWeight: enWeight,
            fontSize: enSize,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          ur,
          style: TextStyle(color: urColor, fontSize: urSize),
        ),
      ],
    );
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: _gold,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(
            color: AppColors.primaryText.withValues(alpha: 0.75),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildSaleTypeOptionCard({
    required String saleType,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedSaleType == saleType;
    return InkWell(
      onTap: _isSubmitting
          ? null
          : () {
              if (_selectedSaleType == saleType) return;
              setState(() {
                _selectedSaleType = saleType;
              });
            },
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isSelected
              ? _gold.withValues(alpha: 0.15)
              : AppColors.primaryText.withValues(alpha: 0.05),
          border: Border.all(
            color: isSelected
                ? _gold
                : AppColors.primaryText.withValues(alpha: 0.2),
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              icon,
              color: isSelected
                  ? _gold
                  : AppColors.primaryText.withValues(alpha: 0.85),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: AppColors.primaryText.withValues(alpha: 0.74),
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: _gold, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleTypeSelector() {
    return _buildResponsiveFields(
      first: _buildSaleTypeOptionCard(
        saleType: 'fixed',
        title: 'Fixed Price / سیدھی قیمت',
        subtitle: 'Direct sale at your set price / اپنی مقررہ قیمت پر فروخت',
        icon: Icons.price_change_outlined,
      ),
      second: _buildSaleTypeOptionCard(
        saleType: 'auction',
        title: 'Auction / بولی',
        subtitle: 'Buyers will place bids / خریدار بولی لگائیں گے',
        icon: Icons.gavel_outlined,
      ),
    );
  }

  Widget _buildSearchableSelectorField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String> onSelected,
    String? Function(String?)? validator,
    String Function(String)? optionLabelBuilder,
    String? helperText,
    bool enabled = true,
  }) {
    return FormField<String>(
      validator: (_) => validator?.call(value),
      builder: (fieldState) {
        return InkWell(
          onTap: (_isSubmitting || !enabled)
              ? null
              : () => _openSearchSheet(
                  title: label,
                  options: options,
                  optionLabelBuilder: optionLabelBuilder,
                  onSelected: (selected) {
                    fieldState.didChange(selected);
                    onSelected(selected);
                  },
                ),
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: _fieldDecoration(label).copyWith(
              suffixIcon: const Icon(Icons.search, color: _gold),
              errorText: fieldState.errorText,
              helperText: helperText,
              helperStyle: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.72),
                fontSize: 11,
              ),
            ),
            child: (value ?? '').isEmpty
                ? Text(
                    'Select / منتخب کریں',
                    style: TextStyle(
                      color: AppColors.primaryText.withValues(alpha: 0.65),
                    ),
                  )
                : _bilingualLabel(value!),
          ),
        );
      },
    );
  }

  Future<void> _openSearchSheet({
    required String title,
    required List<String> options,
    required ValueChanged<String> onSelected,
    String Function(String)? optionLabelBuilder,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _darkGreenMid,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final builder = optionLabelBuilder ?? (String value) => value;
            final filtered = options
                .where(
                  (e) =>
                      e.toLowerCase().contains(query.toLowerCase()) ||
                      builder(e).toLowerCase().contains(query.toLowerCase()),
                )
                .toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 14,
                  right: 14,
                  top: 14,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: 46,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.primaryText.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Search in English or Urdu / انگریزی یا اردو میں تلاش کریں',
                      style: TextStyle(
                        color: AppColors.primaryText.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      style: const TextStyle(color: AppColors.primaryText),
                      decoration: _fieldDecoration(
                        'Search / تلاش',
                        hint: 'e.g. Lahore / لاہور',
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          query = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, separatorIndex) => Divider(
                          color: AppColors.primaryText.withValues(alpha: 0.12),
                        ),
                        itemBuilder: (context, index) {
                          final option = filtered[index];
                          final displayLabel = builder(option);
                          return ListTile(
                            dense: true,
                            tileColor: AppColors.primaryText.withValues(
                              alpha: 0.03,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            title: _bilingualLabel(displayLabel),
                            onTap: () => Navigator.of(context).pop(option),
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

    if (picked == null || picked.trim().isEmpty) return;
    onSelected(picked);
  }

  Widget _buildDistrictField() {
    return _buildSearchableSelectorField(
      label: 'District / ضلع',
      value: _selectedDistrict,
      options: (_selectedProvince ?? '').trim().isEmpty
          ? _allDistricts
          : _districtOptions,
      optionLabelBuilder: _locationOptionLabel,
      helperText: 'District is required / ضلع لازمی ہے',
      validator: (_) {
        final district = (_selectedDistrict ?? '').trim();
        if (district.isEmpty) return 'District is required / ضلع لازمی ہے';

        final province = (_selectedProvince ?? '').trim();
        if (province.isEmpty) return 'Province is required / صوبہ لازمی ہے';

        final districtList = _isLocationAssetReady
            ? _districtOptions
            : (AppConstants.pakistanLocations[province] ?? const <String>[]);
        final isMatch = districtList
            .map((e) => e.toLowerCase())
            .contains(district.toLowerCase());

        if (!isMatch) {
          return 'District must belong to selected province / ضلع منتخب صوبے کے مطابق ہونا چاہیے';
        }
        return null;
      },
      onSelected: (selection) {
        setState(() {
          _selectedDistrict = selection;
          _districtAutocompleteController.text = selection;
          _selectedTehsil = null;
          _selectedCity = null;
          _cityController.clear();
          _localAreaController.clear();
          final autoProvince = _districtToProvince[selection.toLowerCase()];
          if ((autoProvince ?? '').isNotEmpty) {
            _selectedProvince = autoProvince;
          }
          _fraudPrecheck = _runFraudPrecheck();
        });
        unawaited(_refreshMarketIntelligence());
      },
    );
  }

  Widget _buildVerificationSection() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Required Trust Photo + GPS / لازمی ٹرسٹ تصویر + GPS',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Capture a clear photo of your item / اپنے مال کی واضح تصویر لیں',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'GPS will help verify the listing location / GPS لسٹنگ کی جگہ کی تصدیق میں مدد دے گا',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Location required for trusted listing verification / معتبر لسٹنگ کی تصدیق کے لیے لوکیشن ضروری ہے',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _captureTrustPhoto,
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: AppColors.ctaTextDark,
            ),
            icon: const Icon(Icons.photo_camera),
            label: const Text('Capture Trust Photo / ٹرسٹ تصویر لیں'),
          ),
          if (_trustPhoto != null) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_trustPhoto!.path),
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: <Widget>[
                Text(
                  'GPS: ${_trustPhotoLat?.toStringAsFixed(4) ?? '-'}, ${_trustPhotoLng?.toStringAsFixed(4) ?? '-'}',
                  style: const TextStyle(color: AppColors.primaryText),
                ),
                Text(
                  'Size: ${((_trustPhotoFileSize ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB',
                  style: const TextStyle(color: AppColors.primaryText),
                ),
              ],
            ),
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _trustPhoto = null;
                        _trustPhotoLat = null;
                        _trustPhotoLng = null;
                        _trustPhotoCapturedAt = null;
                        _trustPhotoTag = null;
                        _trustPhotoFileSize = null;
                        _logSubmitGateStatus('trust_photo_removed');
                      });
                    },
              icon: const Icon(
                Icons.delete_outline,
                color: AppColors.primaryText,
              ),
              label: const Text(
                'Remove Trust Photo / ٹرسٹ تصویر ہٹائیں',
                style: TextStyle(color: AppColors.primaryText),
              ),
            ),
          ],
          if ((_verificationInlineError ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3CD).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: 0.45)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.info_outline, color: _gold, size: 16),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _verificationInlineError!,
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.95),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_showVerificationRecoveryActions) ...<Widget>[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await Geolocator.openLocationSettings();
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(
                      color: AppColors.primaryText.withValues(alpha: 0.35),
                    ),
                  ),
                  icon: const Icon(Icons.gps_fixed, size: 16),
                  label: const Text('Open GPS Settings / GPS سیٹنگز'),
                ),
                OutlinedButton.icon(
                  onPressed: _isSubmitting
                      ? null
                      : () async {
                          await Geolocator.openAppSettings();
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(
                      color: AppColors.primaryText.withValues(alpha: 0.35),
                    ),
                  ),
                  icon: const Icon(Icons.settings, size: 16),
                  label: const Text('Open App Permissions / اجازت سیٹنگز'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          _buildCollapsedSupportCard(
            title: 'Optional Verification Video / اختیاری تصدیقی ویڈیو',
            subtitle: 'Chahein to chhoti video add karein',
            initiallyExpanded: _videoController?.value.isInitialized == true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'A short live video can improve buyer trust / مختصر لائیو ویڈیو اعتماد بڑھا سکتی ہے',
                  style: TextStyle(
                    color: AppColors.primaryText.withValues(alpha: 0.74),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _isSubmitting ? null : _recordVerificationVideo,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryText,
                    side: BorderSide(
                      color: AppColors.primaryText.withValues(alpha: 0.35),
                    ),
                  ),
                  icon: const Icon(Icons.videocam),
                  label: const Text(
                    'Record Optional Video / اختیاری ویڈیو ریکارڈ کریں',
                  ),
                ),
                if (_videoController?.value.isInitialized == true) ...<Widget>[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AspectRatio(
                      aspectRatio: _videoController!.value.aspectRatio,
                      child: VideoPlayer(_videoController!),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: <Widget>[
                      Text(
                        'Duration: ${_videoDurationSeconds ?? 0}s',
                        style: const TextStyle(color: AppColors.primaryText),
                      ),
                      Text(
                        'Size: ${((_videoFileSize ?? 0) / (1024 * 1024)).toStringAsFixed(2)} MB',
                        style: const TextStyle(color: AppColors.primaryText),
                      ),
                      Text(
                        'GPS: ${_videoLat?.toStringAsFixed(4) ?? '-'}, ${_videoLng?.toStringAsFixed(4) ?? '-'}',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _isSubmitting
                        ? null
                        : () async {
                            final old = _videoController;
                            setState(() {
                              _video = null;
                              _videoController = null;
                              _videoLat = null;
                              _videoLng = null;
                              _videoCapturedAt = null;
                              _videoTag = null;
                              _videoFileSize = null;
                              _videoDurationSeconds = null;
                            });
                            await old?.dispose();
                          },
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.primaryText,
                    ),
                    label: const Text(
                      'Remove Optional Video / اختیاری ویڈیو ہٹائیں',
                      style: TextStyle(color: AppColors.primaryText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionalMediaSection() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Optional Extra Media / اختیاری اضافی میڈیا',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add extra gallery photos and optional audio note / اضافی گیلری تصاویر اور اختیاری وائس نوٹ شامل کریں',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.76),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: (_isSubmitting || _images.length >= 3)
                ? null
                : _pickImage,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(
                color: AppColors.primaryText.withValues(alpha: 0.35),
              ),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(
              'Add Extra Image (${_images.length}/3) / اضافی تصویر شامل کریں',
            ),
          ),
          if (_images.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _images.length,
                separatorBuilder: (_, separatorIndex) =>
                    const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  return Stack(
                    children: <Widget>[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_images[index].path),
                          width: 82,
                          height: 82,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: InkWell(
                          onTap: _isSubmitting
                              ? null
                              : () {
                                  setState(() {
                                    _images.removeAt(index);
                                    _fraudPrecheck = _runFraudPrecheck();
                                  });
                                },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: AppColors.ctaTextDark.withValues(
                                alpha: 0.6,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppColors.primaryText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 12),
          AudioNoteWidget(
            onRecordingComplete: (path) {
              setState(() {
                _recordedAudioPath = path;
                _fraudPrecheck = _runFraudPrecheck();
              });
            },
          ),
          if (_isMediaUploading) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: _mediaUploadProgress,
                minHeight: 8,
                backgroundColor: AppColors.primaryText.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(_gold),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Uploading ${(100 * _mediaUploadProgress).toStringAsFixed(0)}%',
              style: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.86),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalValueCard() {
    final quantityLabel = _isLivestock ? 'weight' : 'qty';
    final conversionNote = _selectedUnitType == UnitType.mann
        ? 'Helper: 1 mann = 40kg'
        : '';

    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Total Value / کل مالیت',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Rs. ${_numericPrice.toStringAsFixed(2)} x ${_valueBaseQuantity.toStringAsFixed(2)} ($quantityLabel) = Rs. ${_totalValue.toStringAsFixed(2)}',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w700),
          ),
          if (conversionNote.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              conversionNote,
              style: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMarketIntelligenceCard() {
    return _glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  'Market Intelligence / مارکیٹ معلومات',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _isLoadingMarket ? null : _refreshMarketIntelligence,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh / تازہ کریں'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (_isLoadingMarket)
            Text(
              'Loading average rate... / اوسط ریٹ لوڈ ہو رہا ہے',
              style: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.8),
              ),
            )
          else
            Text(
              _marketAverage == null
                  ? 'Market average unavailable / اوسط ریٹ دستیاب نہیں'
                  : 'Market average: Rs. ${_marketAverage!.toStringAsFixed(2)} / اوسط ریٹ',
              style: const TextStyle(color: _gold),
            ),
          if (_recommendedPrice != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Recommended price: Rs. ${_recommendedPrice!.toStringAsFixed(2)} / تجویز کردہ قیمت',
              style: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.9),
              ),
            ),
          ],
          if (_priceDeviationPercent != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _sellerPriceInsight.isEmpty
                  ? 'Your price is ${_priceDeviationPercent!.abs().toStringAsFixed(1)}% ${_priceDeviationPercent! >= 0 ? 'above' : 'below'} mandi average.'
                  : _sellerPriceInsight,
              style: TextStyle(
                color: AppColors.primaryText.withValues(alpha: 0.85),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.primaryText.withValues(alpha: 0.07),
              border: Border.all(
                color: AppColors.primaryText.withValues(alpha: 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'AI Trust / Risk Score / اعتماد اسکور',
                  style: TextStyle(
                    color: AppColors.primaryText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Risk Score: ${_fraudPrecheck.riskScore} / 100 / رسک اسکور',
                  style: TextStyle(
                    color: AppColors.primaryText.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Flags: ${_fraudPrecheck.flags.isEmpty ? 'none / کوئی نہیں' : _fraudPrecheck.flags.join(', ')}',
                  style: TextStyle(
                    color: AppColors.primaryText.withValues(alpha: 0.88),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${_fraudPrecheck.status} / اسٹیٹس',
                  style: TextStyle(
                    color: AppColors.primaryText.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Listing / نئی لسٹنگ'),
        backgroundColor: _darkGreenStart,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[_darkGreenStart, _darkGreenMid, _darkGreenEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: <Widget>[
                _buildVoiceAssistCard(),
                const SizedBox(height: 12),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Listing Details / لسٹنگ تفصیلات',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Share complete and accurate details for better buyer trust / بہتر اعتماد کے لیے مکمل اور درست معلومات دیں',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.76),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Sale Type / فروخت کی قسم',
                        'Choose how you want to sell / فروخت کا طریقہ منتخب کریں',
                      ),
                      _buildSaleTypeSelector(),
                      if (_isAuctionSale) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Bidding enabled for this listing / خریدار بولی لگائیں گے',
                          style: TextStyle(
                            color: AppColors.primaryText.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Category, Subcategory & Variety / زمرہ، ذیلی زمرہ اور قسم',
                        'Choose the most relevant market classification / درست مارکیٹ درجہ بندی منتخب کریں',
                      ),
                      _buildSearchableSelectorField(
                        label: 'Category / زمرہ',
                        value: _selectedCategoryDisplay,
                        options: _categoryOptions,
                        helperText: 'Category is required / زمرہ لازمی ہے',
                        validator: (_) {
                          if (_selectedCategoryDisplay.trim().isEmpty) {
                            return 'Category is required / زمرہ لازمی ہے';
                          }
                          return null;
                        },
                        onSelected: (selected) {
                          final mapped = _listingCategoryFromLabel(selected);
                          if (mapped == null) return;
                          final nextUnit = MandiUnitMapper.resolve(
                            categoryId: mapped.id,
                            fallbackType: mapped.mandiType,
                            subcategoryLabel: null,
                          ).defaultUnit;
                          setState(() {
                            _selectedCategoryOptionId = mapped.id;
                            _selectedMandiType = mapped.mandiType;
                            _selectedProduct = null;
                            _selectedRiceVariety = null;
                            _selectedUnitType = nextUnit;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildSearchableSelectorField(
                        label: 'Subcategory / ذیلی زمرہ',
                        value: _selectedProduct,
                        options: _productOptions,
                        helperText:
                            'Subcategory is required / ذیلی زمرہ لازمی ہے',
                        validator: (_) {
                          if ((_selectedProduct ?? '').trim().isEmpty) {
                            return 'Subcategory is required / ذیلی زمرہ لازمی ہے';
                          }
                          return null;
                        },
                        onSelected: (selected) {
                          final nextUnit = MandiUnitMapper.resolve(
                            categoryId: _selectedCategoryOptionId,
                            fallbackType: _selectedMandiType,
                            subcategoryLabel: selected,
                          ).defaultUnit;
                          setState(() {
                            _selectedProduct = selected;
                            if (!_isRiceCropSelected &&
                                !_isProcessedRiceSelected) {
                              _selectedRiceVariety = null;
                            }
                            _selectedUnitType = nextUnit;
                            _fraudPrecheck = _runFraudPrecheck();
                          });
                          unawaited(_refreshMarketIntelligence());
                        },
                      ),
                      if (_isRiceCropSelected || _isProcessedRiceSelected) ...[
                        const SizedBox(height: 12),
                        _buildSearchableSelectorField(
                          label: 'Rice Variety / چاول کی قسم',
                          value: _selectedRiceVariety,
                          options: _riceVarietyOptions,
                          helperText: 'Variety is required / قسم لازمی ہے',
                          validator: (_) {
                            if ((_selectedRiceVariety ?? '').trim().isEmpty) {
                              return 'Variety is required / قسم لازمی ہے';
                            }
                            return null;
                          },
                          onSelected: (selected) {
                            setState(() {
                              _selectedRiceVariety = selected;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Quantity & Price / مقدار اور قیمت',
                        'Enter clear quantity and expected price / واضح مقدار اور قیمت درج کریں',
                      ),
                      _buildResponsiveFields(
                        first: TextFormField(
                          controller: _quantityController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration('Quantity / مقدار'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Quantity is required / مقدار لازمی ہے';
                            }
                            final n = double.tryParse(value!.trim());
                            if (n == null || n <= 0) {
                              return 'Enter a valid quantity / درست مقدار درج کریں';
                            }
                            return null;
                          },
                        ),
                        second: DropdownButtonFormField<UnitType>(
                          initialValue: _selectedUnitType,
                          onChanged: _isSubmitting
                              ? null
                              : (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _selectedUnitType = value;
                                  });
                                },
                          dropdownColor: _darkGreenMid,
                          iconEnabledColor: _gold,
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration('Unit / اکائی'),
                          items: _allowedUnits
                              .map(
                                (u) => DropdownMenuItem<UnitType>(
                                  value: u,
                                  child: Text(
                                    '${u.urduLabel} (${u.wireValue})',
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        style: const TextStyle(color: AppColors.primaryText),
                        decoration: _fieldDecoration(
                          'Price per Unit (Rs.) / فی اکائی قیمت',
                        ),
                        validator: (value) {
                          if ((value ?? '').trim().isEmpty) {
                            return 'Price is required / قیمت لازمی ہے';
                          }
                          final n = double.tryParse(value!.trim());
                          if (n == null || n <= 0) {
                            return 'Enter a valid price / درست قیمت درج کریں';
                          }
                          return null;
                        },
                      ),
                      if (_isAuctionSale)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Auction mode active / بولی موڈ فعال ہے',
                            style: TextStyle(
                              color: AppColors.primaryText.withValues(
                                alpha: 0.78,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Location / مقام',
                        'Select province, district, tehsil, then city / صوبہ، ضلع، تحصیل، پھر شہر منتخب کریں',
                      ),
                      _buildResponsiveFields(
                        first: _buildSearchableSelectorField(
                          label: 'Province / صوبہ',
                          value: _selectedProvince,
                          options: _provinceOptions,
                          optionLabelBuilder: _locationOptionLabel,
                          helperText: 'Province is required / صوبہ لازمی ہے',
                          validator: (_) {
                            if ((_selectedProvince ?? '').trim().isEmpty) {
                              return 'Province is required / صوبہ لازمی ہے';
                            }
                            return null;
                          },
                          onSelected: (selected) {
                            setState(() {
                              _selectedProvince = selected;
                              _selectedDistrict = null;
                              _selectedTehsil = null;
                              _selectedCity = null;
                              _cityController.clear();
                              _localAreaController.clear();
                              _districtAutocompleteController.clear();
                              _fraudPrecheck = _runFraudPrecheck();
                            });
                            unawaited(_refreshMarketIntelligence());
                          },
                        ),
                        second: _buildDistrictField(),
                      ),
                      const SizedBox(height: 12),
                      _buildResponsiveFields(
                        first: _buildSearchableSelectorField(
                          label: 'Tehsil / تحصیل',
                          value: _selectedTehsil,
                          options: _tehsilOptions,
                          optionLabelBuilder: _locationOptionLabel,
                          helperText: 'Tehsil is required / تحصیل لازمی ہے',
                          validator: (_) {
                            if ((_selectedTehsil ?? '').trim().isEmpty) {
                              return 'Tehsil is required / تحصیل لازمی ہے';
                            }
                            return null;
                          },
                          onSelected: (selected) {
                            setState(() {
                              _selectedTehsil = selected;
                              _selectedCity = null;
                              _cityController.clear();
                              _fraudPrecheck = _runFraudPrecheck();
                            });
                          },
                        ),
                        second: TextFormField(
                          controller: _cityController,
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration(
                            'City / شہر',
                            helperText: 'Type city manually / شہر خود لکھیں',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'City required / شہر درج کریں';
                            }
                            return null;
                          },
                          onChanged: (value) {
                            setState(() {
                              _selectedCity = value.trim();
                              _fraudPrecheck = _runFraudPrecheck();
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _villageController,
                        style: const TextStyle(color: AppColors.primaryText),
                        decoration: _fieldDecoration(
                          'Village or Local Area / گاؤں یا محلہ',
                          hint: 'Optional / اختیاری',
                        ),
                      ),
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Description / تفصیل',
                        'Add condition, quality, and delivery notes / معیار، حالت اور ترسیل کی تفصیل لکھیں',
                      ),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 4,
                        style: const TextStyle(color: AppColors.primaryText),
                        decoration: _fieldDecoration(
                          'Description / تفصیل',
                          hint:
                              'Quality, moisture, packing, pickup notes / معیار، نمی، پیکنگ، وصولی نوٹس',
                        ),
                        validator: (value) {
                          final text = (value ?? '').trim();
                          if (text.isEmpty) {
                            return 'Description is required / تفصیل لازمی ہے';
                          }
                          if (text.length < 10) {
                            return 'Please add more detail / مزید تفصیل شامل کریں';
                          }
                          return null;
                        },
                      ),
                      if (_isLivestock) ...<Widget>[
                        const SizedBox(height: 12),
                        _buildResponsiveFields(
                          first: TextFormField(
                            controller: _breedController,
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: _fieldDecoration('Breed / نسل'),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Breed is required / نسل لازمی ہے';
                              }
                              return null;
                            },
                          ),
                          second: TextFormField(
                            controller: _ageController,
                            style: const TextStyle(
                              color: AppColors.primaryText,
                            ),
                            decoration: _fieldDecoration('Age / عمر'),
                            validator: (value) {
                              if ((value ?? '').trim().isEmpty) {
                                return 'Age is required / عمر لازمی ہے';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _weightController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration('Weight / وزن'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Weight is required / وزن لازمی ہے';
                            }
                            final n = double.tryParse(value!.trim());
                            if (n == null || n <= 0) {
                              return 'Enter a valid weight / درست وزن درج کریں';
                            }
                            return null;
                          },
                        ),
                      ],
                      if (_isMilk) ...<Widget>[
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _fatController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration('Fat % / چکنائی ٪'),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Fat percentage is required / چکنائی فیصد لازمی ہے';
                            }
                            return null;
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildVerificationSection(),
                const SizedBox(height: 12),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Promotion / تشہیر',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Aapki listing buyer feed mein upar dikhegi / خریداروں کو اوپر دکھائیں',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Zyada views, zyada calls / زیادہ ویوز، زیادہ کالز',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.72),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fee: Rs ${PromotionPaymentConfig.featuredListingFee} / فیس: ${PromotionPaymentConfig.featuredListingFee} روپے',
                        style: const TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: _gold,
                        value: _featuredListing,
                        onChanged: _isSubmitting
                            ? null
                            : (value) async {
                                if (value) {
                                  // Open payment modal when trying to enable
                                  if (!mounted) return;
                                  final result =
                                      await showModalBottomSheet<
                                        FeaturedListingPaymentData
                                      >(
                                        context: context,
                                        isScrollControlled: true,
                                        backgroundColor: Colors.transparent,
                                        builder: (context) =>
                                            const FeaturedListingPaymentModal(),
                                      );
                                  if (result != null) {
                                    setState(() {
                                      _featuredListing = true;
                                      _featuredPaymentData = result;
                                    });
                                  }
                                  // If user cancelled or didn't complete modal, toggle stays OFF
                                } else {
                                  // User turning off featured listing
                                  setState(() {
                                    _featuredListing = false;
                                    _featuredPaymentData = null;
                                  });
                                }
                              },
                        title: const Text(
                          'Featured Listing / نمایاں لسٹنگ',
                          style: TextStyle(color: AppColors.primaryText),
                        ),
                        subtitle: Text(
                          _featuredListing && _featuredPaymentData != null
                              ? 'Payment received - pending admin review / ادائیگی موصول - ایڈمن جائزے کے زیرِ'
                              : 'Aapki listing buyer feed mein upar dikhegi / خریداروں کو اوپر دکھائیں',
                          style: TextStyle(
                            color: AppColors.primaryText.withValues(
                              alpha: 0.72,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_featuredListing && _featuredPaymentData != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.green.withValues(alpha: 0.8),
                                size: 16,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Payment verified: ${_featuredPaymentData!.paymentMethod} / ادائیگی تصدیق شدہ',
                                  style: TextStyle(
                                    color: Colors.green.withValues(alpha: 0.8),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_featuredListing && _featuredPaymentData == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Payment required to enable featured listing / نمایاں لسٹنگ کے لیے ادائیگی ضروری ہے',
                            style: TextStyle(
                              color: Colors.orange.withValues(alpha: 0.8),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ElevatedButton.icon(
                  onPressed: (_isSubmitting || !_hasAllRequiredForSubmit)
                      ? null
                      : _submitListing,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _gold,
                    foregroundColor: AppColors.ctaTextDark,
                    disabledBackgroundColor: _gold.withValues(alpha: 0.4),
                    minimumSize: const Size(double.infinity, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.campaign_outlined),
                  label: const Text(
                    'Post Listing / لسٹنگ شائع کریں',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Builder(
                  builder: (_) {
                    _logSubmitGateStatus('build_post_button');
                    return const SizedBox.shrink();
                  },
                ),
                if (_approvalCheckInProgress)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Checking approval status... / منظوری کی حالت چیک ہو رہی ہے',
                      style: TextStyle(
                        color: AppColors.primaryText.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_approvalLocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _approvalLockMessage,
                      style: const TextStyle(
                        color: AppColors.urgencyRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (!_hasRequiredTrustPhoto)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Trust photo with GPS is required before posting / پوسٹ کرنے سے پہلے GPS کے ساتھ ٹرسٹ تصویر لازمی ہے',
                      style: TextStyle(
                        color: AppColors.primaryText.withValues(alpha: 0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_hardFraudBlock)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'High-risk listing blocked. Capture trust photo with GPS and add strong details / ہائی رسک لسٹنگ بلاک ہے، GPS کے ساتھ ٹرسٹ تصویر لیں اور بہتر تفصیل شامل کریں',
                      style: TextStyle(
                        color: AppColors.urgencyRed,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                _buildCollapsedSupportCard(
                  title: 'Helpful Insights / مزید مدد',
                  subtitle: 'Total value aur mandi signals',
                  child: Column(
                    children: <Widget>[
                      _buildTotalValueCard(),
                      const SizedBox(height: 12),
                      _buildMarketIntelligenceCard(),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildCollapsedSupportCard(
                  title: 'Optional Extra Media / اختیاری اضافی میڈیا',
                  subtitle: 'Extra photos aur voice note',
                  child: _buildOptionalMediaSection(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceListeningPulse extends StatefulWidget {
  const _VoiceListeningPulse();

  @override
  State<_VoiceListeningPulse> createState() => _VoiceListeningPulseState();
}

class _VoiceListeningPulseState extends State<_VoiceListeningPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final double t = _controller.value;
        final double outer = 28 + (14 * t);
        final double alpha = 0.24 * (1 - t);
        return SizedBox(
          height: 72,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  width: outer,
                  height: outer,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentGold.withValues(alpha: alpha),
                  ),
                ),
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accentGold.withValues(alpha: 0.22),
                    border: Border.all(
                      color: AppColors.accentGold.withValues(alpha: 0.7),
                    ),
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: AppColors.accentGold,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _VoiceProcessingShimmer extends StatefulWidget {
  const _VoiceProcessingShimmer();

  @override
  State<_VoiceProcessingShimmer> createState() =>
      _VoiceProcessingShimmerState();
}

class _VoiceProcessingShimmerState extends State<_VoiceProcessingShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return ShaderMask(
              shaderCallback: (Rect bounds) {
                final double x = (_controller.value * 2) - 1;
                return LinearGradient(
                  begin: Alignment(-1.2 + x, 0),
                  end: Alignment(-0.2 + x, 0),
                  colors: <Color>[
                    AppColors.primaryText.withValues(alpha: 0.14),
                    AppColors.accentGold.withValues(alpha: 0.85),
                    AppColors.primaryText.withValues(alpha: 0.14),
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.srcATop,
              child: Container(
                width: double.infinity,
                color: AppColors.primaryText.withValues(alpha: 0.22),
              ),
            );
          },
        ),
      ),
    );
  }
}
