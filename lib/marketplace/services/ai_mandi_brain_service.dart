import '../../core/constants.dart';
import '../models/ai_mandi_brain_insight.dart';
import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';
import 'mandi_rate_location_service.dart';
import 'mandi_rate_prioritization_service.dart';

class AiMandiBrainService {
  AiMandiBrainService({
    MandiRatesRepository? repository,
    MandiRateLocationService? locationService,
    MandiRatePrioritizationService? ranker,
  }) : _repository = repository ?? MandiRatesRepository(),
       _locationService = locationService ?? const MandiRateLocationService(),
       _ranker = ranker ?? const MandiRatePrioritizationService();

  final MandiRatesRepository _repository;
  final MandiRateLocationService _locationService;
  final MandiRatePrioritizationService _ranker;

  Future<List<AiMandiBrainInsight>> buildInsights({
    required List<Map<String, dynamic>> listings,
    required List<String> pulseCommodityHints,
    MandiType? selectedCategory,
    String? accountCity,
    String? accountDistrict,
    String? accountProvince,
  }) async {
    final location = await _locationService.resolve(
      fallbackCity: accountCity,
      fallbackDistrict: accountDistrict,
      fallbackProvince: accountProvince,
    );

    var rates = await _repository.fetchLocationAwareCandidates(
      location: location,
      targetCount: 180,
    );

    rates = rates.where(_isUsableRate).toList(growable: false);
    if (selectedCategory != null) {
      final key = selectedCategory.wireValue.toLowerCase();
      rates = rates
          .where((rate) {
            final data = '${rate.categoryName} ${rate.categoryId}'.toLowerCase();
            return data.contains(key);
          })
          .toList(growable: false);
    }

    final rankedRates = _ranker.rank(rates: rates, location: location);
    final groups = _groupByCommodity(rankedRates);
    final pulseKeys = pulseCommodityHints
        .map(_norm)
        .where((value) => value.isNotEmpty)
        .toSet();

    final candidates = <AiMandiBrainInsight>[];

    final nearby = _buildNearbyInsights(groups);
    if (nearby != null) candidates.add(nearby);

    final comparison = _buildComparisonInsight(groups);
    if (comparison != null) candidates.add(comparison);

    final movement = _buildMovementInsight(rankedRates);
    if (movement != null) candidates.add(movement);

    final demand = _buildDemandInsight(listings);
    if (demand != null) candidates.add(demand);

    final auction = _buildAuctionStrengthInsight(listings);
    if (auction != null) candidates.add(auction);

    final filtered = candidates.where((insight) {
      final key = _norm(insight.commodity);
      final movementOnly = insight.evidenceTags.length == 1 &&
          insight.evidenceTags.contains('verified_movement');

      // Anti-duplication with pulse: suppress movement-only repeats for the
      // same commodity if pulse already surfaced it.
      if (movementOnly && pulseKeys.contains(key)) {
        return false;
      }
      return true;
    }).toList(growable: false);

    filtered.sort((a, b) => b.priority.compareTo(a.priority));

    final output = <AiMandiBrainInsight>[];
    final seenCommodity = <String>{};
    for (final insight in filtered) {
      final key = _norm(insight.commodity);
      if (seenCommodity.add(key) || output.isEmpty) {
        output.add(insight);
      }
      if (output.length >= 3) break;
    }

    if (output.isNotEmpty) return output;

    if (rankedRates.isEmpty) {
      return const <AiMandiBrainInsight>[];
    }

    final top = rankedRates.first;
    return <AiMandiBrainInsight>[
      AiMandiBrainInsight(
        commodity: _commodityLabel(top.commodityName),
        insight:
            'Trusted mandi signal active hai, lekin nearby comparison kam hai۔',
        action: 'Action: حتمی فیصلہ سے پہلے قریب کی 2 منڈی ریٹس چیک کریں۔',
        type: AiMandiInsightType.nearbyComparison,
        priority: 90,
        evidenceTags: const <String>{'fallback'},
      ),
    ];
  }

  bool _isUsableRate(LiveMandiRate rate) {
    return rate.isTrustedSource && !rate.isStale && getTrustedDisplayPrice(rate) > 0;
  }

  Map<String, List<LiveMandiRate>> _groupByCommodity(List<LiveMandiRate> rates) {
    final groups = <String, List<LiveMandiRate>>{};
    for (final rate in rates) {
      final key = _norm(rate.commodityName);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => <LiveMandiRate>[]).add(rate);
    }
    return groups;
  }

  AiMandiBrainInsight? _buildNearbyInsights(
    Map<String, List<LiveMandiRate>> groups,
  ) {
    AiMandiBrainInsight? best;
    var bestScore = 0.0;

    for (final entry in groups.entries) {
      final rates = entry.value;
      if (rates.length < 2) continue;

      final sortedByPrice = List<LiveMandiRate>.from(rates)
        ..sort((a, b) => getTrustedDisplayPrice(a).compareTo(getTrustedDisplayPrice(b)));
      final low = sortedByPrice.first;
      final high = sortedByPrice.last;
      final lowPrice = getTrustedDisplayPrice(low);
      final highPrice = getTrustedDisplayPrice(high);
      if (lowPrice <= 0 || highPrice <= 0 || highPrice <= lowPrice) continue;

      final spreadPct = ((highPrice - lowPrice) / lowPrice) * 100;
      if (spreadPct < 6) continue;

      final commodity = _commodityLabel(low.commodityName);
      final bestForBuyer = low.mandiName.trim().isNotEmpty ? low.mandiName : low.city;
      final bestForSeller =
          high.mandiName.trim().isNotEmpty ? high.mandiName : high.city;

      final insight = AiMandiBrainInsight(
        commodity: commodity,
        insight:
            '$bestForSeller me rate strong hai, jabke $bestForBuyer side par behtar buying level mil raha hai۔',
        action:
            'Action: فروخت سے پہلے $bestForSeller اور خرید سے پہلے $bestForBuyer compare کریں۔',
        type: AiMandiInsightType.nearbyBestMandi,
        priority: (500 + spreadPct).round(),
        evidenceTags: const <String>{'nearby_advantage', 'cross_mandi'},
        mandi: bestForSeller,
      );

      if (spreadPct > bestScore) {
        bestScore = spreadPct;
        best = insight;
      }
    }

    return best;
  }

  AiMandiBrainInsight? _buildComparisonInsight(
    Map<String, List<LiveMandiRate>> groups,
  ) {
    for (final entry in groups.entries) {
      final rates = entry.value;
      if (rates.length < 2) continue;

      final sorted = List<LiveMandiRate>.from(rates)
        ..sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));

      final topTwo = sorted.take(2).toList(growable: false);
      if (topTwo.length < 2) continue;

      final first = topTwo[0];
      final second = topTwo[1];
      final p1 = getTrustedDisplayPrice(first);
      final p2 = getTrustedDisplayPrice(second);
      if (p1 <= 0 || p2 <= 0) continue;
      final delta = ((p1 - p2).abs() / (p2 == 0 ? 1 : p2)) * 100;
      if (delta < 4) continue;

      final better = p1 >= p2 ? first : second;
      final other = identical(better, first) ? second : first;

      return AiMandiBrainInsight(
        commodity: _commodityLabel(better.commodityName),
        insight:
            '${better.mandiName} aur ${other.mandiName} me verified rate gap nazar aa raha hai۔',
        action: 'Action: deal lock se pehle dono mandi ka تازہ ریٹ match کریں۔',
        type: AiMandiInsightType.nearbyComparison,
        priority: (330 + delta).round(),
        evidenceTags: const <String>{'cross_mandi'},
        mandi: better.mandiName,
      );
    }

    return null;
  }

  AiMandiBrainInsight? _buildMovementInsight(List<LiveMandiRate> rates) {
    for (final rate in rates) {
      final changePct = _changePercent(rate);
      if (changePct.abs() < 4.5) continue;

      final up = changePct > 0;
      final commodity = _commodityLabel(rate.commodityName);

      return AiMandiBrainInsight(
        commodity: commodity,
        insight: up
            ? 'Verified rate me tez barhat signal mila hai۔'
            : 'Verified rate me notable softness signal aya hai۔',
        action: up
            ? 'Action: خریدار جلد فیصلہ کریں، seller margin lock کر سکتے ہیں۔'
            : 'Action: seller dispatch timing optimize کریں، buyer negotiation کریں۔',
        type: up
            ? AiMandiInsightType.buyerUrgency
            : AiMandiInsightType.sellerOpportunity,
        priority: (250 + changePct.abs()).round(),
        evidenceTags: const <String>{'verified_movement'},
        mandi: rate.mandiName,
      );
    }
    return null;
  }

  AiMandiBrainInsight? _buildDemandInsight(List<Map<String, dynamic>> listings) {
    final counts = <String, int>{};
    final display = <String, String>{};

    for (final listing in listings) {
      final commodity = _listingCommodity(listing);
      final key = _norm(commodity);
      if (key.isEmpty) continue;
      counts[key] = (counts[key] ?? 0) + 1;
      display[key] = commodity;
    }

    if (counts.isEmpty) return null;
    final top = counts.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));

    final winner = top.first;
    if (winner.value < 3) return null;

    final commodity = _commodityLabel(display[winner.key] ?? winner.key);
    return AiMandiBrainInsight(
      commodity: commodity,
      insight: 'Category movement active hai aur listing demand steady lag rahi hai۔',
      action: 'Action: quality match aur delivery window clear karke offer کریں۔',
      type: AiMandiInsightType.categoryDemand,
      priority: 210 + winner.value,
      evidenceTags: const <String>{'category_demand', 'listing_activity'},
    );
  }

  AiMandiBrainInsight? _buildAuctionStrengthInsight(
    List<Map<String, dynamic>> listings,
  ) {
    final auctions = listings.where((listing) {
      final saleType = (listing['saleType'] ?? '').toString().toLowerCase();
      return saleType == 'auction';
    }).toList(growable: false);

    if (auctions.length < 2) return null;

    auctions.sort((a, b) {
      final aBid = _toDouble(a['totalBids']) ?? _toDouble(a['bidCount']) ?? 0;
      final bBid = _toDouble(b['totalBids']) ?? _toDouble(b['bidCount']) ?? 0;
      return bBid.compareTo(aBid);
    });

    final top = auctions.first;
    final commodity = _commodityLabel(_listingCommodity(top));
    final bidCount = (_toDouble(top['totalBids']) ?? _toDouble(top['bidCount']) ?? 0)
        .round();
    if (bidCount <= 1) return null;

    return AiMandiBrainInsight(
      commodity: commodity,
      insight: 'Auction side par buyer activity strong dikh rahi hai۔',
      action: 'Action: seller reserve price smart set کریں، buyer cap define کریں۔',
      type: AiMandiInsightType.sellerOpportunity,
      priority: 170 + bidCount,
      evidenceTags: const <String>{'auction_activity', 'listing_activity'},
    );
  }

  double _changePercent(LiveMandiRate rate) {
    final fromMetadata = rate.metadata['priceChangePercent'];
    if (fromMetadata is num) return fromMetadata.toDouble();
    final previous = rate.previousPrice;
    final current = getTrustedDisplayPrice(rate);
    if (previous == null || previous <= 0 || current <= 0) return 0;
    return ((current - previous) / previous) * 100;
  }

  String _listingCommodity(Map<String, dynamic> listing) {
    final candidates = <String>[
      (listing['product'] ?? '').toString(),
      (listing['itemName'] ?? '').toString(),
      (listing['subcategoryLabel'] ?? '').toString(),
      (listing['subcategory'] ?? '').toString(),
      (listing['categoryLabel'] ?? '').toString(),
      (listing['category'] ?? '').toString(),
    ];
    for (final value in candidates) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return 'Commodity';
  }

  String _commodityLabel(String commodity) {
    final value = commodity.trim();
    if (value.isEmpty) return 'Commodity / جنس';
    final lower = value.toLowerCase();

    if (lower.contains('wheat')) return 'Wheat / گندم';
    if (lower.contains('rice') || lower.contains('paddy')) return 'Rice / چاول';
    if (lower.contains('corn') || lower.contains('maize')) return 'Corn / مکئی';
    if (lower.contains('mango')) return 'Mango / آم';
    if (lower == 'dap' || lower.contains('dap')) return 'DAP / ڈی اے پی';

    return value;
  }

  String _norm(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  double? _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim());
  }
}
