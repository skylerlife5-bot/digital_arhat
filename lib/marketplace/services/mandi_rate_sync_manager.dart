import 'dart:async';

import '../models/live_mandi_rate.dart';
import '../repositories/mandi_rates_repository.dart';

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
    final freshest = lastSyncedAt?.toUtc() ??
        rates
            .map((item) => (item.syncedAt ?? item.lastUpdated).toUtc())
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return DateTime.now().toUtc().difference(freshest) >
        const Duration(hours: 72);
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

    try {
      await _repository.refreshFromUpstream();
    } catch (_) {
      // Ignore hard failure; live watch/offline fallback will keep UI alive.
    }

    _liveSub?.cancel();
    _liveSub = _repository.watchLiveRates().listen(
      (rates) {
        final syncedAt = _resolveLastSyncedAt(rates);
        _state = MandiRatesSyncState(
          rates: rates,
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
          rates: fallback,
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
        rates: fallback,
        isLoading: false,
        isOfflineFallback: false,
        lastSyncedAt: syncedAt,
        error: null,
      );
      _emit(_state);
    } catch (e) {
      final fallback = await _repository.loadOfflineFallback();
      _state = MandiRatesSyncState(
        rates: fallback,
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
