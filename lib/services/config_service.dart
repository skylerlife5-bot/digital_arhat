import 'package:firebase_remote_config/firebase_remote_config.dart';

class ConfigService {
  ConfigService._internal();
  static final ConfigService _instance = ConfigService._internal();
  factory ConfigService() => _instance;

  final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;
  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;

    await _remoteConfig.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 15),
        minimumFetchInterval: const Duration(minutes: 15),
      ),
    );

    await _remoteConfig.setDefaults(const <String, dynamic>{});

    _initialized = true;
  }

  Future<void> warmup() async {
    await _ensureInitialized();
    await _remoteConfig.fetchAndActivate();
  }

  Future<String> fetchGeminiApiKey() async {
    // Security hardening: AI provider keys are server-side only.
    return '';
  }

  Future<String> fetchOpenAiApiKey() async {
    // Security hardening: AI provider keys are server-side only.
    return '';
  }
}

