import '../deals/transaction_model.dart';
import 'escrow_service.dart';

class PaymentService {
  final EscrowService _escrowService = EscrowService();

  // �x� Commission Config (1% Each)
  final double sellerCommissionRate = 0.01;
  final double buyerCommissionRate = 0.01;

  // �S& 1. Buyer Payment (Total + 1%) - Digital Arhat acting as 'Ameen'
  Future<void> initiateEscrowPayment({
    required String dealId,
    required double baseAmount, // Asli boli ki raqam (e.g. 100,000)
    required String paymentMethod,
    required String buyerId,
    required String sellerId,
    String? listingId,
  }) async {
    try {
      await _escrowService.initiateEscrowPayment(
        dealId: dealId,
        baseAmount: baseAmount,
        paymentMethod: paymentMethod,
        buyerId: buyerId,
        sellerId: sellerId,
        listingId: listingId,
      );

      // 4. Trigger Notification
      _notifySellerForDelivery(dealId, sellerId, baseAmount);

    } catch (e) {
      rethrow;
    }
  }

  // �S& 2. Seller Payout (Total - 1%) + Admin Revenue Tracking
  Future<void> releaseEscrowToSeller(
    String dealId, {
    required String callerUid,
    required String callerRole,
    String verificationNote = '',
  }) async {
    try {
      await _escrowService.transitionEscrowState(
        dealId: dealId,
        toState: EscrowTransactionState.fundsReleased,
        callerUid: callerUid,
        callerRole: callerRole,
        verificationNote: verificationNote,
      );
    } catch (e) {
      rethrow;
    }
  }

  void _notifySellerForDelivery(String dealId, String sellerId, double amount) {
    // Logic for Firebase Messaging notification
  }
}
