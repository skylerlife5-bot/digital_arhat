import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class QuickLoginService {
  QuickLoginService._();

  static final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static final LocalAuthentication _localAuth = LocalAuthentication();
  static final Set<String> _sessionUnlockedUsers = <String>{};

  static String _key(String userId, String field) =>
      'quick_login:$userId:$field';

  static Future<void> markEligible(String userId) async {
    await _storage.write(key: _key(userId, 'eligible'), value: '1');
  }

  static Future<bool> isEligible(String userId) async {
    final value = await _storage.read(key: _key(userId, 'eligible'));
    return value == '1';
  }

  static Future<void> markSetupPrompted(String userId) async {
    await _storage.write(key: _key(userId, 'setup_prompted'), value: '1');
  }

  static Future<bool> isSetupPrompted(String userId) async {
    final value = await _storage.read(key: _key(userId, 'setup_prompted'));
    return value == '1';
  }

  static Future<void> configureMpin({
    required String userId,
    required String pin,
  }) async {
    final String salt = _randomSalt();
    final String hash = _hashPin(pin: pin, salt: salt);
    await _storage.write(key: _key(userId, 'mpin_salt'), value: salt);
    await _storage.write(key: _key(userId, 'mpin_hash'), value: hash);
  }

  static Future<bool> hasMpin(String userId) async {
    final value = await _storage.read(key: _key(userId, 'mpin_hash'));
    return (value ?? '').isNotEmpty;
  }

  static Future<bool> verifyMpin({
    required String userId,
    required String pin,
  }) async {
    final String? salt = await _storage.read(key: _key(userId, 'mpin_salt'));
    final String? savedHash = await _storage.read(
      key: _key(userId, 'mpin_hash'),
    );
    if ((salt ?? '').isEmpty || (savedHash ?? '').isEmpty) {
      return false;
    }
    final String hash = _hashPin(pin: pin, salt: salt!);
    return hash == savedHash;
  }

  static Future<void> setBiometricEnabled({
    required String userId,
    required bool enabled,
  }) async {
    await _storage.write(
      key: _key(userId, 'biometric_enabled'),
      value: enabled ? '1' : '0',
    );
  }

  static Future<bool> isBiometricEnabled(String userId) async {
    final value = await _storage.read(key: _key(userId, 'biometric_enabled'));
    return value == '1';
  }

  static Future<bool> canUseBiometric() async {
    try {
      final bool canCheck = await _localAuth.canCheckBiometrics;
      final bool supported = await _localAuth.isDeviceSupported();
      if (!canCheck || !supported) return false;
      final List<BiometricType> available = await _localAuth
          .getAvailableBiometrics();
      return available.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Verify your identity to continue',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<bool> needsQuickUnlock(String userId) async {
    if (_sessionUnlockedUsers.contains(userId)) return false;
    final bool eligible = await isEligible(userId);
    if (!eligible) return false;
    return hasMpin(userId);
  }

  static Future<bool> shouldOfferSetup(String userId) async {
    if (_sessionUnlockedUsers.contains(userId)) return false;
    final bool eligible = await isEligible(userId);
    final bool hasPin = await hasMpin(userId);
    final bool prompted = await isSetupPrompted(userId);
    return eligible && !hasPin && !prompted;
  }

  static void markSessionUnlocked(String userId) {
    _sessionUnlockedUsers.add(userId);
  }

  static void clearSessionUnlock(String userId) {
    _sessionUnlockedUsers.remove(userId);
  }

  static String _randomSalt() {
    final Random random = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  static String _hashPin({required String pin, required String salt}) {
    final List<int> digest = utf8.encode('$salt:$pin');
    return sha256.convert(digest).toString();
  }
}
