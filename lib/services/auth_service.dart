import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // �xa� Background persistence for Signup Flow
  String? verifiedCNIC;
  String? autoFilledName;

  // Jab Agri-Stack se data verify ho jaye, tab ye call karein
  void holdTemporaryData({required String cnic, required String name}) {
    verifiedCNIC = cnic;
    autoFilledName = name;
  }

  // OTP Bhejne ka function
  Future<void> sendOTP(String phoneNumber, Function(String) onCodeSent) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        throw Exception(e.message);
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  // OTP Verify karne ka Fast Function
  Future<UserCredential?> verifyOTP(
    String verificationId,
    String smsCode,
  ) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      return await _auth.signInWithCredential(credential);
    } catch (e) {
      throw Exception("Ghalat OTP ya Network ka masla");
    }
  }

  String normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (digits.isEmpty) return '';

    if (digits.startsWith('+')) return digits;
    if (digits.startsWith('00')) return '+${digits.substring(2)}';
    if (digits.startsWith('92')) return '+$digits';
    if (digits.startsWith('0')) return '+92${digits.substring(1)}';
    return '+92$digits';
  }

  String emailFromPhone(String normalizedPhone) {
    final safe = normalizedPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return 'u_$safe@digitalarhat.app';
  }

  Future<Map<String, dynamic>> _getUserByPhone(String normalizedPhone) async {
    final direct = await _db
        .collection('users')
        .where('phone', isEqualTo: normalizedPhone)
        .limit(1)
        .get();
    if (direct.docs.isNotEmpty) {
      return {'uid': direct.docs.first.id, 'data': direct.docs.first.data()};
    }

    final raw92 = normalizedPhone.replaceFirst('+', '');
    final alt = await _db
        .collection('users')
        .where('phone', isEqualTo: raw92)
        .limit(1)
        .get();
    if (alt.docs.isNotEmpty) {
      return {'uid': alt.docs.first.id, 'data': alt.docs.first.data()};
    }

    throw Exception('Is phone number ka account nahi mila.');
  }

  Future<UserCredential> loginWithPhoneAndPassword({
    required String phone,
    required String password,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty || password.trim().isEmpty) {
      throw Exception('Phone aur password dono zaroori hain.');
    }

    final user = await _getUserByPhone(normalizedPhone);
    final data = (user['data'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final storedPassword = (data['password'] ?? '').toString();

    if (storedPassword.isEmpty || storedPassword != password) {
      throw Exception('Password ghalat hai. Dobara koshish karein.');
    }

    final email = emailFromPhone(normalizedPhone);
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found' ||
          e.code == 'invalid-credential' ||
          e.code == 'invalid-email') {
        throw Exception(
          'Login migration required: account ko ek dafa OTP verify karke update karein.',
        );
      }
      throw Exception(e.message ?? 'Login fail hua.');
    }
  }

  Future<void> sendPasswordResetOtpToPhone({
    required String phone,
    required Function(String verificationId) onCodeSent,
  }) async {
    final normalizedPhone = normalizePhone(phone);
    if (normalizedPhone.isEmpty) {
      throw Exception('Sahi phone number likhen.');
    }

    await _getUserByPhone(normalizedPhone);

    await _auth.verifyPhoneNumber(
      phoneNumber: normalizedPhone,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        throw Exception(e.message ?? 'OTP send fail hua.');
      },
      codeSent: (String verificationId, int? resendToken) {
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  Future<void> resetPasswordWithOtp({
    required String phone,
    required String verificationId,
    required String smsCode,
    required String newPassword,
  }) async {
    if (newPassword.trim().length < 6) {
      throw Exception('Naya password kam az kam 6 characters ka ho.');
    }

    final normalizedPhone = normalizePhone(phone);
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );

    final authResult = await _auth.signInWithCredential(credential);
    final firebaseUser = authResult.user;
    if (firebaseUser == null) {
      throw Exception('OTP verify nahi hua.');
    }

    final email = emailFromPhone(normalizedPhone);

    final providerIds = firebaseUser.providerData
        .map((e) => e.providerId)
        .toSet();
    if (!providerIds.contains('password')) {
      await firebaseUser.linkWithCredential(
        EmailAuthProvider.credential(email: email, password: newPassword),
      );
    } else {
      await firebaseUser.updatePassword(newPassword);
    }

    await _db.collection('users').doc(firebaseUser.uid).set({
      'password': newPassword,
      'phone': normalizedPhone,
      'lastPasswordResetAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  String get currentAdminUid => _auth.currentUser?.uid ?? '';

  Future<String> getCurrentAdminRole() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return '';

    try {
      final snap = await _db.collection('users').doc(uid).get();
      final data = snap.data() ?? <String, dynamic>{};
      return (data['role'] ?? '').toString().toLowerCase();
    } catch (_) {
      return '';
    }
  }

  // Logout function
  Future<void> signOut() async {
    await _auth.signOut();
    verifiedCNIC = null;
    autoFilledName = null;
  }
}

