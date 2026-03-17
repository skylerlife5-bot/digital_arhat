import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:developer' as developer;
import '../../core/constants.dart';
import '../../core/widgets/media_preview_widget.dart';
import '../../core/widgets/primary_gradient_button.dart';
import '../../routes.dart';
import 'buyer_listing_detail_screen.dart';
import '../../services/buyer_engagement_service.dart';
import '../../services/market_rate_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/gemini_rate_service.dart';
import '../../services/trust_safety_service.dart';
import '../../theme/app_colors.dart';

import '../components/bid_timer.dart';

class MarketListingCard extends StatelessWidget {
  const MarketListingCard({
    super.key,
    required this.data,
    required this.listingId,
    required this.goldColor,
    required this.currentlyPlayingUrl,
    required this.buyerDistrict,
    required this.selectedMandiType,
    required this.onPlayAudio,
    required this.onBid,
  });

  final Map<String, dynamic> data;
  final String listingId;
  final Color goldColor;
  final String? currentlyPlayingUrl;
  final String buyerDistrict;
  final MandiType? selectedMandiType;
  final void Function(String url) onPlayAudio;
  final void Function(Map<String, dynamic> data, String listingId) onBid;

  bool _isPromotionActive(Map<String, dynamic> map) {
    final status = (map['promotionStatus'] ?? '').toString().toLowerCase();
    if (status == 'active') {
      final expires = map['promotionExpiresAt'];
      if (expires is Timestamp && expires.toDate().isBefore(DateTime.now())) {
        return false;
      }
      return true;
    }
    if (status.isNotEmpty && status != 'none') return false;
    return map['featured'] == true ||
      map['featuredAuction'] == true ||
        (map['priorityScore'] ?? '').toString().toLowerCase() == 'high';
  }

  static final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en_US');
  static final MarketRateService _rateService = MarketRateService();
  static final MarketplaceService _marketplaceService = MarketplaceService();
  static final BuyerEngagementService _engagementService =
      BuyerEngagementService();
  static final GeminiRateService _geminiRateService = GeminiRateService();
  static final ValueNotifier<Set<String>> _liveFetchingCrops =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<Map<String, String>> _liveFetchErrors =
      ValueNotifier<Map<String, String>>(<String, String>{});
  static final ValueNotifier<Set<String>> _aiRateFetchingKeys =
      ValueNotifier<Set<String>>(<String>{});
  static final ValueNotifier<Map<String, double>> _aiRateCache =
      ValueNotifier<Map<String, double>>(<String, double>{});

  static void _setLiveFetching(String cropKey, bool fetching) {
    final next = Set<String>.from(_liveFetchingCrops.value);
    if (fetching) {
      next.add(cropKey);
    } else {
      next.remove(cropKey);
    }
    _liveFetchingCrops.value = next;
  }

  static void _setLiveFetchError(String cropKey, String? errorMessage) {
    final next = Map<String, String>.from(_liveFetchErrors.value);
    if (errorMessage == null || errorMessage.trim().isEmpty) {
      next.remove(cropKey);
    } else {
      next[cropKey] = errorMessage;
    }
    _liveFetchErrors.value = next;
  }

  static void _setAiRateFetching(String rateKey, bool fetching) {
    final next = Set<String>.from(_aiRateFetchingKeys.value);
    if (fetching) {
      next.add(rateKey);
    } else {
      next.remove(rateKey);
    }
    _aiRateFetchingKeys.value = next;
  }

  static void _cacheAiRate(String rateKey, double rate) {
    final next = Map<String, double>.from(_aiRateCache.value);
    next[rateKey] = rate;
    _aiRateCache.value = next;
  }

  String _firstText(Map<String, dynamic> rawData, List<String> keys) {
    for (final key in keys) {
      final value = (rawData[key] ?? '').toString().trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }
    final media = rawData['mediaMetadata'];
    if (media is Map) {
      for (final key in keys) {
        final value = (media[key] ?? '').toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      final verification = media['verificationVideo'];
      if (verification is Map) {
        final url = (verification['url'] ?? '').toString().trim();
        if (url.isNotEmpty && url.toLowerCase() != 'null') return url;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final DateTime nowUtc = DateTime.now().toUtc();
    final String auctionStatus = (data['auctionStatus'] ?? data['status'] ?? '')
        .toString()
        .toLowerCase();
    final bool isLive = auctionStatus == 'live' || auctionStatus == 'active';
    final bool isCompletedAuction = auctionStatus == 'completed';
    final String highestBidderId =
        (data['highestBidderId'] ??
                data['lastBidderId'] ??
                data['buyerId'] ??
                '')
            .toString();
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    final bool isWinner =
        (currentUserId == (data['winnerId'] ?? '') ||
      data['status'] == 'bid_accepted' ||
      data['status'] == 'approved_winner');
    final bool isCompletedWinner =
        isCompletedAuction &&
        highestBidderId.trim().isNotEmpty &&
        highestBidderId.trim() == currentUserId.trim();
    final String sellerId = (data['sellerId'] ?? '').toString().trim();
    final double price = _parseDouble(data['price']) ?? 0;
    final String quality = (data['quality'] ?? '').toString();
    final String? audioUrl = _firstText(data, const ['audioUrl', 'voiceUrl', 'audioURL']).trim().isEmpty
        ? null
        : _firstText(data, const ['audioUrl', 'voiceUrl', 'audioURL']);
    final String videoUrl = _firstText(data, const [
      'videoUrl',
      'verificationVideoUrl',
      'videoURL',
      'mediaVideoUrl',
    ]);
    final List<String> imageUrls = _extractImageUrls(data);
    final bool hasAnyMedia =
        imageUrls.isNotEmpty ||
        videoUrl.trim().isNotEmpty ||
        (audioUrl?.trim().isNotEmpty ?? false);

    final DateTime? endTime = _parseDate(data['endTime'])?.toUtc();
    final String listingStatus = (data['listingStatus'] ?? data['status'] ?? '')
        .toString()
        .toLowerCase();
    final bool isAcceptedState =
      listingStatus == 'bid_accepted' || listingStatus == 'approved_winner';
    final bool isAwaitingApproval =
      !isLive && !isCompletedAuction && !isAcceptedState;
    final bool isForceClosed = data['isBidForceClosed'] == true;
    final bool isBidOver = isLive && endTime != null
        ? (nowUtc.isAfter(endTime) || isForceClosed)
        : isForceClosed;
    final bool showBidOverOverlay = isBidOver && !isCompletedWinner;

    final String location = _resolveLocation(data);
    final String locationTrail = _resolveLocationTrail(data);
    final String distanceLabel = _resolveDistance(
      data,
      buyerDistrict: buyerDistrict,
    );

    final String cropName = _resolveCropName(data);
    final String product = cropName.isEmpty ? 'Category' : cropName;
    final String unit = (data['unit'] ?? 'Munn (40kg)').toString();
    final String quantity = (data['quantity'] ?? '--').toString();
    final String saleType = (data['saleType'] ?? 'auction').toString().trim().toLowerCase();
    final bool isFixedSale = saleType == 'fixed';
    final bool isFeatured = _isPromotionActive(data);
    final int bidCount = _resolveBidCount(data);
    final int watchersCount = _watchersCountValue(data);
    final String? engagementLabel = _auctionEngagementLabel(
      bidCount: bidCount,
      watchersCount: watchersCount,
    );
    final trustBadges = TrustSafetyService.resolveBuyerTrustBadges(
      listingData: data,
    );
    final primaryTrustBadge = _primaryTrustBadgeLabel(
      data: data,
      trustBadges: trustBadges,
    );
    final MandiType resolvedType = _resolveMandiType(
      data,
      preferred: selectedMandiType,
    );
    final Color accentColor = _accentForType(resolvedType);

    final bool isDiscounted = _isDiscounted(data, price);
    final double? originalPrice = _parseDouble(data['originalPrice']);

    return Stack(
      children: [
        Card(
          color: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: AppColors.secondarySurface,
            ),
          ),
          margin: const EdgeInsets.only(bottom: 12),
          shadowColor: AppColors.shadowDark,
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: cropName.trim().isEmpty
                                ? null
                                : () => _triggerLivePakistanRateFetch(
                                    cropName,
                                    type: resolvedType,
                                  ),
                            child: Text(
                              product,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.22,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white54,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _categoryChip(resolvedType, accentColor),
                              _badge(
                                isFixedSale
                                    ? 'Fixed Price / فکسڈ قیمت'
                                    : 'Auction / بولی',
                                isFixedSale
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFFF59E0B),
                              ),
                              if (audioUrl != null && audioUrl.isNotEmpty)
                                IconButton(
                                  padding: const EdgeInsets.only(left: 4),
                                  constraints: const BoxConstraints(),
                                  icon: Icon(
                                    currentlyPlayingUrl == audioUrl
                                        ? Icons.stop_circle
                                        : Icons.play_circle_fill,
                                    color: goldColor,
                                    size: 24,
                                  ),
                                  onPressed: () => onPlayAudio(audioUrl),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (isFeatured)
                                _badge('FEATURED', AppColors.badgeFeatured),
                              if (primaryTrustBadge != null)
                                _badge(primaryTrustBadge, AppColors.badgeVerified),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (!isFixedSale)
                          _buildWatchlistButton(
                            context,
                            sellerId: sellerId,
                          ),
                        const SizedBox(height: 6),
                        if (isDiscounted && originalPrice != null)
                          Text(
                            'Rs. ${_moneyFormat.format(originalPrice)}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        Text(
                          'Rs. ${_moneyFormat.format(price)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.badgeVerified,
                            fontSize: 20,
                          ),
                        ),
                        if (!isFixedSale && engagementLabel != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            engagementLabel,
                            style: const TextStyle(
                              color: Color(0xFFEFD88A),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        if (!isFixedSale) ...[
                          const SizedBox(height: 8),
                          const Text(
                            'Time Left',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          CountdownWidget(
                            endTime: isAwaitingApproval ? null : endTime,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (quality.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      'Quality: $quality',
                      style: const TextStyle(
                          color: AppColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (hasAnyMedia)
                  MediaPreviewWidget(
                    imageUrls: imageUrls,
                    videoUrl: videoUrl,
                    audioUrl: audioUrl,
                    title: 'Media Section',
                  )
                else
                  Container(
                    height: 120,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: Colors.white54,
                          size: 30,
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Image not available',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '${locationTrail.isEmpty ? location : locationTrail} ⬢ $distanceLabel',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          const Icon(
                            Icons.scale,
                            size: 14,
                            color: Colors.white38,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '$quantity $unit',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 25, color: Colors.white10),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: isCompletedWinner
                      ? ElevatedButton(
                          onPressed: null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF5E8D6E),
                            foregroundColor: Colors.white70,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          child: const Text('Accepted / قبول شدہ'),
                        )
                      : PrimaryGradientButton(
                          height: 48,
                          fontSize: 13,
                          onPressed: (isBidOver || isAwaitingApproval)
                              ? null
                              : () {
                                  if (isFixedSale) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => BuyerListingDetailScreen(
                                          listingId: listingId,
                                          initialData: data,
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  onBid(data, listingId);
                                },
                          label: isFixedSale
                              ? 'تفصیل دیکھیں'
                              : (isBidOver ? 'Boli Khatam' : 'Boli Lagaen'),
                        ),
                ),
              ],
            ),
          ),
        ),
        if (!isWinner && showBidOverOverlay)
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'Waqt Khatam',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  int _resolveBidCount(Map<String, dynamic> map) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final values = <int>[
      parseInt(map['totalBids']),
      parseInt(map['bidsCount']),
      parseInt(map['bidCount']),
      parseInt(map['bid_count']),
    ];
    return values.reduce((a, b) => a > b ? a : b);
  }

  int _watchersCountValue(Map<String, dynamic> map) {
    int parseInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse((value ?? '').toString()) ?? 0;
    }

    final resolved = parseInt(map['watchersCount']);
    return resolved < 0 ? 0 : resolved;
  }

  String? _auctionEngagementLabel({
    required int bidCount,
    required int watchersCount,
  }) {
    final parts = <String>[];
    if (bidCount > 0) {
      parts.add('🔥 $bidCount bids');
    }
    if (watchersCount > 0) {
      parts.add('👁️ $watchersCount watching');
    }
    if (parts.isEmpty) return null;
    return parts.join('   ');
  }

  Future<void> _triggerLivePakistanRateFetch(
    String cropName, {
    required MandiType type,
  }) async {
    final crop = cropName.trim();
    if (crop.isEmpty) return;

    final cropKey = crop.toLowerCase();
    if (_liveFetchingCrops.value.contains(cropKey)) return;

    _setLiveFetching(cropKey, true);
    _setLiveFetchError(cropKey, null);
    try {
      developer.log(
        'PAKISTAN_MANDI_LIVE_FETCH|type=${type.wireValue}|item=$crop',
      );
      await _marketplaceService.syncPakistanMandiRates(
        crops: <String>[crop],
        forcedType: type,
      );
    } catch (e) {
      _setLiveFetchError(cropKey, e.toString());
    } finally {
      _setLiveFetching(cropKey, false);
    }
  }

  Widget _buildWatchlistButton(
    BuildContext context, {
    required String sellerId,
  }) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && sellerId.isNotEmpty && sellerId == user.uid) {
      return const SizedBox.shrink();
    }

    if (user == null) {
      return IconButton(
        tooltip: 'Watch auction',
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              duration: Duration(seconds: 3),
              content: Text('Login required to watch auctions'),
            ),
          );
          Navigator.of(context).pushNamed(Routes.login);
        },
        icon: const Icon(
          Icons.star_border_rounded,
          color: Color(0xFFD4AF37),
          size: 22,
        ),
      );
    }

    return StreamBuilder<bool>(
      stream: _engagementService.isListingSavedStream(listingId),
      builder: (context, snapshot) {
        final isSaved = snapshot.data ?? false;
        return IconButton(
          tooltip: isSaved ? 'Watching' : 'Watch',
          onPressed: () async {
            final saved = await _engagementService.toggleWatchlist(
              listingId: listingId,
              listingData: data,
            );
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                duration: const Duration(seconds: 2),
                content: Text(
                  saved ? 'Watching this auction' : 'Removed from watchlist',
                ),
              ),
            );
          },
          icon: Icon(
            isSaved ? Icons.star_rounded : Icons.star_border_rounded,
            color: isSaved ? const Color(0xFFEFD88A) : const Color(0xFFD4AF37),
            size: 22,
          ),
        );
      },
    );
  }

  Future<void> _triggerAiFallbackRateFetch({
    required String rateKey,
    required String cropName,
    required String location,
    required double listingPrice,
  }) async {
    if (_aiRateFetchingKeys.value.contains(rateKey)) return;

    _setAiRateFetching(rateKey, true);
    try {
      final aiRate = await _geminiRateService.getAverageRateFromGeminiFallback(
        item: cropName,
        location: location,
        fallbackListingPrice: listingPrice,
      );
      if (aiRate != null && aiRate > 0) {
        _cacheAiRate(rateKey, aiRate);
      }
    } catch (_) {
      if (listingPrice > 0) {
        _cacheAiRate(rateKey, listingPrice);
      }
    } finally {
      _setAiRateFetching(rateKey, false);
    }
  }

  // ignore: unused_element
  List<Widget> _buildAiBadges({
    required double price,
    required double? marketAverage,
    required String quality,
    required String product,
    required String cropName,
    required String location,
    required MandiType resolvedType,
    required Color accentColor,
  }) {
    final showAiSignals = (data['showAiSignalsForBuyer'] == true);
    if (!showAiSignals) return const <Widget>[];

    final cropForRate = cropName.trim().isEmpty ? product : cropName;
    final bool hasCrop = cropForRate.trim().isNotEmpty;
    final cropKey = cropForRate.trim().toLowerCase();
    final rateKey =
        '${cropForRate.trim().toLowerCase()}|${location.trim().toLowerCase()}';

    return [
      ValueListenableBuilder<Set<String>>(
        valueListenable: _liveFetchingCrops,
        builder: (context, fetchingCrops, child) {
          return ValueListenableBuilder<Map<String, String>>(
            valueListenable: _liveFetchErrors,
            builder: (context, errorMap, child) {
              final isLiveFetching = fetchingCrops.contains(cropKey);
              final String? fetchError = errorMap[cropKey];

              return StreamBuilder<Map<String, dynamic>?>(
                stream: hasCrop
                    ? _marketplaceService.getPakistanMandiRateDocStream(
                        cropForRate,
                        type: resolvedType,
                      )
                    : null,
                builder: (context, cacheSnapshot) {
                  final cacheData = cacheSnapshot.data;
                  final cacheAverage = _parseDouble(cacheData?['average']);
                  final DateTime? lastSynced = _parseDate(
                    cacheData?['updatedAt'] ?? cacheData?['syncedAt'],
                  );
                  final trendAverage = _rateService.getAIVerifiedRateStream(
                    cropForRate,
                  );

                  return StreamBuilder<double?>(
                    stream: hasCrop ? trendAverage : null,
                    builder: (context, trendSnapshot) {
                      return ValueListenableBuilder<Map<String, double>>(
                        valueListenable: _aiRateCache,
                        builder: (context, aiCache, child) {
                          return ValueListenableBuilder<Set<String>>(
                            valueListenable: _aiRateFetchingKeys,
                            builder: (context, fetchingKeys, child) {
                              final aiFallbackRate = aiCache[rateKey];
                              final resolvedAverage =
                                  cacheAverage ??
                                  trendSnapshot.data ??
                                  marketAverage ??
                                  aiFallbackRate;
                              final chips = <Widget>[];

                              if (isLiveFetching) {
                                chips.add(
                                  _shimmerBadge(
                                    'Fetching Live Pakistan Mandi Rates...',
                                  ),
                                );
                              }

                              final streamError = cacheSnapshot.hasError
                                  ? cacheSnapshot.error.toString()
                                  : null;
                              final activeError = fetchError ?? streamError;
                              if (activeError != null &&
                                  activeError.trim().isNotEmpty) {
                                chips.add(_shimmerBadge('Insight Loading...'));
                              }

                              if (resolvedAverage != null &&
                                  resolvedAverage > 0) {
                                final source = cacheAverage != null
                                    ? 'pakistan_cache'
                                    : (trendSnapshot.data != null
                                          ? 'trend'
                                          : (marketAverage != null
                                                ? 'listing'
                                                : 'gemini_fallback'));
                                developer.log(
                                  'MANDI_UI_RATE|type=${resolvedType.wireValue}|crop=$cropForRate|source=$source|average=$resolvedAverage',
                                );

                                final deviationPercent =
                                    (((price - resolvedAverage).abs()) /
                                        resolvedAverage) *
                                    100;
                                if (price > 0 && price < resolvedAverage) {
                                  chips.add(
                                    _badge(
                                      'AI: Sasta Maal',
                                      Colors.lightGreenAccent,
                                    ),
                                  );
                                }
                                if (price > 0 && deviationPercent <= 10) {
                                  chips.add(
                                    _badge(
                                      'Verified by Digital Arhat AI',
                                      accentColor,
                                    ),
                                  );
                                }

                                final isAiMashwara =
                                    cacheAverage == null &&
                                    trendSnapshot.data == null &&
                                    marketAverage == null;

                                if (isAiMashwara) {
                                  chips.add(
                                    _badge(
                                      'AI Mashwara (Average Rate): Rs. ${_moneyFormat.format(resolvedAverage)}',
                                      Colors.cyanAccent,
                                    ),
                                  );
                                  chips.add(
                                    _badge(
                                      'Ye rate pichlay chand dino ki boliyon par mabni hai.',
                                      Colors.white70,
                                    ),
                                  );
                                } else {
                                  chips.add(
                                    _badge(
                                      'Pakistan Mandi Rate: Rs. ${_moneyFormat.format(resolvedAverage)}',
                                      Colors.cyanAccent,
                                    ),
                                  );
                                }
                              } else {
                                if (!fetchingKeys.contains(rateKey)) {
                                  unawaited(
                                    _triggerAiFallbackRateFetch(
                                      rateKey: rateKey,
                                      cropName: cropForRate,
                                      location: location,
                                      listingPrice: price,
                                    ),
                                  );
                                }
                                chips.add(
                                  _shimmerBadge(
                                    'AI Mashwara load ho raha hai...',
                                  ),
                                );
                              }

                              if (lastSynced != null) {
                                chips.add(
                                  _badge(
                                    'Last Synced: ${DateFormat('hh:mm a').format(lastSynced.toLocal())}',
                                    Colors.white70,
                                  ),
                                );
                              }

                              if (quality.toLowerCase() == 'a-grade') {
                                chips.add(
                                  _badge(
                                    'AI: Top Quality',
                                    const Color(0xFFFFD700),
                                  ),
                                );
                              }

                              return GestureDetector(
                                onTap: hasCrop
                                    ? () => _triggerLivePakistanRateFetch(
                                        cropForRate,
                                        type: resolvedType,
                                      )
                                    : null,
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: chips,
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    ];
  }

  String? _primaryTrustBadgeLabel({
    required Map<String, dynamic> data,
    required List<TrustBadge> trustBadges,
  }) {
    final hasVerified = trustBadges.any(
      (badge) => badge.key == 'verified' || badge.key == 'trusted',
    );
    if (hasVerified) return 'Verified Seller';
    if (data['isApproved'] == true) return 'Admin Approved';
    return null;
  }

  MandiType _resolveMandiType(
    Map<String, dynamic> rawData, {
    MandiType? preferred,
  }) {
    try {
      if (preferred != null) {
        return preferred;
      }

      final rawType = (rawData['mandiType'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      for (final type in MandiType.values) {
        if (type.wireValue == rawType) return type;
      }

      final product = _resolveCropName(rawData).toLowerCase();
      if (product.contains('milk') || product.contains('doodh')) {
        return MandiType.milk;
      }
      if (product.contains('goat') ||
          product.contains('bakra') ||
          product.contains('bhains') ||
          product.contains('bail')) {
        return MandiType.livestock;
      }
      if (product.contains('aam') ||
          product.contains('mango') ||
          product.contains('apple') ||
          product.contains('banana')) {
        return MandiType.fruit;
      }
      if (product.contains('aloo') ||
          product.contains('pyaz') ||
          product.contains('tamatar') ||
          product.contains('potato')) {
        return MandiType.vegetables;
      }
    } catch (e) {
      developer.log('MANDI_TYPE_RESOLVE_ERROR|error=$e');
    }
    return MandiType.crops;
  }

  Widget _shimmerBadge(String text) {
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.cyanAccent.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.7)),
          ),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.cyanAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: Colors.white.withValues(alpha: 0.55),
        );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _categoryChip(MandiType type, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.75)),
      ),
      child: Text(
        '${type.wireValue} MARKET',
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Color _accentForType(MandiType type) {
    switch (type) {
      case MandiType.crops:
        return const Color(0xFF2E7D32);
      case MandiType.fruit:
        return const Color(0xFFEF6C00);
      case MandiType.vegetables:
        return const Color(0xFF00897B);
      case MandiType.flowers:
        return const Color(0xFFEC4899);
      case MandiType.livestock:
        return const Color(0xFF6D4C41);
      case MandiType.milk:
        return const Color(0xFF1565C0);
      case MandiType.seeds:
        return const Color(0xFFB45309);
      case MandiType.fertilizer:
        return const Color(0xFF0EA5A4);
      case MandiType.machinery:
        return const Color(0xFF4B5563);
      case MandiType.tools:
        return const Color(0xFF475569);
      case MandiType.dryFruits:
        return const Color(0xFFA16207);
      case MandiType.spices:
        return const Color(0xFFDC2626);
    }
  }

  bool _isDiscounted(Map<String, dynamic> data, double price) {
    final bool discountedFlag = data['isDiscounted'] == true;
    final original = _parseDouble(data['originalPrice']);
    return discountedFlag ||
        (original != null && original > price && price > 0);
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _parseDate(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  String _resolveLocation(Map<String, dynamic> data) {
    final locationDataRaw = data['locationData'];
    final locationData = locationDataRaw is Map
        ? Map<String, dynamic>.from(locationDataRaw)
        : const <String, dynamic>{};

    final String city = (data['city'] ?? locationData['city'] ?? '')
        .toString()
        .trim();
    if (city.isNotEmpty && city.toLowerCase() != 'null') {
      return city;
    }

    final String tehsil = (data['tehsil'] ?? locationData['tehsil'] ?? '')
        .toString()
        .trim();
    if (tehsil.isNotEmpty && tehsil.toLowerCase() != 'null') {
      return tehsil;
    }

    final String district = (data['district'] ?? locationData['district'] ?? '')
        .toString()
        .trim();
    if (district.isNotEmpty && district.toLowerCase() != 'null') {
      return district;
    }

    final String location = (data['location'] ?? '').toString().trim();
    if (location.isNotEmpty && location.toLowerCase() != 'null') {
      return location;
    }

    final String province = (data['province'] ?? locationData['province'] ?? '')
        .toString()
        .trim();
    if (province.isNotEmpty && province.toLowerCase() != 'null') {
      return province;
    }

    return 'Pakistan';
  }

  String _resolveLocationTrail(Map<String, dynamic> data) {
    final locationDataRaw = data['locationData'];
    final locationData = locationDataRaw is Map
        ? Map<String, dynamic>.from(locationDataRaw)
        : const <String, dynamic>{};

    final city = (data['city'] ?? locationData['city'] ?? '').toString().trim();
    final district = (data['district'] ?? locationData['district'] ?? '').toString().trim();
    final province = (data['province'] ?? locationData['province'] ?? '').toString().trim();

    final parts = <String>[city, district, province]
        .where((e) => e.isNotEmpty && e.toLowerCase() != 'null')
        .toList(growable: false);
    return parts.join(', ');
  }

  String _resolveCropName(Map<String, dynamic> data) {
    final candidates = [
      data['cropName'],
      data['productName'],
      data['product'],
      data['crop'],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty && value.toLowerCase() != 'null') {
        return value;
      }
    }

    return '';
  }

  String _resolveDistance(
    Map<String, dynamic> data, {
    required String buyerDistrict,
  }) {
    final double? km = _parseDouble(data['distanceKm'] ?? data['distance_km']);
    if (km != null) {
      final formatted = km % 1 == 0
          ? km.toInt().toString()
          : km.toStringAsFixed(1);
      return '$formatted km door';
    }

    final String sellerDistrict = _resolveDistrict(data);
    final double estimatedKm = _estimateDistanceKm(
      buyerDistrict: buyerDistrict,
      sellerDistrict: sellerDistrict,
    );

    final formatted = estimatedKm % 1 == 0
        ? estimatedKm.toInt().toString()
        : estimatedKm.toStringAsFixed(1);
    return '$formatted km door';
  }

  String _resolveDistrict(Map<String, dynamic> data) {
    final locationDataRaw = data['locationData'];
    final locationData = locationDataRaw is Map
        ? Map<String, dynamic>.from(locationDataRaw)
        : const <String, dynamic>{};

    final String district = (data['district'] ?? locationData['district'] ?? '')
        .toString()
        .trim();
    if (district.isNotEmpty && district.toLowerCase() != 'null') {
      return district;
    }

    final String location = (data['location'] ?? '').toString();
    if (location.trim().isNotEmpty) {
      final first = location.split(',').first.trim();
      if (first.isNotEmpty && first.toLowerCase() != 'null') {
        return first;
      }
    }

    final String city = (data['city'] ?? '').toString().trim();
    if (city.isNotEmpty && city.toLowerCase() != 'null') {
      return city;
    }

    return 'Punjab';
  }

  double _estimateDistanceKm({
    required String buyerDistrict,
    required String sellerDistrict,
  }) {
    final b = buyerDistrict.toLowerCase().trim();
    final s = sellerDistrict.toLowerCase().trim();
    if (b.isEmpty || s.isEmpty || b == s) return 12;

    final key = [b, s]..sort();
    final pair = key.join('|');

    return AppConstants.districtDistancePairsKm[pair] ?? 120.0;
  }

  List<String> _extractImageUrls(Map<String, dynamic> rawData) {
    final urls = <String>[];

    void addIfValid(dynamic value) {
      final candidate = (value ?? '').toString().trim();
      if (candidate.isEmpty || candidate.toLowerCase() == 'null') return;
      if (!candidate.startsWith('http')) return;
      if (!urls.contains(candidate)) {
        urls.add(candidate);
      }
    }

    addIfValid(rawData['imageUrl']);
    addIfValid(rawData['photoUrl']);
    addIfValid(rawData['trustPhotoUrl']);
    addIfValid(rawData['verificationTrustPhotoUrl']);
    addIfValid(rawData['image1']);
    addIfValid(rawData['image2']);
    addIfValid(rawData['image3']);
    addIfValid(rawData['image4']);

    final dynamic imageUrlsRaw = rawData['imageUrls'];
    if (imageUrlsRaw is List) {
      for (final item in imageUrlsRaw) {
        addIfValid(item);
      }
    }

    final dynamic imagesRaw = rawData['images'];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        addIfValid(item);
      }
    }

    final media = rawData['mediaMetadata'];
    if (media is Map) {
      final mediaImageUrls = media['imageUrls'];
      if (mediaImageUrls is List) {
        for (final item in mediaImageUrls) {
          addIfValid(item);
        }
      }
      final trust = media['verificationTrustPhoto'];
      if (trust is Map) {
        addIfValid(trust['url']);
      }
    }

    return urls.take(4).toList();
  }
}

class CountdownWidget extends StatelessWidget {
  final DateTime? endTime;

  const CountdownWidget({super.key, required this.endTime});

  @override
  Widget build(BuildContext context) {
    return BidTimer(endTime: endTime);
  }
}
