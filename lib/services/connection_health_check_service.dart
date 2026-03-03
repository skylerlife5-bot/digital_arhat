import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

class ConnectionHealthCheckResult {
  final bool success;
  final String message;
  final String? appCheckToken;
  final bool appCheckTokenMatchesExpected;
  final int listingsReadCount;
  final Object? error;

  const ConnectionHealthCheckResult({
    required this.success,
    required this.message,
    required this.appCheckToken,
    required this.appCheckTokenMatchesExpected,
    required this.listingsReadCount,
    this.error,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'success': success,
      'message': message,
      'appCheckToken': appCheckToken,
      'appCheckTokenMatchesExpected': appCheckTokenMatchesExpected,
      'listingsReadCount': listingsReadCount,
      'error': error?.toString(),
    };
  }
}

class ConnectionHealthCheckService {
  ConnectionHealthCheckService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<ConnectionHealthCheckResult> run({
    required String expectedDebugToken,
  }) async {
    try {
      final token = await FirebaseAppCheck.instance.getToken(true);

      final listingsSnapshot = await _db
          .collection('listings')
          .limit(5)
          .get(const GetOptions(source: Source.server));

      final tokenAvailable = (token ?? '').trim().isNotEmpty;
      final tokenMatch = token == expectedDebugToken;

      final message = _buildMessage(
        tokenAvailable: tokenAvailable,
        tokenMatch: tokenMatch,
        readCount: listingsSnapshot.docs.length,
      );

      return ConnectionHealthCheckResult(
        success: tokenAvailable,
        message: message,
        appCheckToken: token,
        appCheckTokenMatchesExpected: tokenMatch,
        listingsReadCount: listingsSnapshot.docs.length,
      );
    } catch (error) {
      return ConnectionHealthCheckResult(
        success: false,
        message: 'Connection health check failed.',
        appCheckToken: null,
        appCheckTokenMatchesExpected: false,
        listingsReadCount: 0,
        error: error,
      );
    }
  }

  String _buildMessage({
    required bool tokenAvailable,
    required bool tokenMatch,
    required int readCount,
  }) {
    if (!tokenAvailable) {
      return 'App Check token missing. Verify FirebaseAppCheck.activate() and project enforcement.';
    }

    if (!kReleaseMode && !tokenMatch) {
      return 'App Check token acquired and Firestore read succeeded, but token does not match expected debug token.';
    }

    return 'App Check token acquired and listings read succeeded (docs: $readCount).';
  }
}

