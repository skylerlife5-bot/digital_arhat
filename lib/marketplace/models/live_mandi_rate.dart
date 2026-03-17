import 'package:cloud_firestore/cloud_firestore.dart';

enum MandiFreshnessStatus { live, recent, aging, stale, unknown }

enum MandiSourceTrust {
  trustedLiveSource,
  trustedRecentSource,
  warmupSeed,
  fallbackCache,
  unknownSource,
}

double getTrustedDisplayPrice(LiveMandiRate record) {
  final averagePrice = record.metadata['averagePrice'];
  final avgNum = averagePrice is num
      ? averagePrice.toDouble()
      : double.tryParse('${averagePrice ?? ''}'.trim());
  if (avgNum != null && avgNum > 0) return avgNum;

  if (record.displayPriceSource == 'fqp' && record.price > 0) {
    return record.price;
  }

  if (record.minPrice != null && record.maxPrice != null) {
    final mid = (record.minPrice! + record.maxPrice!) / 2.0;
    if (mid > 0) return mid;
  }

  return record.price > 0 ? record.price : 0;
}

class LiveMandiRate {
  const LiveMandiRate({
    required this.id,
    required this.commodityName,
    required this.commodityNameUr,
    required this.categoryName,
    required this.subCategoryName,
    required this.mandiName,
    required this.city,
    required this.district,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.price,
    required this.previousPrice,
    required this.unit,
    required this.trend,
    required this.source,
    this.sourceId = '',
    this.sourceType = '',
    required this.lastUpdated,
    required this.syncedAt,
    required this.freshnessStatus,
    this.confidenceReason = '',
    this.verificationStatus = '',
    this.contributorType = '',
    this.contributorId = '',
    this.contributorVerificationStatus = '',
    this.trustScore,
    this.reliabilityScore,
    this.trustLevel = '',
    this.trustReason = '',
    this.reviewStatus = '',
    this.corroborationCount = 0,
    this.disputeCount = 0,
    this.acceptedBySystem = false,
    this.acceptedByAdmin = false,
    this.sourcePriorityRank = 99,
    this.submissionTimestamp,
    required this.isNearby,
    required this.isAiCleaned,
    required this.metadata,
    required this.categoryId,
    required this.subCategoryId,
    required this.mandiId,
    required this.currency,
    required this.confidenceScore,
    required this.isLive,
    this.raw,
    this.displayPriceSource = 'unknown',
    this.commodityRefId = '',
    this.minPrice,
    this.maxPrice,
  });

  final String id;
  final String commodityName;
  final String commodityNameUr;
  final String categoryName;
  final String subCategoryName;
  final String mandiName;
  final String city;
  final String district;
  final String province;
  final double? latitude;
  final double? longitude;
  final double price;
  final double? previousPrice;
  final String unit;
  final String trend;
  final String source;
  final String sourceId;
  final String sourceType;
  final DateTime lastUpdated;
  final DateTime? syncedAt;
  final MandiFreshnessStatus freshnessStatus;
  final String confidenceReason;
  final String verificationStatus;
  final String contributorType;
  final String contributorId;
  final String contributorVerificationStatus;
  final double? trustScore;
  final double? reliabilityScore;
  final String trustLevel;
  final String trustReason;
  final String reviewStatus;
  final int corroborationCount;
  final int disputeCount;
  final bool acceptedBySystem;
  final bool acceptedByAdmin;
  final int sourcePriorityRank;
  final DateTime? submissionTimestamp;
  final bool isNearby;
  final bool isAiCleaned;
  final Map<String, dynamic> metadata;

  final String categoryId;
  final String subCategoryId;
  final String mandiId;
  final String currency;
  final double confidenceScore;
  final bool isLive;
  final Map<String, dynamic>? raw;

  final String displayPriceSource;
  final String commodityRefId;
  final double? minPrice;
  final double? maxPrice;

  MandiSourceTrust get sourceTrust => _classifySource(source);

  bool get isTrustedSource {
    return sourceTrust == MandiSourceTrust.trustedLiveSource ||
        sourceTrust == MandiSourceTrust.trustedRecentSource;
  }

  bool get isTrustedLiveOrRecent {
    return isTrustedSource &&
        (freshnessStatus == MandiFreshnessStatus.live ||
            freshnessStatus == MandiFreshnessStatus.recent);
  }

  bool get isHumanContributor => contributorType.isNotEmpty && contributorType != 'official';

  bool get isVerifiedHumanContributor {
    return contributorType == 'verified_mandi_reporter' ||
        contributorType == 'verified_commission_agent' ||
        contributorType == 'verified_dealer';
  }

  bool get isTrustedLocalContributor => contributorType == 'trusted_local_contributor';

  bool get isLimitedConfidenceHuman {
    return isHumanContributor &&
        (reviewStatus.toLowerCase() == 'limited_confidence' ||
            verificationStatus.toLowerCase() == 'limited confidence');
  }

  bool get needsReview {
    return reviewStatus.toLowerCase() == 'needs_review' ||
        verificationStatus.toLowerCase() == 'needs review';
  }

  bool get isRejectedContribution => reviewStatus.toLowerCase() == 'rejected';

  bool get isWarmupSeed => sourceTrust == MandiSourceTrust.warmupSeed;

  bool get isStale {
    if (isWarmupSeed) return true;
    return freshnessStatus == MandiFreshnessStatus.stale ||
        freshnessStatus == MandiFreshnessStatus.unknown;
  }

  bool get isLiveFresh =>
      freshnessStatus == MandiFreshnessStatus.live && isTrustedSource;

  bool get isRecentFresh =>
      freshnessStatus == MandiFreshnessStatus.recent && isTrustedSource;

  String get freshnessLabel {
    switch (freshnessStatus) {
      case MandiFreshnessStatus.live:
        return 'Live';
      case MandiFreshnessStatus.recent:
        return 'Recent';
      case MandiFreshnessStatus.aging:
        return 'Latest Verified';
      case MandiFreshnessStatus.stale:
        return 'Stale';
      case MandiFreshnessStatus.unknown:
        return 'Unknown';
    }
  }

  /// Compact label for the price source shown on cards.
  String get displayPriceLabel {
    if (isSuspiciousRate) {
      return 'Needs Review';
    }
    switch (displayPriceSource) {
      case 'average':
        return 'Avg Rate';
      case 'fqp':
        return 'Fair Quote';
      case 'midpoint':
        return 'Estimated Midpoint';
      case 'fallback':
        return 'Latest Verified';
      case 'rawMin':
        return 'Min Rate';
      default:
        return '';
    }
  }

  bool get hasWeakComparability => metadata['comparabilityWeak'] == true;

  bool get isSuspiciousRate {
    return hasWeakComparability ||
        displayPriceSource == 'unknown' ||
        displayPriceSource == 'rawMin' ||
        metadata['outlier'] == true;
  }

  String get locationLine {
    final parts = <String>[
      city,
      district,
      province,
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList(growable: false);
    return parts.isEmpty ? 'Pakistan' : parts.join(', ');
  }

  String get lastUpdatedLabel {
    final diff = DateTime.now().toUtc().difference(lastUpdated.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get syncedAtLabel {
    final value = syncedAt;
    if (value == null) return '--';
    final diff = DateTime.now().toUtc().difference(value.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String get trendSymbol {
    switch (trend) {
      case 'up':
        return '▲';
      case 'down':
        return '▼';
      default:
        return '•';
    }
  }

  LiveMandiRate copyWith({
    String? id,
    String? categoryId,
    String? subCategoryId,
    String? categoryName,
    String? subCategoryName,
    String? commodityName,
    String? commodityNameUr,
    String? mandiId,
    String? mandiName,
    String? city,
    String? district,
    String? province,
    double? latitude,
    double? longitude,
    double? price,
    double? previousPrice,
    String? unit,
    String? currency,
    String? trend,
    String? source,
    String? sourceId,
    String? sourceType,
    double? confidenceScore,
    DateTime? lastUpdated,
    DateTime? syncedAt,
    MandiFreshnessStatus? freshnessStatus,
    String? confidenceReason,
    String? verificationStatus,
    String? contributorType,
    String? contributorId,
    String? contributorVerificationStatus,
    double? trustScore,
    double? reliabilityScore,
    String? trustLevel,
    String? trustReason,
    String? reviewStatus,
    int? corroborationCount,
    int? disputeCount,
    bool? acceptedBySystem,
    bool? acceptedByAdmin,
    int? sourcePriorityRank,
    DateTime? submissionTimestamp,
    bool? isNearby,
    bool? isLive,
    bool? isAiCleaned,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? raw,
    String? displayPriceSource,
    String? commodityRefId,
    double? minPrice,
    double? maxPrice,
  }) {
    return LiveMandiRate(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      subCategoryId: subCategoryId ?? this.subCategoryId,
      categoryName: categoryName ?? this.categoryName,
      subCategoryName: subCategoryName ?? this.subCategoryName,
      commodityName: commodityName ?? this.commodityName,
      commodityNameUr: commodityNameUr ?? this.commodityNameUr,
      mandiId: mandiId ?? this.mandiId,
      mandiName: mandiName ?? this.mandiName,
      city: city ?? this.city,
      district: district ?? this.district,
      province: province ?? this.province,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      price: price ?? this.price,
      previousPrice: previousPrice ?? this.previousPrice,
      unit: unit ?? this.unit,
      currency: currency ?? this.currency,
      trend: trend ?? this.trend,
      source: source ?? this.source,
      sourceId: sourceId ?? this.sourceId,
      sourceType: sourceType ?? this.sourceType,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      syncedAt: syncedAt ?? this.syncedAt,
      freshnessStatus: freshnessStatus ?? this.freshnessStatus,
      confidenceReason: confidenceReason ?? this.confidenceReason,
      verificationStatus: verificationStatus ?? this.verificationStatus,
      contributorType: contributorType ?? this.contributorType,
        contributorId: contributorId ?? this.contributorId,
        contributorVerificationStatus:
          contributorVerificationStatus ?? this.contributorVerificationStatus,
        trustScore: trustScore ?? this.trustScore,
        reliabilityScore: reliabilityScore ?? this.reliabilityScore,
        trustLevel: trustLevel ?? this.trustLevel,
        trustReason: trustReason ?? this.trustReason,
        reviewStatus: reviewStatus ?? this.reviewStatus,
        corroborationCount: corroborationCount ?? this.corroborationCount,
        disputeCount: disputeCount ?? this.disputeCount,
        acceptedBySystem: acceptedBySystem ?? this.acceptedBySystem,
        acceptedByAdmin: acceptedByAdmin ?? this.acceptedByAdmin,
        sourcePriorityRank: sourcePriorityRank ?? this.sourcePriorityRank,
        submissionTimestamp: submissionTimestamp ?? this.submissionTimestamp,
      isNearby: isNearby ?? this.isNearby,
      isLive: isLive ?? this.isLive,
      isAiCleaned: isAiCleaned ?? this.isAiCleaned,
      metadata: metadata ?? this.metadata,
      raw: raw ?? this.raw,
      displayPriceSource: displayPriceSource ?? this.displayPriceSource,
      commodityRefId: commodityRefId ?? this.commodityRefId,
      minPrice: minPrice ?? this.minPrice,
      maxPrice: maxPrice ?? this.maxPrice,
    );
  }

  static MandiFreshnessStatus _calculateFreshness(DateTime? timestamp) {
    if (timestamp == null) return MandiFreshnessStatus.unknown;
    final age = DateTime.now().toUtc().difference(timestamp.toUtc());
    if (age.inMinutes <= 30) return MandiFreshnessStatus.live;
    if (age.inHours <= 6) return MandiFreshnessStatus.recent;
    if (age.inHours > 24) return MandiFreshnessStatus.stale;
    return MandiFreshnessStatus.aging;
  }

  static MandiSourceTrust _classifySource(String source) {
    final value = source.trim().toLowerCase().replaceAll(' ', '_');
    if (value.isEmpty) return MandiSourceTrust.unknownSource;
    if (value.contains('warmup_seed') || value == 'warmup_seed') {
      return MandiSourceTrust.warmupSeed;
    }
    if (value.contains('fallback_cache') ||
        value.contains('cache_fallback') ||
        value.contains('offline_cache') ||
        value == 'cached_rate') {
      return MandiSourceTrust.fallbackCache;
    }
    if (value == 'trusted_live_source' || value == 'live_feed') {
      return MandiSourceTrust.trustedLiveSource;
    }
    if (value.contains('amis') ||
        value.contains('lahore_official') ||
        value.contains('karachi_official') ||
        value.contains('official')) {
      return MandiSourceTrust.trustedRecentSource;
    }
    if (value.contains('verified_human') || value.contains('human_contributor')) {
      return MandiSourceTrust.trustedRecentSource;
    }
    if (value == 'trusted_recent_source' ||
        value == 'configured_feed' ||
        value == 'amis_scrape') {
      return MandiSourceTrust.trustedRecentSource;
    }
    return MandiSourceTrust.unknownSource;
  }

  static MandiFreshnessStatus _parseFreshness(
    dynamic raw,
    DateTime? fallbackDate,
    String source,
    String sourceType,
    String contributorType,
  ) {
    final trust = _classifySource(source);
    final normalizedSourceType = sourceType.trim().toLowerCase();
    final normalizedContributorType = contributorType.trim().toLowerCase();
    final isOfficialOrHuman = normalizedSourceType.startsWith('official_') ||
        normalizedSourceType == 'human_verified' ||
        normalizedSourceType == 'human_local' ||
        normalizedContributorType == 'official' ||
        normalizedContributorType == 'verified_mandi_reporter' ||
        normalizedContributorType == 'verified_commission_agent' ||
        normalizedContributorType == 'verified_dealer' ||
        normalizedContributorType == 'trusted_local_contributor';

    if (isOfficialOrHuman) {
      final label = (raw ?? '').toString().trim().toLowerCase();
      if (label == 'live') return MandiFreshnessStatus.live;
      if (label == 'recent') return MandiFreshnessStatus.recent;
      if (label == 'stale') return MandiFreshnessStatus.stale;
      if (label == 'aging') return MandiFreshnessStatus.aging;
      return _calculateFreshness(fallbackDate);
    }

    if (trust == MandiSourceTrust.warmupSeed ||
        trust == MandiSourceTrust.fallbackCache ||
        trust == MandiSourceTrust.unknownSource) {
      return MandiFreshnessStatus.stale;
    }

    final label = (raw ?? '').toString().trim().toLowerCase();
    if (label == 'live') return MandiFreshnessStatus.live;
    if (label == 'recent') return MandiFreshnessStatus.recent;
    if (label == 'stale') return MandiFreshnessStatus.stale;
    if (label == 'aging') return MandiFreshnessStatus.aging;
    return _calculateFreshness(fallbackDate);
  }

  static LiveMandiRate fromMap(String id, Map<String, dynamic> data) {
    String pickText(List<String> keys, {String fallback = ''}) {
      for (final key in keys) {
        final value = (data[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return fallback;
    }

    double? pickDouble(List<String> keys) {
      for (final key in keys) {
        final raw = data[key];
        if (raw is num) return raw.toDouble();
        final parsed = double.tryParse((raw ?? '').toString().trim());
        if (parsed != null) return parsed;
      }
      return null;
    }

    DateTime? parseDate(dynamic raw) {
      if (raw is Timestamp) return raw.toDate().toUtc();
      if (raw is DateTime) return raw.toUtc();
      if (raw is String && raw.trim().isNotEmpty) {
        final parsed = DateTime.tryParse(raw.trim());
        if (parsed != null) return parsed.toUtc();
      }
      if (raw is num) {
        if (raw > 1000000000000) {
          return DateTime.fromMillisecondsSinceEpoch(raw.toInt(), isUtc: true);
        }
        if (raw > 1000000000) {
          return DateTime.fromMillisecondsSinceEpoch(
            raw.toInt() * 1000,
            isUtc: true,
          );
        }
      }
      return null;
    }

    DateTime pickDate(List<String> keys) {
      for (final key in keys) {
        final raw = data[key];
        final parsed = parseDate(raw);
        if (parsed != null) return parsed;
      }
      return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }

    DateTime? pickOptionalDate(List<String> keys) {
      for (final key in keys) {
        final raw = data[key];
        final parsed = parseDate(raw);
        if (parsed != null) return parsed;
      }
      return null;
    }

    final commodity = pickText(const <String>[
      'commodityName',
      'cropType',
      'cropName',
      'itemName',
      'product',
    ], fallback: 'Unknown Commodity');
    final categoryName = pickText(const <String>[
      'categoryName',
      'categoryLabel',
      'mandiType',
    ]);
    final subCategoryName = pickText(const <String>[
      'subCategoryName',
      'subcategoryLabel',
      'subcategory',
    ]);

    final price =
        (pickDouble(const <String>[
                  'price',
                  'averagePrice',
                  'average',
                  'rate',
                ]) ??
                0)
            .clamp(0, double.infinity)
            .toDouble();
    final previousPrice = pickDouble(const <String>[
      'previousPrice',
      'prevPrice',
      'lastPrice',
    ]);

    String trend = pickText(const <String>[
      'trend',
      'trendDirection',
    ]).toLowerCase();
    if (trend.isEmpty || trend == 'null') {
      if (previousPrice != null && previousPrice > 0) {
        if (price > previousPrice) trend = 'up';
        if (price < previousPrice) trend = 'down';
      }
    }
    if (trend != 'up' && trend != 'down') trend = 'same';

    final lastUpdated = pickDate(const <String>[
      'lastUpdated',
      'updatedAt',
      'sourceTimestamp',
      'rateDate',
      'createdAt',
    ]);
    final syncedAt = pickOptionalDate(const <String>['syncedAt', 'updatedAt']);
    final source = pickText(const <String>['source'], fallback: 'live_feed');
    final sourceType = pickText(const <String>['sourceType', 'ingestionSource']);
    final contributorType = pickText(const <String>['contributorType']);
    final sourceTrust = _classifySource(source);
    final freshnessStatus = _parseFreshness(
      data['freshnessStatus'],
      lastUpdated,
      source,
      sourceType,
      contributorType,
    );

    return LiveMandiRate(
      id: id,
      commodityName: commodity,
      commodityNameUr: pickText(const <String>[
        'commodityNameUr',
        'cropNameUr',
      ]),
      categoryName: categoryName,
      subCategoryName: subCategoryName,
      mandiName: pickText(const <String>[
        'mandiName',
        'marketName',
        'market',
      ], fallback: 'Pakistan Mandi'),
      city: pickText(const <String>['city']),
      district: pickText(const <String>['district', 'tehsil']),
      province: pickText(const <String>['province']),
      latitude: pickDouble(const <String>['latitude', 'lat']),
      longitude: pickDouble(const <String>['longitude', 'lng', 'lon']),
      price: price,
      previousPrice: previousPrice,
      unit: pickText(const <String>['unit'], fallback: 'per 40kg'),
      trend: trend,
      source: source,
      sourceId: pickText(const <String>['sourceId']),
      sourceType: sourceType,
      lastUpdated: lastUpdated,
      syncedAt: syncedAt,
      freshnessStatus: freshnessStatus,
      confidenceReason: pickText(const <String>['confidenceReason']),
      verificationStatus: pickText(const <String>['verificationStatus']),
      contributorType: contributorType,
      contributorId: pickText(const <String>['contributorId']),
      contributorVerificationStatus: pickText(const <String>[
        'contributorVerificationStatus',
      ]),
      trustScore: pickDouble(const <String>['trustScore']),
      reliabilityScore: pickDouble(const <String>['reliabilityScore']),
      trustLevel: pickText(const <String>['trustLevel']),
      trustReason: pickText(const <String>['trustReason']),
      reviewStatus: pickText(const <String>['reviewStatus']),
      corroborationCount: (pickDouble(const <String>['corroborationCount']) ?? 0).toInt(),
      disputeCount: (pickDouble(const <String>['disputeCount']) ?? 0).toInt(),
      acceptedBySystem: data['acceptedBySystem'] == true,
      acceptedByAdmin: data['acceptedByAdmin'] == true,
      sourcePriorityRank: (pickDouble(const <String>['sourcePriorityRank']) ?? 99).toInt(),
      submissionTimestamp: pickOptionalDate(const <String>['submissionTimestamp']),
      isNearby: data['isNearby'] == true,
      isAiCleaned: data['isAiCleaned'] == true,
      metadata: (data['metadata'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(data['metadata'] as Map<String, dynamic>)
          : <String, dynamic>{},
      categoryId: pickText(const <String>[
        'categoryId',
        'category',
      ], fallback: 'uncategorized').toLowerCase(),
      subCategoryId: pickText(const <String>[
        'subCategoryId',
        'subcategory',
      ], fallback: 'misc').toLowerCase(),
      mandiId: pickText(const <String>['mandiId', 'marketId'], fallback: id),
      currency: pickText(const <String>['currency'], fallback: 'PKR'),
      confidenceScore:
          (pickDouble(const <String>['confidenceScore', 'confidence']) ?? 0.8)
              .clamp(0, 1)
              .toDouble(),
      isLive:
          freshnessStatus == MandiFreshnessStatus.live &&
          (sourceTrust == MandiSourceTrust.trustedLiveSource ||
              sourceTrust == MandiSourceTrust.trustedRecentSource),
      raw: data,
      displayPriceSource: _deriveDisplayPriceSource(
        data: data,
        explicitValue: pickText(const <String>['displayPriceSource']),
        price: price,
        minPrice: pickDouble(const <String>['minPrice']),
        maxPrice: pickDouble(const <String>['maxPrice']),
      ),
      commodityRefId: pickText(const <String>['commodityRefId'], fallback: ''),
      minPrice: pickDouble(const <String>['minPrice']),
      maxPrice: pickDouble(const <String>['maxPrice']),
    );
  }

  /// Derives [displayPriceSource] from the raw Firestore map when the field
  /// is not explicitly set.  Official AMIS / Lahore / Karachi records typically
  /// omit this field; without derivation every such record is flagged as
  /// 'suspicious' and removed from the trustworthy Home pool.
  static String _deriveDisplayPriceSource({
    required Map<String, dynamic> data,
    required String explicitValue,
    required double price,
    required double? minPrice,
    required double? maxPrice,
  }) {
    // 1. Honour an explicit non-empty, non-unknown value from Firestore.
    if (explicitValue.isNotEmpty &&
        explicitValue.toLowerCase() != 'unknown' &&
        explicitValue.toLowerCase() != 'null') {
      return explicitValue;
    }

    // 2. averagePrice at top level (most AMIS records expose this directly).
    final avgRaw = data['averagePrice'];
    if (avgRaw is num && avgRaw > 0) return 'average';
    if (double.tryParse((avgRaw ?? '').toString().trim()) != null &&
        (double.tryParse((avgRaw ?? '').toString().trim()) ?? 0) > 0) {
      return 'average';
    }

    // 3. averagePrice inside metadata map.
    if (data['metadata'] is Map) {
      final meta = data['metadata'] as Map;
      final metaAvg = meta['averagePrice'];
      if (metaAvg is num && metaAvg > 0) return 'average';
    }

    // 4. Both min and max supplied → midpoint is computable.
    if (minPrice != null && maxPrice != null && minPrice > 0 && maxPrice > 0) {
      return 'midpoint';
    }

    // 5. At least a raw price is present → treat as fair quote price.
    if (price > 0) return 'fqp';

    return 'unknown';
  }

  Map<String, dynamic> toCacheMap() {
    return <String, dynamic>{
      'id': id,
      'categoryId': categoryId,
      'subCategoryId': subCategoryId,
      'categoryName': categoryName,
      'subCategoryName': subCategoryName,
      'commodityName': commodityName,
      'commodityNameUr': commodityNameUr,
      'mandiId': mandiId,
      'mandiName': mandiName,
      'city': city,
      'district': district,
      'province': province,
      'latitude': latitude,
      'longitude': longitude,
      'price': price,
      'previousPrice': previousPrice,
      'unit': unit,
      'currency': currency,
      'trend': trend,
      'source': source,
      'sourceId': sourceId,
      'sourceType': sourceType,
      'sourceTrust': sourceTrust.name,
      'confidenceScore': confidenceScore,
      'confidenceReason': confidenceReason,
      'verificationStatus': verificationStatus,
      'contributorType': contributorType,
      'contributorId': contributorId,
      'contributorVerificationStatus': contributorVerificationStatus,
      'trustScore': trustScore,
      'reliabilityScore': reliabilityScore,
      'trustLevel': trustLevel,
      'trustReason': trustReason,
      'reviewStatus': reviewStatus,
      'corroborationCount': corroborationCount,
      'disputeCount': disputeCount,
      'acceptedBySystem': acceptedBySystem,
      'acceptedByAdmin': acceptedByAdmin,
      'sourcePriorityRank': sourcePriorityRank,
      'submissionTimestamp': submissionTimestamp?.toIso8601String(),
      'lastUpdated': lastUpdated.toIso8601String(),
      'syncedAt': syncedAt?.toIso8601String(),
      'freshnessStatus': freshnessLabel.toLowerCase(),
      'isNearby': isNearby,
      'isLive': isLive,
      'isAiCleaned': isAiCleaned,
      'metadata': metadata,
      'displayPriceSource': displayPriceSource,
      'commodityRefId': commodityRefId,
      'minPrice': minPrice,
      'maxPrice': maxPrice,
    };
  }

  static LiveMandiRate fromCacheMap(Map<String, dynamic> map) {
    final id = (map['id'] ?? '').toString().trim();
    return fromMap(id.isEmpty ? 'cached_rate' : id, map);
  }
}
