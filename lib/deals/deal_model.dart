import 'package:cloud_firestore/cloud_firestore.dart';

/// �S& Deals ke statuses ko track karne ke liye professional constants
class DealStatus {
  static const String live = "Live Mandi";
  static const String pendingEscrow = "Amanat Pending";     // Buyer ne abhi payment karni hai
  static const String paymentReceived = "Paise Mosool";      // Admin (Escrow) ke pas paise aa gaye
  static const String completed = "Sauda Mukammal";         // Kisan ko paise mil gaye aur deal khatam
  static const String dispute = "Masla (Dispute)";          // Koi shikayat ya masla
  static const String cancelled = "Mansookh";               // Deal khatam kar di gayi
}

class DealModel {
  final String dealId;
  final String listingId;
  final String sellerId;
  final String buyerId;
  final String productName;
  final double dealAmount;        // Asli Boli (e.g. 10,000)
  final double buyerTotal;        // 10,000 + 1% = 10,100
  final double sellerReceivable;  // 10,000 - 1% = 9,900
  final double appCommission;     // Total 2% (Buyer 1% + Seller 1%)
  final String status;            // Use DealStatus constants
  final DateTime createdAt;
  final String? deliveryAddress;
  final String? adminTrxId;       // �S& Added for Payout tracking (Admin record)
  final DateTime? closedAt;       // �S& Added for final record

  DealModel({
    required this.dealId,
    required this.listingId,
    required this.sellerId,
    required this.buyerId,
    required this.productName,
    required this.dealAmount,
    required this.buyerTotal,
    required this.sellerReceivable,
    required this.appCommission,
    required this.status,
    required this.createdAt,
    this.deliveryAddress,
    this.adminTrxId,
    this.closedAt,
  });

  /// �x� Firestore mein data save karne ke liye
  Map<String, dynamic> toMap() {
    return {
      'dealId': dealId,
      'listingId': listingId,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'productName': productName,
      'dealAmount': dealAmount,
      'buyerTotal': buyerTotal,
      'sellerReceivable': sellerReceivable,
      'appCommission': appCommission,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt), // Converting to Firestore Timestamp
      'deliveryAddress': deliveryAddress,
      'adminTrxId': adminTrxId,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
    };
  }

  /// �x� Firestore se data nikalne ke liye
  factory DealModel.fromMap(Map<String, dynamic> map, String id) {
    return DealModel(
      dealId: id,
      listingId: map['listingId'] ?? '',
      sellerId: map['sellerId'] ?? '',
      buyerId: map['buyerId'] ?? '',
      productName: map['productName'] ?? '',
      dealAmount: (map['dealAmount'] ?? 0).toDouble(),
      buyerTotal: (map['buyerTotal'] ?? 0).toDouble(),
      sellerReceivable: (map['sellerReceivable'] ?? 0).toDouble(),
      appCommission: (map['appCommission'] ?? 0).toDouble(),
      status: map['status'] ?? DealStatus.pendingEscrow,
      createdAt: (map['createdAt'] is Timestamp) 
          ? (map['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
      deliveryAddress: map['deliveryAddress'],
      adminTrxId: map['adminTrxId'],
      closedAt: (map['closedAt'] is Timestamp) 
          ? (map['closedAt'] as Timestamp).toDate() 
          : null,
    );
  }
}
