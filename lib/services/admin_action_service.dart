import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'auth_service.dart';

class AdminActionService {
  AdminActionService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;
  final AuthService _authService = AuthService();

  String get _functionsBaseUrl =>
      'https://asia-south1-${DefaultFirebaseOptions.android.projectId}.cloudfunctions.net';

  Future<Map<String, dynamic>> _postAdminAction({
    required String action,
    required String docPath,
    required String functionName,
    required Map<String, dynamic> payload,
  }) async {
    final bool hasSession = await _authService.ensureFirebaseSessionForAdminWrite(
      flowLabel: 'admin_action_$action',
    );
    final String firebaseUid = (_auth.currentUser?.uid ?? '').trim();
    debugPrint('[ADMIN_ACTION] action=$action');
    debugPrint('[ADMIN_ACTION] firebaseUid=$firebaseUid');
    debugPrint('[ADMIN_ACTION] docPath=$docPath');
    debugPrint('[ADMIN_ACTION] payload=${jsonEncode(payload)}');
    if (!hasSession) {
      debugPrint('[ADMIN_ACTION] errorCode=auth-missing');
      debugPrint(
        '[ADMIN_ACTION] errorMessage=Firebase auth session missing for admin write',
      );
      debugPrint('[ADMIN_ACTION] success=false');
      throw Exception('Admin authentication required');
    }

    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('[ADMIN_ACTION] errorCode=auth-null-current-user');
      debugPrint('[ADMIN_ACTION] errorMessage=Admin authentication required');
      debugPrint('[ADMIN_ACTION] success=false');
      throw Exception('Admin authentication required');
    }

    final token = await user.getIdToken();
    final uri = Uri.parse('$_functionsBaseUrl/$functionName');

    final response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    );

    final body = response.body.trim();
    final decoded = body.isEmpty
        ? <String, dynamic>{}
        : (jsonDecode(body) as Map<String, dynamic>);

    if (response.statusCode < 200 || response.statusCode >= 300 || decoded['ok'] != true) {
      final String errorCode = (decoded['code'] ?? response.statusCode).toString();
      final String errorMessage =
          (decoded['error'] ?? decoded['message'] ?? 'admin-action-failed')
              .toString();
      debugPrint('[ADMIN_ACTION] errorCode=$errorCode');
      debugPrint('[ADMIN_ACTION] errorMessage=$errorMessage');
      debugPrint('[ADMIN_ACTION] success=false');
      throw Exception((decoded['error'] ?? 'admin-action-failed').toString());
    }

    debugPrint('[ADMIN_ACTION] errorCode=');
    debugPrint('[ADMIN_ACTION] errorMessage=');
    debugPrint('[ADMIN_ACTION] success=true');
    return decoded;
  }

  Future<Map<String, dynamic>> approveListingAdmin({required String listingId}) {
    return _postAdminAction(
      action: 'approve_listing',
      docPath: 'listings/$listingId',
      functionName: 'approveListingAdmin',
      payload: <String, dynamic>{'listingId': listingId},
    );
  }


  Future<Map<String, dynamic>> approveListingAdminWithNote({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
      action: 'approve_listing',
      docPath: 'listings/$listingId',
      functionName: 'approveListingAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }
  Future<Map<String, dynamic>> rejectListingAdmin({
    required String listingId,
    required String note,
  }) {
    return _postAdminAction(
      action: 'reject_listing',
      docPath: 'listings/$listingId',
      functionName: 'rejectListingAdmin',
      payload: <String, dynamic>{'listingId': listingId, 'note': note},
    );
  }

  Future<Map<String, dynamic>> requestListingChangesAdmin({
    required String listingId,
    required String note,
  }) {
    return _postAdminAction(
      action: 'request_changes',
      docPath: 'listings/$listingId',
      functionName: 'requestListingChangesAdmin',
      payload: <String, dynamic>{'listingId': listingId, 'note': note},
    );
  }

  Future<Map<String, dynamic>> startAuctionAdmin({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
      action: 'start_auction',
      docPath: 'listings/$listingId',
      functionName: 'startAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> pauseAuctionAdmin({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
      action: 'pause_auction',
      docPath: 'listings/$listingId',
      functionName: 'pauseAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> resumeAuctionAdmin({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
      action: 'resume_auction',
      docPath: 'listings/$listingId',
      functionName: 'resumeAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> cancelAuctionAdmin({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
      action: 'cancel_auction',
      docPath: 'listings/$listingId',
      functionName: 'cancelAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }

  Future<Map<String, dynamic>> extendAuctionAdmin({
    required String listingId,
    int extensionHours = 2,
    String? note,
  }) {
    return _postAdminAction(
      action: 'extend_auction',
      docPath: 'listings/$listingId',
      functionName: 'extendAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        'extensionHours': extensionHours,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }
}
