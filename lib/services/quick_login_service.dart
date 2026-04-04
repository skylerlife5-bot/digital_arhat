import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:local_auth/local_auth.dart';

import 'auth_service.dart';

class QuickLoginConfig {
  const QuickLoginConfig({
    required this.enabled,
    required this.mpinEnabled,
    required this.biometricEnabled,
    required this.mpinHash,
    required this.failedAttempts,
    this.lockUntil,
  });

  final bool enabled;
  final bool mpinEnabled;
  final bool biometricEnabled;
  final String mpinHash;
  final int failedAttempts;
  final DateTime? lockUntil;

  bool get isLocked {
    final until = lockUntil;
    if (until == null) return false;
    return DateTime.now().toUtc().isBefore(until.toUtc());
  }

  factory QuickLoginConfig.fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate().toUtc();
      if (value is DateTime) return value.toUtc();
      return null;
    }

    bool asBool(dynamic value) {
      if (value is bool) return value;
      final text = value?.toString().trim().toLowerCase() ?? '';
      return text == 'true' || text == '1' || text == 'yes';
    }

    int asInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      return int.tryParse(value?.toString() ?? '') ?? 0;
    }

    final mpinHash = (data['mpinHash'] ?? '').toString().trim();
    final mpinEnabled = asBool(data['mpinEnabled']) && mpinHash.isNotEmpty;
    final biometricEnabled = asBool(data['biometricEnabled']);

    return QuickLoginConfig(
      enabled: asBool(data['enabled']) && (mpinEnabled || biometricEnabled),
      mpinEnabled: mpinEnabled,
      biometricEnabled: biometricEnabled,
      mpinHash: mpinHash,
      failedAttempts: asInt(data['failedAttempts']),
      lockUntil: parseDate(data['lockUntil']),
    );
  }
}

class QuickLoginService {
  QuickLoginService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final LocalAuthentication _localAuth = LocalAuthentication();

  static const String _quickLoginRoot = 'quickLogin';
  static String? _unlockedUid;

  static bool isUnlockedFor(String uid) {
    return _unlockedUid != null && _unlockedUid == uid;
  }

  static void markUnlocked(String uid) {
    _unlockedUid = uid;
  }

  static void clearUnlocked() {
    _unlockedUid = null;
  }

  static Future<QuickLoginConfig> loadConfig(String uid) async {
    final userSnap = await _db.collection('users').doc(uid).get();
    final data = userSnap.data() ?? const <String, dynamic>{};
    final root = data[_quickLoginRoot];
    if (root is Map<String, dynamic>) {
      return QuickLoginConfig.fromMap(root);
    }
    if (root is Map) {
      final casted = root.map((key, value) => MapEntry(key.toString(), value));
      return QuickLoginConfig.fromMap(casted);
    }
    return QuickLoginConfig.fromMap(null);
  }

  static Future<void> saveMpin({
    required String uid,
    required String mpin,
    required bool biometricEnabled,
  }) async {
    final hash = hashMpin(uid: uid, mpin: mpin);
    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'enabled': true,
        'mpinEnabled': true,
        'biometricEnabled': biometricEnabled,
        'mpinHash': hash,
        'failedAttempts': 0,
        'lockUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<void> saveBiometricOnly({required String uid}) async {
    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'enabled': true,
        'mpinEnabled': false,
        'biometricEnabled': true,
        'failedAttempts': 0,
        'lockUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<void> disableQuickLogin({required String uid}) async {
    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'enabled': false,
        'mpinEnabled': false,
        'biometricEnabled': false,
        'mpinHash': '',
        'failedAttempts': 0,
        'lockUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<void> enableBiometric({
    required String uid,
    required bool enabled,
  }) async {
    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'enabled': enabled,
        'biometricEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static String hashMpin({required String uid, required String mpin}) {
    // Deterministic, non-plain-text digest for MPIN storage.
    final input = '$uid|$mpin|digital_arhat_phase1';
    const int fnvPrime = 0x01000193;
    int hash = 0x811C9DC5;
    for (final byte in utf8.encode(input)) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static bool verifyMpin({
    required String uid,
    required String mpin,
    required QuickLoginConfig config,
  }) {
    if (!config.mpinEnabled || config.mpinHash.isEmpty) return false;
    return hashMpin(uid: uid, mpin: mpin) == config.mpinHash;
  }

  static Future<void> registerFailure({
    required String uid,
    required QuickLoginConfig config,
  }) async {
    final nextAttempts = config.failedAttempts + 1;
    DateTime? lockUntil;
    if (nextAttempts >= 5) {
      lockUntil = DateTime.now().toUtc().add(const Duration(minutes: 2));
    }

    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'failedAttempts': nextAttempts,
        if (lockUntil != null) 'lockUntil': Timestamp.fromDate(lockUntil),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<void> resetFailures({required String uid}) async {
    await _db.collection('users').doc(uid).set({
      _quickLoginRoot: {
        'failedAttempts': 0,
        'lockUntil': null,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<bool> canUseRealBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return false;
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticateBiometric() async {
    try {
      return _localAuth.authenticate(
        localizedReason: 'Quick login unlock ke liye biometric verify karein',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static Future<void> forcePasswordFallback() async {
    clearUnlocked();
    await FirebaseAuth.instance.signOut();
    await AuthService().clearPersistedSessionUid();
  }
}
