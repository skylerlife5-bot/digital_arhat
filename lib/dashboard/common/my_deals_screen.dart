import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../services/deal_service.dart';
import '../../deals/deal_model.dart';
import '../../chat/chat_screen.dart';
import '../../models/deal_status.dart' as deal_status;

class MyDealsScreen extends StatelessWidget {
  final bool isSeller;
  const MyDealsScreen({super.key, required this.isSeller});

  @override
  Widget build(BuildContext context) {
    final DealService dealService = DealService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isSeller ? "Meri Farokht (Sales)" : "Meri Khareedari (Purchases)",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppColors.ctaTextDark,
          ),
        ),
        backgroundColor: AppColors.accentGold,
        foregroundColor: AppColors.ctaTextDark,
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // �S& Quranic Reminder for Fair Trade
          _buildDealBarkatHeader(),

          Expanded(
            child: StreamBuilder<List<DealModel>>(
              stream: dealService.getMyDeals(isSeller),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accentGold,
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return _buildEmptyState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    DealModel deal = snapshot.data![index];
                    return _buildRoyalDealCard(context, deal, dealService);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // �S& Royal Deal Card UI
  Widget _buildRoyalDealCard(
    BuildContext context,
    DealModel deal,
    DealService service,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadowDark,
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: _getStatusColor(deal.status).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          // Top Status Bar
          _buildCardHeader(deal),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildProductIcon(deal.status),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deal.productName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryText,
                            ),
                          ),
                          Text(
                            "ID: #${deal.dealId.substring(0, 8).toUpperCase()}",
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondaryText,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _buildChatButton(context, deal),
                  ],
                ),
                const SizedBox(height: 20),

                // Money Section
                _buildMoneyContainer(deal),

                const SizedBox(height: 20),

                // Action Buttons Logic
                _buildConditionalAction(context, deal, service),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardHeader(DealModel deal) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _getStatusColor(deal.status).withValues(alpha: 0.08),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                Icons.shield_outlined,
                size: 14,
                color: _getStatusColor(deal.status),
              ),
              const SizedBox(width: 5),
              const Text(
                "Digital Arhat Escrow Protected",
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          _buildStatusChip(deal.status),
        ],
      ),
    );
  }

  Widget _buildMoneyContainer(DealModel deal) {
    double commission = deal.dealAmount * 0.01;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSeller
                    ? "Net Payout (1% Fee Cut)"
                    : "Total Bill (Inc. 1% Fee)",
                style: const TextStyle(fontSize: 11, color: AppColors.dividerGrey),
              ),
              Text(
                "Rs. ${isSeller ? deal.sellerReceivable : deal.buyerTotal}",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppColors.accentGold,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                "Arhat Commission",
                style: TextStyle(fontSize: 10, color: AppColors.secondaryText),
              ),
              Text(
                "Rs. ${commission.toStringAsFixed(0)}",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppColors.urgencyRedAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // �S& Action Button Logic with Desi Royal Styling
  Widget _buildConditionalAction(
    BuildContext context,
    DealModel deal,
    DealService service,
  ) {
    // 1. Buyer: Payment Jama Karein
    if (!isSeller && _isAwaitingPaymentStatus(deal.status)) {
      return _actionButton(
        "Paisa Escrow Mein Jama Karein",
        AppColors.accentGold,
        () => _handlePayment(context, deal, service),
      );
    }

    // 2. Seller: Maal Bhaij Diya
    if (isSeller && deal.status == 'escrow_locked') {
      return _actionButton(
        "Maal Bhaij Diya (Mark Shipped)",
        AppColors.divider,
        () => service.updateDealStatus(deal.dealId, 'shipped'),
      );
    }

    // 3. Buyer: Maal Mil Gaya
    if (!isSeller && deal.status == 'shipped') {
      return _actionButton(
        "Maal Mil Gaya (Release Payment)",
        AppColors.accentGold,
        () => service.updateDealStatus(deal.dealId, 'completed'),
      );
    }

    if (deal.status == deal_status.DealStatus.dealCompleted.value) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, color: AppColors.divider, size: 16),
          SizedBox(width: 5),
          Text(
            "Deal Mukammal Ho Chuki Hai",
            style: TextStyle(
              color: AppColors.divider,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _actionButton(String label, Color color, VoidCallback onPressed) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: AppColors.ctaTextDark,
          padding: const EdgeInsets.symmetric(vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }

  // �S& Helpers
  Widget _buildDealBarkatHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppColors.cardSurface,
      child: const Column(
        children: [
          Text(
            "\"Aye imaan walon! Apne mua'hido (contracts) ko poora karo.\"",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryText,
            ),
          ),
          Text(
            "(Surah Al-Ma'idah: 1)",
            style: TextStyle(fontSize: 9, color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildProductIcon(String status) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _getStatusColor(status).withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.inventory_2_outlined, color: _getStatusColor(status)),
    );
  }

  Widget _buildChatButton(BuildContext context, DealModel deal) {
    return IconButton(
      onPressed: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            dealId: deal.dealId,
            receiverId: isSeller ? deal.buyerId : deal.sellerId,
            productName: deal.productName,
          ),
        ),
      ),
      icon: const Icon(
        Icons.chat_bubble_outline_rounded,
        color: AppColors.accentGold,
      ),
    );
  }

  void _handlePayment(
    BuildContext context,
    DealModel deal,
    DealService service,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Escrow Payment"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person_rounded, size: 50, color: AppColors.divider),
            const SizedBox(height: 15),
            Text(
              "Total: Rs. ${deal.buyerTotal}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              "Aapka paisa Digital Arhat ke pass mehfooz rahay ga jab tak aap maal ki wasooli confirm nahi karte.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              service.updateDealStatus(deal.dealId, 'escrow_locked');
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentGold,
            ),
            child: const Text(
              "Confirm & Pay",
              style: TextStyle(color: AppColors.primaryText),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    if (_isAwaitingPaymentStatus(status)) {
      return AppColors.accentGold;
    }

    switch (status) {
      case 'awaiting_payment':
        return AppColors.accentGold;
      case 'escrow_locked':
        return AppColors.divider;
      case 'shipped':
        return AppColors.accentGold;
      case 'completed':
        return AppColors.divider;
      case 'disputed':
        return AppColors.urgencyRed;
      default:
        return AppColors.secondaryText;
    }
  }

  bool _isAwaitingPaymentStatus(String status) {
    final normalized = status.trim().toLowerCase();
    return normalized == deal_status.DealStatus.awaitingPayment.value ||
        normalized == deal_status.DealStatus.awaitingPayment.name.toLowerCase();
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.handshake_outlined,
            size: 80,
            color: AppColors.secondaryText,
          ),
          const Text(
            "Abhi tak koi deal record nahi hui.",
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }
}

