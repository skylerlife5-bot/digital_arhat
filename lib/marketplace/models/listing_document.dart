import 'package:cloud_firestore/cloud_firestore.dart';

class ListingDocument {
  final String? id;
  final String sellerId;
  final String cropType;
  final double price;
  final double quantity;
  final bool isSuspicious;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ListingDocument({
    this.id,
    required this.sellerId,
    required this.cropType,
    required this.price,
    required this.quantity,
    this.isSuspicious = false,
    this.createdAt,
    this.updatedAt,
  });

  ListingDocument copyWith({
    String? id,
    String? sellerId,
    String? cropType,
    double? price,
    double? quantity,
    bool? isSuspicious,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ListingDocument(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      cropType: cropType ?? this.cropType,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      isSuspicious: isSuspicious ?? this.isSuspicious,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ListingDocument.fromJson(Map<String, dynamic> json, {String? id}) {
    return ListingDocument(
      id: id,
      sellerId: (json['sellerId'] ?? '').toString(),
      cropType: (json['cropType'] ?? '').toString(),
      price: _toDouble(json['price']),
      quantity: _toDouble(json['quantity']),
      isSuspicious: json['isSuspicious'] == true,
      createdAt: _toDateTime(json['createdAt']),
      updatedAt: _toDateTime(json['updatedAt']),
    );
  }

  factory ListingDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return ListingDocument.fromJson(doc.data() ?? <String, dynamic>{}, id: doc.id);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sellerId': sellerId,
      'cropType': cropType,
      'price': price,
      'quantity': quantity,
      'isSuspicious': isSuspicious,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static double _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '') ?? 0.0;
  }

  static DateTime? _toDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }
}

