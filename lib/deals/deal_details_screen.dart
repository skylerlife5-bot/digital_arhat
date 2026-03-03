import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../deals/deal_model.dart';
import '../../models/deal_status.dart' as deal_status;
import '../../services/deal_service.dart';
import '../../chat/chat_screen.dart';
import '../dashboard/components/escrow_timeline_widget.dart';

class DealDetailsScreen extends StatefulWidget {
  final DealModel deal;
  final bool isSeller;

  const DealDetailsScreen({
    super.key,
    required this.deal,
    required this.isSeller,
  });

  @override
  State<DealDetailsScreen> createState() => _DealDetailsScreenState();
}

class _DealDetailsScreenState extends State<DealDetailsScreen> {
  final DealService _dealService = DealService();
  bool _isLoading = false;

  // �S& Check if the deal has moved past the initial awaiting state
  bool get _isUnlocked =>
      widget.deal.status != deal_status.DealStatus.awaitingPayment.value;

  void _processEscrowPayment() async {
    setState(() => _isLoading = true);

    try {
      // Status ko 'escrow_locked' kar rahe hain
      await _dealService.updateDealStatus(widget.deal.dealId, 'escrow_locked');

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(duration: Duration(seconds: 5), 
            behavior: SnackBarBehavior.floating,
            content: Text("Mubarak! Raqam Escrow mein mehfooz ho chuki hai."),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(duration: const Duration(seconds: 5), 
            behavior: SnackBarBehavior.floating,
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text("Deal ki Tafseelat"),
        backgroundColor: AppColors.primaryGreen,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDealCard(),
                  const SizedBox(height: 25),
                  const Text(
                    "Raabta aur Security",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  _buildContactCard(),
                  const SizedBox(height: 30),
                  const Text(
                    "Deal Progress",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 15),
                  EscrowTimelineWidget(dealId: widget.deal.dealId),
                  const SizedBox(height: 40),
                  _buildChatButton(context),
                ],
              ),
            ),
    );
  }

  Widget _buildDealCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.05,
            ), // �S& Fixed Opacity Error
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            widget.deal.productName,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 15),
          _priceRow("Asal Qeemat:", "Rs. ${widget.deal.dealAmount}"),
          _priceRow(
            widget.isSeller ? "Aapko Milenge:" : "Aapki Total Adaigi:",
            "Rs. ${widget.isSeller ? widget.deal.sellerReceivable : widget.deal.buyerTotal}",
            isBold: true,
          ),
          const SizedBox(height: 10),
          Text(
            "Commission (1% Arhat): Rs. ${widget.deal.dealAmount * 0.01}",
            style: const TextStyle(
              fontSize: 12,
              color: Colors.blueGrey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 16,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? AppColors.primaryGreen : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard() {
    return Card(
      elevation: 0,
      color: _isUnlocked
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.orange.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        leading: Icon(
          _isUnlocked ? Icons.verified_user : Icons.lock_clock,
          color: _isUnlocked ? Colors.green : Colors.orange,
        ),
        title: Text(_isUnlocked ? "Security: Verified" : "Aitemad ki Lakeer"),
        subtitle: Text(
          _isUnlocked
              ? "Paisa Escrow mein hai. Maal bhaij dein."
              : "Paisa jama karwa kar deal shuru karein.",
        ),
        trailing:
            (!widget.isSeller &&
                widget.deal.status ==
                    deal_status.DealStatus.awaitingPayment.value)
            ? ElevatedButton(
                onPressed: _processEscrowPayment,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text(
                  "Pay Now",
                  style: TextStyle(color: Colors.white),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildChatButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                dealId: widget.deal.dealId,
                receiverId: widget.isSeller
                    ? widget.deal.buyerId
                    : widget.deal.sellerId,
                productName: widget.deal.productName,
              ),
            ),
          );
        },
        icon: const Icon(Icons.chat_outlined),
        label: const Text("Chat Support / Partner"),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.primaryGreen),
          foregroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

