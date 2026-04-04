import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/location_display_helper.dart';

enum RiskLevel { low, medium, high, unknown }

enum OrderLifecycleStatus { pendingAdmin, approved, paid, rejected, cancelled, unknown }

class BuyerListing {
  BuyerListing({
    required this.id,
    required this.itemName,
    required this.quantity,
    required this.unit,
    required this.province,
    required this.district,
    required this.tehsil,
    required this.city,
    required this.locationDisplay,
    required this.sellerId,
    required this.status,
    required this.expiresAt,
    required this.riskLevel,
    required this.riskScore,
    this.marketAveragePrice,
    this.approvedAt,
    this.description,
  });

  final String id;
  final String itemName;
  final double quantity;
  final String unit;
  final String province;
  final String district;
  final String tehsil;
  final String city;
  final String locationDisplay;
  final String sellerId;
  final String status;
  final DateTime expiresAt;
  final DateTime? approvedAt;
  final RiskLevel riskLevel;
  final int riskScore;
  final double? marketAveragePrice;
  final String? description;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt.toUtc());

  String get locationLabel {
    return LocationDisplayHelper.locationDisplayFromData(<String, dynamic>{
      'locationDisplay': locationDisplay,
      'city': city,
      'tehsil': tehsil,
      'district': district,
      'province': province,
    });
  }

  static BuyerListing fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    final approvedAt = _timestampToDate(map['approvedAt']);
    final expiresAt =
        _timestampToDate(map['expiresAt']) ??
        (approvedAt ?? DateTime.now().toUtc()).add(const Duration(hours: 24));
    final locationDataRaw = map['locationData'];
    final locationData = locationDataRaw is Map
        ? Map<String, dynamic>.from(locationDataRaw)
        : const <String, dynamic>{};

    final province = _readString(
      map['province'],
      fallback: _readString(locationData['province'], fallback: 'Pakistan'),
    );
    final district = _readString(
      map['district'],
      fallback: _readString(locationData['district']),
    );
    final tehsil = _readString(
      map['tehsil'],
      fallback: _readString(locationData['tehsil']),
    );
    final city = _readString(
      map['city'],
      fallback: _readString(locationData['city']),
    );
    final locationDisplay = _readString(
      map['locationDisplay'],
      fallback: _readString(map['location']),
    );

    return BuyerListing(
      id: doc.id,
      itemName: _readString(map['itemName'], fallback: _readString(map['cropName'], fallback: 'Item')),
      quantity: _readDouble(map['quantity'], fallback: 0),
      unit: _readString(map['unit'], fallback: 'kg'),
      province: province,
      district: district,
      tehsil: tehsil,
      city: city,
      locationDisplay: locationDisplay,
      sellerId: _readString(map['sellerId']),
      status: _readString(map['status'], fallback: 'live'),
      expiresAt: expiresAt,
      approvedAt: approvedAt,
      riskLevel: parseRiskLevel(map['riskLevel']),
      riskScore: _readInt(map['riskScore'], fallback: 0),
      marketAveragePrice: _readNullableDouble(
        map['marketAverageRate'] ?? map['marketAveragePrice'] ?? map['aiMarketRate'],
      ),
      description: _readString(map['description']),
    );
  }
}

class BuyerOrder {
  BuyerOrder({
    required this.id,
    required this.listingId,
    required this.buyerId,
    required this.sellerId,
    required this.itemName,
    required this.bidAmount,
    required this.status,
    required this.chatUnlocked,
    this.exactAddress,
  });

  final String id;
  final String listingId;
  final String buyerId;
  final String sellerId;
  final String itemName;
  final double bidAmount;
  final OrderLifecycleStatus status;
  final bool chatUnlocked;
  final String? exactAddress;

  bool get canPayEscrow => status == OrderLifecycleStatus.approved;
  bool get isPaid => status == OrderLifecycleStatus.paid;

  static BuyerOrder fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? const <String, dynamic>{};
    return BuyerOrder(
      id: doc.id,
      listingId: _readString(map['listingId']),
      buyerId: _readString(map['buyerId']),
      sellerId: _readString(map['sellerId']),
      itemName: _readString(map['itemName'], fallback: 'Item'),
      bidAmount: _readDouble(map['bidAmount'], fallback: 0),
      status: parseOrderStatus(map['status']),
      chatUnlocked: map['chatUnlocked'] == true,
      exactAddress: _readString(map['exactAddress']),
    );
  }
}

OrderLifecycleStatus parseOrderStatus(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  switch (normalized) {
    case 'pending_admin':
      return OrderLifecycleStatus.pendingAdmin;
    case 'approved':
      return OrderLifecycleStatus.approved;
    case 'paid':
      return OrderLifecycleStatus.paid;
    case 'rejected':
      return OrderLifecycleStatus.rejected;
    case 'cancelled':
      return OrderLifecycleStatus.cancelled;
    default:
      return OrderLifecycleStatus.unknown;
  }
}

RiskLevel parseRiskLevel(dynamic value) {
  final normalized = value?.toString().trim().toLowerCase() ?? '';
  switch (normalized) {
    case 'low':
      return RiskLevel.low;
    case 'medium':
      return RiskLevel.medium;
    case 'high':
      return RiskLevel.high;
    default:
      return RiskLevel.unknown;
  }
}

class BuyerUiTheme {
  static const Color deepGreen = Color(0xFF0A3321);
  static const Color greenMid = Color(0xFF11422B);
  static const Color greenDark = Color(0xFF062517);
  static const Color gold = Color(0xFFD4AF37);

  static TextStyle urduLabelStyle({
    double size = 14,
    FontWeight weight = FontWeight.w600,
    Color color = Colors.white,
  }) {
    return TextStyle(
      fontFamily: 'JameelNoori',
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.3,
    );
  }
}

class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.level, required this.score});

  final RiskLevel level;
  final int score;

  @override
  Widget build(BuildContext context) {
    final config = switch (level) {
      RiskLevel.low => (label: 'Low Risk', urdu: 'کم خطرہ', color: const Color(0xFF2ECC71), icon: Icons.verified_rounded),
      RiskLevel.medium => (label: 'Medium Risk', urdu: 'درمیانی خطرہ', color: const Color(0xFFF39C12), icon: Icons.warning_amber_rounded),
      RiskLevel.high => (label: 'High Risk', urdu: 'زیادہ خطرہ', color: const Color(0xFFE74C3C), icon: Icons.gpp_bad_rounded),
      RiskLevel.unknown => (label: 'Unknown', urdu: 'غیر واضح', color: Colors.blueGrey, icon: Icons.help_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: config.color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: config.color.withValues(alpha: 0.85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 16, color: config.color),
          const SizedBox(width: 6),
          Text(
            '${config.label} • $score',
            style: TextStyle(color: config.color, fontWeight: FontWeight.w700, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Directionality(
            textDirection: TextDirection.rtl,
            child: Text(config.urdu, style: BuyerUiTheme.urduLabelStyle(size: 13, color: config.color)),
          ),
        ],
      ),
    );
  }
}

DateTime? _timestampToDate(dynamic value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
  return null;
}

double _readDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? fallback;
}

double? _readNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

int _readInt(dynamic value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

String _readString(dynamic value, {String fallback = ''}) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}
