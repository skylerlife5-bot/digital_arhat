import 'package:flutter/material.dart';

class CustomSnackBar {
  static void success({
    required BuildContext context,
    required String message,
    required String transactionId,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green.shade700,
        content: Text('$message | Transaction ID: $transactionId'),
      ),
    );
  }

  static void error({
    required BuildContext context,
    required String message,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.red.shade700,
        content: Text(message),
      ),
    );
  }
}

