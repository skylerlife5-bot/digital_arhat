import 'package:firebase_remote_config/firebase_remote_config.dart';

class ConfigService {
  static const String _geminiKeyParam = 'sys_gateway_v4';
  static const String _openAiKeyParam = 'sys_gateway_alt_v4';

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

    await _remoteConfig.setDefaults(const <String, dynamic>{
      _geminiKeyParam: '',
      _openAiKeyParam: '',
    });

    _initialized = true;
  }

  Future<void> warmup() async {
    await _ensureInitialized();
    await _remoteConfig.fetchAndActivate();
  }

  Future<String> fetchGeminiApiKey() async {
    await _ensureInitialized();
    return _remoteConfig.getString(_geminiKeyParam).trim();
  }

  Future<String> fetchOpenAiApiKey() async {
    await _ensureInitialized();
    return _remoteConfig.getString(_openAiKeyParam).trim();
  }
}

