import 'package:cloud_firestore/cloud_firestore.dart';

class BidModel {
  final String? bidId; // Unique ID for the bid
  final String listingId; // Reference to the crop listing
  final String sellerId;
  final String buyerId;
  final String buyerName; // Added for UI display
  final String buyerPhone;
  final String productName; 
  final double bidAmount;
  final String status; // 'pending', 'accepted', 'rejected'
  final DateTime createdAt;

  BidModel({
    this.bidId,
    required this.listingId,
    required this.sellerId,
    required this.buyerId,
    required this.buyerName,
    required this.buyerPhone,
    required this.productName,
    required this.bidAmount,
    this.status = 'pending',
    required this.createdAt,
  });

  // Factory constructor to create a BidModel from Firestore document
  factory BidModel.fromMap(Map<String, dynamic> map, String id) {
    return BidModel(
      bidId: id,
      listingId: map['listingId'] ?? '',
      sellerId: map['sellerId'] ?? '',
      buyerId: map['buyerId'] ?? '',
      buyerName: map['buyerName'] ?? 'Anjaan Kharidar',
      buyerPhone: map['buyerPhone'] ?? '',
      productName: map['productName'] ?? '',
      bidAmount: (map['bidAmount'] as num).toDouble(),
      status: map['status'] ?? 'pending',
      createdAt: (map['createdAt'] as Timestamp).toDate(),
    );
  }

  // To save data to Firestore
  Map<String, dynamic> toMap() {
    return {
      'listingId': listingId,
      'sellerId': sellerId,
      'buyerId': buyerId,
      'currentUserId': buyerId,
      'buyerName': buyerName,
      'buyerPhone': buyerPhone,
      'productName': productName,
      'bidAmount': bidAmount,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(), // Always use server time for fairness
    };
  }
}
