import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';
import 'amis_wheat_scraper_service.dart';

class MandiRatesSyncState {
  const MandiRatesSyncState({
    required this.rates,
    required this.isLoading,
    required this.isOfflineFallback,
    required this.lastSyncedAt,
    required this.error,
  });

  final List<LiveMandiRate> rates;
  final bool isLoading;
  final bool isOfflineFallback;
  final DateTime? lastSyncedAt;
  final String? error;

  bool get isStale {
    if (rates.isEmpty) return true;
    final freshest = rates
      .map((item) => item.lastUpdated.toUtc())
      .reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().toUtc().difference(freshest) >
      const Duration(hours: 24);
  }

  static const MandiRatesSyncState initial = MandiRatesSyncState(
    rates: <LiveMandiRate>[],
    isLoading: true,
    isOfflineFallback: false,
    lastSyncedAt: null,
    error: null,
  );
}

class MandiRateSyncManager {
  MandiRateSyncManager({MandiRatesRepository? repository})
      : _repository = repository ?? MandiRatesRepository();

  final MandiRatesRepository _repository;
  final StreamController<MandiRatesSyncState> _controller =
      StreamController<MandiRatesSyncState>.broadcast();

  StreamSubscription<List<LiveMandiRate>>? _liveSub;
  Timer? _periodic;
  MandiRatesSyncState _state = MandiRatesSyncState.initial;

  // --- Real-time Wheat scraper state --------------------------------------
  LiveMandiRate? _scrapedWheatRate;
  DateTime? _lastWheatScrapeAt;
  // Re-scrape at most once per 30 minutes to avoid hammering public sources.
  static const Duration _wheatScrapeInterval = Duration(minutes: 30);

  Stream<MandiRatesSyncState> get stream => _controller.stream;

  DateTime? _resolveLastSyncedAt(List<LiveMandiRate> rates) {
    if (rates.isEmpty) return null;
    final candidates = rates
        .map((item) => item.syncedAt ?? item.lastUpdated)
        .whereType<DateTime>()
        .map((item) => item.toUtc())
        .toList(growable: false);
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a.isAfter(b) ? a : b);
  }

  Future<void> start() async {
    _emit(_state);

    // Kick off the wheat scraper concurrently — do not await so it never
    // blocks the Firestore stream from starting.
    unawaited(_refreshScrapedWheatRate());

    try {
      await _repository.refreshFromUpstream();
    } catch (_) {
      // Ignore hard failure; live watch/offline fallback will keep UI alive.
    }

    _liveSub?.cancel();
    _liveSub = _repository.watchLiveRates().listen(
      (rates) {
        // Trigger a background wheat re-scrape if the cached rate is stale.
        _maybeRefreshWheatInBackground();
        final mergedRates = _mergeWithScrapedWheat(rates);
        final syncedAt = _resolveLastSyncedAt(rates);
        _state = MandiRatesSyncState(
          rates: mergedRates,
          isLoading: false,
          isOfflineFallback: false,
          lastSyncedAt: syncedAt,
          error: null,
        );
        _emit(_state);
      },
      onError: (e) async {
        final fallback = await _repository.loadOfflineFallback();
        _state = MandiRatesSyncState(
          rates: _mergeWithScrapedWheat(fallback),
          isLoading: false,
          isOfflineFallback: true,
          lastSyncedAt: _state.lastSyncedAt,
          error: e.toString(),
        );
        _emit(_state);
      },
    );

    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(minutes: 2), (_) {
      unawaited(refresh());
    });
  }

  // Fetches a fresh wheat rate from AMIS/UrduPoint and re-emits state.
  Future<void> _refreshScrapedWheatRate() async {
    try {
      final rate = await AmisWheatScraperService.fetchWheat40kgLiveRate();
      if (rate != null) {
        _scrapedWheatRate = rate;
        _lastWheatScrapeAt = DateTime.now();
        debugPrint(
          '[MandiSync] wheat_scrape_ok price=${rate.price.toStringAsFixed(0)} '
          'source=${rate.source}',
        );
        // Re-emit current state with freshly scraped wheat at top.
        _state = MandiRatesSyncState(
          rates: _mergeWithScrapedWheat(_state.rates),
          isLoading: _state.isLoading,
          isOfflineFallback: _state.isOfflineFallback,
          lastSyncedAt: _state.lastSyncedAt,
          error: _state.error,
        );
        _emit(_state);
      } else {
        debugPrint('[MandiSync] wheat_scrape_returned_null — using Firestore data');
      }
    } catch (e) {
      debugPrint('[MandiSync] wheat_scrape_error: $e');
    }
  }

  void _maybeRefreshWheatInBackground() {
    final last = _lastWheatScrapeAt;
    if (last == null ||
        DateTime.now().difference(last) > _wheatScrapeInterval) {
      unawaited(_refreshScrapedWheatRate());
    }
  }

  /// Prepends the scraped wheat rate (Tier-1 WHEAT_GENERIC) to the rate list,
  /// replacing any existing entry with the same id to avoid duplicates.
  List<LiveMandiRate> _mergeWithScrapedWheat(List<LiveMandiRate> rates) {
    final wheat = _scrapedWheatRate;
    if (wheat == null) return rates;
    // Remove any stale scraped-wheat entry already in the list.
    final filtered =
        rates.where((r) => !r.id.startsWith('wheat_generic_scraped_')).toList();
    return [wheat, ...filtered];
  }

  Future<void> refresh() async {
    _emit(
      MandiRatesSyncState(
        rates: _state.rates,
        isLoading: true,
        isOfflineFallback: _state.isOfflineFallback,
        lastSyncedAt: _state.lastSyncedAt,
        error: _state.error,
      ),
    );

    try {
      await _repository.refreshFromUpstream();
      final fallback = await _repository.loadOfflineFallback();
      final syncedAt = _resolveLastSyncedAt(fallback);
      _state = MandiRatesSyncState(
        rates: _mergeWithScrapedWheat(fallback),
        isLoading: false,
        isOfflineFallback: false,
        lastSyncedAt: syncedAt,
        error: null,
      );
      _emit(_state);
    } catch (e) {
      final fallback = await _repository.loadOfflineFallback();
      _state = MandiRatesSyncState(
        rates: _mergeWithScrapedWheat(fallback),
        isLoading: false,
        isOfflineFallback: true,
        lastSyncedAt: _state.lastSyncedAt,
        error: e.toString(),
      );
      _emit(_state);
    }
  }

  void _emit(MandiRatesSyncState value) {
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }

  Future<void> dispose() async {
    await _liveSub?.cancel();
    _periodic?.cancel();
    await _controller.close();
  }
}
