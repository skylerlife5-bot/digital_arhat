import 'package:cloud_firestore/cloud_firestore.dart';

class MandiRateDocument {
  final String? id;
  final String cropType;
  final DateTime rateDate;
  final double averagePrice;
  final String unit;
  final String source;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MandiRateDocument({
    this.id,
    required this.cropType,
    required this.rateDate,
    required this.averagePrice,
    this.unit = 'PKR/40kg',
    this.source = 'daily_aggregation',
    this.createdAt,
    this.updatedAt,
  });

  MandiRateDocument copyWith({
    String? id,
    String? cropType,
    DateTime? rateDate,
    double? averagePrice,
    String? unit,
    String? source,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return MandiRateDocument(
      id: id ?? this.id,
      cropType: cropType ?? this.cropType,
      rateDate: rateDate ?? this.rateDate,
      averagePrice: averagePrice ?? this.averagePrice,
      unit: unit ?? this.unit,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory MandiRateDocument.fromJson(Map<String, dynamic> json, {String? id}) {
    return MandiRateDocument(
      id: id,
      cropType: (json['cropType'] ?? '').toString(),
      rateDate:
          _toDateTime(json['rateDate']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      averagePrice: _toDouble(json['averagePrice']),
      unit: (json['unit'] ?? 'PKR/40kg').toString(),
      source: (json['source'] ?? 'daily_aggregation').toString(),
      createdAt: _toDateTime(json['createdAt']),
      updatedAt: _toDateTime(json['updatedAt']),
    );
  }

  factory MandiRateDocument.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return MandiRateDocument.fromJson(doc.data() ?? <String, dynamic>{}, id: doc.id);
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'cropType': cropType,
      'rateDate': Timestamp.fromDate(
        DateTime(rateDate.year, rateDate.month, rateDate.day),
      ),
      'averagePrice': averagePrice,
      'unit': unit,
      'source': source,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String dailyDocId(String cropType, DateTime date) {
    final normalizedCrop = cropType.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
    final day = DateTime(date.year, date.month, date.day);
    final mm = day.month.toString().padLeft(2, '0');
    final dd = day.day.toString().padLeft(2, '0');
    return '${normalizedCrop}_${day.year}-$mm-$dd';
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

