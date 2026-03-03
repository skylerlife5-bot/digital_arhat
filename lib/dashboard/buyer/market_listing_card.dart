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
import 'payment_dialog.dart';
import '../../marketplace/listing_detail_screen.dart';
import '../../services/market_rate_service.dart';
import '../../services/marketplace_service.dart';
import '../../services/gemini_rate_service.dart';

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

  static final NumberFormat _moneyFormat = NumberFormat('#,##0', 'en_US');
  static final MarketRateService _rateService = MarketRateService();
  static final MarketplaceService _marketplaceService = MarketplaceService();
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
        data['status'] == 'awaiting_payment');
    final bool isCompletedWinner =
        isCompletedAuction &&
        highestBidderId.trim().isNotEmpty &&
        highestBidderId.trim() == currentUserId.trim();
    final double price = _parseDouble(data['price']) ?? 0;
    final double? listingMarketAverage = _parseDouble(
      data['market_average'] ?? data['marketAverage'],
    );
    final String quality = (data['quality'] ?? '').toString();
    final String? audioUrl = data['audioUrl']?.toString();
    final String videoUrl = (data['videoUrl'] ?? '').toString();
    final List<String> imageUrls = _extractImageUrls(data);
    final bool hasAnyMedia =
      imageUrls.isNotEmpty ||
      videoUrl.trim().isNotEmpty ||
      (audioUrl?.trim().isNotEmpty ?? false);

    final DateTime? endTime = _parseDate(data['endTime'])?.toUtc();
    final String listingStatus = (data['listingStatus'] ?? data['status'] ?? '')
      .toString()
      .toLowerCase();
    final bool isAwaitingPayment = listingStatus == 'awaiting_payment';
    final bool isAwaitingApproval =
      !isLive && !isCompletedAuction && !isAwaitingPayment;
    final bool isForceClosed = data['isBidForceClosed'] == true;
    final bool isBidOver = isLive && endTime != null
        ? (nowUtc.isAfter(endTime) || isForceClosed)
        : isForceClosed;
    final bool showBidOverOverlay = isBidOver && !isCompletedWinner;

    final String location = _resolveLocation(data);
    final String distanceLabel = _resolveDistance(
      data,
      buyerDistrict: buyerDistrict,
    );

    final String cropName = _resolveCropName(data);
    final String product = cropName.isEmpty ? 'Category' : cropName;
    final String unit = (data['unit'] ?? 'Munn (40kg)').toString();
    final String quantity = (data['quantity'] ?? '--').toString();
    final bool isAiVerifiedSource =
        data['isVerifiedSource'] == true &&
        (data['videoUrl'] ?? '').toString().trim().isNotEmpty;
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
          color: Colors.white.withValues(alpha: 0.08),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
          margin: const EdgeInsets.only(bottom: 12),
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
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  onTap: cropName.trim().isEmpty
                                      ? null
                                      : () => _triggerLivePakistanRateFetch(
                                          cropName,
                                          type: resolvedType,
                                        ),
                                  child: Text(
                                    product.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      decoration: TextDecoration.underline,
                                      decorationColor: Colors.white54,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Wrap(
                                spacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  _categoryChip(resolvedType, accentColor),
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
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ..._buildAiBadges(
                                price: price,
                                marketAverage: listingMarketAverage,
                                quality: quality,
                                product: product,
                                cropName: cropName,
                                location: location,
                                resolvedType: resolvedType,
                                accentColor: accentColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
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
                            color: Colors.greenAccent,
                            fontSize: 20,
                          ),
                        ),
                        if (isAiVerifiedSource)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 14,
                                  color: Color(0xFFFFD700),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'AI Verified',
                                  style: TextStyle(
                                    color: Color(0xFFFFD700),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
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
                        color: Colors.white54,
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
                              '$location ⬢ $distanceLabel',
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
                Row(
                  children: [
                    Expanded(
                      child: isCompletedWinner
                          ? SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  showDialog<void>(
                                    context: context,
                                    builder: (_) => PaymentDialog(
                                      listingId: listingId,
                                      listingData: data,
                                    ),
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF00C853),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  textStyle: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                child: const Text('Payment Karein'),
                              ),
                            )
                          : SizedBox(
                              height: 48,
                              child: PrimaryGradientButton(
                                height: 48,
                                fontSize: 13,
                                onPressed: (isBidOver || isAwaitingApproval)
                                    ? null
                                    : () => onBid(data, listingId),
                                label: isBidOver ? 'Boli Khatam' : 'Boli Lagaen',
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: SizedBox(
                      height: 48,
                      child: OutlinedButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ListingDetailScreen(
                                  listingId: listingId,
                                  initialData: data,
                                ),
                              ),
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Color(0xFFFFD700)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Details',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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
      case MandiType.livestock:
        return const Color(0xFF6D4C41);
      case MandiType.milk:
        return const Color(0xFF1565C0);
      case MandiType.fruit:
        return const Color(0xFFEF6C00);
      case MandiType.vegetables:
        return const Color(0xFF00897B);
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
    final String city = (data['city'] ?? '').toString().trim();
    if (city.isNotEmpty && city.toLowerCase() != 'null') {
      return city;
    }

    final String location = (data['location'] ?? '').toString().trim();
    if (location.isNotEmpty && location.toLowerCase() != 'null') {
      return location;
    }

    return 'Mandi Location';
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
    final String district = (data['district'] ?? '').toString().trim();
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
    addIfValid(rawData['image1']);
    addIfValid(rawData['image2']);
    addIfValid(rawData['image3']);
    addIfValid(rawData['image4']);

    final dynamic imagesRaw = rawData['images'];
    if (imagesRaw is List) {
      for (final item in imagesRaw) {
        addIfValid(item);
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

