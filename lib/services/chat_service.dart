import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/security_filter.dart';

class ChatService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Message Bhejna
  Future<void> sendMessage(
    String dealId,
    String receiverId,
    String message,
  ) async {
    final String currentUserId = _auth.currentUser!.uid;
    final String filteredMsg = SecurityFilter.maskAll(message);

    await _firestore
        .collection('deals')
        .doc(dealId)
        .collection('messages')
        .add({
          'senderId': currentUserId,
          'receiverId': receiverId,
          'message': filteredMsg,
          'timestamp': FieldValue.serverTimestamp(),
        });
  }

  // Real-time Messages hasil karna
  Stream<QuerySnapshot> getMessages(String dealId) {
    return _firestore
        .collection('deals')
        .doc(dealId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }
}
