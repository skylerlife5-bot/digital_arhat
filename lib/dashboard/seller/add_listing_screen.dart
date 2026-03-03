import 'dart:io';
import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:developer' as developer; // Professional logging ke liye

// �S& Services
import '../../services/marketplace_service.dart';
import '../../services/ai_generative_service.dart';
import '../../services/market_rate_service.dart';
import '../../core/constants.dart';
import '../../core/widgets/spiritual_header.dart';
import '../components/audio_recorder_widget.dart';

class AddListingScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  const AddListingScreen({super.key, required this.userData});

  @override
  State<AddListingScreen> createState() => _AddListingScreenState();
}

class _AddListingScreenState extends State<AddListingScreen> {
  static const String _urduFont = 'Jameel Noori Nastaliq';
  static const Color _deepGreen = Color(0xFF004D40);
  static const Color _lightEmerald = Color(0xFF00695C);
  static const Color _gold = Color(0xFFFFD700);

  static final List<String> _allPakistanDistrictsCache = (() {
    final districts = AppConstants.pakistanLocations.values
        .expand((items) => items)
        .toSet()
        .toList();
    districts.sort();
    return List<String>.unmodifiable(districts);
  })();

  final _formKey = GlobalKey<FormState>();
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final MandiIntelligenceService _intelligenceService =
      MandiIntelligenceService();
  final MarketRateService _marketRateService = MarketRateService();
  final MarketplaceService _marketService = MarketplaceService();
  final ImagePicker _picker = ImagePicker();

  // --- State Variables ---
  final List<XFile> _images = [];
  XFile? _video;
  VideoPlayerController? _videoPreviewController;
  String? _recordedAudioPath;
  MandiType _selectedMandiType = MandiType.crops;
  String _selectedProduct = "Wheat (Gandum)";
  UnitType _selectedUnitType = UnitType.mann;
  ListingGrade _selectedGrade = ListingGrade.a;
  String _selectedProvince = 'Punjab';
  String _selectedDistrict = "Lahore";

  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _villageController = TextEditingController();
  final TextEditingController _fatController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // --- Market Intelligence & Calculation States ---
  double? _ruleBasedAverageRate;
  bool _isMarketEstimate = false;
  String? _marketIntelligenceError;
  String? _marketInsight;
  bool _isRateLoading = false;
  String _lastRequestedItem = '';
  bool _isSubmitting = false;
  bool _isMediaUploading = false;
  double _mediaUploadProgress = 0.0;
  Duration? _videoDuration;
  double? _videoLatitude;
  double? _videoLongitude;
  DateTime? _videoCapturedAt;
  String? _verificationVideoTag;
  double _totalValue = 0.0;

  @override
  void initState() {
    super.initState();
    _priceController.addListener(_updateCalculations);
    _quantityController.addListener(_updateCalculations);
    _weightController.addListener(_updateCalculations);
    _priceController.addListener(_refreshFormState);
    _quantityController.addListener(_refreshFormState);
    _villageController.addListener(_refreshFormState);
    _fatController.addListener(_refreshFormState);
    _breedController.addListener(_refreshFormState);
    _ageController.addListener(_refreshFormState);
    _weightController.addListener(_refreshFormState);
    _descriptionController.addListener(_refreshFormState);
    _selectedProduct = _itemsForType(_selectedMandiType).first;
    _selectedUnitType = _defaultUnitForType(_selectedMandiType);
    final initialDistricts = AppConstants.districtsForProvince(
      _selectedProvince,
    );
    if (initialDistricts.isNotEmpty) {
      _selectedDistrict = initialDistricts.first;
    }
    unawaited(
      _fetchMarketIntelligence(
        _selectedProduct,
        province: _selectedProvince,
        district: _selectedDistrict,
      ),
    );
  }

  void _refreshFormState() {
    if (!mounted) return;
    setState(() {});
  }

  void _updateCalculations() {
    final String rateText = _priceController.text.trim();
    final String quantityText = _selectedMandiType == MandiType.livestock
        ? _weightController.text.trim()
        : _quantityController.text.trim();
    final double rate = _parseDouble(rateText);
    final double quantity = _parseDouble(quantityText);

    setState(() {
      _totalValue = rate * quantity;
    });
  }

  double _parseDouble(String value) {
    if (value.isEmpty) return 0;
    try {
      return double.parse(value);
    } catch (_) {
      return 0;
    }
  }

  Future<void> _fetchMarketIntelligence(
    String itemName, {
    String? province,
    String? district,
  }) async {
    final requestedItem = itemName.trim();
    if (requestedItem.isEmpty) {
      if (!mounted) return;
      setState(() {
        _ruleBasedAverageRate = null;
        _isMarketEstimate = false;
        _marketInsight = null;
        _marketIntelligenceError = 'Market rate unavailable';
        _isRateLoading = false;
      });
      return;
    }

    setState(() {
      _isRateLoading = true;
      _isMarketEstimate = false;
      _marketIntelligenceError = null;
      _marketInsight = null;
      _lastRequestedItem = requestedItem;
    });

    try {
      final rateResult = await _intelligenceService
          .fetchMandiAverageRateWithMeta(
            requestedItem,
            province: province ?? _selectedProvince,
            district: district ?? _selectedDistrict,
          );
      final average = rateResult.rate;
      if (!mounted || _lastRequestedItem != requestedItem) return;
      if (average == null || average <= 0) {
        setState(() {
          _ruleBasedAverageRate = null;
          _isMarketEstimate = false;
          _marketInsight = null;
          _marketIntelligenceError = 'No mandi average available for this item';
          _isRateLoading = false;
        });
        return;
      }

      final recentNews = await _marketRateService.fetchRecentNewsHeadlines(
        requestedItem,
        limit: 3,
      );
      if (!mounted || _lastRequestedItem != requestedItem) return;

      final insight = await _intelligenceService.explainMarketTrend(
        cropName: requestedItem,
        movingAverage: average,
        recentNews: recentNews,
        province: province ?? _selectedProvince,
        district: district ?? _selectedDistrict,
      );
      if (!mounted || _lastRequestedItem != requestedItem) return;

      setState(() {
        _ruleBasedAverageRate = average;
        _isMarketEstimate = rateResult.isEstimate;
        _marketInsight = insight;
        _marketIntelligenceError = null;
        _isRateLoading = false;
      });
    } catch (e) {
      if (!mounted || _lastRequestedItem != requestedItem) return;
      setState(() {
        _ruleBasedAverageRate = null;
        _isMarketEstimate = false;
        _marketInsight =
            'Mandi server busy, using offline insights. Is waqt bazaar stable lag raha hai, ehtiyaat se boli lagayen.';
        _marketIntelligenceError = 'Mandi server busy, using offline insights';
        _isRateLoading = false;
      });
    }
  }

  List<String> _itemsForType(MandiType type) {
    return CategoryConstants.itemsForMandiType(type);
  }

  UnitType _defaultUnitForType(MandiType type) {
    return CategoryConstants.defaultUnitForMandiType(type);
  }

  List<UnitType> _allowedUnitsForType(MandiType type) {
    return CategoryConstants.allowedUnitsForMandiType(type);
  }

  List<String> _allPakistanDistricts() {
    return _allPakistanDistrictsCache;
  }

  String? _provinceForDistrict(String district) {
    for (final entry in AppConstants.pakistanLocations.entries) {
      if (entry.value.contains(district)) {
        return entry.key;
      }
    }
    return null;
  }

  String _calculatorFormula() {
    final String rateText = _priceController.text.trim();
    final String quantityText = _selectedMandiType == MandiType.livestock
        ? _weightController.text.trim()
        : _quantityController.text.trim();
    final double rate = _parseDouble(rateText);
    final double quantity = _parseDouble(quantityText);
    final double totalPrice = rate * quantity;
    return 'Rs. ${rate.toStringAsFixed(0)} x ${quantity.toStringAsFixed(0)} = Rs. ${totalPrice.toStringAsFixed(0)}';
  }

  String? _priceDeviationTip() {
    final avg = _ruleBasedAverageRate;
    if (avg == null || avg <= 0) return null;
    final entered = double.tryParse(_priceController.text.trim()) ?? 0.0;
    if (entered <= 0) return null;

    final deviationPercent = ((entered - avg).abs() / avg) * 100;
    if (deviationPercent < 15) return null;
    return 'Your price is ${deviationPercent.toStringAsFixed(1)}% off the current mandi average.';
  }

  // --- Submission Logic ---
  Future<void> _handleSubmission() async {
    FocusScope.of(context).unfocus();

    if (!_canSubmit) {
      _showInfoSnackBar('Please complete all required fields before posting.');
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Submitting to Mandi...')));

    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    // Logging using developer.log instead of print (Professional approach)
    developer.log("Processing listing for: ${widget.userData['name']}");

    final Map<String, dynamic> listingData = {
      'sellerId': widget.userData['uid'],
      'mandiType': _selectedMandiType.wireValue,
      'category': _selectedMandiType.wireValue,
      'product': _selectedProduct,
      'itemName': _selectedProduct,
      'cropType': _selectedProduct,
      'quantity': _quantityController.text,
      'unit': _selectedUnitType.wireValue,
      'unitType': _selectedUnitType.wireValue,
      'price': _priceController.text,
      'estimatedValue': _totalValue,
      'description': _descriptionController.text.trim(),
      'grade':
          (_selectedMandiType == MandiType.fruit ||
              _selectedMandiType == MandiType.vegetables)
          ? _selectedGrade.wireValue
          : null,
      'breed': _selectedMandiType == MandiType.livestock
          ? _breedController.text.trim()
          : null,
      'age': _selectedMandiType == MandiType.livestock
          ? _ageController.text.trim()
          : null,
      'weight': _selectedMandiType == MandiType.livestock
          ? double.tryParse(_weightController.text.trim())
          : null,
      'fatPercentage': _selectedMandiType == MandiType.milk
          ? double.tryParse(_fatController.text.trim())
          : null,
      'province': _selectedProvince,
      'district': _selectedDistrict,
      'location':
          '${_villageController.text.trim()}, $_selectedDistrict, $_selectedProvince',
      'locationData': {
        'province': _selectedProvince,
        'district': _selectedDistrict,
        'village': _villageController.text.trim(),
      },
      'audioPath': _recordedAudioPath, // Using the field here
      'images': _images.map((img) => img.path).toList(),
      'video': _video?.path,
      'isVerifiedSource': true,
      'verificationGeo': {'lat': _videoLatitude, 'lng': _videoLongitude},
      'verificationCapturedAt': _videoCapturedAt?.toIso8601String(),
      'verificationVideoTag': _verificationVideoTag,
    };

    try {
      // Using _marketService here to fix unused_field
      setState(() {
        _isMediaUploading =
            _images.isNotEmpty || _video != null || _recordedAudioPath != null;
        _mediaUploadProgress = 0.0;
      });

      await _marketService
          .createListing(
            listingData,
            onMediaUploadProgress: (progress) {
              if (!mounted) return;
              setState(() => _mediaUploadProgress = progress.clamp(0.0, 1.0));
            },
          )
          .timeout(const Duration(minutes: 2));

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      developer.log("Upload error: $e");
      final quotaExceeded = _isQuotaExceededError(e);
      if (quotaExceeded) {
        try {
          await _saveTextOnlyListingFallback(listingData);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
                content: Text(
                  'Storage quota exceeded. Text listing saved successfully.',
                ),
              ),
            );
            Navigator.pop(context);
          }
          return;
        } catch (fallbackError) {
          developer.log('Fallback save error: $fallbackError');
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), content: Text('Upload failed, try again')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isMediaUploading = false;
        });
      }
    }
  }

  bool _isQuotaExceededError(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('quota') && message.contains('exceed');
  }

  Future<void> _saveTextOnlyListingFallback(Map<String, dynamic> data) async {
    final sellerId = (widget.userData['uid'] ?? '').toString().trim();
    if (sellerId.isEmpty) {
      throw Exception('Seller id missing');
    }

    final fallbackData = <String, dynamic>{
      'sellerId': sellerId,
      'sellerName': widget.userData['name'] ?? 'Kisan Bhai',
      'mandiType': data['mandiType'] ?? MandiType.crops.wireValue,
      'category': data['category'],
      'product': data['product'],
      'itemName': data['itemName'],
      'cropType': data['cropType'],
      'quantity': data['quantity'],
      'unit': data['unit'],
      'unitType': data['unitType'],
      'price': double.tryParse(data['price'].toString()) ?? 0,
      'estimatedValue': double.tryParse(data['estimatedValue'].toString()) ?? 0,
      'description': data['description'],
      'grade': data['grade'],
      'breed': data['breed'],
      'age': data['age'],
      'weight': data['weight'],
      'fatPercentage': data['fatPercentage'],
      'province': data['province'],
      'district': data['district'],
      'location': data['location'],
      'locationData': data['locationData'],
      'imageUrl': '',
      'videoUrl': '',
      'audioUrl': '',
      'isVerifiedSource': false,
      'status': 'pending',
      'isSuspicious': false,
      'suspiciousReason': '',
      'isApproved': false,
      'startTime': null,
      'endTime': null,
      'highestBid': null,
      'highestBidAt': null,
      'totalBids': 0,
      'isBidForceClosed': false,
      'bidClosedAt': null,
      'approvedAt': null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final listingId =
        '${sellerId}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    await _db
        .collection('listings')
        .doc(listingId)
        .set(fallbackData, SetOptions(merge: true));
  }

  @override
  void dispose() {
    _priceController.dispose();
    _quantityController.dispose();
    _villageController.dispose();
    _fatController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _descriptionController.dispose();
    _videoPreviewController?.dispose();
    unawaited(VideoCompress.deleteAllCache());
    super.dispose();
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(duration: const Duration(seconds: 5), content: Text(message)));
  }

  Future<void> _prepareVideoPreview(String filePath) async {
    try {
      await _videoPreviewController?.dispose();
      final controller = VideoPlayerController.file(File(filePath));
      await controller.initialize();
      controller.setLooping(true);
      controller.pause();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoPreviewController = controller;
        _videoDuration = controller.value.duration;
      });
    } catch (e) {
      _showInfoSnackBar('Video preview load nahi ho saki.');
    }
  }

  Future<String> _buildVerifiedVideoFilePath(String sourcePath) async {
    final tempDir = await getTemporaryDirectory();
    final capturedAt = _videoCapturedAt ?? DateTime.now().toUtc();
    final timestamp = capturedAt
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final lat = (_videoLatitude ?? 0).toStringAsFixed(5);
    final lng = (_videoLongitude ?? 0).toStringAsFixed(5);
    final fileName = 'verified_${timestamp}_${lat}_$lng.mp4';
    final targetPath = '${tempDir.path}/$fileName';
    await File(sourcePath).copy(targetPath);
    _verificationVideoTag = fileName;
    return targetPath;
  }

  Future<void> _removeVerificationVideo() async {
    try {
      await _videoPreviewController?.dispose();
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _video = null;
      _videoPreviewController = null;
      _videoDuration = null;
      _videoLatitude = null;
      _videoLongitude = null;
      _videoCapturedAt = null;
      _verificationVideoTag = null;
    });
  }

  Future<void> _captureVerificationGeo() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showInfoSnackBar(
          'Location service off hai. Verification GPS attach nahi ho saka.',
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showInfoSnackBar(
          'Location permission denied. GPS proof attach nahi ho saka.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _videoLatitude = position.latitude;
        _videoLongitude = position.longitude;
      });
    } catch (e) {
      _showInfoSnackBar('GPS capture mein masla aya.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _deepGreen,
      appBar: AppBar(
        title: Text(
          "Add New Listing",
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: Colors.white,
            fontSize: 17,
            fontFamily: _urduFont,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SizedBox.expand(
        child: Stack(
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_deepGreen, _lightEmerald],
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      15,
                      8,
                      15,
                      MediaQuery.of(context).padding.bottom + 8,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.68),
                              width: 1,
                            ),
                          ),
                          child: SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              MediaQuery.of(context).viewInsets.bottom + 20,
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SpiritualHeader(
                                    backgroundColor: Color(0x1400C853),
                                    borderColor: Color(0x5500C853),
                                  ),
                                  const SizedBox(height: 15),
                                  SizedBox(
                                    width: double.infinity,
                                    child: _buildMediaHubSection(),
                                  ),
                                  const SizedBox(height: 15),
                                  _buildDropdown(
                                    _selectedMandiType.wireValue,
                                    MandiType.values
                                        .map((type) => type.wireValue)
                                        .toList(),
                                    (val) {
                                      if (val == null) return;
                                      HapticFeedback.lightImpact();
                                      final selected = MandiType.values
                                          .firstWhere(
                                            (type) => type.wireValue == val,
                                          );
                                      final products = _itemsForType(selected);
                                      setState(() {
                                        _selectedMandiType = selected;
                                        _selectedProduct = products.first;
                                        _selectedUnitType = _defaultUnitForType(
                                          selected,
                                        );
                                        _selectedGrade = ListingGrade.a;
                                        _fatController.clear();
                                        _breedController.clear();
                                        _ageController.clear();
                                        _weightController.clear();
                                        _quantityController.clear();
                                      });
                                      unawaited(
                                        _fetchMarketIntelligence(
                                          _selectedProduct,
                                          province: _selectedProvince,
                                          district: _selectedDistrict,
                                        ),
                                      );
                                    },
                                    'Category / �س�&',
                                    _mandiTypeDisplay,
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildSearchableSelectorField(
                                          label: "Item / � �Rز",
                                          selectedValue: _selectedProduct,
                                          items: _itemsForType(
                                            _selectedMandiType,
                                          ),
                                          onSelected: (value) {
                                            HapticFeedback.lightImpact();
                                            setState(
                                              () => _selectedProduct = value,
                                            );
                                            unawaited(
                                              _fetchMarketIntelligence(
                                                value,
                                                province: _selectedProvince,
                                                district: _selectedDistrict,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      if (_selectedMandiType ==
                                              MandiType.fruit ||
                                          _selectedMandiType ==
                                              MandiType.vegetables) ...[
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildDropdown(
                                            _selectedGrade.wireValue,
                                            ListingGrade.values
                                                .map((g) => g.wireValue)
                                                .toList(),
                                            (val) {
                                              if (val == null) return;
                                              HapticFeedback.lightImpact();
                                              setState(() {
                                                _selectedGrade = ListingGrade
                                                    .values
                                                    .firstWhere(
                                                      (grade) =>
                                                          grade.wireValue ==
                                                          val,
                                                    );
                                              });
                                            },
                                            "Quality Grade / �&ع�Rار",
                                            _gradeDisplay,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 15),
                                  if (_selectedMandiType == MandiType.milk)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInputField(
                                            _fatController,
                                            "Fat Content (%) / Chiknai",
                                            Icons.opacity,
                                            isNumber: true,
                                            validator: (val) {
                                              if (_selectedMandiType !=
                                                  MandiType.milk) {
                                                return null;
                                              }
                                              final value = (val ?? '').trim();
                                              final parsed = double.tryParse(
                                                value,
                                              );
                                              if (parsed == null ||
                                                  parsed <= 0) {
                                                return 'Fat % zaroori hai';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(child: _buildQuantityField()),
                                      ],
                                    )
                                  else if (_selectedMandiType ==
                                      MandiType.livestock)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _buildInputField(
                                            _ageController,
                                            "Age (Years) / Umar",
                                            Icons.cake_outlined,
                                            isNumber: true,
                                            validator: (val) {
                                              if (_selectedMandiType !=
                                                  MandiType.livestock) {
                                                return null;
                                              }
                                              final value = (val ?? '').trim();
                                              final parsed = double.tryParse(
                                                value,
                                              );
                                              if (parsed == null ||
                                                  parsed <= 0) {
                                                return 'Umar lazmi hai';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _buildInputField(
                                            _breedController,
                                            "Breed / Nasl",
                                            Icons.pets,
                                            isNumber: false,
                                            validator: (val) {
                                              if (_selectedMandiType !=
                                                  MandiType.livestock) {
                                                return null;
                                              }
                                              if ((val ?? '').trim().isEmpty) {
                                                return 'Nasl lazmi hai';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    )
                                  else
                                    Row(
                                      children: [
                                        Expanded(child: _buildQuantityField()),
                                      ],
                                    ),
                                  if (_selectedMandiType ==
                                      MandiType.livestock) ...[
                                    const SizedBox(height: 15),
                                    _buildInputField(
                                      _weightController,
                                      "Weight (KG) / Wazan",
                                      Icons.monitor_weight,
                                      isNumber: true,
                                      validator: (val) {
                                        if (_selectedMandiType !=
                                            MandiType.livestock) {
                                          return null;
                                        }
                                        final value = (val ?? '').trim();
                                        final parsed = double.tryParse(value);
                                        if (parsed == null || parsed <= 0) {
                                          return 'Wazan lazmi hai';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 15),
                                  _buildInputField(
                                    _descriptionController,
                                    "Detailed Description / Tafseeli Bayaan",
                                    Icons.description_outlined,
                                    isNumber: false,
                                    maxLines: 4,
                                    validator: (val) {
                                      if ((val ?? '').trim().isEmpty) {
                                        return 'Tafseeli bayaan lazmi hai';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: _buildInputField(
                                          _priceController,
                                          "Rate / ر�Rٹ",
                                          Icons.payments,
                                          isNumber: true,
                                          isPrice: true,
                                          validator: (val) {
                                            final value = (val ?? '').trim();
                                            final parsed = double.tryParse(
                                              value,
                                            );
                                            if (parsed == null || parsed <= 0) {
                                              return 'Rate lazmi hai';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: _buildUnitDropdown(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _buildMarketIntelligenceBadge(_gold),
                                  if (_marketInsight != null &&
                                      _marketInsight!.trim().isNotEmpty)
                                    _buildMandiInsightCard(),
                                  if (_priceDeviationTip() != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        _priceDeviationTip()!,
                                        style: const TextStyle(
                                          color: Colors.orangeAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  if (_totalValue > 0)
                                    _buildTotalValueCard(_gold),
                                  const SizedBox(height: 15),
                                  _buildSectionTitle(
                                    "Location / Mandi ki Jagah",
                                  ),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 2,
                                        child: _buildSearchableSelectorField(
                                          label: "Province / ص��بہ",
                                          selectedValue: _selectedProvince,
                                          items: AppConstants.provinces,
                                          onSelected: (value) {
                                            HapticFeedback.lightImpact();
                                            final districts =
                                                AppConstants.districtsForProvince(
                                                  value,
                                                );
                                            setState(() {
                                              _selectedProvince = value;
                                              if (districts.contains(
                                                _selectedDistrict,
                                              )) {
                                                return;
                                              }
                                              _selectedDistrict =
                                                  districts.isNotEmpty
                                                  ? districts.first
                                                  : '';
                                            });
                                            if (_selectedProduct
                                                .trim()
                                                .isNotEmpty) {
                                              unawaited(
                                                _fetchMarketIntelligence(
                                                  _selectedProduct,
                                                  province: _selectedProvince,
                                                  district: _selectedDistrict,
                                                ),
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        flex: 2,
                                        child: _buildSearchableDistrictField(),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 15),
                                  Row(
                                    children: [
                                      Expanded(
                                        flex: 4,
                                        child: _buildInputField(
                                          _villageController,
                                          "Village / گاؤں",
                                          Icons.home,
                                          isNumber: false,
                                          validator: (value) {
                                            if ((value ?? '').trim().isEmpty) {
                                              return 'Gaon ka naam lazmi hai';
                                            }
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 15),
                                  _buildSubmitButton(),
                                  const SizedBox(height: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- UI Components ---

  String _mandiTypeDisplay(String value) {
    switch (value) {
      case 'crops':
        return 'Crops (Galla / Faslain)';
      case 'livestock':
        return 'Livestock (Maweshi)';
      case 'fruits':
        return 'Fruits (Phal)';
      case 'vegetables':
        return 'Vegetables (Sabziyan)';
      case 'milk':
        return 'Milk (Doodh)';
      default:
        return value;
    }
  }

  String _gradeDisplay(String value) {
    return 'Grade ${value.toUpperCase()}';
  }

  String _unitDisplay(String value) {
    switch (value) {
      case 'KG':
      case 'kg':
        return 'Kilogram (Kilo)';
      case 'Mann':
      case 'mann':
        return 'Mann (40kg)';
      case 'Litre':
      case 'litre':
        return 'Litre (Litr)';
      case 'Peti':
      case 'piece':
        return 'Petti/Crate (Petti)';
      default:
        return value;
    }
  }

  bool get _canSubmit {
    if (_isSubmitting) return false;
    if (_selectedProduct.trim().isEmpty) return false;
    if (_selectedProvince.trim().isEmpty || _selectedDistrict.trim().isEmpty) {
      return false;
    }
    if (_villageController.text.trim().isEmpty) return false;
    if (_descriptionController.text.trim().isEmpty) return false;
    final rate = double.tryParse(_priceController.text.trim());
    if (rate == null || rate <= 0) return false;

    if (_selectedMandiType == MandiType.livestock) {
      if (_breedController.text.trim().isEmpty) return false;
      final age = double.tryParse(_ageController.text.trim());
      final weight = double.tryParse(_weightController.text.trim());
      if (age == null || age <= 0) return false;
      if (weight == null || weight <= 0) return false;
      return true;
    }

    if (_selectedMandiType == MandiType.milk) {
      final fat = double.tryParse(_fatController.text.trim());
      final qty = double.tryParse(_quantityController.text.trim());
      if (fat == null || fat <= 0) return false;
      if (qty == null || qty <= 0) return false;
      return true;
    }

    final qty = double.tryParse(_quantityController.text.trim());
    return qty != null && qty > 0;
  }

  Widget _buildMarketIntelligenceBadge(Color gold) {
    return Container(
      constraints: const BoxConstraints(minWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isRateLoading
              ? Colors.cyanAccent
              : ((_ruleBasedAverageRate != null && _ruleBasedAverageRate! > 0)
                    ? gold.withValues(alpha: 0.55)
                    : Colors.white30),
        ),
      ),
      child: _isRateLoading
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Analysis loading (Tajzia load ho raha hai)...',
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                      width: 120,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: 1200.ms,
                      color: Colors.white.withValues(alpha: 0.45),
                    ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isMarketEstimate
                      ? 'Market Estimate'
                      : 'Mandi Average (Mandi Osat)',
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
                const SizedBox(height: 3),
                if (_ruleBasedAverageRate != null && _ruleBasedAverageRate! > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Rs. ${_ruleBasedAverageRate!.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: _isMarketEstimate ? Colors.orangeAccent : gold,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color:
                              (_isMarketEstimate
                                      ? Colors.orangeAccent
                                      : Colors.greenAccent)
                                  .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                (_isMarketEstimate
                                        ? Colors.orangeAccent
                                        : Colors.greenAccent)
                                    .withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isMarketEstimate
                                  ? Icons.query_stats
                                  : Icons.verified,
                              size: 11,
                              color: _isMarketEstimate
                                  ? Colors.orangeAccent
                                  : Colors.greenAccent,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _isMarketEstimate
                                  ? 'Estimate'
                                  : 'Verified (Tasdeeq Shuda)',
                              style: TextStyle(
                                color: _isMarketEstimate
                                    ? Colors.orangeAccent
                                    : Colors.greenAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  GestureDetector(
                    onTap: () =>
                        unawaited(_fetchMarketIntelligence(_selectedProduct)),
                    child: Text(
                      _marketIntelligenceError ?? 'Rate unavailable',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMandiInsightCard() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.cyanAccent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Market Insight (Market ki Soorat-e-haal)',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _marketInsight!,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalValueCard(Color gold) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: gold.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: gold.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Rate x Quantity = Total Price (Kul Raqam)',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            _calculatorFormula(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Rs. ${_totalValue.toStringAsFixed(0)}",
            style: TextStyle(
              color: gold,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchableSelectorField({
    required String label,
    required String selectedValue,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        _showSearchableSelectionSheet(
          title: '$label Select Karein',
          items: items,
          onSelected: onSelected,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B2F18).withValues(alpha: 0.64),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: _urduFont,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    selectedValue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      fontFamily: _urduFont,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.search, color: Color(0xFFFFD700), size: 18),
          ],
        ),
      ),
    );
  }

  void _showSearchableSelectionSheet({
    required String title,
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    final TextEditingController searchController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF011A0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text.trim().toLowerCase();
            final filtered = items
                .where((item) => item.toLowerCase().contains(query))
                .toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.70,
                  child: Column(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFFFD700),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: searchController,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (_) => setModalState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: Color(0xFFFFD700),
                          ),
                          filled: true,
                          fillColor: const Color(
                            0xFF0B2F18,
                          ).withValues(alpha: 0.70),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: const Color(
                                0xFFFFD700,
                              ).withValues(alpha: 0.18),
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFFFD700),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return ListTile(
                              title: Text(
                                item,
                                style: const TextStyle(color: Colors.white),
                              ),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                onSelected(item);
                                Navigator.pop(sheetContext);
                              },
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
    ).whenComplete(searchController.dispose);
  }

  void _openAudioRecorderSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF011A0A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AudioNoteWidget(
              onRecordingComplete: (path) {
                setState(() => _recordedAudioPath = path);
                Navigator.of(sheetContext).pop();
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaHubSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Media Section / �&�R���Rا س�Rکش� '),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _buildMediaActionButton(
                  icon: Icons.add_a_photo_outlined,
                  label: '�x� تص���Rر',
                  onTap: _pickImages,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _buildProductVideoWidget()),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMediaActionButton(
                  icon: Icons.mic_none_rounded,
                  label: '�x}� آ���R��',
                  onTap: _openAudioRecorderSheet,
                ),
              ),
            ],
          ),
        ),
        if (_images.isNotEmpty || _video != null || _recordedAudioPath != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (_images.isNotEmpty)
                  _buildMediaThumb(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_images.first.path),
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                      ),
                    ),
                    onDelete: () => setState(() => _images.clear()),
                  ),
                if (_recordedAudioPath != null)
                  _buildMediaThumb(
                    child: const Center(
                      child: Icon(Icons.audiotrack, color: Colors.white70),
                    ),
                    onDelete: () => setState(() => _recordedAudioPath = null),
                  ),
              ],
            ),
          ),
        if (_isMediaUploading) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _mediaUploadProgress > 0 ? _mediaUploadProgress : null,
            color: const Color(0xFFFFD700),
            backgroundColor: Colors.white12,
          ),
        ],
      ],
    );
  }

  Widget _buildProductVideoWidget() {
    final hasVideo = _video != null;

    return GestureDetector(
      onTap: _isSubmitting ? null : _pickVideo,
      child: Container(
        height: 86,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasVideo ? Colors.greenAccent : Colors.white24,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasVideo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child:
                          _videoPreviewController != null &&
                              _videoPreviewController!.value.isInitialized
                          ? VideoPlayer(_videoPreviewController!)
                          : const Center(
                              child: Icon(
                                Icons.videocam,
                                color: Colors.white70,
                              ),
                            ),
                    )
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          color: Color(0xFFFFD700),
                          size: 22,
                        ),
                        SizedBox(height: 4),
                        Text(
                          '�x}� ���R���R��',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
            ),
            if (hasVideo)
              Positioned(
                top: 3,
                right: 3,
                child: GestureDetector(
                  onTap: _removeVerificationVideo,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: _gold, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaThumb({
    required Widget child,
    required VoidCallback onDelete,
  }) {
    return SizedBox(
      width: 86,
      height: 86,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              clipBehavior: Clip.antiAlias,
              child: child,
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    required bool isNumber,
    bool isPrice = false,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      onTap: () => HapticFeedback.lightImpact(),
      style: TextStyle(
        color: isPrice ? _gold : Colors.white,
        fontSize: isPrice ? 26 : 16,
        fontWeight: isPrice ? FontWeight.w900 : FontWeight.w600,
        fontFamily: _urduFont,
      ),
      validator:
          validator ??
          (val) => val == null || val.trim().isEmpty ? 'Required hai' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: isPrice ? _gold : Colors.white70,
          fontSize: isPrice ? 26 : 14,
          fontWeight: isPrice ? FontWeight.w900 : FontWeight.bold,
          fontFamily: _urduFont,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFFFFD700), size: 18),
        prefixText: isPrice ? "Rs. " : null,
        prefixStyle: const TextStyle(
          color: _gold,
          fontFamily: _urduFont,
          fontSize: 26,
          fontWeight: FontWeight.w900,
        ),
        filled: true,
        fillColor: isPrice
            ? _lightEmerald.withValues(alpha: 0.30)
            : Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _gold, width: isPrice ? 2.2 : 1.3),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
        contentPadding: EdgeInsets.symmetric(
          vertical: maxLines > 1 ? 14 : 12,
          horizontal: 12,
        ),
      ),
    );
  }

  Widget _buildDropdown(
    String initialValue,
    List<String> items,
    Function(String?) onChanged,
    String label, [
    String Function(String)? displayTextBuilder,
  ]) {
    return DropdownButtonFormField<String>(
      initialValue: initialValue,
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(
                displayTextBuilder?.call(e) ?? e,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: onChanged,
      dropdownColor: const Color(0xFF011A0A),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        fontFamily: _urduFont,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          fontFamily: _urduFont,
        ),
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 1.3),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white24),
        ),
      ),
    );
  }

  Widget _buildQuantityField() {
    final isMilk = _selectedMandiType == MandiType.milk;
    final label =
        _selectedMandiType == MandiType.crops &&
            _selectedUnitType == UnitType.mann
        ? "Quantity (KG) / �&�دار"
        : "Quantity / �&�دار";

    return _buildInputField(
      _quantityController,
      label,
      isMilk ? Icons.local_drink : Icons.inventory_2,
      isNumber: true,
      validator: (val) {
        if (_selectedMandiType == MandiType.livestock) {
          return null;
        }
        final value = (val ?? '').trim();
        final parsed = double.tryParse(value);
        if (parsed == null || parsed <= 0) {
          return isMilk ? 'Litre miqdar lazmi hai' : 'Miqdar lazmi hai';
        }
        return null;
      },
    );
  }

  Widget _buildUnitDropdown() {
    return _buildDropdown(
      _selectedUnitType.wireValue,
      _allowedUnitsForType(_selectedMandiType).map((u) => u.wireValue).toList(),
      (val) {
        if (val == null) return;
        HapticFeedback.lightImpact();
        setState(() {
          _selectedUnitType = UnitType.values.firstWhere(
            (unit) => unit.wireValue == val,
          );
        });
      },
      "Unit / پ�R�&ا� ہ",
      _unitDisplay,
    );
  }

  Widget _buildSearchableDistrictField() {
    final districtItems = _allPakistanDistricts();
    final selected = districtItems.contains(_selectedDistrict)
        ? _selectedDistrict
        : (districtItems.isNotEmpty
              ? districtItems.first
              : 'District Select Karein');

    return Autocomplete<String>(
      key: ValueKey('district_${_selectedProvince}_$selected'),
      initialValue: TextEditingValue(text: selected),
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) return districtItems;
        return districtItems.where(
          (item) => item.toLowerCase().contains(query),
        );
      },
      onSelected: (value) {
        HapticFeedback.lightImpact();
        final matchedProvince = _provinceForDistrict(value);
        setState(() {
          _selectedDistrict = value;
          if (matchedProvince != null) {
            _selectedProvince = matchedProvince;
          }
        });
        if (_selectedProduct.trim().isNotEmpty) {
          unawaited(
            _fetchMarketIntelligence(
              _selectedProduct,
              province: _selectedProvince,
              district: _selectedDistrict,
            ),
          );
        }
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            labelText: 'District / ض�ع',
            labelStyle: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: _urduFont,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: Color(0xFFFFD700),
              size: 18,
            ),
            filled: true,
            fillColor: const Color(0xFF0B2F18).withValues(alpha: 0.64),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: const Color(0xFFFFD700).withValues(alpha: 0.20),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Color(0xFFFFD700),
                width: 1.5,
              ),
            ),
          ),
          onFieldSubmitted: (_) => onFieldSubmitted(),
          validator: (value) => (value == null || value.trim().isEmpty)
              ? 'District Select Karein'
              : null,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final choices = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: const Color(0xFF011A0A),
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 380),
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: choices.length,
                itemBuilder: (context, index) {
                  final item = choices[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      item,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    onTap: () => onSelected(item),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFFFD700),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFamily: _urduFont,
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    final List<XFile> selected = await _picker.pickMultiImage(imageQuality: 50);
    if (selected.isNotEmpty) {
      setState(() {
        if (_images.length < 3) {
          _images.addAll(selected.take(3 - _images.length));
        }
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? recorded = await _picker.pickVideo(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
        maxDuration: const Duration(seconds: 15),
      );

      if (recorded == null) return;
      _videoCapturedAt = DateTime.now().toUtc();

      await _prepareVideoPreview(recorded.path);
      final durationSeconds = _videoDuration?.inSeconds ?? 0;
      if (durationSeconds < 5 || durationSeconds > 15) {
        _showInfoSnackBar(
          'Verification video 5 se 15 seconds ke darmiyan record karein.',
        );
        await _removeVerificationVideo();
        return;
      }

      final MediaInfo? compressed = await VideoCompress.compressVideo(
        recorded.path,
        quality: VideoQuality.MediumQuality,
        includeAudio: true,
        deleteOrigin: false,
      );

      String finalPath = recorded.path;
      int finalSize = File(recorded.path).lengthSync();

      if (compressed?.path != null && compressed!.path!.isNotEmpty) {
        finalPath = compressed.path!;
        finalSize = compressed.filesize ?? File(finalPath).lengthSync();
      }

      if (finalSize > 10 * 1024 * 1024) {
        _showInfoSnackBar(
          'Video size 10MB se zyada hai. Choti video dobara record karein.',
        );
        await _removeVerificationVideo();
        return;
      }

      await _captureVerificationGeo();
      if (_videoLatitude == null || _videoLongitude == null) {
        await _removeVerificationVideo();
        return;
      }

      final taggedPath = await _buildVerifiedVideoFilePath(finalPath);
      await _prepareVideoPreview(taggedPath);

      if (!mounted) return;
      setState(() {
        _video = XFile(taggedPath);
      });
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (code.contains('camera_access_denied') ||
          code.contains('camera_access_denied_without_prompt')) {
        _showInfoSnackBar(
          'Camera permission denied. Settings se camera allow karke dobara koshish karein.',
        );
      } else {
        _showInfoSnackBar('Video recording start nahi ho saki.');
      }
    } catch (e) {
      _showInfoSnackBar('Verification video record karte waqt masla aya.');
    }
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFF00695C)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _isSubmitting
              ? null
              : () {
                  setState(() {});
                  developer.log('Submit Button Pressed');
                  developer.log(
                    'Form Validation Status: ${_formKey.currentState?.validate()}',
                  );
                  _handleSubmission();
                },
          child: _isSubmitting
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Post Ad / پ��سٹ ا�R��',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFamily: _urduFont,
                  ),
                ),
        ),
      ),
    );
  }
}

