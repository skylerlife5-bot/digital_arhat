import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

class FirebaseService {
  FirebaseService._();

  static const String expectedAndroidPackage = 'com.yourname.digital_arhat';

  static Future<bool> initializeSafely() async {
    try {
      await _logAndroidPackageNameMismatchIfAny();
      return true;
    } on PlatformException catch (e) {
      final combined = '${e.code} ${e.message ?? ''}'.toUpperCase();
      if (combined.contains('DEVELOPER_ERROR')) {
        debugPrint(_developerErrorGuidance());
      }
      return false;
    } catch (e) {
      debugPrint('Firebase init failed: $e');
      return false;
    }
  }

  static Future<void> _logAndroidPackageNameMismatchIfAny() async {
    if (!Platform.isAndroid) return;

    final info = await PackageInfo.fromPlatform();
    if (info.packageName != expectedAndroidPackage) {
      debugPrint(
        'Package mismatch warning. Android package is ${info.packageName}, '
        'Firebase config expects $expectedAndroidPackage. '
        'If you see Firebase auth/storage failures, align applicationId and google-services.json.',
      );
    }
  }

  static String _developerErrorGuidance() {
    return 'DEVELOPER_ERROR detected from Firebase/Play Services. '
        'Verify android/app/google-services.json has package_name '
        '"$expectedAndroidPackage", and ensure SHA-1/SHA-256 fingerprints '
        'for this package are added in Firebase Console.';
  }
}
