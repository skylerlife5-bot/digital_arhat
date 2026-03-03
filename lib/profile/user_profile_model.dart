class UserProfile {
  final String uid;         // Firebase Auth ID
  final String name;        // Agri-Stack se auto-filled
  final String cnic;        // Step 1 se verified
  final String phoneNumber; // Verified via OTP
  final String district;    // Step 2 selection
  final String tehsil;      // Step 2 selection
  final String primaryCrop; // User's main crop

  UserProfile({
    required this.uid,
    required this.name,
    required this.cnic,
    required this.phoneNumber,
    required this.district,
    required this.tehsil,
    required this.primaryCrop,
  });

  // Data ko Firestore mein save karne ke liye Map mein convert karna
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'cnic': cnic,
      'phoneNumber': phoneNumber,
      'district': district,
      'tehsil': tehsil,
      'primaryCrop': primaryCrop,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  // Firestore se data wapis model mein lane ke liye
  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] ?? '',
      name: map['name'] ?? '',
      cnic: map['cnic'] ?? '',
      phoneNumber: map['phoneNumber'] ?? '',
      district: map['district'] ?? '',
      tehsil: map['tehsil'] ?? '',
      primaryCrop: map['primaryCrop'] ?? '',
    );
  }
}
