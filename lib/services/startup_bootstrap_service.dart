import 'dart:async';

import 'package:flutter/foundation.dart';

enum StartupBootstrapState { initializing, ready, failed }

class StartupBootstrapService {
  StartupBootstrapService._internal();

  static final StartupBootstrapService instance =
      StartupBootstrapService._internal();

  final ValueNotifier<StartupBootstrapState> state =
      ValueNotifier<StartupBootstrapState>(StartupBootstrapState.initializing);

  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      await Future.delayed(const Duration(milliseconds: 400));

      state.value = StartupBootstrapState.ready;
    } catch (e) {
      debugPrint('Firebase init error: $e');
      state.value = StartupBootstrapState.failed;
    }
  }
}

