import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String fullName;
  final String phoneNumber;
  final String password;
  final String userCategory;
  final String cnic;
  final String? cnicFrontUrl;
  final String? cnicBackUrl;
  final String role;
  final bool isVerified;
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.fullName,
    required this.phoneNumber,
    required this.password,
    required this.userCategory,
    required this.cnic,
    required this.role,
    required this.isVerified,
    required this.createdAt,
    this.cnicFrontUrl,
    this.cnicBackUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': fullName,
      'fullName': fullName,
      'phone': phoneNumber,
      'password': password,
      'userCategory': userCategory,
      'category': userCategory,
      'cnic': cnic,
      'cnicFrontUrl': cnicFrontUrl,
      'cnicBackUrl': cnicBackUrl,
      'cnicImageUrl': cnicFrontUrl,
      'role': role,
      'is_verified': isVerified,
      'verificationStatus': 'pending',
      'createdAt': Timestamp.fromDate(createdAt),
      'created_at': FieldValue.serverTimestamp(),
    };
  }

  factory UserModel.fromMap(Map<String, dynamic> map) {
    final createdAtRaw = map['createdAt'];
    DateTime created = DateTime.now();
    if (createdAtRaw is Timestamp) {
      created = createdAtRaw.toDate();
    } else if (createdAtRaw is String) {
      created = DateTime.tryParse(createdAtRaw) ?? DateTime.now();
    }

    return UserModel(
      uid: (map['uid'] ?? '').toString(),
      fullName: (map['fullName'] ?? map['name'] ?? '').toString(),
      phoneNumber: (map['phone'] ?? map['phoneNumber'] ?? '').toString(),
      password: (map['password'] ?? '').toString(),
      userCategory: (map['userCategory'] ?? map['category'] ?? '').toString(),
      cnic: (map['cnic'] ?? '').toString(),
      cnicFrontUrl: map['cnicFrontUrl']?.toString(),
      cnicBackUrl: map['cnicBackUrl']?.toString(),
      role: (map['role'] ?? 'buyer').toString(),
      isVerified: map['is_verified'] == true || map['isVerified'] == true,
      createdAt: created,
    );
  }
}

