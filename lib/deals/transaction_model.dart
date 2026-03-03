import 'package:cloud_firestore/cloud_firestore.dart';

enum EscrowTransactionState {
  fundsLocked,
  stockInTransit,
  stockVerified,
  fundsReleased,
  disputed,
  refunded,
}

extension EscrowTransactionStateX on EscrowTransactionState {
  String get wireValue {
    switch (this) {
      case EscrowTransactionState.fundsLocked:
        return 'FUNDS_LOCKED';
      case EscrowTransactionState.stockInTransit:
        return 'STOCK_IN_TRANSIT';
      case EscrowTransactionState.stockVerified:
        return 'STOCK_VERIFIED';
      case EscrowTransactionState.fundsReleased:
        return 'FUNDS_RELEASED';
      case EscrowTransactionState.disputed:
        return 'DISPUTED';
      case EscrowTransactionState.refunded:
        return 'REFUNDED';
    }
  }

  static EscrowTransactionState fromWireValue(String raw) {
    final value = raw.trim().toUpperCase();
    for (final state in EscrowTransactionState.values) {
      if (state.wireValue == value) {
        return state;
      }
    }
    return EscrowTransactionState.fundsLocked;
  }
}

class EscrowStateMachine {
  static const Map<EscrowTransactionState, Set<EscrowTransactionState>> _allowedTransitions = {
    EscrowTransactionState.fundsLocked: {
      EscrowTransactionState.stockInTransit,
      EscrowTransactionState.disputed,
    },
    EscrowTransactionState.stockInTransit: {
      EscrowTransactionState.stockVerified,
      EscrowTransactionState.disputed,
    },
    EscrowTransactionState.stockVerified: {
      EscrowTransactionState.fundsReleased,
      EscrowTransactionState.disputed,
    },
    EscrowTransactionState.disputed: {
      EscrowTransactionState.refunded,
      EscrowTransactionState.stockVerified,
    },
    EscrowTransactionState.fundsReleased: {},
    EscrowTransactionState.refunded: {},
  };

  static bool canTransition({
    required EscrowTransactionState from,
    required EscrowTransactionState to,
  }) {
    return _allowedTransitions[from]?.contains(to) ?? false;
  }
}

class EscrowModel {
  const EscrowModel({
    required this.dealId,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.baseAmount,
    required this.buyerServiceFee,
    required this.totalPaidByBuyer,
    required this.method,
    required this.state,
    required this.isHighRisk,
    this.verificationNote,
    this.sellerServiceFee,
    this.totalAdminEarnings,
    this.finalPayoutToSeller,
    this.fundsLockedAt,
    this.stockInTransitAt,
    this.stockVerifiedAt,
    this.fundsReleasedAt,
    this.disputedAt,
    this.refundedAt,
    this.updatedAt,
    this.createdAt,
  });

  final String dealId;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final double baseAmount;
  final double buyerServiceFee;
  final double totalPaidByBuyer;
  final String method;
  final EscrowTransactionState state;
  final bool isHighRisk;
  final String? verificationNote;
  final double? sellerServiceFee;
  final double? totalAdminEarnings;
  final double? finalPayoutToSeller;
  final DateTime? fundsLockedAt;
  final DateTime? stockInTransitAt;
  final DateTime? stockVerifiedAt;
  final DateTime? fundsReleasedAt;
  final DateTime? disputedAt;
  final DateTime? refundedAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'dealId': dealId,
      'listingId': listingId,
      'buyerId': buyerId,
      'sellerId': sellerId,
      'baseAmount': baseAmount,
      'buyerServiceFee': buyerServiceFee,
      'totalPaidByBuyer': totalPaidByBuyer,
      'method': method,
      'state': state.wireValue,
      'isHighRisk': isHighRisk,
      'verificationNote': verificationNote,
      'sellerServiceFee': sellerServiceFee,
      'totalAdminEarnings': totalAdminEarnings,
      'finalPayoutToSeller': finalPayoutToSeller,
      'fundsLockedAt': fundsLockedAt == null ? null : Timestamp.fromDate(fundsLockedAt!),
      'stockInTransitAt': stockInTransitAt == null ? null : Timestamp.fromDate(stockInTransitAt!),
      'stockVerifiedAt': stockVerifiedAt == null ? null : Timestamp.fromDate(stockVerifiedAt!),
      'fundsReleasedAt': fundsReleasedAt == null ? null : Timestamp.fromDate(fundsReleasedAt!),
      'disputedAt': disputedAt == null ? null : Timestamp.fromDate(disputedAt!),
      'refundedAt': refundedAt == null ? null : Timestamp.fromDate(refundedAt!),
      'updatedAt': updatedAt == null ? null : Timestamp.fromDate(updatedAt!),
      'createdAt': createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }

  factory EscrowModel.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    double parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0.0;
    }

    return EscrowModel(
      dealId: (map['dealId'] ?? '').toString(),
      listingId: (map['listingId'] ?? '').toString(),
      buyerId: (map['buyerId'] ?? '').toString(),
      sellerId: (map['sellerId'] ?? '').toString(),
      baseAmount: parseDouble(map['baseAmount']),
      buyerServiceFee: parseDouble(map['buyerServiceFee']),
      totalPaidByBuyer: parseDouble(map['totalPaidByBuyer']),
      method: (map['method'] ?? '').toString(),
      state: EscrowTransactionStateX.fromWireValue((map['state'] ?? '').toString()),
      isHighRisk: map['isHighRisk'] == true,
      verificationNote: map['verificationNote']?.toString(),
      sellerServiceFee: map['sellerServiceFee'] == null ? null : parseDouble(map['sellerServiceFee']),
      totalAdminEarnings: map['totalAdminEarnings'] == null ? null : parseDouble(map['totalAdminEarnings']),
      finalPayoutToSeller: map['finalPayoutToSeller'] == null ? null : parseDouble(map['finalPayoutToSeller']),
      fundsLockedAt: parseDate(map['fundsLockedAt']),
      stockInTransitAt: parseDate(map['stockInTransitAt']),
      stockVerifiedAt: parseDate(map['stockVerifiedAt']),
      fundsReleasedAt: parseDate(map['fundsReleasedAt']),
      disputedAt: parseDate(map['disputedAt']),
      refundedAt: parseDate(map['refundedAt']),
      updatedAt: parseDate(map['updatedAt']),
      createdAt: parseDate(map['createdAt']),
    );
  }
}

