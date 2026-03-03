import 'package:cloud_firestore/cloud_firestore.dart';

class SignupService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> saveUserProfileAndSendWelcome({
    required String uid,
    required Map<String, dynamic> userData,
  }) async {
    await _db.collection('users').doc(uid).set(userData, SetOptions(merge: true));

    await _db.collection('notifications').add({
      'userId': uid,
      'title': 'خ��ش آ�&د�Rد! ���Rج�Rٹ� آ�ھت �&�Rں آپ کا است�با� ہ�',
      'body': '���Rج�Rٹ� آ�ھت ک� ذر�Rع� �&حف��ظ اسکر�� ���R�ز�R بہتر�R�  �&� ���R ر�Rٹس�R ا��ر ا� در��� ِ ا�Rپ � �Rٹ س� تجارت �&ز�Rد �&حف��ظ ب� ائ�Rں�',
      'type': 'WELCOME_NOTIFICATION',
      'isRead': false,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}

