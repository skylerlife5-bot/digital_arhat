import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Aapke projects ke relative imports
import '../ai/price_deviation_flagger.dart';
import '../bidding/bid_model.dart';
import '../core/constants.dart';
import 'ai_generative_service.dart';
import 'bidding_logic_engine.dart';
import 'gemini_rate_service.dart';
import 'market_rate_service.dart';

class MarketplaceService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final PriceDeviationFlagger _flagger = PriceDeviationFlagger();
  final MarketRateService _marketRateService = MarketRateService();
  final GeminiRateService _geminiRateService = GeminiRateService();
  final MandiIntelligenceService _intelligenceService =
      MandiIntelligenceService();

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
      case MandiType.milk:
        return 2500;
      case MandiType.livestock:
        return 120000;
      case MandiType.fruit:
        return 5200;
      case MandiType.vegetables:
        return 3600;
      case MandiType.crops:
        return 4200;
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
          final geminiAverage = await _geminiRateService
              .getAverageRateFromGeminiFallback(
                item: item.itemName,
                location: 'Pakistan',
                fallbackListingPrice: 0,
              );

          if (geminiAverage != null && geminiAverage > 0) {
            average = geminiAverage;
            min = geminiAverage;
            max = geminiAverage;
            source = 'AI_MASHWARA_FALLBACK';
          } else {
            final existingDoc = await _db
                .collection('pakistan_mandi_rates')
                .doc(docId)
                .get();
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
              source = 'AI_MASHWARA_SAFE_DEFAULT';
            }
          }
        }

        await _db.collection('pakistan_mandi_rates').doc(docId).set({
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
        }, SetOptions(merge: true));
      } catch (_) {
        continue;
      }
    }
  }

  Stream<Map<String, double>?> getPakistanMandiRateStream(
    String cropName, {
    MandiType type = MandiType.crops,
  }) {
    final docId = _buildMandiRateDocId(type, cropName);
    return _db.collection('pakistan_mandi_rates').doc(docId).snapshots().map((
      doc,
    ) {
      final data = doc.data();
      if (data == null) return null;

      final average = _toDouble(data['average']);
      final min = _toDouble(data['min']);
      final max = _toDouble(data['max']);

      if (average == null ||
          min == null ||
          max == null ||
          average <= 0 ||
          min <= 0 ||
          max <= 0) {
        return null;
      }

      return <String, double>{'average': average, 'min': min, 'max': max};
    });
  }

  Future<Map<String, double>?> getPakistanMandiRate(
    String cropName, {
    MandiType type = MandiType.crops,
  }) async {
    final docId = _buildMandiRateDocId(type, cropName);
    final doc = await _db.collection('pakistan_mandi_rates').doc(docId).get();
    final data = doc.data();
    if (data == null) return null;

    final average = _toDouble(data['average']);
    final min = _toDouble(data['min']);
    final max = _toDouble(data['max']);
    if (average == null ||
        min == null ||
        max == null ||
        average <= 0 ||
        min <= 0 ||
        max <= 0) {
      return null;
    }

    return <String, double>{'average': average, 'min': min, 'max': max};
  }

  Stream<Map<String, dynamic>?> getPakistanMandiRateDocStream(
    String cropName, {
    MandiType type = MandiType.crops,
  }) {
    final docId = _buildMandiRateDocId(type, cropName);
    return _db
        .collection('pakistan_mandi_rates')
        .doc(docId)
        .snapshots()
        .map((doc) => doc.data());
  }

  /// �S& Generic File Upload (Handles Images, Videos, and Audios)
  Future<String> _uploadToStorage(
    File file,
    String storagePath, {
    void Function(double progress)? onProgress,
  }) async {
    try {
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
        throw Exception("File upload nakam hui.");
      }
      TaskSnapshot snapshot = await uploadTask;
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      throw Exception("File upload nakam hui.");
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
      } catch (_) {
        if (attempt >= maxAttempts) rethrow;
        await Future.delayed(Duration(milliseconds: 700 * attempt));
      }
    }
    throw Exception('File upload nakam hui.');
  }

  /// �S& Main Professional Method: Create Listing
  /// Is mein UI se aane wala data aur Files dono handle hotay hain.
  Future<void> createListing(
    Map<String, dynamic> data, {
    void Function(double progress)? onMediaUploadProgress,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("User authorize nahi hai.");

      final String requestedId = (data['listingId'] ?? '').toString().trim();
      final String listingId = requestedId.isNotEmpty
          ? requestedId
          : '${user.uid}_${DateTime.now().toUtc().millisecondsSinceEpoch}';
      final rawVideoPath = (data['video'] ?? '').toString().trim();
      final rawImages = (data['images'] as List?)?.cast<dynamic>() ?? const [];
      final imagePaths = rawImages
          .map((item) => item.toString().trim())
          .where((path) => path.isNotEmpty)
          .toList();
      final String rawAudioPath = (data['audioPath'] ?? '').toString().trim();

      int completedUploads = 0;
      final int totalUploads =
          imagePaths.length + (rawVideoPath.isNotEmpty ? 1 : 0) + (rawAudioPath.isNotEmpty ? 1 : 0);

      void reportProgress() {
        if (onMediaUploadProgress == null || totalUploads <= 0) return;
        onMediaUploadProgress((completedUploads / totalUploads).clamp(0.0, 1.0));
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
            final storagePath =
                'listings/$listingId/media/${now + index}.jpg';
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
              'audio_notes/${user.uid}/${DateTime.now().millisecondsSinceEpoch}.m4a';
          audioUrl = await _uploadToStorage(File(rawAudioPath), audioStoragePath);
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
        'sellerId': user.uid,
        'sellerName': data['sellerName'] ?? "Kisan Bhai",
        'mandiType': data['mandiType'] ?? MandiType.crops.wireValue,
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
        'province': data['province'],
        'district': data['district'],
        'location': data['location'],
        'locationData': data['locationData'],
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
        'status': analysis['status'] ?? 'pending',
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
      };

      // 4. Save to Firestore (explicit doc id to reduce double-submission duplicates)
      final DocumentReference docRef = _db
          .collection('listings')
          .doc(listingId);
      await docRef.set(finalData, SetOptions(merge: true));

      // 5. Automatic Admin Alert for Suspicious Price
      if (finalData['isSuspicious'] == true) {
        await _createAdminAlert(docRef.id, finalData);
      }
    } catch (e) {
      throw Exception(e.toString());
    }
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

    final Map<String, dynamic> listingData =
        listingSnap.data() ?? <String, dynamic>{};

    final double basePrice =
        _safeNumber(listingData, 'startingPrice') ??
        _safeNumber(listingData, 'basePrice') ??
        _safeNumber(listingData, 'price') ??
        0.0;
    final double currentMax =
        _safeNumber(listingData, 'highestBid') ?? basePrice;

    final bool isForceClosed = _safeBool(listingData, 'isBidForceClosed');
    if (isForceClosed) {
      throw Exception('Auction admin ne force close kar di hai.');
    }

    final bool isApproved = _safeBool(listingData, 'isApproved');
    final String status = (listingData['status'] ?? '')
        .toString()
        .toLowerCase();
    if (!isApproved || (status != 'live' && status != 'active')) {
      throw Exception('Bidding admin verification ke baad hi start hoti hai.');
    }

    final DateTime nowUtc = DateTime.now().toUtc();
    final DateTime? approvedAt = _safeDate(listingData, 'approvedAt')?.toUtc();
    final DateTime? startTime = _safeDate(listingData, 'startTime')?.toUtc();
    final DateTime biddingStart = startTime ?? approvedAt ?? nowUtc;
    final DateTime biddingEnd =
        _safeDate(listingData, 'endTime')?.toUtc() ??
        biddingStart.add(const Duration(hours: 24));

    if (nowUtc.isAfter(biddingEnd)) {
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
      throw Exception('SPAM_LOCK|Too many bids in 5 minutes. Account locked.');
    }

    final bool isSuspicious = anomalyCheck['isSuspicious'] == true;
    final String suspiciousReason =
        anomalyCheck['reason']?.toString() ?? 'Price Anomaly Detected';

    final String? oldBidderToken = listingData['lastBidderToken']?.toString();
    final String? oldBidderId = listingData['lastBidderId']?.toString();
    final String? currentToken = await FirebaseMessaging.instance.getToken();

    final bidRef = listingRef.collection('bids').doc();
    final batch = _db.batch();

    batch.set(bidRef, {
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
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    batch.update(listingRef, {
      'highestBid': bid.bidAmount,
      'highestBidAt': FieldValue.serverTimestamp(),
      'highestBidStatus': isSuspicious ? 'pending_verification' : 'verified',
      'lastBidderName': bid.buyerName,
      'lastBidderId': user.uid,
      'lastBidderToken': currentToken,
      'bid_count': FieldValue.increment(1),
      'totalBids': FieldValue.increment(1),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (isSuspicious) {
      batch.set(_db.collection('admin_alerts').doc(), {
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
        'status': 'pending_verification',
        'timestamp': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    if (oldBidderToken != null && oldBidderId != user.uid) {
      _sendOutbidNotification(oldBidderToken, bid.productName, bid.bidAmount);
    }
  }

  void _sendOutbidNotification(String token, String product, double amount) {}

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

