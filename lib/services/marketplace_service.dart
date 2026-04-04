import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

// Aapke projects ke relative imports
import '../ai/price_deviation_flagger.dart';
import '../bidding/bid_model.dart';
import '../core/constants.dart';
import '../firebase_options.dart';
import 'ai_generative_service.dart';
import 'auction_lifecycle_service.dart';
import 'bid_eligibility_service.dart';
import 'bidding_logic_engine.dart';
import 'market_rate_service.dart';
import 'phase1_notification_engine.dart';
import 'trust_safety_service.dart';

class MarketplaceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final PriceDeviationFlagger _flagger = PriceDeviationFlagger();
  final MarketRateService _marketRateService = MarketRateService();
  final MandiIntelligenceService _intelligenceService =
      MandiIntelligenceService();
  final Phase1NotificationEngine _phase1Notifications =
      Phase1NotificationEngine();
  final AuctionLifecycleService _auctionLifecycleService =
      AuctionLifecycleService();
  static const String _bidProbeListingId = 'XqRWvNzhZiE9nS6txc4N';
  static const bool _bidProbeEnabled = false;

  static const String _canonicalMandiRatesCollection =
      AppConstants.mandiRatesCollection;
  static const String _legacyMandiRatesCollection =
      AppConstants.pakistanMandiRatesCollection;

  static const List<_MandiSyncItem> _defaultMandiSyncItems = <_MandiSyncItem>[
    _MandiSyncItem(itemName: 'Wheat', mandiType: MandiType.crops),
    _MandiSyncItem(itemName: 'Rice', mandiType: MandiType.crops),
    _MandiSyncItem(itemName: 'Cotton', mandiType: MandiType.crops),
    _MandiSyncItem(itemName: 'Corn', mandiType: MandiType.crops),
    _MandiSyncItem(itemName: 'Cow Milk', mandiType: MandiType.milk),
    _MandiSyncItem(itemName: 'Goat', mandiType: MandiType.livestock),
    _MandiSyncItem(itemName: 'Mango', mandiType: MandiType.fruit),
    _MandiSyncItem(itemName: 'Potato', mandiType: MandiType.vegetables),
  ];

  // --- Singleton Pattern ---
  MarketplaceService._internal();
  static final MarketplaceService _instance = MarketplaceService._internal();
  factory MarketplaceService() => _instance;

  String _normalizeCropDocId(String cropName) {
    return cropName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  String _buildMandiRateDocId(MandiType mandiType, String itemName) {
    return '${mandiType.wireValue.toLowerCase()}_${_normalizeCropDocId(itemName)}';
  }

  MandiType _inferMandiTypeFromName(String itemName) {
    final key = itemName.trim().toLowerCase();
    const milkTerms = <String>{'milk', 'doodh'};
    const livestockTerms = <String>{
      'goat',
      'bakra',
      'cow',
      'bull',
      'bail',
      'buffalo',
      'bhains',
    };
    const fruitTerms = <String>{
      'mango',
      'aam',
      'apple',
      'seb',
      'banana',
      'kela',
    };
    const vegetableTerms = <String>{
      'potato',
      'aloo',
      'onion',
      'pyaz',
      'tomato',
      'tamatar',
    };

    if (milkTerms.any(key.contains)) return MandiType.milk;
    if (livestockTerms.any(key.contains)) return MandiType.livestock;
    if (fruitTerms.any(key.contains)) return MandiType.fruit;
    if (vegetableTerms.any(key.contains)) return MandiType.vegetables;
    return MandiType.crops;
  }

  double _fallbackAverageByType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return 4200;
      case MandiType.fruit:
        return 5200;
      case MandiType.vegetables:
        return 3600;
      case MandiType.flowers:
        return 4800;
      case MandiType.livestock:
        return 120000;
      case MandiType.milk:
        return 2500;
      case MandiType.seeds:
        return 6200;
      case MandiType.fertilizer:
        return 6800;
      case MandiType.machinery:
        return 150000;
      case MandiType.tools:
        return 18000;
      case MandiType.dryFruits:
        return 3200;
      case MandiType.spices:
        return 1400;
    }
  }

  Future<void> syncPakistanMandiRates({
    List<String>? crops,
    MandiType? forcedType,
  }) async {
    final items = crops != null
        ? crops
              .where((crop) => crop.trim().isNotEmpty)
              .map(
                (crop) => _MandiSyncItem(
                  itemName: crop.trim(),
                  mandiType: forcedType ?? _inferMandiTypeFromName(crop),
                ),
              )
              .toList()
        : _defaultMandiSyncItems;

    for (final item in items) {
      if (item.itemName.isEmpty) {
        continue;
      }

      try {
        final docId = _buildMandiRateDocId(item.mandiType, item.itemName);

        final rateSnapshot = await _marketRateService
            .fetchRuleBasedRateSnapshot(item.itemName);
        double? average = rateSnapshot?['average'];
        double? min = rateSnapshot?['min'];
        double? max = rateSnapshot?['max'];
        String source = 'RULE_BASED_MOVING_AVERAGE';

        if (average == null ||
            min == null ||
            max == null ||
            average <= 0 ||
            min <= 0 ||
            max <= 0) {
          final existingDoc = await _readMandiRateDoc(docId);
          final existing = existingDoc.data() ?? <String, dynamic>{};
          final existingAverage = _toDouble(existing['average']);

          if (existingAverage != null && existingAverage > 0) {
            average = existingAverage;
            min = existingAverage;
            max = existingAverage;
            source = 'CACHED_FALLBACK';
          } else {
            final fallback = _fallbackAverageByType(item.mandiType);
            average = fallback;
            min = fallback;
            max = fallback;
            source = 'SAFE_DEFAULT_NO_SOURCE';
          }
        }

        final payload = {
          'cropName': item.itemName,
          'itemName': item.itemName,
          'itemNameLower': _normalizeCropDocId(item.itemName),
          'cropNameLower': _normalizeCropDocId(item.itemName),
          'mandiType': item.mandiType.wireValue,
          'average': average,
          'min': min,
          'max': max,
          'unit': 'per 40kg',
          'region': 'Pakistan Mandi Hub',
          'source': source,
          'syncedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        };

        await _db
            .collection(_canonicalMandiRatesCollection)
            .doc(docId)
            .set(payload, SetOptions(merge: true));

        // Keep legacy collection in sync for older app builds.
        await _db
            .collection(_legacyMandiRatesCollection)
            .doc(docId)
            .set(payload, SetOptions(merge: true));
      } catch (_) {
        continue;
      }
    }
  }

  Stream<Map<String, dynamic>?> getPakistanMandiRateDocStream(
    String cropName, {
    MandiType type = MandiType.crops,
  }) {
    final docId = _buildMandiRateDocId(type, cropName);
    return _db
        .collection(_canonicalMandiRatesCollection)
        .doc(docId)
        .snapshots()
        .map((doc) => doc.data());
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _readMandiRateDoc(
    String docId,
  ) async {
    final primary = await _db
        .collection(_canonicalMandiRatesCollection)
        .doc(docId)
        .get();
    if (primary.exists) return primary;
    return _db.collection(_legacyMandiRatesCollection).doc(docId).get();
  }

  /// �S& Generic File Upload (Handles Images, Videos, and Audios)
  bool _looksLikeAppCheckOrAuthIssue(String raw) {
    final text = raw.toLowerCase();
    return text.contains('app check') ||
        text.contains('appcheck') ||
        text.contains('app_check') ||
        text.contains('placeholder token') ||
        text.contains('attestation failed') ||
        text.contains('too many attempts') ||
        text.contains('unauthenticated') ||
        text.contains('unauthorized') ||
        text.contains('permission-denied');
  }

  bool _looksLikeTransientNetworkIssue(String raw) {
    final text = raw.toLowerCase();
    return text.contains('network') ||
        text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection');
  }

  Future<String> _uploadToStorage(
    File file,
    String storagePath, {
    void Function(double progress)? onProgress,
  }) async {
    try {
      final String authUid = (_auth.currentUser?.uid ?? '').trim();
      debugPrint(
        '[AddListingUpload] start path=$storagePath authUid=${authUid.isEmpty ? 'null' : authUid} fileExists=${await file.exists()}',
      );
      Reference ref = _storage.ref().child(storagePath);
      UploadTask? uploadTask;
      if (await file.exists()) {
        uploadTask = ref.putFile(file);
      }

      if (onProgress != null && uploadTask != null) {
        uploadTask.snapshotEvents.listen((snapshot) {
          final total = snapshot.totalBytes;
          if (total <= 0) return;
          onProgress(snapshot.bytesTransferred / total);
        });
      }

      if (uploadTask == null) {
        throw Exception('upload_failed:no_upload_task');
      }
      TaskSnapshot snapshot = await uploadTask;
      final String downloadUrl = await snapshot.ref.getDownloadURL();
      debugPrint(
        '[AddListingUpload] success path=$storagePath authUid=${authUid.isEmpty ? 'null' : authUid}',
      );
      return downloadUrl;
    } on FirebaseException catch (e) {
      debugPrint(
        '[AddListingUpload] failed path=$storagePath code=${e.code} message=${e.message ?? ''}',
      );
      throw Exception(
        'upload_failed:firebase_storage/${e.code}:${e.message ?? ''}',
      );
    } catch (e) {
      debugPrint(
        '[AddListingUpload] failed path=$storagePath error=${e.toString()}',
      );
      throw Exception('upload_failed:${e.toString()}');
    }
  }

  Future<String> _uploadToStorageWithRetry(
    File file,
    String storagePath, {
    void Function(double progress)? onProgress,
    int maxAttempts = 2,
  }) async {
    int attempt = 0;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        return await _uploadToStorage(
          file,
          storagePath,
          onProgress: onProgress,
        );
      } catch (e) {
        final raw = e.toString();
        final nonRetryable =
            _looksLikeAppCheckOrAuthIssue(raw) ||
            raw.toLowerCase().contains('cancelled');
        final retryable = _looksLikeTransientNetworkIssue(raw);

        if (nonRetryable || !retryable || attempt >= maxAttempts) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
    throw Exception('File upload nakam hui.');
  }

  Future<void> _ensureAppCheckReadyForUpload() async {
    // Firebase App Check SDK auto-attaches tokens to all Firebase SDK calls
    // (Storage, Firestore). Calling getToken() here is unnecessary and can
    // cause "Too many attempts" rate-limit errors — so we skip it entirely.
    debugPrint(
      '[UploadTrace] App Check is auto-managed by SDK for Storage/Firestore calls.',
    );
  }

  /// �S& Main Professional Method: Create Listing
  /// Is mein UI se aane wala data aur Files dono handle hotay hain.
  Future<void> createListing(
    Map<String, dynamic> data, {
    void Function(double progress)? onMediaUploadProgress,
  }) async {
    try {
      final user = _auth.currentUser;
      final String resolvedSellerId = (user?.uid ?? data['sellerId'] ?? '')
          .toString()
          .trim();
      if (resolvedSellerId.isEmpty) throw Exception("User authorize nahi hai.");

      final String requestedId = (data['listingId'] ?? '').toString().trim();
      final String listingId = requestedId.isNotEmpty
          ? requestedId
          : '${resolvedSellerId}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final rawVideoPath = (data['video'] ?? '').toString().trim();
      final rawImages = (data['images'] as List?)?.cast<dynamic>() ?? const [];
      final imagePaths = rawImages
          .map((item) => item.toString().trim())
          .where((path) => path.isNotEmpty)
          .toList();
      final String rawAudioPath = (data['audioPath'] ?? '').toString().trim();

      int completedUploads = 0;
      final int totalUploads =
          imagePaths.length +
          (rawVideoPath.isNotEmpty ? 1 : 0) +
          (rawAudioPath.isNotEmpty ? 1 : 0);

      void reportProgress() {
        if (onMediaUploadProgress == null || totalUploads <= 0) return;
        onMediaUploadProgress(
          (completedUploads / totalUploads).clamp(0.0, 1.0),
        );
      }

      void markUploadDone() {
        completedUploads += 1;
        reportProgress();
      }

      if (totalUploads > 0) {
        onMediaUploadProgress?.call(0.0);
      }

      // 1. Handle Media Uploads (Checking if paths exist)
      String? imageUrl;
      List<String> imageUrls = <String>[];
      String? videoUrl;
      String? audioUrl;

      // Images handling (parallel uploads for better speed)
      try {
        if (imagePaths.isNotEmpty) {
          final now = DateTime.now().millisecondsSinceEpoch;
          final uploadFutures = <Future<String>>[];
          for (int index = 0; index < imagePaths.length; index++) {
            final path = imagePaths[index];
            final storagePath = 'listings/$listingId/media/${now + index}.jpg';
            uploadFutures.add(
              _uploadToStorage(File(path), storagePath).then((url) {
                markUploadDone();
                return url;
              }),
            );
          }
          imageUrls = await Future.wait(uploadFutures);
          imageUrl = imageUrls.isNotEmpty ? imageUrls.first : '';
        }
      } catch (e) {
        imageUrl = '';
        imageUrls = <String>[];
      }

      try {
        if (rawVideoPath.isNotEmpty) {
          final videoStoragePath =
              'listings/$listingId/media/${DateTime.now().millisecondsSinceEpoch}.mp4';
          videoUrl = await _uploadToStorageWithRetry(
            File(rawVideoPath),
            videoStoragePath,
            onProgress: (_) {},
            maxAttempts: 3,
          );
          markUploadDone();
        }
      } catch (e) {
        final message = e.toString().toLowerCase();
        if (message.contains('quota') && message.contains('exceed')) {
          videoUrl = '';
        } else {
          throw Exception(
            'Verification video upload interrupt ho gaya. Network check karke dobara submit karein.',
          );
        }
      }

      try {
        if (rawAudioPath.isNotEmpty) {
          final audioStoragePath =
              'audio_notes/$resolvedSellerId/${DateTime.now().millisecondsSinceEpoch}.m4a';
          audioUrl = await _uploadToStorage(
            File(rawAudioPath),
            audioStoragePath,
          );
          markUploadDone();
        }
      } catch (e) {
        audioUrl = '';
      }

      if (totalUploads > 0) {
        onMediaUploadProgress?.call(1.0);
      }

      // 2. AI Price Analysis (Using PriceDeviationFlagger)
      final double price = double.tryParse(data['price'].toString()) ?? 0.0;
      final double estimatedValue =
          double.tryParse(data['estimatedValue'].toString()) ?? 0.0;
      final analysis = _flagger.analyzePrice(data['product'], price);
      final bool isVerifiedSource =
          data['isVerifiedSource'] == true && (videoUrl?.isNotEmpty ?? false);

      String sellerBadge = '';
      try {
        sellerBadge = await _intelligenceService.resolveSellerVerificationBadge(
          itemName: (data['product'] ?? data['cropType'] ?? '').toString(),
          price: price,
          videoUrl: videoUrl,
          isVerifiedSource: isVerifiedSource,
        );
      } catch (_) {
        sellerBadge = '';
      }

      // 3. Prepare Final Data Packet
      final Map<String, dynamic> finalData = {
        'sellerId': resolvedSellerId,
        'sellerName': data['sellerName'] ?? "Kisan Bhai",
        'mandiType': data['mandiType'] ?? MandiType.crops.wireValue,
        'category': data['category'] ?? '',
        'categoryLabel': data['categoryLabel'] ?? '',
        'subcategory': data['subcategory'] ?? '',
        'subcategoryLabel': data['subcategoryLabel'] ?? '',
        'product': data['product'],
        'quantity': data['quantity'],
        'unit': data['unit'],
        'unitType': data['unitType'],
        'breed': data['breed'],
        'weight': data['weight'],
        'fatPercentage': data['fatPercentage'],
        'price': price,
        'estimatedValue': estimatedValue,
        'grade': data['grade'],
        'country': data['country'] ?? 'Pakistan',
        'province': data['province'],
        'district': data['district'],
        'tehsil': data['tehsil'] ?? '',
        'city': data['city'] ?? '',
        'village': data['village'] ?? '',
        'location': data['location'],
        'locationData': data['locationData'],
        'saleType': data['saleType'] ?? 'auction',
        'isAuction':
            data['isAuction'] == true ||
            (data['saleType'] ?? 'auction').toString().toLowerCase() ==
                'auction',
        'featured':
            data['promotionStatus'] == 'active' && data['featured'] == true,
        'featuredAuction':
            data['promotionStatus'] == 'active' &&
            data['featuredAuction'] == true,
        'featuredCost': _toDouble(data['featuredCost']) ?? 0,
        'promotionType': (data['promotionType'] ?? 'none').toString(),
        'promotionStatus': (data['promotionStatus'] ?? 'none').toString(),
        'promotionRequestedAt': data['promotionRequestedAt'],
        'promotionPaymentRequired': data['promotionPaymentRequired'] == true,
        'promotionRequestedFeaturedListing':
            data['promotionRequestedFeaturedListing'] == true,
        'promotionRequestedFeaturedAuction':
            data['promotionRequestedFeaturedAuction'] == true,
        'priorityScore':
            (data['promotionStatus'] ?? '').toString().toLowerCase() == 'active'
            ? (data['priorityScore'] ?? 'high').toString()
            : 'normal',
        'isSeasonalQurbani': data['isSeasonalQurbani'] == true,
        'seasonalTags': data['seasonalTags'] ?? const <String>[],
        'directContactEnabled': data['directContactEnabled'] == true,
        'sellerPhone': (data['sellerPhone'] ?? '').toString(),
        'sellerWhatsapp': (data['sellerWhatsapp'] ?? '').toString(),
        'bakraExpiresAt': data['bakraExpiresAt'],
        'archiveAfter': data['archiveAfter'],
        'imageUrl': imageUrl ?? '',
        'imageUrls': imageUrls,
        'videoUrl': videoUrl ?? '',
        'isVerifiedSource': isVerifiedSource,
        'sellerBadge': sellerBadge,
        'isAiVerifiedSeller': sellerBadge == 'AI Verified Seller',
        'verificationGeo': data['verificationGeo'],
        'verificationCapturedAt': data['verificationCapturedAt'],
        'verificationVideoTag': data['verificationVideoTag'],
        'audioUrl': audioUrl ?? '',
        'isSuspicious': analysis['isSuspicious'] ?? false,
        'suspiciousReason': analysis['reason'] ?? '',
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
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // 4. Save to Firestore (explicit doc id to reduce double-submission duplicates)
      final DocumentReference docRef = _db
          .collection('listings')
          .doc(listingId);
      debugPrint(
        '[CreateListing] firestore_write_start listingId=$listingId sellerId=$resolvedSellerId',
      );
      try {
        await docRef.set(finalData, SetOptions(merge: true));
      } on FirebaseException catch (e) {
        debugPrint(
          '[CreateListing] firestore_write_failed listingId=$listingId sellerId=$resolvedSellerId code=${e.code} message=${e.message ?? ''}',
        );
        rethrow;
      }
      debugPrint(
        '[CreateListing] firestore_write_success listingId=$listingId',
      );

      // 5. Automatic Admin Alert for Suspicious Price
      if (finalData['isSuspicious'] == true) {
        await _createAdminAlert(docRef.id, finalData);
      }
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  String get _projectId {
    try {
      return DefaultFirebaseOptions.currentPlatform.projectId;
    } catch (_) {
      return DefaultFirebaseOptions.android.projectId;
    }
  }

  String get _functionsBaseUrl =>
      'https://asia-south1-$_projectId.cloudfunctions.net';

  String _responsePreview(String body, {int maxChars = 300}) {
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return normalized.substring(0, maxChars);
  }

  Future<Map<String, dynamic>> _postSecureFunction({
    required String functionName,
    required Map<String, dynamic> payload,
  }) async {
    debugPrint(
      '[AddListing] _postSecureFunction_start functionName=$functionName',
    );
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User authorize nahi hai.');
    }

    final token = await user.getIdToken();
    final uri = Uri.parse('$_functionsBaseUrl/$functionName');

    // Attach App Check token so Cloud Functions with App Check enforcement
    // accept the request.  Non-blocking: if the token is unavailable we
    // still attempt the call and let the backend decide.
    String? appCheckToken;
    try {
      appCheckToken = await FirebaseAppCheck.instance.getToken(false);
      debugPrint(
        '[AddListing] app_check_token hasToken=${(appCheckToken ?? '').isNotEmpty}',
      );
    } catch (e) {
      debugPrint(
        '[AddListing] app_check_token_fetch_failed (non-blocking) error=$e',
      );
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    if ((appCheckToken ?? '').isNotEmpty) {
      headers['X-Firebase-AppCheck'] = appCheckToken!;
    }

    debugPrint('[AddListing] http_post_start uri=$uri');
    final response = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );

    final rawBody = response.body;
    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    final bodyPreview = _responsePreview(rawBody);
    debugPrint(
      '[AddListing] http_response_received status=${response.statusCode} contentType=$contentType',
    );
    debugPrint('[AddListing] http_response_body=$bodyPreview');

    final looksLikeJson =
        contentType.contains('application/json') ||
        rawBody.trimLeft().startsWith('{') ||
        rawBody.trimLeft().startsWith('[');

    if (!looksLikeJson && rawBody.trim().isNotEmpty) {
      debugPrint(
        '[AddListing] http_response_not_json contentType=$contentType rawBody=$rawBody',
      );
      throw Exception(
        'non_json_response:'
        'status=${response.statusCode};'
        'contentType=$contentType;'
        'uri=$uri;'
        'body=$bodyPreview',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = rawBody.trim().isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(rawBody) as Map<String, dynamic>);
      debugPrint('[AddListing] http_json_decoded ok');
    } on FormatException {
      debugPrint(
        '[AddListing] http_json_decode_failed status=${response.statusCode}',
      );
      throw Exception(
        'invalid_json_response:'
        'status=${response.statusCode};'
        'contentType=$contentType;'
        'uri=$uri;'
        'body=$bodyPreview',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorFromResponse =
          (decoded['error'] ??
                  'LISTING_CREATE_FAILED(status=${response.statusCode})')
              .toString();
      debugPrint(
        '[AddListing] http_request_failed status=${response.statusCode} error=$errorFromResponse decoded=$decoded',
      );
      throw Exception(errorFromResponse);
    }

    debugPrint('[AddListing] http_success status=${response.statusCode}');
    return decoded;
  }

  Future<String> createListingSecure(
    Map<String, dynamic> listingData,
    Map<String, dynamic> mediaFiles, {
    void Function(double progress)? onProgress,
    void Function(String stage)? onStage,
    void Function(String issueCode)? onNonBlockingIssue,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('User authorize nahi hai.');
    final String localSellerId = (listingData['sellerId'] ?? '')
        .toString()
        .trim();
    debugPrint(
      '[AddListingSubmit] auth_snapshot '
      'firebaseUid=${user.uid} '
      'payloadSellerId=${localSellerId.isEmpty ? 'null' : localSellerId} '
      'finalResolvedUid=${user.uid}',
    );

    final String listingId =
        '${user.uid}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
    debugPrint(
      '[AddListing] createListingSecure_start listingId=$listingId uid=${user.uid}',
    );

    final imageFiles = (mediaFiles['images'] as List?) ?? const [];
    final videoFile = mediaFiles['video'];
    final audioPath = (mediaFiles['audioPath'] ?? '').toString().trim();
    final paymentProofImageFile = mediaFiles['paymentProofImage'];

    final imagePaths = imageFiles
        .map((file) {
          if (file is File) return file.path;
          final dynamic anyFile = file;
          if (anyFile != null && anyFile.path is String) {
            return (anyFile.path as String).trim();
          }
          return file.toString().trim();
        })
        .where((path) => path.isNotEmpty)
        .toList(growable: false);

    String videoPath = '';
    if (videoFile is File) {
      videoPath = videoFile.path;
    } else {
      final dynamic anyVideo = videoFile;
      if (anyVideo != null && anyVideo.path is String) {
        videoPath = (anyVideo.path as String).trim();
      }
    }

    onStage?.call('preparing');
    debugPrint('[AddListing] appcheck_preflight_start');
    await _ensureAppCheckReadyForUpload();
    debugPrint('[AddListing] appcheck_preflight_passed');

    int completedUploads = 0;
    final int totalUploads =
        imagePaths.length +
        (videoPath.isNotEmpty ? 1 : 0) +
        (audioPath.isNotEmpty ? 1 : 0) +
        (paymentProofImageFile != null ? 1 : 0);

    void reportProgress() {
      if (onProgress == null || totalUploads <= 0) return;
      onProgress((completedUploads / totalUploads).clamp(0.0, 1.0));
    }

    void markUploadDone() {
      completedUploads += 1;
      reportProgress();
    }

    if (totalUploads > 0) {
      onProgress?.call(0.0);
    }

    final List<String> imageUrls = <String>[];
    String videoUrl = '';
    String uploadedAudioUrl = '';
    String paymentProofUrl = '';

    if (imagePaths.isNotEmpty) {
      onStage?.call('uploading_trust_photo');
      debugPrint(
        '[AddListing] image_upload_start totalImages=${imagePaths.length}',
      );
    }

    for (int index = 0; index < imagePaths.length; index++) {
      final path = imagePaths[index];
      final storagePath =
          'listings/$listingId/images/${DateTime.now().millisecondsSinceEpoch}_$index.jpg';
      try {
        debugPrint(
          '[AddListingUpload] image_start path=$storagePath index=$index',
        );
        if (index > 0) {
          debugPrint('[UploadTrace] extra image upload start index=$index');
        }
        final url = await _uploadToStorage(File(path), storagePath);
        imageUrls.add(url);
        debugPrint(
          '[AddListingUpload] image_success path=$storagePath index=$index',
        );
      } catch (e) {
        debugPrint(
          '[AddListingUpload] image_failed path=$storagePath index=$index error=${e.toString()}',
        );
        if (index == 0) {
          throw Exception('trust_photo_upload_failed:${e.toString()}');
        }
        if (_looksLikeAppCheckOrAuthIssue(e.toString())) {
          onNonBlockingIssue?.call('extra_image_upload_app_check_failed');
        } else {
          onNonBlockingIssue?.call('extra_image_upload_failed');
        }
      } finally {
        markUploadDone();
      }
    }

    if (videoPath.isNotEmpty) {
      onStage?.call('uploading_media');
      debugPrint('[UploadTrace] optional video upload start');
      final storagePath =
          'listings/$listingId/video/${DateTime.now().millisecondsSinceEpoch}.mp4';
      try {
        debugPrint('[AddListingUpload] video_start path=$storagePath');
        videoUrl = await _uploadToStorageWithRetry(
          File(videoPath),
          storagePath,
          maxAttempts: 2,
        );
        debugPrint('[AddListingUpload] video_success path=$storagePath');
      } catch (e) {
        debugPrint(
          '[AddListingUpload] video_failed path=$storagePath error=${e.toString()}',
        );
        if (_looksLikeAppCheckOrAuthIssue(e.toString())) {
          onNonBlockingIssue?.call('video_upload_app_check_failed');
        } else {
          onNonBlockingIssue?.call('video_upload_failed');
        }
        videoUrl = '';
      } finally {
        markUploadDone();
      }
    }

    if (audioPath.isNotEmpty) {
      onStage?.call('uploading_media');
      debugPrint('[UploadTrace] audio upload start');
      final storagePath =
          'audio_notes/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      try {
        debugPrint('[AddListingUpload] audio_start path=$storagePath');
        uploadedAudioUrl = await _uploadToStorage(File(audioPath), storagePath);
        debugPrint('[AddListingUpload] audio_success path=$storagePath');
      } catch (e) {
        debugPrint(
          '[AddListingUpload] audio_failed path=$storagePath error=${e.toString()}',
        );
        if (_looksLikeAppCheckOrAuthIssue(e.toString())) {
          onNonBlockingIssue?.call('audio_upload_app_check_failed');
        } else {
          onNonBlockingIssue?.call('audio_upload_failed');
        }
        uploadedAudioUrl = '';
      } finally {
        markUploadDone();
      }
    }

    if (paymentProofImageFile != null) {
      onStage?.call('uploading_payment_proof');
      debugPrint('[UploadTrace] payment proof upload start');
      
      String paymentProofPath = '';
      if (paymentProofImageFile is File) {
        paymentProofPath = paymentProofImageFile.path;
      } else {
        final dynamic anyFile = paymentProofImageFile;
        if (anyFile != null && anyFile.path is String) {
          paymentProofPath = (anyFile.path as String).trim();
        }
      }
      
      if (paymentProofPath.isNotEmpty) {
        final storagePath =
            'listings/$listingId/payment_proof/${DateTime.now().millisecondsSinceEpoch}.jpg';
        try {
          debugPrint('[AddListingUpload] payment_proof_start path=$storagePath');
          paymentProofUrl = await _uploadToStorage(File(paymentProofPath), storagePath);
          debugPrint('[AddListingUpload] payment_proof_success path=$storagePath');
        } catch (e) {
          debugPrint(
            '[AddListingUpload] payment_proof_failed path=$storagePath error=${e.toString()}',
          );
          if (_looksLikeAppCheckOrAuthIssue(e.toString())) {
            onNonBlockingIssue?.call('payment_proof_upload_app_check_failed');
          } else {
            onNonBlockingIssue?.call('payment_proof_upload_failed');
          }
          paymentProofUrl = '';
        } finally {
          markUploadDone();
        }
      } else {
        markUploadDone();
      }
    }

    if (totalUploads > 0) {
      onProgress?.call(1.0);
    }

    final verificationVideoMeta =
        (listingData['verificationVideoMeta'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final verificationTrustPhotoMeta =
        (listingData['verificationTrustPhotoMeta'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final verificationGeo =
        (listingData['verificationGeo'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};

    final quantityValue = double.tryParse(
      (listingData['quantity'] ?? listingData['weight'] ?? '0').toString(),
    );

    final payload = <String, dynamic>{
      'listingData': <String, dynamic>{
        'sellerId': user.uid,
        'product': (listingData['product'] ?? '').toString(),
        'price': double.tryParse((listingData['price'] ?? '0').toString()) ?? 0,
        'quantity': quantityValue ?? 0,
        'country': (listingData['country'] ?? 'Pakistan').toString(),
        'province': (listingData['province'] ?? '').toString(),
        'district': (listingData['district'] ?? '').toString(),
        'tehsil': (listingData['tehsil'] ?? '').toString(),
        'city': (listingData['city'] ?? '').toString(),
        'village': (listingData['village'] ?? '').toString(),
        'location': (listingData['location'] ?? '').toString(),
        'description': (listingData['description'] ?? '').toString(),
        'mandiType': (listingData['mandiType'] ?? '').toString(),
        'category': (listingData['category'] ?? '').toString(),
        'categoryLabel': (listingData['categoryLabel'] ?? '').toString(),
        'subcategory': (listingData['subcategory'] ?? '').toString(),
        'subcategoryLabel': (listingData['subcategoryLabel'] ?? '').toString(),
        'saleType': (listingData['saleType'] ?? 'auction').toString(),
        'isAuction':
            listingData['isAuction'] == true ||
            (listingData['saleType'] ?? 'auction').toString().toLowerCase() ==
                'auction',
        'featured': listingData['featured'] == true,
        'featuredAuction': listingData['featuredAuction'] == true,
        'featuredCost': _toDouble(listingData['featuredCost']) ?? 0,
        'promotionType': (listingData['promotionType'] ?? 'none').toString(),
        'promotionStatus': (listingData['promotionStatus'] ?? 'none')
            .toString(),
        'promotionRequestedAt': (listingData['promotionRequestedAt'] ?? '')
            .toString(),
        'promotionPaymentRequired':
            listingData['promotionPaymentRequired'] == true ||
            listingData['promotionRequestedFeaturedListing'] == true ||
            listingData['promotionRequestedFeaturedAuction'] == true ||
            listingData['featured'] == true ||
            listingData['featuredAuction'] == true,
        'promotionRequestedFeaturedListing':
            listingData['promotionRequestedFeaturedListing'] == true ||
            listingData['featured'] == true,
        'promotionRequestedFeaturedAuction':
            listingData['promotionRequestedFeaturedAuction'] == true ||
            listingData['featuredAuction'] == true,
        'promotionPaymentReference':
            (listingData['promotionPaymentReference'] ?? '').toString(),
        'promotionProofUrl': (listingData['promotionProofUrl'] ?? '')
            .toString(),
        'paymentMethod': (listingData['paymentMethod'] ?? '').toString(),
        'paymentRef': (listingData['paymentRef'] ?? '').toString(),
        'paymentProofUrl': paymentProofUrl,
        'paymentProofFileName': (listingData['paymentProofFileName'] ?? '')
            .toString(),
        'promotionPaymentSubmittedAt': (listingData['promotionPaymentSubmittedAt'] ?? '')
            .toString(),
        'priorityScore':
            (listingData['promotionStatus'] ?? '').toString().toLowerCase() ==
                'active'
            ? (listingData['priorityScore'] ?? 'high').toString()
            : 'normal',
        'isSeasonalQurbani': listingData['isSeasonalQurbani'] == true,
        'seasonalTags':
            (listingData['seasonalTags'] as List?) ?? const <dynamic>[],
        'directContactEnabled': listingData['directContactEnabled'] == true,
        'sellerPhone': (listingData['sellerPhone'] ?? '').toString(),
        'sellerWhatsapp': (listingData['sellerWhatsapp'] ?? '').toString(),
        'bakraExpiresAt': listingData['bakraExpiresAt'],
        'archiveAfter': listingData['archiveAfter'],
        'locationData':
            (listingData['locationData'] as Map<String, dynamic>?) ??
            const <String, dynamic>{},
        'unitType': (listingData['unitType'] ?? listingData['unit'] ?? '')
            .toString(),
      },
      'mediaMetadata': <String, dynamic>{
        'verificationVideo': <String, dynamic>{
          'url': videoUrl,
          'lat':
              _toDouble(
                verificationGeo['lat'] ?? verificationVideoMeta['lat'],
              ) ??
              _toDouble(verificationTrustPhotoMeta['lat']) ??
              _toDouble(listingData['videoLat']) ??
              0,
          'lng':
              _toDouble(
                verificationGeo['lng'] ?? verificationVideoMeta['lng'],
              ) ??
              _toDouble(verificationTrustPhotoMeta['lng']) ??
              _toDouble(listingData['videoLng']) ??
              0,
          'durationSeconds':
              _toDouble(verificationVideoMeta['durationSeconds'])?.round() ?? 0,
          'capturedAt':
              (verificationVideoMeta['capturedAt'] ??
                      verificationTrustPhotoMeta['capturedAt'] ??
                      listingData['verificationCapturedAt'])
                  .toString(),
          'tag':
              (verificationVideoMeta['tag'] ??
                      listingData['verificationVideoTag'] ??
                      '')
                  .toString(),
          'fileSizeBytes':
              _toDouble(verificationVideoMeta['fileSize'])?.round() ?? 0,
        },
        'verificationTrustPhoto': <String, dynamic>{
          'lat':
              _toDouble(verificationTrustPhotoMeta['lat']) ??
              _toDouble(verificationGeo['lat']) ??
              0,
          'lng':
              _toDouble(verificationTrustPhotoMeta['lng']) ??
              _toDouble(verificationGeo['lng']) ??
              0,
          'capturedAt':
              (verificationTrustPhotoMeta['capturedAt'] ??
                      listingData['verificationCapturedAt'] ??
                      '')
                  .toString(),
          'tag': (verificationTrustPhotoMeta['tag'] ?? '').toString(),
          'fileSizeBytes':
              _toDouble(verificationTrustPhotoMeta['fileSize'])?.round() ?? 0,
        },
        'imageUrls': imageUrls,
        'audioUrl': uploadedAudioUrl,
      },
    };

    onStage?.call('saving_listing');
    debugPrint(
      '[UploadTrace] Firestore save start (via createListingSecureHttp)',
    );
    debugPrint(
      '[CreateListingSecure] payload_keys_listingData=${(payload['listingData'] as Map).keys.toList()}',
    );
    debugPrint(
      '[CreateListingSecure] forbidden_fields_check status=${(payload['listingData'] as Map?)?.containsKey('status')} riskScore=${(payload['listingData'] as Map?)?.containsKey('riskScore')} fraudFlags=${(payload['listingData'] as Map?)?.containsKey('fraudFlags')}',
    );

    Map<String, dynamic> response;
    try {
      response = await _postSecureFunction(
        functionName: 'createListingSecureHttp',
        payload: payload,
      );
    } catch (e) {
      debugPrint('[UploadTrace] save failed error=$e');
      debugPrint(
        '[CreateListingSecure] error_type=${e.runtimeType} error_message=$e',
      );
      throw Exception('save_failed:${e.toString()}');
    }
    debugPrint('[UploadTrace] save succeeded status=${response['status']}');

    final createdListingId = (response['listingId'] ?? '').toString().trim();
    if (createdListingId.isNotEmpty) {
      // Fire-and-forget suggestion refresh; listing flow must not fail on AI issues.
      unawaited(
        _postSecureFunction(
          functionName: 'evaluateListingRiskHttp',
          payload: <String, dynamic>{'listingId': createdListingId},
        ).catchError((_) => <String, dynamic>{}),
      );
    }

    // Server enforces pending review by default, so listing remains admin-gated.
    return (response['status'] ?? 'pending_review').toString();
  }

  /// �S& Buyer Bid Context (Null-safe highestBid/basePrice + 24h cycle)
  Future<Map<String, dynamic>> getListingBidContext(String listingId) async {
    final doc = await _db.collection('listings').doc(listingId).get();
    if (!doc.exists) {
      throw Exception('Listing not found');
    }

    final Map<String, dynamic> map = doc.data() ?? <String, dynamic>{};

    final double basePrice =
        _safeNumber(map, 'startingPrice') ??
        _safeNumber(map, 'basePrice') ??
        _safeNumber(map, 'price') ??
        0.0;
    final double? highestBid = _safeNumber(map, 'highestBid');

    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime? startTime = _safeDate(map, 'startTime')?.toUtc();
    final DateTime? approvedAt = _safeDate(map, 'approvedAt')?.toUtc();
    final DateTime? biddingStart = startTime ?? approvedAt;
    final DateTime? biddingEnd = _safeDate(map, 'endTime')?.toUtc();
    final bool isForceClosed = _safeBool(map, 'isBidForceClosed');
    final bool isApproved = _safeBool(map, 'isApproved');

    return {
      ...map,
      'basePrice': basePrice,
      'highestBid': highestBid,
      'biddingEnd': biddingEnd,
      'isBiddingOpen':
          isApproved &&
          biddingStart != null &&
          biddingEnd != null &&
          nowUtc.isBefore(biddingEnd) &&
          !isForceClosed,
    };
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  double? _safeNumber(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key)) return null;
    return _toDouble(map[key]);
  }

  bool _safeBool(
    Map<String, dynamic> map,
    String key, {
    bool fallback = false,
  }) {
    if (!map.containsKey(key)) return fallback;
    final value = map[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  DateTime? _safeDate(Map<String, dynamic> map, String key) {
    if (!map.containsKey(key)) return null;
    final value = map[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  /// �S& Internal Helper: Create Admin Alert
  Future<void> _createAdminAlert(
    String listingId,
    Map<String, dynamic> data,
  ) async {
    await _db.collection('alerts').add({
      'listingId': listingId,
      'type': 'PRICE_DEVIATION',
      'severity': 'high',
      'message': 'Ghair-fitt rate detect hua: ${data['suspiciousReason']}',
      'product': data['product'],
      'price': data['price'],
      'timestamp': FieldValue.serverTimestamp(),
      'isResolved': false,
    });
  }

  /// �S& Unified Bid Placement (Dual-Path Routing + Atomic Batch Write)
  Future<void> placeBid({
    required BidModel bid,
    double marketPrice = 0.0,
    Map<String, dynamic>? aiMeta,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Boli lagane ke liye login zaroori hai');
    }

    final listingRef = _db.collection('listings').doc(bid.listingId);
    final listingSnap = await listingRef.get();
    if (!listingSnap.exists) {
      throw Exception('Fasal ka record nahi mila');
    }

    debugPrint(
      '[BidFlow] attempt listing=${bid.listingId} buyer=${user.uid} amount=${bid.bidAmount.toStringAsFixed(2)}',
    );

    final Map<String, dynamic> listingData =
        listingSnap.data() ?? <String, dynamic>{};

    final eligibility = BidEligibilityService.evaluate(
      buyerId: user.uid,
      listingData: listingData,
      bidAmount: bid.bidAmount,
    );
    if (!eligibility.allowed) {
      debugPrint(
        '[BidFlow] blocked listing=${bid.listingId} buyer=${user.uid} reason=${eligibility.message}',
      );
      throw Exception(eligibility.message);
    }

    final userSnap = await _db.collection('users').doc(user.uid).get();
    final userData = userSnap.data() ?? <String, dynamic>{};
    final blockStatus = TrustSafetyService.evaluateBidBlock(userData: userData);
    if (blockStatus.isBlocked) {
      throw Exception(
        blockStatus.reasonUr.isEmpty
            ? blockStatus.reason
            : '${blockStatus.reason} ${blockStatus.reasonUr}',
      );
    }

    final double basePrice =
        _safeNumber(listingData, 'startingPrice') ??
        _safeNumber(listingData, 'basePrice') ??
        _safeNumber(listingData, 'price') ??
        0.0;
    final double currentMax =
        _safeNumber(listingData, 'highestBid') ?? basePrice;

    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime? approvedAt = _safeDate(listingData, 'approvedAt')?.toUtc();
    final DateTime? startTime = _safeDate(listingData, 'startTime')?.toUtc();
    final DateTime biddingStart = startTime ?? approvedAt ?? nowUtc;
    final DateTime biddingEnd =
        _safeDate(listingData, 'endTime')?.toUtc() ??
        biddingStart.add(const Duration(hours: 24));

    if (nowUtc.isAfter(biddingEnd)) {
      await _auctionLifecycleService.finalizeAuctionIfEnded(
        listingId: bid.listingId,
        source: 'place_bid_guard',
      );
      throw Exception('Boli ka waqt khatam ho chuka hai.');
    }

    if (bid.bidAmount <= currentMax) {
      throw Exception(
        'Aapki boli maujooda boli (Rs. $currentMax) se zyada honi chahiye',
      );
    }

    final String cropName = (listingData['product'] ?? bid.productName)
        .toString()
        .trim();
    Map<String, double>? ruleRates;
    double? ruleAverage;

    if (cropName.isNotEmpty) {
      ruleRates = await _marketRateService.fetchRuleBasedRateSnapshot(cropName);
      ruleAverage = ruleRates?['average'];
    }

    final double checkPrice = marketPrice > 0 ? marketPrice : basePrice;
    final double referenceMarketPrice = (ruleAverage != null && ruleAverage > 0)
        ? ruleAverage
        : (checkPrice > 0 ? checkPrice : bid.bidAmount);
    final String resolvedListingId = (listingSnap.id).trim().isNotEmpty
        ? listingSnap.id
        : bid.listingId;
    final String resolvedSellerId =
        (listingData['sellerId'] ?? '').toString().trim().isNotEmpty
        ? (listingData['sellerId'] ?? '').toString().trim()
        : bid.sellerId;

    final anomalyCheck = BiddingLogicEngine.validateBid(
      bid.bidAmount,
      referenceMarketPrice,
    );
    final velocityCheck = await BiddingLogicEngine.enforceVelocityAndLock(
      db: _db,
      userId: user.uid,
    );

    final bool isSpamLock = velocityCheck['code'] == 'SPAM_LOCK';
    if (isSpamLock) {
      await TrustSafetyService.registerStrike(
        userId: user.uid,
        reason: 'SPAM_LOCK',
        source: 'bid_velocity_guard',
        db: _db,
      );
    }

    final int aiBidRiskScore = (_toDouble(aiMeta?['aiBidRiskScore']) ?? 0)
        .round();
    final String aiBidRiskLevel = (aiMeta?['aiBidRiskLevel'] ?? '')
        .toString()
        .trim();
    final String aiBidAdviceUrdu = (aiMeta?['aiBidAdviceUrdu'] ?? '')
        .toString()
        .trim();
    final String aiBidAdvice =
        (aiMeta?['aiBidAdvice'] ?? aiMeta?['aiBidAdviceEn'] ?? '')
            .toString()
            .trim();
    final String aiBidAdviceEn = (aiMeta?['aiBidAdviceEn'] ?? '')
        .toString()
        .trim();
    final List<String> aiBidFlags =
        ((aiMeta?['aiBidFlags'] as List?) ?? const <dynamic>[])
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

    String bidReviewStatus = (aiMeta?['bidReviewStatus'] ?? 'ok')
        .toString()
        .trim();
    if (bidReviewStatus.isEmpty) bidReviewStatus = 'ok';
    bool adminReviewRequired = aiMeta?['adminReviewRequired'] == true;

    if (isSpamLock) {
      bidReviewStatus = 'pendingReview';
      adminReviewRequired = true;
    }

    final bool isSuspicious = anomalyCheck['isSuspicious'] == true;
    final String suspiciousReason =
        anomalyCheck['reason']?.toString() ?? 'Price Anomaly Detected';

    final String? oldBidderId = listingData['lastBidderId']?.toString();
    final String? currentToken = await FirebaseMessaging.instance.getToken();

    final bidRef = listingRef.collection('bids').doc();
    final batch = _db.batch();
    final String bidWritePath = 'listings/${bid.listingId}/bids/${bidRef.id}';
    final String listingWritePath = 'listings/${bid.listingId}';
    final Map<String, dynamic> bidPayload = <String, dynamic>{
      ...bid.toMap(),
      'buyerId': user.uid,
      'listingId': resolvedListingId,
      'sellerId': resolvedSellerId,
      'bidAmount': bid.bidAmount,
      'status': 'pending',
      'isSuspicious': isSuspicious,
      'suspiciousReason': isSuspicious
          ? (suspiciousReason.isNotEmpty
                ? suspiciousReason
                : 'Rule threshold exceeded')
          : '',
      'aiMinRate': ruleRates?['min'],
      'aiMaxRate': ruleRates?['max'],
      'aiAverageRate': ruleAverage,
      'ruleMinRate': ruleRates?['min'],
      'ruleMaxRate': ruleRates?['max'],
      'ruleAverageRate': ruleAverage,
      'fraudCode': anomalyCheck['code'],
      'velocityCode': velocityCheck['code'],
      'route': isSuspicious ? 'alert' : 'normal',
      'aiBidRiskScore': aiBidRiskScore,
      'aiBidRiskLevel': aiBidRiskLevel,
      'aiBidAdvice': aiBidAdvice,
      'aiBidAdviceUrdu': aiBidAdviceUrdu,
      'aiBidAdviceEn': aiBidAdviceEn,
      'aiBidFlags': aiBidFlags,
      'aiBidUpdatedAt': FieldValue.serverTimestamp(),
      'bidReviewStatus': bidReviewStatus,
      'adminReviewRequired': adminReviewRequired,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    final int currentBidCount = (_toDouble(listingData['bid_count']) ?? 0)
        .round();
    final int currentTotalBids = (_toDouble(listingData['totalBids']) ?? 0)
        .round();
    final DateTime nowWrite = DateTime.now().toUtc();
    debugPrint('[BidFlowDebug] listing_snapshot=$listingData');
    final Map<String, dynamic> listingUpdatePayload = <String, dynamic>{
      'highestBid': bid.bidAmount,
      'highestBidAt': nowWrite,
      'highestBidStatus': isSuspicious ? 'pending_verification' : 'verified',
      'lastBidderName': bid.buyerName,
      'lastBidderId': user.uid,
      'lastBidderToken': currentToken,
      'bid_count': currentBidCount + 1,
      'totalBids': currentTotalBids + 1,
      'updatedAt': nowWrite,
    };
    final Map<String, dynamic> listingUpdateLiteralPayload =
        Map<String, dynamic>.from(listingUpdatePayload);
    debugPrint(
      '[BidFlow] write_prepare bidPath=$bidWritePath listingPath=$listingWritePath buyer=${user.uid} amount=${bid.bidAmount.toStringAsFixed(2)}',
    );
    debugPrint(
      '[BidFlowDebug] auth_uid=${user.uid} resource_highestBid_before=${listingData['highestBid']} resource_lastBidderId_before=${listingData['lastBidderId']} request_highestBid_intended=${listingUpdatePayload['highestBid']}',
    );
    debugPrint('[BidFlowDebug] bid_payload=$bidPayload');
    debugPrint('[BidFlowDebug] listing_update_payload=$listingUpdatePayload');
    debugPrint('[BidProbe] submit_handler=MarketplaceService.placeBid');
    debugPrint('[BidProbe] bid_payload=$bidPayload');
    debugPrint('[BidProbe] listing_update_payload=$listingUpdatePayload');

    batch.set(bidRef, bidPayload);

    batch.update(listingRef, listingUpdatePayload);

    Map<String, dynamic>? adminAlertPayload;
    if (isSuspicious || adminReviewRequired) {
      adminAlertPayload = <String, dynamic>{
        'type': 'FRAUD_ALERT',
        'reason': suspiciousReason.isNotEmpty
            ? suspiciousReason
            : (anomalyCheck['reason']?.toString() ?? 'Price Anomaly Detected'),
        'action': 'PENDING_ADMIN_APPROVAL',
        'message': 'Deterministic rule engine detected suspicious bid.',
        'userId': user.uid,
        'amount': bid.bidAmount,
        'listingId': bid.listingId,
        'bidId': bidRef.id,
        'bidReviewStatus': bidReviewStatus,
        'adminReviewRequired': adminReviewRequired,
        'aiBidRiskScore': aiBidRiskScore,
        'aiBidRiskLevel': aiBidRiskLevel,
        'aiBidFlags': aiBidFlags,
        'status': 'pending_verification',
        'timestamp': FieldValue.serverTimestamp(),
      };
    }

    if (adminAlertPayload != null) {
      debugPrint('[BidProbe] admin_alert_payload=$adminAlertPayload');
    } else {
      debugPrint('[BidProbe] admin_alert_payload=NOT_USED');
    }

    if (_shouldRunBidProbe(bid.listingId)) {
      final probe = await _runStandaloneBidProbes(
        listingRef: listingRef,
        bidRef: bidRef,
        listingId: bid.listingId,
        bidId: bidRef.id,
        bidPayload: bidPayload,
        listingUpdatePayload: listingUpdatePayload,
        listingUpdateLiteralPayload: listingUpdateLiteralPayload,
        adminAlertPayload: adminAlertPayload,
        userId: user.uid,
        bidAmount: bid.bidAmount,
      );
      if (!probe.allPass) {
        throw probe.error ??
            FirebaseException(
              plugin: 'cloud_firestore',
              code: 'permission-denied',
              message: 'Bid probe failed at ${probe.failedPath ?? 'unknown'}',
            );
      }
    }

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      debugPrint(
        '[BidFlowDebug] firebase_exception_during_batch code=${e.code} message=${e.message ?? ''} plugin=${e.plugin} details=${e.toString()}',
      );
      debugPrint(
        '[BidProbe] exception code=${e.code} message=${e.message ?? ''}',
      );
      debugPrint('[BidProbe] failed_path=$listingWritePath');
      debugPrint(
        '[BidFlow] write_failed bidPath=$bidWritePath listingPath=$listingWritePath buyer=${user.uid} listing=${bid.listingId} error=${e.toString()}',
      );
      rethrow;
    } catch (e) {
      debugPrint(
        '[BidFlowDebug] non_firebase_exception_during_batch details=${e.toString()}',
      );
      debugPrint(
        '[BidProbe] exception code=non-firebase message=${e.toString()}',
      );
      debugPrint('[BidProbe] failed_path=$listingWritePath');
      debugPrint(
        '[BidFlow] write_failed bidPath=$bidWritePath listingPath=$listingWritePath buyer=${user.uid} listing=${bid.listingId} error=${e.toString()}',
      );
      rethrow;
    }

    debugPrint(
      '[BidFlow] success listing=${bid.listingId} buyer=${user.uid} bidId=${bidRef.id} highest=${bid.bidAmount.toStringAsFixed(2)}',
    );

    if (adminAlertPayload != null) {
      try {
        await _db.collection('admin_alerts').add(adminAlertPayload);
      } on FirebaseException catch (e) {
        debugPrint(
          '[BidFlow] admin_alert_write_skipped code=${e.code} message=${e.message ?? ''}',
        );
      } catch (e) {
        debugPrint('[BidFlow] admin_alert_write_skipped error=${e.toString()}');
      }
    }

    await _notifyBidLifecycleEvents(
      listingRef: listingRef,
      listingData: listingData,
      listingId: resolvedListingId,
      sellerId: resolvedSellerId,
      currentBuyerId: user.uid,
      oldBidderId: oldBidderId,
      bidId: bidRef.id,
      bidAmount: bid.bidAmount,
    );
  }

  bool _shouldRunBidProbe(String listingId) {
    return _bidProbeEnabled && listingId == _bidProbeListingId;
  }

  Future<_BidProbeResult> _runStandaloneBidProbes({
    required DocumentReference<Map<String, dynamic>> listingRef,
    required DocumentReference<Map<String, dynamic>> bidRef,
    required String listingId,
    required String bidId,
    required Map<String, dynamic> bidPayload,
    required Map<String, dynamic> listingUpdatePayload,
    required Map<String, dynamic> listingUpdateLiteralPayload,
    required Map<String, dynamic>? adminAlertPayload,
    required String userId,
    required double bidAmount,
  }) async {
    final String bidPath = 'listings/$listingId/bids/$bidId';
    final String listingPath = 'listings/$listingId';

    try {
      await bidRef.set(bidPayload);
      debugPrint('[BidProbe] bid_create PASS path=$bidPath');
    } catch (e) {
      _logBidProbeFailure(path: bidPath, error: e, label: 'bid_create');
      return _BidProbeResult(allPass: false, failedPath: bidPath, error: e);
    }

    try {
      await listingRef.update(listingUpdateLiteralPayload);
      debugPrint('[BidProbe] listing_update_literal PASS path=$listingPath');
    } catch (e) {
      _logBidProbeFailure(
        path: listingPath,
        error: e,
        label: 'listing_update_literal',
      );
      return _BidProbeResult(allPass: false, failedPath: listingPath, error: e);
    }

    try {
      await listingRef.update(listingUpdatePayload);
      debugPrint('[BidProbe] listing_update PASS path=$listingPath');
    } catch (e) {
      _logBidProbeFailure(path: listingPath, error: e, label: 'listing_update');
      return _BidProbeResult(allPass: false, failedPath: listingPath, error: e);
    }

    if (adminAlertPayload != null) {
      final adminAlertRef = _db.collection('admin_alerts').doc();
      final adminAlertPath = 'admin_alerts/${adminAlertRef.id}';
      try {
        await adminAlertRef.set(adminAlertPayload);
        debugPrint('[BidProbe] admin_alert_create PASS path=$adminAlertPath');
      } catch (e) {
        _logBidProbeFailure(
          path: adminAlertPath,
          error: e,
          label: 'admin_alert_create',
        );
        return _BidProbeResult(
          allPass: false,
          failedPath: adminAlertPath,
          error: e,
        );
      }
    } else {
      debugPrint('[BidProbe] admin_alert_create PASS path=NOT_USED');
    }

    final notificationId = 'probe_${listingId}_$bidId'.replaceAll('/', '_');
    final notificationPath = 'notifications/$notificationId';
    final notificationPayload = <String, dynamic>{
      'toUid': userId,
      'userId': userId,
      'type': Phase1NotificationType.bidPlacedConfirmation,
      'entityId': listingId,
      'listingId': listingId,
      'bidId': bidId,
      'targetRole': 'buyer',
      'amount': bidAmount,
      'title': 'Bid Placed | بولی لگ گئی',
      'body':
          'Your bid has been submitted successfully. | آپ کی بولی کامیابی سے لگ گئی ہے',
      'titleEn': 'Bid Placed',
      'bodyEn': 'Your bid has been submitted successfully.',
      'titleUr': 'بولی لگ گئی',
      'bodyUr': 'آپ کی بولی کامیابی سے لگ گئی ہے',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'phase': 'PHASE_1',
      'eventKey': notificationId,
      'tapAction': 'OPEN_LISTING_DETAILS',
      'routeName': '/listing-details',
      'routeArgs': <String, dynamic>{'listingId': listingId},
    };
    debugPrint('[BidProbe] notification_payload=$notificationPayload');
    try {
      await _db
          .collection('notifications')
          .doc(notificationId)
          .set(notificationPayload);
      debugPrint('[BidProbe] notification_create PASS path=$notificationPath');
    } catch (e) {
      _logBidProbeFailure(
        path: notificationPath,
        error: e,
        label: 'notification_create',
      );
      return _BidProbeResult(
        allPass: false,
        failedPath: notificationPath,
        error: e,
      );
    }

    return const _BidProbeResult(allPass: true);
  }

  void _logBidProbeFailure({
    required String path,
    required Object error,
    required String label,
  }) {
    debugPrint('[BidProbe] $label FAIL path=$path');
    if (error is FirebaseException) {
      debugPrint(
        '[BidProbe] exception code=${error.code} message=${error.message ?? ''}',
      );
    } else {
      debugPrint(
        '[BidProbe] exception code=non-firebase message=${error.toString()}',
      );
    }
    debugPrint('[BidProbe] failed_path=$path');
  }

  Future<void> _notifyBidLifecycleEvents({
    required DocumentReference<Map<String, dynamic>> listingRef,
    required Map<String, dynamic> listingData,
    required String listingId,
    required String sellerId,
    required String currentBuyerId,
    required String? oldBidderId,
    required String bidId,
    required double bidAmount,
  }) async {
    if (sellerId.isNotEmpty && sellerId != currentBuyerId) {
      await _phase1Notifications.createOnce(
        userId: sellerId,
        type: Phase1NotificationType.newBidReceived,
        listingId: listingId,
        bidId: bidId,
        actorUserId: currentBuyerId,
        targetRole: 'seller',
        amount: bidAmount,
      );
    }

    await _phase1Notifications.createOnce(
      userId: currentBuyerId,
      type: Phase1NotificationType.bidPlacedConfirmation,
      listingId: listingId,
      bidId: bidId,
      targetRole: 'buyer',
      amount: bidAmount,
    );

    final previousBidder = (oldBidderId ?? '').trim();
    if (previousBidder.isNotEmpty && previousBidder != currentBuyerId) {
      await _phase1Notifications.createOnce(
        userId: previousBidder,
        type: Phase1NotificationType.outbid,
        listingId: listingId,
        bidId: bidId,
        actorUserId: currentBuyerId,
        targetRole: 'buyer',
        amount: bidAmount,
      );
    }

    final endingSuffix = _endingSoonSuffix(listingData);
    if (endingSuffix == null) return;

    final bidsSnap = await listingRef
        .collection('bids')
        .orderBy('timestamp', descending: true)
        .limit(40)
        .get();
    final Set<String> recipientIds = <String>{};
    for (final doc in bidsSnap.docs) {
      final buyerId = (doc.data()['buyerId'] ?? '').toString().trim();
      if (buyerId.isEmpty) continue;
      recipientIds.add(buyerId);
    }

    if (sellerId.isNotEmpty) {
      await _phase1Notifications.createOnce(
        userId: sellerId,
        type: Phase1NotificationType.auctionEndingSoon,
        listingId: listingId,
        eventSuffix: 'seller_$endingSuffix',
        titleEn: 'Auction Ending Soon',
        bodyEn: 'Your auction is closing soon.',
        titleUr: 'بولی جلد ختم ہو رہی ہے',
        bodyUr: 'آپ کی بولی جلد بند ہونے والی ہے',
        targetRole: 'seller',
      );
    }

    for (final buyerId in recipientIds) {
      await _phase1Notifications.createOnce(
        userId: buyerId,
        type: Phase1NotificationType.auctionEndingSoon,
        listingId: listingId,
        eventSuffix: 'buyer_$endingSuffix',
        targetRole: 'buyer',
      );
    }
  }

  String? _endingSoonSuffix(Map<String, dynamic> listingData) {
    final DateTime? endTime =
        _safeDate(listingData, 'endTime')?.toUtc() ??
        _safeDate(listingData, 'bidExpiryTime')?.toUtc();
    if (endTime == null) return null;

    final Duration remaining = endTime.difference(DateTime.now().toUtc());
    if (remaining <= Duration.zero) return null;
    if (remaining > const Duration(minutes: 10)) return null;

    return '${endTime.year}${endTime.month}${endTime.day}${endTime.hour}${endTime.minute}';
  }

  // --- Read Operations ---

  /// Mandi mein mojud active maal dikhane ke liye
  Stream<QuerySnapshot<Map<String, dynamic>>> getActiveListings() {
    return _db
        .collection('listings')
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  /// Seller ka real-time stock stream
  Stream<QuerySnapshot<Map<String, dynamic>>> getSellerListingsStream(
    String sellerId,
  ) {
    return _db
        .collection('listings')
        .where('sellerId', isEqualTo: sellerId)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Seller ke tamam incoming bids ka live stream (badge/snackbar ke liye)
  Stream<QuerySnapshot<Map<String, dynamic>>> getSellerIncomingBidsStream(
    String sellerId,
  ) {
    return _db.collectionGroup('bids').snapshots();
  }

  /// Listing level bid history stream (UI pe 24 ghante filter hoga)
  Stream<QuerySnapshot<Map<String, dynamic>>> getBidsStream(String listingId) {
    return FirebaseFirestore.instance
        .collection('listings')
        .doc(listingId)
        .collection('bids')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Backward-compatible alias
  Stream<QuerySnapshot<Map<String, dynamic>>> getListingBidsStream(
    String listingId,
  ) {
    return getBidsStream(listingId);
  }

  /// Admin ke liye listing specific bids stream
  Stream<QuerySnapshot<Map<String, dynamic>>> getAdminListingBidsStream(
    String listingId,
  ) {
    return _db
        .collectionGroup('bids')
        .where('listingId', isEqualTo: listingId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Admin Pakistan Mandi Hub bids stream: tamam listings ki boliyan
  Stream<QuerySnapshot<Map<String, dynamic>>> getAllBidsStream() {
    return _db
        .collectionGroup('bids')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  /// Admin ke liye tamam listings (Pending/Suspicious)
  Stream<QuerySnapshot> getAllListings() {
    return _db
        .collection('listings')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Admin pending queue (includes legacy docs missing isApproved)
  Stream<QuerySnapshot<Map<String, dynamic>>> getPendingListingsStream() {
    return _db
        .collection('listings')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Admin: Approve and start 24h auction (Buyer Countdown trigger)
  Future<void> approveAndStartAuction(
    String listingId, {
    bool isSuspicious = false,
    double? deviationPercent,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.collection('listings').doc(listingId).update({
      'status': 'active',
      'isApproved': true,
      'startTime': FieldValue.serverTimestamp(),
      'endTime': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'bidStartTime': FieldValue.serverTimestamp(),
      'bidExpiryTime': Timestamp.fromDate(now.add(const Duration(hours: 24))),
      'approvedAt': FieldValue.serverTimestamp(),
      'isBidForceClosed': false,
      'bidClosedAt': null,
      'isSuspicious': isSuspicious,
      'aiDeviationPercent': deviationPercent ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Financial integrity: total revenue = (listingPrice * 0.01) * 2 for completed deals
  Future<double> calculateTotalRevenue() async {
    final deals = await _db.collection('deals').get();
    double total = 0.0;

    for (final doc in deals.docs) {
      final map = doc.data();
      final status = (map['status'] ?? '').toString().toLowerCase();
      if (status != 'completed' && status != 'deal_completed') {
        continue;
      }

      final listingPrice =
          _safeNumber(map, 'dealAmount') ??
          _safeNumber(map, 'finalPrice') ??
          0.0;
      total += (listingPrice * 0.01) * 2;
    }

    return total;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getDealsStream() {
    return _db
        .collection('deals')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> getUnverifiedUsersStream() {
    return _db
        .collection('users')
        .where('isVerified', isEqualTo: false)
        .snapshots();
  }

  Future<void> setUserVerification(String userId, bool isVerified) async {
    await _db.collection('users').doc(userId).update({
      'isVerified': isVerified,
      'verifiedAt': isVerified ? FieldValue.serverTimestamp() : null,
    });
  }

  /// Status Update (Admin Approval/Rejection)
  Future<void> updateStatus(String docId, String status) async {
    try {
      await _db.collection('listings').doc(docId).update({'status': status});
    } catch (e) {
      _swallowError(e);
    }
  }

  /// Admin: Approve listing and start 24-hour bidding cycle now
  Future<void> approveListing(String listingId) async {
    await approveAndStartAuction(listingId);
  }

  /// Admin: Reject listing
  Future<void> rejectListing(String listingId) async {
    await _db.collection('listings').doc(listingId).update({
      'status': 'rejected',
      'isApproved': false,
      'rejectedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Admin: Force close auction early
  Future<void> forceCloseBidding(String listingId) async {
    final listingRef = _db.collection('listings').doc(listingId);

    await _db.runTransaction((transaction) async {
      final listingSnap = await transaction.get(listingRef);
      if (!listingSnap.exists) {
        throw Exception('Listing not found');
      }

      final bidsSnap = await listingRef
          .collection('bids')
          .orderBy('bidAmount', descending: true)
          .limit(1)
          .get();

      String? winnerId;
      String? finalBidId;
      double? winningBid;

      if (bidsSnap.docs.isNotEmpty) {
        final topBidDoc = bidsSnap.docs.first;
        final topBid = topBidDoc.data();
        winnerId = topBid['buyerId']?.toString();
        finalBidId = topBidDoc.id;
        winningBid = _safeNumber(topBid, 'bidAmount');
      }

      final map = listingSnap.data() ?? <String, dynamic>{};
      final fallbackPrice =
          _safeNumber(map, 'highestBid') ?? _safeNumber(map, 'price') ?? 0.0;

      transaction.update(listingRef, {
        'isBidForceClosed': true,
        'bidClosedAt': FieldValue.serverTimestamp(),
        'status': 'Completed',
        'winnerId': winnerId,
        'buyerId': winnerId,
        'finalBidId': finalBidId,
        'finalPrice': winningBid ?? fallbackPrice,
      });
    });
  }

  /// Listing Delete
  Future<void> deleteListing(String docId) async {
    try {
      await _db.collection('listings').doc(docId).delete();
    } catch (e) {
      _swallowError(e);
    }
  }

  void _swallowError(Object error) {}
}

class _MandiSyncItem {
  const _MandiSyncItem({required this.itemName, required this.mandiType});

  final String itemName;
  final MandiType mandiType;
}

class _BidProbeResult {
  const _BidProbeResult({required this.allPass, this.failedPath, this.error});

  final bool allPass;
  final String? failedPath;
  final Object? error;
}
