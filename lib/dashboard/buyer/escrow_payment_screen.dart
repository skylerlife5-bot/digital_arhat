import 'package:flutter/material.dart';
import '../../services/payment_service.dart';
import '../../core/widgets/spiritual_header.dart';

class EscrowPaymentScreen extends StatelessWidget {
  final Map<String, dynamic> dealData;
  const EscrowPaymentScreen({super.key, required this.dealData});

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFFFD700);
    final double basePrice =
      _toDouble(dealData['finalPrice']) > 0
        ? _toDouble(dealData['finalPrice'])
        : _toDouble(dealData['dealAmount']);
    // 1% Service Fee calculation for UI display
    double serviceFee = basePrice * 0.01;
    double totalToPay = basePrice + serviceFee;

    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      appBar: AppBar(
        title: const Text("Amanat Jama Karwayein", 
          style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SpiritualHeader(
              backgroundColor: Color(0x1400C853),
              borderColor: Color(0x5500C853),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Account ki Tafseel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  SizedBox(height: 6),
                  Text('Bank Name: Faysal Bank', style: TextStyle(color: Colors.white70)),
                  Text('Account Name: Amir Ghaffar', style: TextStyle(color: Colors.white70)),
                  Text('Account No: 3456786000005200', style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
            
            const SizedBox(height: 30),
            
            // �x� Amount Display Card (With 1% Breakdown)
            _buildAmountCard(basePrice, serviceFee, totalToPay),
            
            const SizedBox(height: 30),
            const Text("Payment ka tariqa chunein:", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 15),

            // �x� Payment Options
            _buildPaymentOption(context, "JazzCash", Icons.phone_android, basePrice),
            const SizedBox(height: 10),
            _buildPaymentOption(context, "Easypaisa", Icons.account_balance_wallet, basePrice),
            const SizedBox(height: 10),
            _buildPaymentOption(context, "Bank Transfer", Icons.account_balance, basePrice),

            const Spacer(),
            
            // �x� Educational Tooltip
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: goldColor, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Aap ke paise hamare paas amanat hain. Jab tak maal nahi milta, kisan ko paise nahi jayenge.",
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard(double base, double fee, double total) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(15), 
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10)
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Boli ki Raqam:", style: TextStyle(color: Colors.white54)),
              Text("Rs. ${base.toInt()}", style: const TextStyle(color: Colors.white)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Service Fee (1%):", style: TextStyle(color: Colors.white54)),
              Text("Rs. ${fee.toInt()}", style: const TextStyle(color: Colors.white)),
            ],
          ),
          const Divider(color: Colors.white10, height: 20),
          const Text("Kul Raqam (To Pay)", style: TextStyle(color: Colors.white54)),
          Text("Rs. ${total.toInt()}", 
            style: const TextStyle(color: Color(0xFFFFD700), fontSize: 32, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPaymentOption(BuildContext context, String title, IconData icon, double baseAmount) {
    return ListTile(
      onTap: () async {
        final dealId = (dealData['dealId'] ?? dealData['id'] ?? dealData['docId'] ?? '')
            .toString()
            .trim();
        final buyerId = (dealData['buyerId'] ?? '').toString().trim();
        final sellerId = (dealData['sellerId'] ?? '').toString().trim();
        final listingId = (dealData['listingId'] ?? '').toString().trim();

        if (dealId.isEmpty || buyerId.isEmpty || sellerId.isEmpty || baseAmount <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
              behavior: SnackBarBehavior.floating,
              content: Text('Payment data incomplete hai. د��بارہ ک��شش کر�Rں�'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }

        try {
          await PaymentService().initiateEscrowPayment(
            dealId: dealId,
            baseAmount: baseAmount,
            paymentMethod: title,
            buyerId: buyerId,
            sellerId: sellerId,
            listingId: listingId.isEmpty ? null : listingId,
          );

          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
              behavior: SnackBarBehavior.floating,
              content: Text('$title payment verify ho gayi. Amanat lock kar di gayi hai.'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context);
        } catch (e) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
              behavior: SnackBarBehavior.floating,
              content: Text(e.toString().replaceAll('Exception: ', '')),
              backgroundColor: Colors.red,
            ),
          );
        }
      },
      leading: Icon(icon, color: const Color(0xFFFFD700)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
      tileColor: Colors.white.withAlpha(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }
}
