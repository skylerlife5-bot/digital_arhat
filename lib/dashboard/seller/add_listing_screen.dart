import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants.dart';
import '../../core/market_hierarchy.dart';
import '../../config/promotion_payment_config.dart';
import '../../services/ai_generative_service.dart';
import '../../services/layer2_market_intelligence_service.dart';
import '../../services/marketplace_service.dart';
import '../components/audio_recorder_widget.dart';
import '../../theme/app_colors.dart';

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
  final List<_LocationLeaf> tehsils;
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
  final MarketplaceService _marketplaceService = MarketplaceService();
  final MandiIntelligenceService _intelligenceService =
      MandiIntelligenceService();
  final Layer2MarketIntelligenceService _layer2Service =
      Layer2MarketIntelligenceService();

  MandiType _selectedMandiType = MandiType.crops;
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
  bool _isMediaUploading = false;
  double _mediaUploadProgress = 0;
  bool _isLoadingMarket = false;
  bool _featuredListing = false;
  bool _featuredAuctionUpgrade = false;

  double? _marketAverage;
  double? _recommendedPrice;
  double? _priceDeviationPercent;
  String _sellerPriceInsight = '';
  bool _isLocationAssetReady = false;
  List<_ProvinceNode> _locationAssetProvinces = const <_ProvinceNode>[];

  final Map<String, String> _provinceUrduByEn = <String, String>{};
  final Map<String, String> _districtUrduByEn = <String, String>{};
  final Map<String, String> _tehsilUrduByEn = <String, String>{};

  FraudPrecheckResult _fraudPrecheck = const FraudPrecheckResult(
    riskScore: 0,
    flags: <String>[],
    status: 'Low Risk',
  );

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
      return <String>[tehsil, district];
    }

    return PakistanLocationHierarchy.citiesForTehsil(
      district: district,
      tehsil: tehsil,
    );
  }

  List<String> get _localAreaSuggestions {
    final set = <String>{..._cityOptions};
    final selectedCity = (_selectedCity ?? '').trim();
    if (selectedCity.isNotEmpty) {
      set.add(selectedCity);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<String> get _productOptions =>
      CategoryConstants.itemsForMandiType(_selectedMandiType);

  List<String> get _categoryOptions => MandiType.values
      .map(MarketHierarchy.categoryLabelForMandiType)
      .toList(growable: false);

  String get _selectedCategoryDisplay =>
      MarketHierarchy.categoryLabelForMandiType(_selectedMandiType);

  String get _selectedCategoryId =>
      MarketHierarchy.categoryIdForMandiType(_selectedMandiType);

  String get _selectedCategoryLabel =>
      MarketHierarchy.categoryLabelForMandiType(_selectedMandiType);

  String get _selectedSubcategoryId =>
      MarketHierarchy.subcategoryIdFromProduct(_selectedProduct ?? '');

  String get _selectedSubcategoryLabel =>
      MarketHierarchy.subcategoryDisplayFromProduct(_selectedProduct ?? '');

  List<UnitType> get _allowedUnits =>
      CategoryConstants.allowedUnitsForMandiType(_selectedMandiType);

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

  MandiType? _mandiTypeFromCategoryLabel(String selected) {
    for (final type in MandiType.values) {
      if (MarketHierarchy.categoryLabelForMandiType(type) == selected) {
        return type;
      }
    }
    return null;
  }

  bool get _hasRequiredTrustPhoto {
    return _trustPhoto != null &&
        _trustPhotoLat != null &&
        _trustPhotoLng != null &&
        _trustPhotoCapturedAt != null;
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

  bool get _hasAllRequiredForSubmit {
    // Keep button state lightweight; full validation still runs inside _submitListing.
    return !_isSubmitting && _hasRequiredTrustPhoto && !_hardFraudBlock;
  }

  @override
  void initState() {
    super.initState();
    _selectedUnitType = CategoryConstants.defaultUnitForMandiType(
      _selectedMandiType,
    );

    final listeners = <TextEditingController>[
      _priceController,
      _quantityController,
      _weightController,
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
    unawaited(_loadPakistanLocationsAsset());
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _weightController.dispose();
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
    });
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
            final tehsils = <_LocationLeaf>[];

            if (tehsilsRaw is List) {
              for (final tehsilItem in tehsilsRaw) {
                if (tehsilItem is! Map) continue;
                final tehsilMap = tehsilItem.cast<String, dynamic>();
                final tehsilEn = (tehsilMap['name_en'] ?? '').toString().trim();
                if (tehsilEn.isEmpty) continue;

                final tehsilUr = (tehsilMap['name_ur'] ?? '').toString().trim();
                tehsilUrdu[tehsilEn] = tehsilUr;

                tehsils.add(
                  _LocationLeaf(
                    id: (tehsilMap['id'] ?? tehsilEn)
                        .toString()
                        .trim()
                        .toLowerCase(),
                    nameEn: tehsilEn,
                    nameUr: tehsilUr,
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
        _provinceUrduByEn[trimmed] ??
        _districtUrduByEn[trimmed] ??
        _tehsilUrduByEn[trimmed] ??
        '';
    if (urdu.isEmpty) return trimmed;
    return '$trimmed / $urdu';
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
        unit: _selectedUnitType.wireValue,
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[AddListingUI] user_null');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login required / لاگ اِن ضروری ہے')),
      );
      return;
    }
    debugPrint('[AddListingUI] validation_pass uid=${user.uid}');

    setState(() {
      _isSubmitting = true;
      _isMediaUploading = true;
      _mediaUploadProgress = 0;
    });
    debugPrint('[AddListingUI] media_upload_start images=${_allListingImages.length}');

    final bool requestedFeaturedListing = _featuredListing;
    final bool requestedFeaturedAuction =
        _featuredListing && _featuredAuctionUpgrade;
    final bool promotionRequested =
        requestedFeaturedListing || requestedFeaturedAuction;
    final String promotionType = requestedFeaturedAuction
        ? 'featured_auction'
        : (requestedFeaturedListing ? 'featured_listing' : 'none');
    final int promotionCost = requestedFeaturedAuction
        ? PromotionPaymentConfig.featuredAuctionFee
        : (requestedFeaturedListing
              ? PromotionPaymentConfig.featuredListingFee
              : 0);

    final String resolvedCity = _localAreaController.text.trim().isEmpty
      ? (_selectedCity ?? '')
      : _localAreaController.text.trim();
    final String resolvedVillage = _villageController.text.trim().isEmpty
      ? resolvedCity
      : _villageController.text.trim();

    final listingData = <String, dynamic>{
      'sellerId': user.uid,
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
      'unit': _selectedUnitType.wireValue,
      'price': _numericPrice,
      'description': _mappedDescriptionForPayload,
      'country': _selectedCountry,
      'province': _selectedProvince,
      'district': _selectedDistrict,
      'tehsil': _selectedTehsil,
      'city': resolvedCity,
      'village': resolvedVillage,
      'location':
          '$resolvedCity, ${_selectedTehsil ?? ''}, ${_selectedDistrict ?? ''}, ${_selectedProvince ?? ''}',
      'locationData': <String, dynamic>{
        'country': _selectedCountry,
        'province': _selectedProvince ?? '',
        'district': _selectedDistrict ?? '',
        'tehsil': _selectedTehsil ?? '',
        'city': resolvedCity,
        'village': resolvedVillage,
      },
      'saleType': 'auction',
      'featured': false,
      'featuredAuction': false,
      'priorityScore': 'normal',
      'featuredCost': promotionCost,
      'promotionType': promotionType,
      'promotionStatus': promotionRequested ? 'pending_review' : 'none',
      'promotionRequestedAt': DateTime.now().toUtc().toIso8601String(),
      'promotionPaymentRequired': promotionRequested,
      'promotionRequestedFeaturedListing': requestedFeaturedListing,
      'promotionRequestedFeaturedAuction': requestedFeaturedAuction,
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
      'riskScore': _fraudPrecheck.riskScore,
      'fraudFlags': _fraudPrecheck.flags,
      'status': 'pending_review',
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
    };

    try {
      final status = await _marketplaceService.createListingSecure(
        listingData,
        mediaFiles,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _mediaUploadProgress = progress.clamp(0.0, 1.0);
          });
        },
      );

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
      debugPrint('[AddListingUI] submit_error_caught type=${error.runtimeType} message=$error');
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isMediaUploading = false;
      });
      final errorMsg = error.toString();
      debugPrint('[AddListingUI] error_msg=$errorMsg');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Listing could not be submitted right now. Your form data is still here. Please retry. / لسٹنگ اس وقت جمع نہ ہو سکی، آپ کا فارم یہیں محفوظ ہے، دوبارہ کوشش کریں\nError: $errorMsg',
          ),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: AppColors.primaryText.withValues(alpha: 0.08),
      hintStyle: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.65)),
      labelStyle: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.95)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primaryText.withValues(alpha: 0.22)),
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
            border: Border.all(color: AppColors.primaryText.withValues(alpha: 0.2)),
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

  Widget _buildSearchableSelectorField({
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String> onSelected,
    String? Function(String?)? validator,
    String Function(String)? optionLabelBuilder,
    String? helperText,
  }) {
    return FormField<String>(
      validator: (_) => validator?.call(value),
      builder: (fieldState) {
        return InkWell(
          onTap: _isSubmitting
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
                            tileColor: AppColors.primaryText.withValues(alpha: 0.03),
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
    return FormField<String>(
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
      builder: (fieldState) {
        return Autocomplete<String>(
          optionsBuilder: (value) {
            final source = (_selectedProvince ?? '').trim().isEmpty
                ? _allDistricts
                : _districtOptions;
            final q = value.text.trim().toLowerCase();
            if (q.isEmpty) return source;
            return source.where(
              (d) =>
                  d.toLowerCase().contains(q) ||
                  _locationOptionLabel(d).toLowerCase().contains(q),
            );
          },
          displayStringForOption: (option) => option,
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: _darkGreenMid,
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _gold.withValues(alpha: 0.35)),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 260,
                      minWidth: 220,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: _bilingualLabel(_locationOptionLabel(option)),
                          onTap: () => onSelected(option),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
          },
          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
            if (_districtAutocompleteController.text != controller.text &&
                _selectedDistrict == null) {
              _districtAutocompleteController.text = controller.text;
            }
            if (controller.text != (_selectedDistrict ?? '')) {
              controller.text = _selectedDistrict ?? '';
              controller.selection = TextSelection.collapsed(
                offset: controller.text.length,
              );
            }

            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              enabled: !_isSubmitting,
              style: const TextStyle(color: AppColors.primaryText),
              decoration: _fieldDecoration(
                'District / ضلع',
              ).copyWith(errorText: fieldState.errorText),
              onChanged: (value) {
                final text = value.trim();
                setState(() {
                  _selectedDistrict = text.isEmpty ? null : text;
                  _selectedTehsil = null;
                  _selectedCity = null;
                  _localAreaController.clear();
                  final autoProvince = _districtToProvince[text.toLowerCase()];
                  if ((autoProvince ?? '').isNotEmpty) {
                    _selectedProvince = autoProvince;
                  }
                  _fraudPrecheck = _runFraudPrecheck();
                });
                fieldState.didChange(_selectedDistrict);
              },
            );
          },
          onSelected: (selection) {
            setState(() {
              _selectedDistrict = selection;
              _districtAutocompleteController.text = selection;
              _selectedTehsil = null;
              _selectedCity = null;
              _localAreaController.clear();
              final autoProvince = _districtToProvince[selection.toLowerCase()];
              if ((autoProvince ?? '').isNotEmpty) {
                _selectedProvince = autoProvince;
              }
              _fraudPrecheck = _runFraudPrecheck();
            });
            fieldState.didChange(selection);
            unawaited(_refreshMarketIntelligence());
          },
        );
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
            style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.82)),
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
                      });
                    },
              icon: const Icon(Icons.delete_outline, color: AppColors.primaryText),
              label: const Text(
                'Remove Trust Photo / ٹرسٹ تصویر ہٹائیں',
                style: TextStyle(color: AppColors.primaryText),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Divider(color: AppColors.primaryText.withValues(alpha: 0.2)),
          const SizedBox(height: 8),
          const Text(
            'Add verification video (optional) / اختیاری تصدیقی ویڈیو شامل کریں',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'A short live video can improve buyer trust / مختصر لائیو ویڈیو خریدار کا اعتماد بڑھا سکتی ہے',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Verified video listings may appear more trustworthy / ویڈیو والی لسٹنگ زیادہ قابلِ اعتماد محسوس ہو سکتی ہے',
            style: TextStyle(
              color: AppColors.primaryText.withValues(alpha: 0.72),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isSubmitting ? null : _recordVerificationVideo,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryText,
              side: BorderSide(color: AppColors.primaryText.withValues(alpha: 0.35)),
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
                  style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.9)),
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
              icon: const Icon(Icons.delete_outline, color: AppColors.primaryText),
              label: const Text(
                'Remove Optional Video / اختیاری ویڈیو ہٹائیں',
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
              side: BorderSide(color: AppColors.primaryText.withValues(alpha: 0.35)),
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
                              color: AppColors.ctaTextDark.withValues(alpha: 0.6),
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
              style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.86)),
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
              style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.8)),
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
              style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.8)),
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
              style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.9)),
            ),
          ],
          if (_priceDeviationPercent != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              _sellerPriceInsight.isEmpty
                  ? 'Your price is ${_priceDeviationPercent!.abs().toStringAsFixed(1)}% ${_priceDeviationPercent! >= 0 ? 'above' : 'below'} mandi average.'
                  : _sellerPriceInsight,
              style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.85)),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: AppColors.primaryText.withValues(alpha: 0.07),
              border: Border.all(color: AppColors.primaryText.withValues(alpha: 0.15)),
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
                  style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.88)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Flags: ${_fraudPrecheck.flags.isEmpty ? 'none / کوئی نہیں' : _fraudPrecheck.flags.join(', ')}',
                  style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.88)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Status: ${_fraudPrecheck.status} / اسٹیٹس',
                  style: TextStyle(color: AppColors.primaryText.withValues(alpha: 0.88)),
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
                          final mapped = _mandiTypeFromCategoryLabel(selected);
                          if (mapped == null) return;
                          setState(() {
                            _selectedMandiType = mapped;
                            _selectedProduct = null;
                            _selectedRiceVariety = null;
                            _selectedUnitType =
                                CategoryConstants.defaultUnitForMandiType(
                                  mapped,
                                );
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
                          setState(() {
                            _selectedProduct = selected;
                            if (!_isRiceCropSelected &&
                                !_isProcessedRiceSelected) {
                              _selectedRiceVariety = null;
                            }
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
                                  child: Text(u.wireValue),
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
                        decoration: _fieldDecoration('Price (Rs.) / قیمت'),
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
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Location / مقام',
                        'Select province, district, tehsil, and local area / صوبہ، ضلع، تحصیل اور مقامی علاقہ منتخب کریں',
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
                              _localAreaController.clear();
                              _fraudPrecheck = _runFraudPrecheck();
                            });
                          },
                        ),
                        second: TextFormField(
                          controller: _localAreaController,
                          style: const TextStyle(color: AppColors.primaryText),
                          decoration: _fieldDecoration(
                            'Local Area / مقامی علاقہ',
                            hint: 'City, town, mohalla / شہر، قصبہ، محلہ',
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty &&
                                (_selectedCity ?? '').trim().isEmpty) {
                              return 'Local area is required / مقامی علاقہ لازمی ہے';
                            }
                            return null;
                          },
                          onChanged: (_) {
                            setState(() {
                              _fraudPrecheck = _runFraudPrecheck();
                            });
                          },
                        ),
                      ),
                      if (_localAreaSuggestions.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: _localAreaSuggestions
                              .take(6)
                              .map(
                                (suggestion) => ActionChip(
                                  label: Text(
                                    suggestion,
                                    style: const TextStyle(color: AppColors.primaryText),
                                  ),
                                  backgroundColor: AppColors.primaryText.withValues(
                                    alpha: 0.1,
                                  ),
                                  side: BorderSide(
                                    color: AppColors.primaryText.withValues(alpha: 0.25),
                                  ),
                                  onPressed: _isSubmitting
                                      ? null
                                      : () {
                                          setState(() {
                                            _selectedCity = suggestion;
                                            _localAreaController.text =
                                                suggestion;
                                            _fraudPrecheck =
                                                _runFraudPrecheck();
                                          });
                                          unawaited(
                                            _refreshMarketIntelligence(),
                                          );
                                        },
                                ),
                              )
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 12),
                      _sectionHeader(
                        'Description / تفصیل',
                        'Add condition, quality, and delivery notes / معیار، حالت اور ترسیل کی تفصیل لکھیں',
                      ),
                      TextFormField(
                        controller: _villageController,
                        style: const TextStyle(color: AppColors.primaryText),
                        decoration: _fieldDecoration(
                          'Village / گاؤں (Optional / اختیاری)',
                          hint:
                              'Optional for rural locations / دیہی علاقوں کے لیے اختیاری',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descriptionController,
                        maxLines: 3,
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
                            style: const TextStyle(color: AppColors.primaryText),
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
                            style: const TextStyle(color: AppColors.primaryText),
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
                _buildTotalValueCard(),
                const SizedBox(height: 12),
                _buildMarketIntelligenceCard(),
                const SizedBox(height: 12),
                _buildVerificationSection(),
                const SizedBox(height: 12),
                _buildOptionalMediaSection(),
                const SizedBox(height: 12),
                _glassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Promotion / تشہیری اپ گریڈ',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Featured listings appear higher in buyer feeds / نمایاں لسٹنگ خریدار فیڈ میں اوپر دکھتی ہے',
                        style: TextStyle(
                          color: AppColors.primaryText.withValues(alpha: 0.78),
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
                            : (value) {
                                setState(() {
                                  _featuredListing = value;
                                  if (!value) {
                                    _featuredAuctionUpgrade = false;
                                  }
                                });
                              },
                        title: const Text(
                          'Featured Listing / نمایاں لسٹنگ',
                          style: TextStyle(color: AppColors.primaryText),
                        ),
                        subtitle: Text(
                          _featuredListing
                              ? 'Request fee: Rs ${PromotionPaymentConfig.featuredListingFee} | Pending review'
                              : 'Enable to request Featured Listing',
                          style: TextStyle(
                            color: AppColors.primaryText.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        activeThumbColor: _gold,
                        value: _featuredAuctionUpgrade,
                        onChanged: (_isSubmitting || !_featuredListing)
                            ? null
                            : (value) {
                                setState(() {
                                  _featuredAuctionUpgrade = value;
                                });
                              },
                        title: const Text(
                          'Featured Auction / نمایاں بولی',
                          style: TextStyle(color: AppColors.primaryText),
                        ),
                        subtitle: Text(
                          'Cost: Rs ${PromotionPaymentConfig.featuredAuctionFee} / قیمت: ${PromotionPaymentConfig.featuredAuctionFee} روپے',
                          style: TextStyle(
                            color: AppColors.primaryText.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      if (_featuredListing)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _featuredAuctionUpgrade
                                ? 'Requested promotion: Featured Auction (pending review) | Rs ${PromotionPaymentConfig.featuredAuctionFee}'
                                : 'Requested promotion: Featured Listing (pending review) | Rs ${PromotionPaymentConfig.featuredListingFee}',
                            style: TextStyle(
                              color: AppColors.primaryText.withValues(alpha: 0.78),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
