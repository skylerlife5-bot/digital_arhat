enum DealStatus {
  active,
  pendingAdminApproval,
  awaitingPayment,
  paymentPendingVerification,
  paymentConfirmed,
  dealCompleted,
  rejected,
}

extension DealStatusValue on DealStatus {
  String get value {
    switch (this) {
      case DealStatus.active:
        return 'active';
      case DealStatus.pendingAdminApproval:
        return 'pending_admin_approval';
      case DealStatus.awaitingPayment:
        return 'awaiting_payment';
      case DealStatus.paymentPendingVerification:
        return 'payment_pending_verification';
      case DealStatus.paymentConfirmed:
        return 'payment_confirmed';
      case DealStatus.dealCompleted:
        return 'completed';
      case DealStatus.rejected:
        return 'rejected';
    }
  }
}

extension DealStatusParsing on String {
  bool isStatus(DealStatus status) {
    return trim().toLowerCase() == status.value;
  }
}

