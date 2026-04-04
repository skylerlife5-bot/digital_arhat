import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../firebase_options.dart';

class PhoneOtpException implements Exception {
  PhoneOtpException({
    required this.flowLabel,
    required this.code,
    required this.message,
    required this.normalizedPhone,
  });

  final String flowLabel;
  final String code;
  final String message;
  final String normalizedPhone;

  @override
  String toString() {
    return 'PhoneOtpException(flow: $flowLabel, code: $code, message: $message, phone: $normalizedPhone)';
  }
}

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const String _sessionUidKey = 'auth_session_uid';
  static const String _sessionPhoneKey = 'auth_session_phone';
  static const String _sessionPasswordKey = 'auth_session_password';

  String get _functionsBaseUrl =>
      'https://asia-south1-${DefaultFirebaseOptions.android.projectId}.cloudfunctions.net';

  void _logProdAuthSessionFlow({
    required String phone,
    required String matchedUid,
    required String firebaseUidBefore,
    required String firebaseSignInAttempt,
    required String firebaseSignInMethod,
    required bool firebaseSignInSuccess,
    required String firebaseErrorCode,
    required String firebaseErrorMessage,
    required String finalAuthenticatedUid,
  }) {
    debugPrint('[PROD_AUTH] phone=$phone');
    debugPrint('[PROD_AUTH] matchedUid=$matchedUid');
    debugPrint('[PROD_AUTH] firebaseUidBefore=$firebaseUidBefore');
    debugPrint('[PROD_AUTH] firebaseSignInAttempt=$firebaseSignInAttempt');
    debugPrint('[PROD_AUTH] firebaseSignInMethod=$firebaseSignInMethod');
    debugPrint('[PROD_AUTH] firebaseSignInSuccess=$firebaseSignInSuccess');
    debugPrint('[PROD_AUTH] firebaseErrorCode=$firebaseErrorCode');
    debugPrint('[PROD_AUTH] firebaseErrorMessage=$firebaseErrorMessage');
    debugPrint('[PROD_AUTH] finalAuthenticatedUid=$finalAuthenticatedUid');
  }

  void _logProdAuthSnapshot({
    required String currentFirebaseUid,
    required String persistedUid,
    required bool customSessionValid,
  }) {
    final bool mismatchSuspected =
        currentFirebaseUid.isEmpty ||
        (persistedUid.isNotEmpty && currentFirebaseUid != persistedUid);
    debugPrint('[PROD_AUTH] currentFirebaseUid=$currentFirebaseUid');
    debugPrint('[PROD_AUTH] persistedUid=$persistedUid');
    debugPrint('[PROD_AUTH] customSessionValid=$customSessionValid');
    debugPrint(
      '[PROD_AUTH] requestAuthMismatchSuspected=$mismatchSuspected',
    );
  }

  String _maskPhoneForLog(String? phone) {
    final String digits = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return '***';
    return '***${digits.substring(digits.length - 4)}';
  }

  // 🚩 Background persistence for Signup Flow
  String? verifiedCNIC;
  String? autoFilledName;

  // Jab Agri-Stack se data verify ho jaye, tab ye call karein
  void holdTemporaryData({required String cnic, required String name}) {
    verifiedCNIC = cnic;
    autoFilledName = name;
  }

  static const String pakistanPhoneValidationMessage =
      'Enter a valid Pakistani mobile number in 03001234567, 3001234567, or +923001234567 format.';
    static const String urduVerificationIssueMessage =
      'تصدیق میں مسئلہ ہے، دوبارہ کوشش کریں';

  void _logPhoneAuthEvent(
    String flowLabel,
    String event, {
    String? normalizedPhone,
    FirebaseAuthException? error,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      'flow': flowLabel,
      'event': event,
      'normalizedPhone': normalizedPhone,
      'exceptionCode': error?.code,
      'exceptionMessage': error?.message,
      ...extra,
    };
    final String debugCode = (error?.code ?? '').trim().isEmpty
        ? 'none'
        : error!.code;
    final String debugMessage = (error?.message ?? '').trim().isEmpty
        ? 'none'
        : error!.message!;
    debugPrint(
      '[OTP_DEBUG][$flowLabel] event=$event code=$debugCode message=$debugMessage phone=${_maskPhoneForLog(normalizedPhone)}',
    );
    developer.log(jsonEncode(payload), name: 'DigitalArhat.PhoneAuth');
  }

  void _logPhoneIndexEvent(
    String event, {
    String? normalizedPhone,
    String? uid,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final FirebaseException? firestoreError = error is FirebaseException
        ? error
        : null;
    final Map<String, Object?> payload = <String, Object?>{
      'event': event,
      'normalizedPhone': normalizedPhone,
      'uid': uid,
      'error': error?.toString(),
      'firestoreExceptionCode': firestoreError?.code,
      'firestoreExceptionMessage': firestoreError?.message,
      ...extra,
    };
    developer.log(jsonEncode(payload), name: 'DigitalArhat.PhoneIndex');
    if (error != null) {
      developer.log(
        'phone_index_error',
        name: 'DigitalArhat.PhoneIndex',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logCustomLoginEvent(
    String event, {
    String? normalizedPhone,
    String? uid,
    bool? passwordMatched,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final Map<String, Object?> payload = <String, Object?>{
      'event': event,
      'normalizedPhone': normalizedPhone,
      'uid': uid,
      'passwordMatched': passwordMatched,
      'error': error?.toString(),
      ...extra,
    };
    debugPrint(
      '[CUSTOM_LOGIN] event=$event uid=${uid ?? 'none'} passwordMatched=${passwordMatched ?? 'n/a'} phone=${_maskPhoneForLog(normalizedPhone)}',
    );
    developer.log(jsonEncode(payload), name: 'DigitalArhat.CustomLogin');
    if (error != null) {
      developer.log(
        'custom_login_error',
        name: 'DigitalArhat.CustomLogin',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _logLoginLookupEvent(
    String event, {
    String? enteredPhone,
    String? normalizedPhone,
    String? collection,
    String? lookupPath,
    String? matchedDocId,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final FirebaseException? firestoreError = error is FirebaseException
        ? error
        : null;
    final Map<String, Object?> payload = <String, Object?>{
      'event': event,
      'enteredPhone': enteredPhone,
      'normalizedPhone': normalizedPhone,
      'collection': collection,
      'lookupPath': lookupPath,
      'matchedDocId': matchedDocId,
      'error': error?.toString(),
      'firestoreExceptionCode': firestoreError?.code,
      'firestoreExceptionMessage': firestoreError?.message,
      ...extra,
    };
    debugPrint(
      '[LOGIN_LOOKUP] event=$event collection=${collection ?? 'n/a'} path=${lookupPath ?? 'n/a'} matchedDocId=${matchedDocId ?? 'none'} phone=${_maskPhoneForLog(normalizedPhone)}',
    );
    developer.log(jsonEncode(payload), name: 'DigitalArhat.LoginLookup');
    if (error != null) {
      developer.log(
        'login_lookup_error',
        name: 'DigitalArhat.LoginLookup',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String hashPassword(String rawPassword) {
    final String input = rawPassword.trim();
    if (input.isEmpty) return '';
    return sha256.convert(utf8.encode(input)).toString();
  }

  bool _passwordMatches({
    required String enteredPassword,
    required Map<String, dynamic> userData,
  }) {
    final String entered = enteredPassword.trim();
    if (entered.isEmpty) {
      return false;
    }

    final String storedHash = (userData['passwordHash'] ?? '')
        .toString()
        .trim();
    if (storedHash.isNotEmpty) {
      return hashPassword(entered) == storedHash;
    }

    final String storedPlain = (userData['password'] ?? '').toString();
    return storedPlain.isNotEmpty && storedPlain == entered;
  }

  Future<void> persistSessionUid(String uid) async {
    final String cleanUid = uid.trim();
    if (cleanUid.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionUidKey, cleanUid);
  }

  Future<String?> getPersistedSessionUid() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String uid = (prefs.getString(_sessionUidKey) ?? '').trim();
    return uid.isEmpty ? null : uid;
  }

  Future<void> clearPersistedSessionUid() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionUidKey);
    await prefs.remove(_sessionPhoneKey);
    await prefs.remove(_sessionPasswordKey);
  }

  Future<void> _persistSessionCredentials({
    required String normalizedPhone,
    required String password,
  }) async {
    final String cleanPhone = normalizePhone(normalizedPhone);
    final String cleanPassword = password.trim();
    if (cleanPhone.isEmpty || cleanPassword.isEmpty) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionPhoneKey, cleanPhone);
    await prefs.setString(_sessionPasswordKey, cleanPassword);
  }

  Future<Map<String, String>> _getPersistedSessionCredentials() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String phone = (prefs.getString(_sessionPhoneKey) ?? '').trim();
    final String password = (prefs.getString(_sessionPasswordKey) ?? '').trim();
    return <String, String>{'phone': phone, 'password': password};
  }

  Future<bool> ensureFirebaseSessionForAdminWrite({
    String flowLabel = 'admin_write_guard',
  }) async {
    final String persistedUid = (await getPersistedSessionUid() ?? '').trim();
    final Map<String, String> persistedCreds =
        await _getPersistedSessionCredentials();
    final String persistedPhone = persistedCreds['phone'] ?? '';
    final String persistedPassword = persistedCreds['password'] ?? '';
    String currentUid = (_auth.currentUser?.uid ?? '').trim();

    if (currentUid.isEmpty &&
        persistedUid.isNotEmpty &&
        persistedPhone.isNotEmpty &&
        persistedPassword.isNotEmpty) {
      await ensureFirebaseSessionForPhoneAndPassword(
        normalizedPhone: persistedPhone,
        password: persistedPassword,
        expectedUid: persistedUid,
        flowLabel: '${flowLabel}_persisted_credentials',
      );
      currentUid = (_auth.currentUser?.uid ?? '').trim();
    }

    if (currentUid.isEmpty && persistedUid.isNotEmpty) {
      await restoreFirebaseSessionForUid(
        persistedUid,
        flowLabel: flowLabel,
      );
      currentUid = (_auth.currentUser?.uid ?? '').trim();
    }

    final bool customSessionValid =
        persistedUid.isNotEmpty && currentUid == persistedUid;
    _logProdAuthSnapshot(
      currentFirebaseUid: currentUid,
      persistedUid: persistedUid,
      customSessionValid: customSessionValid,
    );

    if (currentUid.isEmpty) {
      return false;
    }

    final String adminRole = await getCurrentAdminRole();
    final bool isAdmin = adminRole == 'admin';
    _logCustomLoginEvent(
      '${flowLabel}_admin_role_check',
      uid: currentUid,
      extra: <String, Object?>{'resolvedRole': adminRole, 'isAdmin': isAdmin},
    );
    return isAdmin;
  }

  Future<bool> ensureFirebaseSessionForPhoneAndPassword({
    required String normalizedPhone,
    required String password,
    String expectedUid = '',
    String flowLabel = 'password_session_restore',
  }) async {
    final String cleanPhone = normalizePhone(normalizedPhone);
    final String cleanPassword = password.trim();
    final String targetUid = expectedUid.trim();
    String currentUid = (_auth.currentUser?.uid ?? '').trim();
    final String logPhone = cleanPhone;

    if (currentUid.isNotEmpty && (targetUid.isEmpty || currentUid == targetUid)) {
      _logProdAuthSessionFlow(
        phone: logPhone,
        matchedUid: targetUid,
        firebaseUidBefore: currentUid,
        firebaseSignInAttempt: '${flowLabel}_already_authenticated',
        firebaseSignInMethod: 'other',
        firebaseSignInSuccess: true,
        firebaseErrorCode: '',
        firebaseErrorMessage: '',
        finalAuthenticatedUid: currentUid,
      );
      _logCustomLoginEvent(
        '${flowLabel}_already_authenticated',
        normalizedPhone: cleanPhone,
        uid: currentUid,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
      return true;
    }

    if (cleanPhone.isEmpty || cleanPassword.isEmpty) {
      _logProdAuthSessionFlow(
        phone: logPhone,
        matchedUid: targetUid,
        firebaseUidBefore: currentUid,
        firebaseSignInAttempt: '${flowLabel}_missing_credentials',
        firebaseSignInMethod: 'other',
        firebaseSignInSuccess: false,
        firebaseErrorCode: 'missing-credentials',
        firebaseErrorMessage: 'Phone or password missing',
        finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
      );
      _logCustomLoginEvent(
        '${flowLabel}_missing_credentials',
        normalizedPhone: cleanPhone,
        uid: targetUid,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
      return false;
    }

    if (currentUid.isNotEmpty && targetUid.isNotEmpty && currentUid != targetUid) {
      await _auth.signOut();
      _logCustomLoginEvent(
        '${flowLabel}_signed_out_mismatched_user',
        normalizedPhone: cleanPhone,
        uid: currentUid,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
      currentUid = (_auth.currentUser?.uid ?? '').trim();
    }

    String email = emailFromPhone(cleanPhone);
    String emailErrorCode = '';
    String emailErrorMessage = '';
    String customTokenErrorCode = '';
    String customTokenErrorMessage = '';
    String originalUidForLog = targetUid;
    bool duplicateUidFound = false;
    bool emailLinkAttachedToOriginalUid = false;
    bool signInWithEmailPathUsed = false;

    debugPrint('[PROD_AUTH] originalUid=$originalUidForLog');
    debugPrint('[PROD_AUTH] canonicalEmail=$email');
    debugPrint('[PROD_AUTH] duplicateUidFound=$duplicateUidFound');
    debugPrint('[PROD_AUTH] emailLinkAttachedToOriginalUid=$emailLinkAttachedToOriginalUid');
    debugPrint('[PROD_AUTH] signInWithEmailPathUsed=$signInWithEmailPathUsed');

    // Prefer server-issued custom token first for custom phone+password login.
    // This path safely bridges Firestore password validation to a real
    // Firebase Auth session and can create a missing Auth user on the server.
    try {
      final Uri uri = Uri.parse('$_functionsBaseUrl/establishCustomSession');
      _logProdAuthSessionFlow(
        phone: logPhone,
        matchedUid: targetUid,
        firebaseUidBefore: (_auth.currentUser?.uid ?? '').trim(),
        firebaseSignInAttempt: '${flowLabel}_custom_token_attempt',
        firebaseSignInMethod: 'custom_token',
        firebaseSignInSuccess: false,
        firebaseErrorCode: '',
        firebaseErrorMessage: '',
        finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
      );

      final http.Response response = await http.post(
        uri,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'phone': cleanPhone,
          'password': cleanPassword,
          'expectedUid': targetUid,
        }),
      );

      final String rawBody = response.body.trim();
      Map<String, dynamic> decoded = <String, dynamic>{};
      if (rawBody.isNotEmpty) {
        try {
          final Object? parsed = jsonDecode(rawBody);
          if (parsed is Map<String, dynamic>) {
            decoded = parsed;
          }
        } catch (_) {
          // Non-JSON body (for example, upstream 500 plain text).
          decoded = <String, dynamic>{
            'ok': false,
            'error': 'non-json-response',
            'message': rawBody,
          };
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
        final String code = (decoded['error'] ?? response.statusCode).toString();
        final String message =
            (decoded['message'] ?? decoded['error'] ?? 'custom-token-failed').toString();
        customTokenErrorCode = code;
        customTokenErrorMessage = message;
        _logProdAuthSessionFlow(
          phone: logPhone,
          matchedUid: targetUid,
          firebaseUidBefore: (_auth.currentUser?.uid ?? '').trim(),
          firebaseSignInAttempt: '${flowLabel}_custom_token_http_failed',
          firebaseSignInMethod: 'custom_token',
          firebaseSignInSuccess: false,
          firebaseErrorCode: code,
          firebaseErrorMessage: message,
          finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
        );
      } else {
        originalUidForLog = (decoded['originalUid'] ?? targetUid).toString().trim();
        duplicateUidFound = decoded['duplicateUidFound'] == true;
        emailLinkAttachedToOriginalUid = decoded['emailLinkAttachedToOriginalUid'] == true;
        final String serverAuthEmail = (decoded['authEmail'] ?? '').toString().trim();
        if (serverAuthEmail.isNotEmpty) {
          email = serverAuthEmail;
        }
        debugPrint('[PROD_AUTH] originalUid=$originalUidForLog');
        debugPrint('[PROD_AUTH] canonicalEmail=$email');
        debugPrint('[PROD_AUTH] duplicateUidFound=$duplicateUidFound');
        debugPrint('[PROD_AUTH] emailLinkAttachedToOriginalUid=$emailLinkAttachedToOriginalUid');
        final String customToken = (decoded['customToken'] ?? '').toString().trim();
        if (customToken.isEmpty) {
          customTokenErrorCode = 'custom-token-missing';
          customTokenErrorMessage = 'Server did not return custom token';
          _logProdAuthSessionFlow(
            phone: logPhone,
            matchedUid: targetUid,
            firebaseUidBefore: (_auth.currentUser?.uid ?? '').trim(),
            firebaseSignInAttempt: '${flowLabel}_custom_token_missing',
            firebaseSignInMethod: 'custom_token',
            firebaseSignInSuccess: false,
            firebaseErrorCode: 'custom-token-missing',
            firebaseErrorMessage: 'Server did not return custom token',
            finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
          );
        } else {
          final UserCredential credential = await _auth.signInWithCustomToken(customToken);
          final String resolvedUid = (credential.user?.uid ?? '').trim();
          final bool uidMatches = targetUid.isEmpty || resolvedUid == targetUid;
          if (!uidMatches) {
            await _auth.signOut();
            _logProdAuthSessionFlow(
              phone: logPhone,
              matchedUid: targetUid,
              firebaseUidBefore: currentUid,
              firebaseSignInAttempt: '${flowLabel}_custom_token_uid_mismatch',
              firebaseSignInMethod: 'custom_token',
              firebaseSignInSuccess: false,
              firebaseErrorCode: 'uid-mismatch',
              firebaseErrorMessage: 'Custom token UID did not match expected UID',
              finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
            );
            return false;
          }

          await _auth.currentUser?.reload();
          final String finalUid = (_auth.currentUser?.uid ?? '').trim();
          final bool finalUidMatches = targetUid.isEmpty || finalUid == targetUid;
          if (!finalUidMatches || finalUid.isEmpty) {
            _logProdAuthSessionFlow(
              phone: logPhone,
              matchedUid: targetUid,
              firebaseUidBefore: currentUid,
              firebaseSignInAttempt: '${flowLabel}_custom_token_final_uid_invalid',
              firebaseSignInMethod: 'custom_token',
              firebaseSignInSuccess: false,
              firebaseErrorCode: 'auth-state-mismatch',
              firebaseErrorMessage: 'Firebase currentUser missing or mismatched after custom token sign-in',
              finalAuthenticatedUid: finalUid,
            );
          } else {
            _logProdAuthSessionFlow(
              phone: logPhone,
              matchedUid: targetUid,
              firebaseUidBefore: currentUid,
              firebaseSignInAttempt: '${flowLabel}_custom_token_success',
              firebaseSignInMethod: 'custom_token',
              firebaseSignInSuccess: true,
              firebaseErrorCode: '',
              firebaseErrorMessage: '',
              finalAuthenticatedUid: finalUid,
            );
            return true;
          }
        }
      }
    } catch (error, stackTrace) {
      customTokenErrorCode = 'unknown';
      customTokenErrorMessage = error.toString();
      if (error is FirebaseAuthException) {
        customTokenErrorCode = error.code;
        customTokenErrorMessage = (error.message ?? '').trim();
      }
      _logProdAuthSessionFlow(
        phone: logPhone,
        matchedUid: targetUid,
        firebaseUidBefore: currentUid,
        firebaseSignInAttempt: '${flowLabel}_custom_token_failed',
        firebaseSignInMethod: 'custom_token',
        firebaseSignInSuccess: false,
        firebaseErrorCode: customTokenErrorCode,
        firebaseErrorMessage: customTokenErrorMessage,
        finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
      );
      _logCustomLoginEvent(
        '${flowLabel}_custom_token_sign_in_failed',
        normalizedPhone: cleanPhone,
        uid: targetUid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
    }

    _logProdAuthSessionFlow(
      phone: logPhone,
      matchedUid: targetUid,
      firebaseUidBefore: (_auth.currentUser?.uid ?? '').trim(),
      firebaseSignInAttempt: '${flowLabel}_email_password_attempt',
      firebaseSignInMethod: 'email_password',
      firebaseSignInSuccess: false,
      firebaseErrorCode: '',
      firebaseErrorMessage: '',
      finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
    );
    signInWithEmailPathUsed = true;
    debugPrint('[PROD_AUTH] signInWithEmailPathUsed=$signInWithEmailPathUsed');
    try {
      final UserCredential credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: cleanPassword,
      );
      final String resolvedUid = (credential.user?.uid ?? '').trim();
      final bool uidMatches = targetUid.isEmpty || resolvedUid == targetUid;
      _logCustomLoginEvent(
        '${flowLabel}_firebase_password_sign_in',
        normalizedPhone: cleanPhone,
        uid: resolvedUid,
        passwordMatched: true,
        extra: <String, Object?>{
          'expectedUid': targetUid,
          'uidMatchesExpected': uidMatches,
        },
      );

      if (!uidMatches) {
        await _auth.signOut();
        _logProdAuthSessionFlow(
          phone: logPhone,
          matchedUid: targetUid,
          firebaseUidBefore: currentUid,
          firebaseSignInAttempt: '${flowLabel}_email_password_uid_mismatch',
          firebaseSignInMethod: 'email_password',
          firebaseSignInSuccess: false,
          firebaseErrorCode: 'uid-mismatch',
          firebaseErrorMessage: 'Signed-in Firebase UID did not match expected UID',
          finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
        );
        _logCustomLoginEvent(
          '${flowLabel}_firebase_uid_mismatch',
          normalizedPhone: cleanPhone,
          uid: resolvedUid,
          extra: <String, Object?>{'expectedUid': targetUid},
        );
        return false;
      }

      await _auth.currentUser?.reload();
      final String finalUid = (_auth.currentUser?.uid ?? '').trim();
      final bool finalUidMatches = targetUid.isEmpty || finalUid == targetUid;
      if (!finalUidMatches || finalUid.isEmpty) {
        _logProdAuthSessionFlow(
          phone: logPhone,
          matchedUid: targetUid,
          firebaseUidBefore: currentUid,
          firebaseSignInAttempt: '${flowLabel}_email_password_final_uid_invalid',
          firebaseSignInMethod: 'email_password',
          firebaseSignInSuccess: false,
          firebaseErrorCode: 'auth-state-mismatch',
          firebaseErrorMessage: 'Firebase currentUser missing or mismatched after email/password sign-in',
          finalAuthenticatedUid: finalUid,
        );
        return false;
      }

      _logProdAuthSessionFlow(
        phone: logPhone,
        matchedUid: targetUid,
        firebaseUidBefore: currentUid,
        firebaseSignInAttempt: '${flowLabel}_email_password_success',
        firebaseSignInMethod: 'email_password',
        firebaseSignInSuccess: true,
        firebaseErrorCode: '',
        firebaseErrorMessage: '',
        finalAuthenticatedUid: finalUid,
      );
      debugPrint('[PROD_AUTH] finalAuthenticatedUid=$finalUid');

      return true;
    } on FirebaseAuthException catch (error, stackTrace) {
      emailErrorCode = error.code;
      emailErrorMessage = (error.message ?? '').trim();
      _logCustomLoginEvent(
        '${flowLabel}_firebase_password_sign_in_failed',
        normalizedPhone: cleanPhone,
        uid: targetUid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
    } catch (error, stackTrace) {
      emailErrorCode = 'unknown';
      emailErrorMessage = error.toString();
      _logCustomLoginEvent(
        '${flowLabel}_firebase_password_sign_in_failed',
        normalizedPhone: cleanPhone,
        uid: targetUid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'expectedUid': targetUid},
      );
    }

    _logProdAuthSessionFlow(
      phone: logPhone,
      matchedUid: targetUid,
      firebaseUidBefore: currentUid,
      firebaseSignInAttempt: '${flowLabel}_email_password_failed',
      firebaseSignInMethod: 'email_password',
      firebaseSignInSuccess: false,
      firebaseErrorCode: emailErrorCode,
      firebaseErrorMessage: emailErrorMessage,
      finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
    );

    _logProdAuthSessionFlow(
      phone: logPhone,
      matchedUid: targetUid,
      firebaseUidBefore: currentUid,
      firebaseSignInAttempt: '${flowLabel}_all_methods_failed',
      firebaseSignInMethod: 'other',
      firebaseSignInSuccess: false,
      firebaseErrorCode: customTokenErrorCode.isEmpty ? emailErrorCode : customTokenErrorCode,
      firebaseErrorMessage:
          customTokenErrorMessage.isEmpty ? emailErrorMessage : customTokenErrorMessage,
      finalAuthenticatedUid: (_auth.currentUser?.uid ?? '').trim(),
    );
    debugPrint('[PROD_AUTH] finalAuthenticatedUid=${(_auth.currentUser?.uid ?? '').trim()}');
    return false;
  }

  Future<bool> restoreFirebaseSessionForUserData(
    Map<String, dynamic> userData, {
    String flowLabel = 'user_data_session_restore',
  }) async {
    final String uid = (userData['uid'] ?? '').toString().trim();
    final String phone = (userData['phone'] ?? '').toString().trim();
    final String password = (userData['password'] ?? '').toString().trim();
    final String normalizedPhone = normalizePhone(phone);

    if (uid.isEmpty || normalizedPhone.isEmpty || password.isEmpty) {
      _logCustomLoginEvent(
        '${flowLabel}_missing_user_data',
        normalizedPhone: normalizedPhone,
        uid: uid,
        extra: <String, Object?>{
          'hasUid': uid.isNotEmpty,
          'hasPhone': normalizedPhone.isNotEmpty,
          'hasPassword': password.isNotEmpty,
        },
      );
      return false;
    }

    return ensureFirebaseSessionForPhoneAndPassword(
      normalizedPhone: normalizedPhone,
      password: password,
      expectedUid: uid,
      flowLabel: flowLabel,
    );
  }

  Future<bool> restoreFirebaseSessionForUid(
    String uid, {
    String flowLabel = 'persisted_uid_session_restore',
  }) async {
    final String cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      _logCustomLoginEvent('${flowLabel}_missing_uid');
      return false;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await _db.collection('users').doc(cleanUid).get();
      if (!snapshot.exists) {
        _logCustomLoginEvent(
          '${flowLabel}_user_doc_missing',
          uid: cleanUid,
        );
        return false;
      }

      final Map<String, dynamic> userData = <String, dynamic>{
        'uid': cleanUid,
        ...(snapshot.data() ?? const <String, dynamic>{}),
      };
      return restoreFirebaseSessionForUserData(
        userData,
        flowLabel: flowLabel,
      );
    } catch (error, stackTrace) {
      _logCustomLoginEvent(
        '${flowLabel}_user_doc_read_failed',
        uid: cleanUid,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<bool> ensurePasswordProviderLinkedForCurrentUser({
    required String normalizedPhone,
    required String password,
    String flowLabel = 'signup_password_link',
  }) async {
    final String cleanPhone = normalizePhone(normalizedPhone);
    final String cleanPassword = password.trim();
    User? current = _auth.currentUser;

    if (current == null || cleanPhone.isEmpty || cleanPassword.isEmpty) {
      _logCustomLoginEvent(
        '${flowLabel}_missing_prerequisites',
        normalizedPhone: cleanPhone,
        uid: current?.uid,
        extra: <String, Object?>{
          'hasCurrentUser': current != null,
          'hasPhone': cleanPhone.isNotEmpty,
          'hasPassword': cleanPassword.isNotEmpty,
        },
      );
      return false;
    }

    await current.reload();
    current = _auth.currentUser;
    if (current == null) {
      _logCustomLoginEvent(
        '${flowLabel}_current_user_missing_after_reload',
        normalizedPhone: cleanPhone,
      );
      return false;
    }

    final bool hasPasswordProvider = current.providerData.any(
      (provider) => provider.providerId == 'password',
    );
    final String email = emailFromPhone(cleanPhone);
    final String expectedEmail = email.toLowerCase();

    Future<bool> acceptIfPasswordProviderNowPresent(String reason) async {
      await current?.reload();
      final User? refreshed = _auth.currentUser;
      if (refreshed == null) {
        _logCustomLoginEvent(
          '${flowLabel}_${reason}_user_missing_after_refresh',
          normalizedPhone: cleanPhone,
        );
        return false;
      }

      final bool passwordNowPresent = refreshed.providerData.any(
        (provider) => provider.providerId == 'password',
      );
      final String refreshedEmail = (refreshed.email ?? '').trim().toLowerCase();
      final bool emailMatches =
          refreshedEmail.isNotEmpty && refreshedEmail == expectedEmail;

      if (!passwordNowPresent) {
        _logCustomLoginEvent(
          '${flowLabel}_${reason}_password_provider_missing_after_refresh',
          normalizedPhone: cleanPhone,
          uid: refreshed.uid,
          extra: <String, Object?>{'expectedEmail': email},
        );
        return false;
      }

      if (!emailMatches) {
        _logCustomLoginEvent(
          '${flowLabel}_${reason}_email_mismatch_after_refresh',
          normalizedPhone: cleanPhone,
          uid: refreshed.uid,
          extra: <String, Object?>{
            'expectedEmail': email,
            'actualEmail': refreshed.email,
          },
        );
        return false;
      }

      try {
        await refreshed.updatePassword(cleanPassword);
      } on FirebaseAuthException catch (error, stackTrace) {
        _logCustomLoginEvent(
          '${flowLabel}_${reason}_password_update_failed',
          normalizedPhone: cleanPhone,
          uid: refreshed.uid,
          error: error,
          stackTrace: stackTrace,
          extra: <String, Object?>{'expectedEmail': email},
        );
      }

      _logCustomLoginEvent(
        '${flowLabel}_${reason}_accepted_existing_password_provider',
        normalizedPhone: cleanPhone,
        uid: refreshed.uid,
        extra: <String, Object?>{'expectedEmail': email},
      );
      return true;
    }

    try {
      if (!hasPasswordProvider) {
        await current.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: cleanPassword),
        );
        _logCustomLoginEvent(
          '${flowLabel}_linked_password_provider',
          normalizedPhone: cleanPhone,
          uid: current.uid,
        );
        return true;
      }

      await current.updatePassword(cleanPassword);
      _logCustomLoginEvent(
        '${flowLabel}_updated_password_provider',
        normalizedPhone: cleanPhone,
        uid: current.uid,
      );
      return true;
    } on FirebaseAuthException catch (error, stackTrace) {
      if (error.code == 'provider-already-linked') {
        final bool accepted = await acceptIfPasswordProviderNowPresent(
          'provider_already_linked',
        );
        if (accepted) {
          return true;
        }
      }

      if (error.code == 'email-already-in-use' ||
          error.code == 'credential-already-in-use') {
        final bool accepted = await acceptIfPasswordProviderNowPresent(
          'email_already_in_use',
        );
        if (accepted) {
          return true;
        }
      }

      _logCustomLoginEvent(
        '${flowLabel}_link_failed',
        normalizedPhone: cleanPhone,
        uid: current.uid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'hadPasswordProvider': hasPasswordProvider},
      );
      return false;
    } catch (error, stackTrace) {
      _logCustomLoginEvent(
        '${flowLabel}_link_failed',
        normalizedPhone: cleanPhone,
        uid: current.uid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'hadPasswordProvider': hasPasswordProvider},
      );
      return false;
    }
  }

  Future<bool> isPhoneRegisteredInIndex(
    String normalizedPhone, {
    String? ignoreUid,
  }) async {
    if (normalizedPhone.isEmpty) {
      return false;
    }

    _logPhoneIndexEvent(
      'duplicate_check_started',
      normalizedPhone: normalizedPhone,
      uid: ignoreUid,
      extra: <String, Object?>{
        'sourcePath': 'phone_index/$normalizedPhone',
        'lookupMethod': 'doc_get',
      },
    );

    try {
      // Only use phone_index doc get (allow get: if true in rules).
      // Do NOT query the users collection with where() — Firestore rules only
      // allow single-document get on /users/{uid}, not list/where queries.
      // Using where() throws permission-denied and blocks signup entirely.
      final DocumentReference<Map<String, dynamic>> indexDocRef = _db
          .collection('phone_index')
          .doc(normalizedPhone);
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await indexDocRef
          .get();
      final Map<String, dynamic> data = snapshot.data() ?? <String, dynamic>{};
      final String indexedUid = (data['uid'] ?? '').toString().trim();
      final bool registered = data['registered'] == true;
      final bool duplicateExists = snapshot.exists &&
          registered &&
          indexedUid.isNotEmpty &&
          (ignoreUid == null || indexedUid != ignoreUid);

      _logPhoneIndexEvent(
        duplicateExists
            ? 'duplicate_check_duplicate_exists'
            : snapshot.exists
                ? 'duplicate_check_exists_but_ignored'
                : 'duplicate_check_not_found',
        normalizedPhone: normalizedPhone,
        uid: ignoreUid,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'duplicateExists': duplicateExists,
          'indexedUid': indexedUid,
          'registered': registered,
          'phoneIndexConflict': duplicateExists,
          'lookupMethod': 'doc_get_only',
        },
      );

      return duplicateExists;
    } catch (error) {
      _logPhoneIndexEvent(
        'duplicate_check_failed',
        normalizedPhone: normalizedPhone,
        uid: ignoreUid,
        error: error,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'lookupMethod': 'doc_get',
        },
      );
      rethrow;
    }
  }

  Future<void> upsertPhoneIndex({
    required String normalizedPhone,
    required String uid,
  }) async {
    if (normalizedPhone.isEmpty || uid.trim().isEmpty) {
      return;
    }

    final String? authUid = _auth.currentUser?.uid;

    try {
      _logPhoneIndexEvent(
        'index_upsert_started',
        normalizedPhone: normalizedPhone,
        uid: uid,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'authCurrentUid': authUid,
          'authUidMatchesPayloadUid': authUid == uid,
        },
      );

      await _db.collection('phone_index').doc(normalizedPhone).set({
        'phone': normalizedPhone,
        'registered': true,
        'uid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _logPhoneIndexEvent(
        'index_upsert_succeeded',
        normalizedPhone: normalizedPhone,
        uid: uid,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'authCurrentUid': authUid,
          'authUidMatchesPayloadUid': authUid == uid,
        },
      );
    } catch (error, stackTrace) {
      _logPhoneIndexEvent(
        'index_upsert_failed',
        normalizedPhone: normalizedPhone,
        uid: uid,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{
          'sourcePath': 'phone_index/$normalizedPhone',
          'authCurrentUid': authUid,
          'authUidMatchesPayloadUid': authUid == uid,
        },
      );
      rethrow;
    }
  }

  // OTP Bhejne ka function
  Future<void> sendOTP(
    String phoneNumber,
    Function(String) onCodeSent, {
    String flowLabel = 'unknown',
    int? forceResendingToken,
    Function(int?)? onResendToken,
    Function(String)? onAutoRetrievalTimeout,
    Function(String)? onVerificationFailedMessage,
    Function(FirebaseAuthException)? onVerificationFailed,
    Future<void> Function(UserCredential credential)? onVerificationCompleted,
  }) async {
    if (kIsWeb) {
      throw PhoneOtpException(
        flowLabel: flowLabel,
        code: 'native-app-required',
        message: urduVerificationIssueMessage,
        normalizedPhone: phoneNumber.trim(),
      );
    }

    // Keep OTP verification strictly in native app flow.
    // We do not force reCAPTCHA flow and we never trigger browser redirects.
    _auth.setSettings(
      appVerificationDisabledForTesting: false,
      forceRecaptchaFlow: false,
    );

    final String normalizedPhone = normalizePhone(phoneNumber);
    if (normalizedPhone.isEmpty) {
      final PhoneOtpException error = PhoneOtpException(
        flowLabel: flowLabel,
        code: 'invalid-phone-number',
        message: pakistanPhoneValidationMessage,
        normalizedPhone: phoneNumber.trim(),
      );
      _logPhoneAuthEvent(
        flowLabel,
        'validation_failed',
        normalizedPhone: phoneNumber.trim(),
        extra: <String, Object?>{'verifyPhoneNumberStarted': false},
      );
      throw error;
    }

    final Completer<void> sendResult = Completer<void>();
    bool verifyPhoneNumberStarted = true;
    bool codeSentFired = false;
    bool verificationFailedFired = false;
    bool autoRetrievalTimeoutFired = false;
    bool verificationCompletedFired = false;

    _logPhoneAuthEvent(
      flowLabel,
      'verify_phone_number_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'firebaseAppId': Firebase.app().options.appId,
        'firebaseProjectId': Firebase.app().options.projectId,
        'verifyPhoneNumberStarted': true,
        'codeSentFired': false,
        'verificationFailedFired': false,
        'autoRetrievalTimeoutFired': false,
        'verificationCompletedFired': false,
      },
    );

    // NOTE: Do NOT call FirebaseAppCheck.instance.getToken() here as a
    // preflight. Firebase handles App Check internally during verifyPhoneNumber.
    // A failed preflight getToken() does not prevent SMS delivery but adds
    // latency and can cause timeout races.

    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      forceResendingToken: forceResendingToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        verificationCompletedFired = true;
        _logPhoneAuthEvent(
          flowLabel,
          'verification_completed',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
            'codeSentFired': codeSentFired,
            'verificationFailedFired': verificationFailedFired,
            'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
            'verificationCompletedFired': verificationCompletedFired,
          },
        );
        try {
          final UserCredential userCredential = await _auth
              .signInWithCredential(credential);
          if (onVerificationCompleted != null) {
            await onVerificationCompleted(userCredential);
          }
        } on FirebaseAuthException catch (e) {
          _logPhoneAuthEvent(
            flowLabel,
            'verification_completed_sign_in_failed',
            normalizedPhone: normalizedPhone,
            error: e,
            extra: <String, Object?>{
              'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
              'codeSentFired': codeSentFired,
              'verificationFailedFired': verificationFailedFired,
              'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
              'verificationCompletedFired': verificationCompletedFired,
            },
          );
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        verificationFailedFired = true;
        final String code = e.code.toLowerCase();
        String message = urduVerificationIssueMessage;
        if (code.contains('network')) {
          message = 'انٹرنیٹ مسئلہ ہے، دوبارہ کوشش کریں';
        } else if (code.contains('invalid-phone-number')) {
          message = 'درست پاکستانی موبائل نمبر درج کریں';
        } else if (code.contains('too-many-requests')) {
          message = 'زیادہ کوششیں ہو گئیں، کچھ دیر بعد دوبارہ کوشش کریں';
        }
        _logPhoneAuthEvent(
          flowLabel,
          'verification_failed',
          normalizedPhone: normalizedPhone,
          error: e,
          extra: <String, Object?>{
            'firebaseExceptionMessage': e.message,
            'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
            'codeSentFired': codeSentFired,
            'verificationFailedFired': verificationFailedFired,
            'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
            'verificationCompletedFired': verificationCompletedFired,
          },
        );
        final FirebaseAuthException safeError = FirebaseAuthException(
          code: e.code,
          message: message,
        );
        if (onVerificationFailed != null) {
          onVerificationFailed(safeError);
        }
        if (onVerificationFailedMessage != null) {
          onVerificationFailedMessage(message);
        }
        if (!sendResult.isCompleted) {
          sendResult.completeError(
            PhoneOtpException(
              flowLabel: flowLabel,
              code: e.code,
              message: message,
              normalizedPhone: normalizedPhone,
            ),
          );
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        codeSentFired = true;
        _logPhoneAuthEvent(
          flowLabel,
          'code_sent',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
            'codeSentFired': codeSentFired,
            'verificationFailedFired': verificationFailedFired,
            'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
            'verificationCompletedFired': verificationCompletedFired,
            'resendTokenAvailable': resendToken != null,
          },
        );
        onCodeSent(verificationId);
        if (onResendToken != null) {
          onResendToken(resendToken);
        }
        if (!sendResult.isCompleted) {
          sendResult.complete();
        }
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        autoRetrievalTimeoutFired = true;
        _logPhoneAuthEvent(
          flowLabel,
          'auto_retrieval_timeout',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
            'codeSentFired': codeSentFired,
            'verificationFailedFired': verificationFailedFired,
            'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
            'verificationCompletedFired': verificationCompletedFired,
          },
        );
        if (onAutoRetrievalTimeout != null) {
          onAutoRetrievalTimeout(verificationId);
        }
      },
    );

    await sendResult.future.timeout(
      const Duration(seconds: 70),
      onTimeout: () {
        _logPhoneAuthEvent(
          flowLabel,
          'code_send_timeout',
          normalizedPhone: normalizedPhone,
          extra: <String, Object?>{
            'verifyPhoneNumberStarted': verifyPhoneNumberStarted,
            'codeSentFired': codeSentFired,
            'verificationFailedFired': verificationFailedFired,
            'autoRetrievalTimeoutFired': autoRetrievalTimeoutFired,
            'verificationCompletedFired': verificationCompletedFired,
          },
        );
        throw PhoneOtpException(
          flowLabel: flowLabel,
          code: 'code-send-timeout',
          message: 'OTP request timed out before code was sent.',
          normalizedPhone: normalizedPhone,
        );
      },
    );
  }

  // OTP Verify karne ka Fast Function
  Future<UserCredential?> verifyOTP(
    String verificationId,
    String smsCode, {
    String flowLabel = 'unknown',
    String? phoneNumber,
  }) async {
    try {
      final String normalizedPhone = normalizePhone(phoneNumber ?? '');
      _logPhoneAuthEvent(
        flowLabel,
        'otp_verify_started',
        normalizedPhone: normalizedPhone.isEmpty ? null : normalizedPhone,
        extra: <String, Object?>{
          'verificationIdPresent': verificationId.isNotEmpty,
          'smsCodeLength': smsCode.trim().length,
        },
      );
      
      if (smsCode.trim().length != 6) {
        throw PhoneOtpException(
          flowLabel: flowLabel,
          code: 'invalid-otp-format',
          message: 'OTP must be 6 digits / او ٹی پی 6 ہندسوں کا ہونا چاہیے',
          normalizedPhone: normalizedPhone,
        );
      }
      
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final UserCredential result = await _auth.signInWithCredential(
        credential,
      );
      _logPhoneAuthEvent(
        flowLabel,
        'otp_verify_succeeded',
        normalizedPhone: normalizedPhone.isEmpty ? null : normalizedPhone,
        extra: <String, Object?>{
          'verificationIdPresent': verificationId.isNotEmpty,
          'smsCodeLength': smsCode.trim().length,
        },
      );
      return result;
    } on FirebaseAuthException catch (e) {
      final String normalizedPhone = normalizePhone(phoneNumber ?? '');
      final String friendlyMessage = _mapFirebaseAuthError(e.code, e.message);
      _logPhoneAuthEvent(
        flowLabel,
        'otp_verify_failed',
        normalizedPhone: normalizedPhone.isEmpty ? null : normalizedPhone,
        error: e,
        extra: <String, Object?>{
          'verificationIdPresent': verificationId.isNotEmpty,
          'smsCodeLength': smsCode.trim().length,
          'firebaseErrorCode': e.code,
        },
      );
      throw PhoneOtpException(
        flowLabel: flowLabel,
        code: e.code,
        message: friendlyMessage,
        normalizedPhone: normalizedPhone,
      );
    } on PhoneOtpException {
      rethrow;
    } catch (e) {
      final String normalizedPhone = normalizePhone(phoneNumber ?? '');
      _logPhoneAuthEvent(
        flowLabel,
        'otp_verify_failed_unknown',
        normalizedPhone: normalizedPhone.isEmpty ? null : normalizedPhone,
        error: e is FirebaseAuthException ? e : null,
        extra: <String, Object?>{
          'verificationIdPresent': verificationId.isNotEmpty,
          'smsCodeLength': smsCode.trim().length,
        },
      );
      throw PhoneOtpException(
        flowLabel: flowLabel,
        code: 'unknown-error',
        message: 'Unable to verify OTP / او ٹی پی تصدیق نہیں ہو سکی',
        normalizedPhone: normalizedPhone,
      );
    }
  }

  String _mapFirebaseAuthError(String code, String? message) {
    final String c = code.toLowerCase();
    if (c == 'invalid-verification-code' || c == 'invalid-credential') {
      return 'The OTP code you entered is incorrect. Please check and try again. / آپ نے درج کیا ہوا او ٹی پی کوڈ غلط ہے۔ براہ کرم دوبارہ کوشش کریں۔';
    }
    if (c == 'too-many-requests') {
      return 'You have made too many verification attempts. Please try again in a few minutes. / آپ نے بہت سی کوششیں کر لیں ہیں۔ براہ کرم کچھ منٹ بعد دوبارہ کوشش کریں۔';
    }
    if (c == 'user-token-expired') {
      return 'Your verification session has expired. Please request a new OTP. / آپ کا تصدیق سیشن ختم ہو گیا۔ براہ کرم نیا او ٹی پی درخواست کریں۔';
    }
    if (c.contains('network') || c == 'unavailable') {
      return 'Network connection error. Please check your internet and try again. / انٹرنیٹ کنکشن میں مسئلہ ہے۔ براہ کرم دوبارہ کوشش کریں۔';
    }
    return message?.isNotEmpty == true
        ? message!
        : 'OTP verification failed. Please try again. / او ٹی پی تصدیق ناکام۔ براہ کرم دوبارہ کوشش کریں۔';
  }

  String normalizePhone(String raw) {
    String digits = raw.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('0092')) {
      digits = digits.substring(4);
    }
    if (digits.startsWith('92')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }

    if (digits.length != 10 || !digits.startsWith('3')) {
      return '';
    }

    return '+92$digits';
  }

  String normalizePhoneDigits(String raw) {
    final String normalizedPhone = normalizePhone(raw);
    if (normalizedPhone.isEmpty) {
      return '';
    }
    return normalizedPhone.substring(3);
  }

  String emailFromPhone(String normalizedPhone) {
    final safe = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return 'u_$safe@digitalarhat.app';
  }

  Future<Map<String, dynamic>> _getUserByPhone(
    String normalizedPhone, {
    String? enteredPhone,
  }) async {
    final String phoneIndexPath = 'phone_index/$normalizedPhone';
    _logLoginLookupEvent(
      'lookup_started',
      enteredPhone: enteredPhone,
      normalizedPhone: normalizedPhone,
      collection: 'phone_index',
      lookupPath: phoneIndexPath,
    );

    final DocumentSnapshot<Map<String, dynamic>> indexSnap;
    try {
      indexSnap = await _db.collection('phone_index').doc(normalizedPhone).get();
    } on FirebaseException catch (error, stackTrace) {
      _logLoginLookupEvent(
        'lookup_failed_permission_phone_index',
        enteredPhone: enteredPhone,
        normalizedPhone: normalizedPhone,
        collection: 'phone_index',
        lookupPath: phoneIndexPath,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'permissionFailureSource': 'phone_index_get'},
      );
      rethrow;
    }

    if (!indexSnap.exists) {
      _logLoginLookupEvent(
        'lookup_not_found_phone_index',
        enteredPhone: enteredPhone,
        normalizedPhone: normalizedPhone,
        collection: 'phone_index',
        lookupPath: phoneIndexPath,
      );
      throw Exception('Is phone number ka account nahi mila.');
    }

    final Map<String, dynamic> indexData = indexSnap.data() ?? <String, dynamic>{};
    final String uidFromIndex = (indexData['uid'] ?? '').toString().trim();
    _logLoginLookupEvent(
      'lookup_matched_phone_index',
      enteredPhone: enteredPhone,
      normalizedPhone: normalizedPhone,
      collection: 'phone_index',
      lookupPath: phoneIndexPath,
      matchedDocId: uidFromIndex,
    );

    if (uidFromIndex.isEmpty) {
      throw Exception('Is phone number ka account nahi mila.');
    }

    final String userDocPath = 'users/$uidFromIndex';
    final DocumentSnapshot<Map<String, dynamic>> userSnap;
    try {
      userSnap = await _db.collection('users').doc(uidFromIndex).get();
    } on FirebaseException catch (error, stackTrace) {
      _logLoginLookupEvent(
        'lookup_failed_permission_user_doc',
        enteredPhone: enteredPhone,
        normalizedPhone: normalizedPhone,
        collection: 'users',
        lookupPath: userDocPath,
        matchedDocId: uidFromIndex,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'permissionFailureSource': 'users_doc_get'},
      );
      rethrow;
    }

    if (!userSnap.exists) {
      _logLoginLookupEvent(
        'lookup_not_found_user_doc',
        enteredPhone: enteredPhone,
        normalizedPhone: normalizedPhone,
        collection: 'users',
        lookupPath: userDocPath,
        matchedDocId: uidFromIndex,
      );
      throw Exception('Is phone number ka account nahi mila.');
    }

    _logLoginLookupEvent(
      'lookup_matched_user_doc',
      enteredPhone: enteredPhone,
      normalizedPhone: normalizedPhone,
      collection: 'users',
      lookupPath: userDocPath,
      matchedDocId: uidFromIndex,
    );

    return <String, dynamic>{
      'uid': userSnap.id,
      'data': userSnap.data() ?? <String, dynamic>{},
      'lookupMethod': 'phone_index_doc_lookup',
      'lookupPath': userDocPath,
    };
  }

  Future<String> loginWithPhoneAndPassword({
    required String phone,
    required String password,
  }) async {
    final String enteredPhone = phone.trim();
    final String normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty || password.trim().isEmpty) {
      _logCustomLoginEvent(
        'login_validation_failed',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{'enteredPhone': enteredPhone},
      );
      throw Exception('Phone aur password dono zaroori hain.');
    }

    try {
      _logCustomLoginEvent(
        'login_started',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{'enteredPhone': enteredPhone},
      );

      final Map<String, dynamic> user = await _getUserByPhone(
        normalizedPhone,
        enteredPhone: enteredPhone,
      );
      final String uid = (user['uid'] ?? '').toString().trim();
      final Map<String, dynamic> data =
          (user['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};

      _logCustomLoginEvent(
        'phone_lookup_result',
        normalizedPhone: normalizedPhone,
        uid: uid,
        extra: <String, Object?>{
          'lookupMethod': user['lookupMethod']?.toString(),
          'lookupPath': user['lookupPath']?.toString(),
          'userFound': uid.isNotEmpty,
          'enteredPhone': enteredPhone,
        },
      );

      if (uid.isEmpty) {
        _logCustomLoginEvent(
          'login_failed_user_not_found',
          normalizedPhone: normalizedPhone,
        );
        throw Exception('Is phone number ka account nahi mila.');
      }

      final bool passwordMatched = _passwordMatches(
        enteredPassword: password,
        userData: data,
      );
      _logCustomLoginEvent(
        'password_match_result',
        normalizedPhone: normalizedPhone,
        uid: uid,
        passwordMatched: passwordMatched,
        extra: <String, Object?>{'enteredPhone': enteredPhone},
      );

      if (!passwordMatched) {
        _logCustomLoginEvent(
          'login_failed_invalid_password',
          normalizedPhone: normalizedPhone,
          uid: uid,
          passwordMatched: false,
        );
        throw Exception('Password ghalat hai. Dobara koshish karein.');
      }

        final String firebaseUidBefore =
          (_auth.currentUser?.uid ?? '').trim();
        final bool firebaseSessionReady =
          await ensureFirebaseSessionForPhoneAndPassword(
            normalizedPhone: normalizedPhone,
            password: password,
            expectedUid: uid,
            flowLabel: 'password_login',
          );

      final String finalAuthenticatedUid = (_auth.currentUser?.uid ?? '').trim();
      final bool uidMatches = finalAuthenticatedUid.isNotEmpty && finalAuthenticatedUid == uid;
      if (firebaseSessionReady && uidMatches) {
        await persistSessionUid(uid);
        await _persistSessionCredentials(
          normalizedPhone: normalizedPhone,
          password: password,
        );
        _logCustomLoginEvent(
          'login_succeeded_session_restored',
          normalizedPhone: normalizedPhone,
          uid: uid,
          passwordMatched: true,
          extra: <String, Object?>{
            'enteredPhone': enteredPhone,
            'firebaseSessionReady': firebaseSessionReady,
            'authCurrentUid': finalAuthenticatedUid,
            'role': (data['role'] ?? data['userRole'] ?? '').toString(),
            'phone': (data['phone'] ?? '').toString(),
          },
        );
      } else {
        _logCustomLoginEvent(
          'login_failed_session_not_established',
          normalizedPhone: normalizedPhone,
          uid: uid,
          passwordMatched: true,
          extra: <String, Object?>{
            'enteredPhone': enteredPhone,
            'firebaseSessionReady': firebaseSessionReady,
            'authCurrentUid': finalAuthenticatedUid,
            'expectedUid': uid,
          },
        );
      }
      _logProdAuthSessionFlow(
        phone: normalizedPhone,
        matchedUid: uid,
        firebaseUidBefore: firebaseUidBefore,
        firebaseSignInAttempt: 'password_login_final_state_check',
        firebaseSignInMethod: 'other',
        firebaseSignInSuccess: firebaseSessionReady && uidMatches,
        firebaseErrorCode: firebaseSessionReady && uidMatches ? '' : 'auth-state-mismatch',
        firebaseErrorMessage: firebaseSessionReady && uidMatches
            ? ''
            : 'Firebase session not established after successful custom password match',
        finalAuthenticatedUid: finalAuthenticatedUid,
      );
      if (!firebaseSessionReady || !uidMatches) {
        throw Exception(
          'Firebase auth session could not be established for this account. Please sign in again.',
        );
      }
      return uid;
    } catch (error, stackTrace) {
      _logCustomLoginEvent(
        'login_failed',
        normalizedPhone: normalizedPhone,
        error: error,
        stackTrace: stackTrace,
        extra: <String, Object?>{'enteredPhone': enteredPhone},
      );
      rethrow;
    }
  }

  Future<void> sendPasswordResetOtpToPhone({
    required String phone,
    String flowLabel = 'forgot_password',
    required Function(String verificationId) onCodeSent,
    Function(String)? onAutoRetrievalTimeout,
    Function(FirebaseAuthException)? onVerificationFailed,
    Future<void> Function(UserCredential credential)? onVerificationCompleted,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) {
      throw PhoneOtpException(
        flowLabel: flowLabel,
        code: 'invalid-phone-number',
        message: pakistanPhoneValidationMessage,
        normalizedPhone: phone.trim(),
      );
    }

    _logPhoneAuthEvent(
      flowLabel,
      'existence_check_started',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{'lookupPath': 'phone_index/$normalizedPhone'},
    );

    final bool accountExists;
    try {
      accountExists = await isPhoneRegisteredInIndex(normalizedPhone);
    } on FirebaseException catch (error) {
      _logPhoneAuthEvent(
        flowLabel,
        'existence_check_failed',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'lookupPath': 'phone_index/$normalizedPhone',
          'firestoreExceptionCode': error.code,
          'firestoreExceptionMessage': error.message,
          'lookupMethod': 'doc_get',
        },
      );
      rethrow;
    } catch (error) {
      _logPhoneAuthEvent(
        flowLabel,
        'existence_check_failed',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'lookupPath': 'phone_index/$normalizedPhone',
          'error': error.toString(),
          'lookupMethod': 'doc_get',
        },
      );
      rethrow;
    }

    if (!accountExists) {
      _logPhoneAuthEvent(
        flowLabel,
        'existence_check_not_found',
        normalizedPhone: normalizedPhone,
        extra: <String, Object?>{
          'lookupPath': 'phone_index/$normalizedPhone',
          'lookupMethod': 'doc_get',
        },
      );
      throw PhoneOtpException(
        flowLabel: flowLabel,
        code: 'account-not-found',
        message:
            'No registered account found for this phone number. Please sign up first.',
        normalizedPhone: normalizedPhone,
      );
    }

    _logPhoneAuthEvent(
      flowLabel,
      'existence_check_found',
      normalizedPhone: normalizedPhone,
      extra: <String, Object?>{
        'lookupPath': 'phone_index/$normalizedPhone',
        'lookupMethod': 'doc_get',
      },
    );

    await sendOTP(
      normalizedPhone,
      onCodeSent,
      flowLabel: flowLabel,
      onAutoRetrievalTimeout: onAutoRetrievalTimeout,
      onVerificationFailed: onVerificationFailed,
      onVerificationCompleted: onVerificationCompleted,
    );
  }

  Future<void> resetPasswordWithOtp({
    required String phone,
    String? verificationId,
    String? smsCode,
    required String newPassword,
    User? verifiedUser,
  }) async {
    if (newPassword.trim().length < 6) {
      throw Exception('Naya password kam az kam 6 characters ka ho.');
    }

    final normalizedPhone = normalizePhone(phone);
    User? firebaseUser = verifiedUser;

    if (firebaseUser == null) {
      if ((verificationId ?? '').isEmpty ||
          (smsCode ?? '').trim().length != 6) {
        throw Exception('OTP verify nahi hua.');
      }
      final PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId!,
        smsCode: smsCode!.trim(),
      );

      final authResult = await _auth.signInWithCredential(credential);
      firebaseUser = authResult.user;
    }

    if (firebaseUser == null) {
      throw Exception('OTP verify nahi hua.');
    }

    final email = emailFromPhone(normalizedPhone);

    final providerIds = firebaseUser.providerData
        .map((e) => e.providerId)
        .toSet();
    if (!providerIds.contains('password')) {
      try {
        await firebaseUser.linkWithCredential(
          EmailAuthProvider.credential(email: email, password: newPassword),
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'provider-already-linked') {
          // providerData was stale — email already linked, just update password.
          await firebaseUser.updatePassword(newPassword);
        } else if (e.code != 'email-already-in-use') {
          rethrow;
        }
        // email-already-in-use: email belongs to another Firebase account for
        // this same phone number from a previous session. Firestore password
        // is still updated below so the flow completes for the user.
      }
    } else {
      await firebaseUser.updatePassword(newPassword);
    }

    await _db.collection('users').doc(firebaseUser.uid).set({
      'password': newPassword,
      'passwordHash': hashPassword(newPassword),
      'phone': normalizedPhone,
      'lastPasswordResetAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await upsertPhoneIndex(
      normalizedPhone: normalizedPhone,
      uid: firebaseUser.uid,
    );
  }

  String get currentAdminUid => _auth.currentUser?.uid ?? '';

  Future<String> getCurrentAdminRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '';

    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data() ?? <String, dynamic>{};
      return (data['role'] ?? data['userRole'] ?? data['userType'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
    } catch (_) {
      return '';
    }
  }

  // Logout function
  Future<void> signOut() async {
    await _auth.signOut();
    await clearPersistedSessionUid();
    verifiedCNIC = null;
    autoFilledName = null;
  }
}
