import 'package:flutter/material.dart';

/// 1. The Status Engine (Enums)
/// In codes se system decide karega ke kis step par kya dikhana hai.
enum TransactionStatus {
  pending,       // Buyer ne abhi pay nahi kiya
  heldInEscrow,  // Paisa Digital Arhat ke pas aa gaya (Paisa Moosul)
  disputed,      // Maal mein masla hai, paise rok liye gaye hain
  released,      // Kisan ko paise bhej diye gaye hain (Deal Complete)
  refunded       // Buyer ko paise wapis mil gaye
}

/// 2. Payment Status UI Widget
/// Ye widget kisi bhi screen par status ka "Badge" dikhane ke liye use hoga.
class PaymentStatusWidget extends StatelessWidget {
  final TransactionStatus status;

  const PaymentStatusWidget({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // Status ke mutabiq color aur text set karna
    final config = _getStatusConfig(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: config.color, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 16, color: config.color),
          const SizedBox(width: 6),
          Text(
            config.label,
            style: TextStyle(
              color: config.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Helper function to keep UI clean
  _StatusData _getStatusConfig(TransactionStatus status) {
    switch (status) {
      case TransactionStatus.pending:
        return _StatusData("Adaigi Baqi", Colors.orange, Icons.hourglass_empty);
      case TransactionStatus.heldInEscrow:
        return _StatusData("Paisa Moosul (Held)", Colors.blueAccent, Icons.security);
      case TransactionStatus.disputed:
        return _StatusData("Masla (Disputed)", Colors.red, Icons.report_problem);
      case TransactionStatus.released:
        return _StatusData("Deal Mukammal", Colors.green, Icons.check_circle);
      case TransactionStatus.refunded:
        return _StatusData("Paisa Wapis (Refunded)", Colors.grey, Icons.replay);
    }
  }
}

// Internal class for configuration
class _StatusData {
  final String label;
  final Color color;
  final IconData icon;
  _StatusData(this.label, this.color, this.icon);
}

/// 3. Placeholder Screen (If you need a full page)
class PaymentStatusScreen extends StatelessWidget {
  final TransactionStatus currentStatus;
  
  const PaymentStatusScreen({super.key, this.currentStatus = TransactionStatus.pending});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011A0A), // Dark Mandi Theme
      appBar: AppBar(
        title: const Text('Payment Status', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Maujooda Surat-e-Haal:", 
              style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 20),
            PaymentStatusWidget(status: currentStatus),
          ],
        ),
      ),
    );
  }
}
