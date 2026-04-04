import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AdminAccessService {
  AdminAccessService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  Future<bool> isAdminUser(String uid) async {
    final String cleanUid = uid.trim();
    if (cleanUid.isEmpty) {
      debugPrint('[ADMIN_ACCESS] uid=empty -> isAdmin=false');
      return false;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snap = await _db
          .collection('admins')
          .doc(cleanUid)
          .get()
          .timeout(const Duration(seconds: 4));

      final Map<String, dynamic> data = snap.data() ?? <String, dynamic>{};
      final bool isActive = data['isActive'] == true;
      final String role = (data['role'] ?? '').toString().trim().toLowerCase();
      final bool isAdmin = snap.exists && isActive && role == 'admin';

      debugPrint(
        '[ADMIN_ACCESS] uid=$cleanUid adminDocExists=${snap.exists} isActive=$isActive role=$role isAdmin=$isAdmin',
      );
      return isAdmin;
    } on TimeoutException {
      debugPrint('[ADMIN_ACCESS] uid=$cleanUid admin lookup timeout -> isAdmin=false');
      return false;
    } catch (e) {
      debugPrint('[ADMIN_ACCESS] uid=$cleanUid admin lookup failed -> isAdmin=false error=$e');
      return false;
    }
  }
}
