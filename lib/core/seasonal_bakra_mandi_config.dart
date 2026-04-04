import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Seasonal Bakra Mandi (Eid animal marketplace) configuration.
///
/// **Admin Control Location:**
/// File: lib/core/seasonal_bakra_mandi_config.dart
/// Variable: SeasonalBakraMandiConfig.showBakraMandi
///
/// **To Enable/Disable Bakra Mandi:**
/// 1. Edit lib/core/seasonal_bakra_mandi_config.dart
/// 2. Change: static bool showBakraMandi = true;  //  Set to false to disable
/// 3. Rebuild and run: flutter run -d [device-id]
///
/// **Optional: Set Season Dates**
/// Set startDate and endDate in this file to auto-enable only during specific dates.
///
/// **Status:** Currently enabled = [USE FILE VARIABLE ABOVE]
class SeasonalBakraMandiConfig {
  /// Toggle to show/hide Bakra Mandi feature globally.
  /// Set to FALSE to completely disable the seasonal feature.
  /// Set to TRUE to enable (subject to date constraints below).
  static bool showBakraMandi = false;

  static const bool allowPosting = true;
  static const String settingsCollection = 'app_settings';
  static const String settingsDocId = 'seasonal_bakra_mandi';
  static const String enabledField = 'enabled';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Optional: Start date for auto-enabling Bakra Mandi.
  /// Leave null to always show (if showBakraMandi = true).
  static DateTime? startDate;

  /// Optional: End date for auto-disabling Bakra Mandi.
  /// Leave null to always show (if showBakraMandi = true).
  static DateTime? endDate;

  // Keep validity short for seasonal turnover and easy manual moderation.
  static const Duration listingLifetime = Duration(days: 10);

  static DocumentReference<Map<String, dynamic>> get _settingsRef =>
      _db.collection(settingsCollection).doc(settingsDocId);

  static bool _enabledFromData(
    Map<String, dynamic>? data, {
    required bool fallback,
  }) {
    if (data == null) return fallback;
    final raw = data[enabledField];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final normalized = (raw ?? '').toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return fallback;
  }

  static Future<bool> loadRuntimeVisibility() async {
    debugPrint('[BakraToggle] cache_value=$showBakraMandi');
    try {
      final snap = await _settingsRef.get();
      final firestoreValue = _enabledFromData(
        snap.data(),
        fallback: showBakraMandi,
      );
      debugPrint('[BakraToggle] firestore_value=$firestoreValue');
      showBakraMandi = firestoreValue;
      debugPrint('[BakraToggle] runtime_read value=$showBakraMandi');
      return showBakraMandi;
    } catch (error) {
      debugPrint('[BakraToggle] runtime_read_error=$error');
      debugPrint('[BakraToggle] runtime_read value=$showBakraMandi');
      return showBakraMandi;
    }
  }

  static Stream<bool> visibilityStream() {
    return _settingsRef.snapshots().map((snapshot) {
      final firestoreValue = _enabledFromData(
        snapshot.data(),
        fallback: showBakraMandi,
      );
      debugPrint('[BakraToggle] firestore_value=$firestoreValue');
      showBakraMandi = firestoreValue;
      debugPrint('[BakraToggle] runtime_read value=$showBakraMandi');
      return showBakraMandi;
    });
  }

  static Future<void> setRuntimeVisibility({
    required bool enabled,
    required String actorUid,
  }) async {
    final uid = actorUid.trim().isEmpty ? 'admin' : actorUid.trim();
    debugPrint('[BakraToggle] admin_write value=$enabled');
    await _settingsRef.set({
      enabledField: enabled,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': uid,
      'updatedByRole': 'admin',
    }, SetOptions(merge: true));
    showBakraMandi = enabled;
  }

  static bool isEnabled([bool? runtimeEnabled]) {
    final visible = runtimeEnabled ?? showBakraMandi;
    if (!visible) {
      debugPrint('[BakraToggle] final_visible=false');
      return false;
    }

    final now = DateTime.now();

    if (startDate != null && now.isBefore(startDate!)) {
      debugPrint('[BakraToggle] final_visible=false');
      return false;
    }
    if (endDate != null && now.isAfter(endDate!)) {
      debugPrint('[BakraToggle] final_visible=false');
      return false;
    }

    debugPrint('[BakraToggle] final_visible=true');
    return true;
  }

  static bool isBakraCategory(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase() == 'bakra_mandi';
  }
}
