import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class AuthState {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static String _selectedUserType = 'buyer';

  static String get selectedUserType => _selectedUserType;

  static String get selectedRole => _selectedUserType;

  static void setSelectedUserType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'admin') {
      _selectedUserType = 'admin';
      return;
    }
    if (normalized == 'seller') {
      _selectedUserType = 'seller';
      return;
    }
    _selectedUserType = 'buyer';
  }

  static void setSelectedRole(String value) => setSelectedUserType(value);

  static void clearSelectedRoleCache() {
    _selectedUserType = 'buyer';
  }

  // Current User ID hasil karne ke liye
  String? get userId => _auth.currentUser?.uid;

  // User ka role Firestore se check karne ke liye
  Future<String?> getUserRole() async {
    try {
      if (userId == null) return null;
      
      DocumentSnapshot doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists) {
        return doc.get('role'); // 'buyer', 'seller', ya 'admin'
      }
    } catch (e) {
      debugPrint("Error fetching role: $e");
    }
    return null;
  }
}
