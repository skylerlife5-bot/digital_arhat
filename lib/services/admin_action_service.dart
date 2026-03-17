import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';

class AdminActionService {
  AdminActionService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  String get _functionsBaseUrl =>
      'https://asia-south1-${DefaultFirebaseOptions.android.projectId}.cloudfunctions.net';

  Future<Map<String, dynamic>> _postAdminAction({
    required String functionName,
    required Map<String, dynamic> payload,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
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
      throw Exception((decoded['error'] ?? 'admin-action-failed').toString());
    }

    return decoded;
  }

  Future<Map<String, dynamic>> approveListingAdmin({required String listingId}) {
    return _postAdminAction(
      functionName: 'approveListingAdmin',
      payload: <String, dynamic>{'listingId': listingId},
    );
  }


  Future<Map<String, dynamic>> approveListingAdminWithNote({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
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
      functionName: 'rejectListingAdmin',
      payload: <String, dynamic>{'listingId': listingId, 'note': note},
    );
  }

  Future<Map<String, dynamic>> requestListingChangesAdmin({
    required String listingId,
    required String note,
  }) {
    return _postAdminAction(
      functionName: 'requestListingChangesAdmin',
      payload: <String, dynamic>{'listingId': listingId, 'note': note},
    );
  }

  Future<Map<String, dynamic>> startAuctionAdmin({
    required String listingId,
    String? note,
  }) {
    return _postAdminAction(
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
      functionName: 'extendAuctionAdmin',
      payload: <String, dynamic>{
        'listingId': listingId,
        'extensionHours': extensionHours,
        if ((note ?? '').trim().isNotEmpty) 'note': note,
      },
    );
  }
}
