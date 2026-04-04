import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/constants.dart';
import '../../core/mandi_unit_mapper.dart';

class ListingModel {
  final String? id;
  final String sellerId;
  final String productName;
  final double price;
  final String? breed;
  final double? weight;
  final double? fatPercentage;
  final ListingGrade? grade;
  final UnitType? unitType;
  final MandiType mandiType;
  final String category;
  final String subcategory;
  final bool isSuspicious;
  final String videoUrl;
  final bool isVerifiedSource;
  final String country;
  final String province;
  final String district;
  final String tehsil;
  final String city;
  final String location;
  final Map<String, dynamic> locationData;
  final double? verificationLatitude;
  final double? verificationLongitude;
  final String suspiciousReason;
  final String status; // 'active', 'pending', 'sold'
  final DateTime createdAt;

  bool get hasVerifiedSource {
    return isVerifiedSource && videoUrl.trim().isNotEmpty;
  }

  ListingModel({
    this.id,
    required this.sellerId,
    required this.productName,
    required this.price,
    this.breed,
    this.weight,
    this.fatPercentage,
    this.grade,
    this.unitType,
    this.mandiType = MandiType.crops,
    this.category = '',
    this.subcategory = '',
    this.isSuspicious = false,
    this.videoUrl = '',
    this.isVerifiedSource = false,
    this.country = 'Pakistan',
    this.province = '',
    this.district = '',
    this.tehsil = '',
    this.city = '',
    this.location = '',
    this.locationData = const <String, dynamic>{},
    this.verificationLatitude,
    this.verificationLongitude,
    this.suspiciousReason = "",
    this.status = 'active',
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    final normalizedVideoUrl = videoUrl.trim();
    final normalizedVerifiedSource =
        isVerifiedSource && normalizedVideoUrl.isNotEmpty;
    return {
      'sellerId': sellerId,
      'productName': productName,
      'price': price,
      'breed': breed,
      'weight': weight,
      'fatPercentage': fatPercentage,
      'grade': grade?.wireValue,
      'unitType': unitType?.wireValue,
      'mandiType': mandiType.wireValue,
      'category': category,
      'subcategory': subcategory,
      'isSuspicious': isSuspicious,
      'videoUrl': normalizedVideoUrl,
      'isVerifiedSource': normalizedVerifiedSource,
      'country': country,
      'province': province,
      'district': district,
      'tehsil': tehsil,
      'city': city,
      'location': location,
      'locationData': locationData,
      'verificationGeo': {
        'lat': verificationLatitude,
        'lng': verificationLongitude,
      },
      'suspiciousReason': suspiciousReason,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory ListingModel.fromMap(Map<String, dynamic> map, {String? id}) {
    final verificationGeoRaw = map['verificationGeo'];
    final verificationGeo = verificationGeoRaw is Map
        ? verificationGeoRaw
        : const <String, dynamic>{};
    final locationDataRaw = map['locationData'];
    final locationData = locationDataRaw is Map
        ? Map<String, dynamic>.from(locationDataRaw)
        : <String, dynamic>{
            'province': map['province']?.toString() ?? '',
            'district': map['district']?.toString() ?? '',
            'location': map['location']?.toString() ?? '',
          };

    double? parseDouble(dynamic value) {
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '');
    }

    MandiType parseMandiType(dynamic value) {
      final text = (value ?? '').toString().toUpperCase();
      return MandiType.values.firstWhere(
        (type) => type.wireValue.toUpperCase() == text,
        orElse: () => MandiType.crops,
      );
    }

    ListingGrade? parseGrade(dynamic value) {
      final text = (value ?? '').toString().toUpperCase();
      for (final grade in ListingGrade.values) {
        if (grade.wireValue.toUpperCase() == text) {
          return grade;
        }
      }
      return null;
    }

    final createdAtRaw = map['createdAt'];
    final createdAt = createdAtRaw is Timestamp
        ? createdAtRaw.toDate()
        : DateTime.tryParse(createdAtRaw?.toString() ?? '') ?? DateTime.now();

    final videoUrl = (map['videoUrl'] ?? map['video'] ?? '').toString().trim();
    final isVerifiedSource =
        map['isVerifiedSource'] == true && videoUrl.isNotEmpty;
    final mandiType = parseMandiType(map['mandiType']);
    final categoryId = (map['category'] ?? '').toString().trim();
    final subcategoryLabel = (map['subcategoryLabel'] ??
        map['subcategory'] ??
        map['productName'] ??
        map['product'] ??
        '')
      .toString();
    final normalizedUnitType = MandiUnitMapper.normalizeUnitType(
      rawUnit: map['unitType'] ?? map['unit'],
      categoryId: categoryId,
      fallbackType: mandiType,
      subcategoryLabel: subcategoryLabel,
    );

    return ListingModel(
      id: id ?? map['id']?.toString(),
      sellerId: (map['sellerId'] ?? '').toString(),
      productName: (map['productName'] ?? map['product'] ?? '').toString(),
      price: parseDouble(map['price']) ?? 0,
      breed: map['breed']?.toString(),
      weight: parseDouble(map['weight']),
      fatPercentage: parseDouble(map['fatPercentage']),
      grade: parseGrade(map['grade']),
      unitType: normalizedUnitType,
      mandiType: mandiType,
      isSuspicious: map['isSuspicious'] == true,
      videoUrl: videoUrl,
      isVerifiedSource: isVerifiedSource,
      country: (map['country'] ?? 'Pakistan').toString(),
      province: (map['province'] ?? '').toString(),
      district: (map['district'] ?? '').toString(),
      tehsil: (map['tehsil'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      category: (map['category'] ?? map['mandiType'] ?? '').toString(),
      subcategory: (map['subcategory'] ?? map['product'] ?? '').toString(),
      location: (map['location'] ?? '').toString(),
      locationData: locationData,
      verificationLatitude: parseDouble(verificationGeo['lat']),
      verificationLongitude: parseDouble(verificationGeo['lng']),
      suspiciousReason: (map['suspiciousReason'] ?? '').toString(),
      status: (map['status'] ?? 'active').toString(),
      createdAt: createdAt,
    );
  }
}
