import 'package:geolocator/geolocator.dart';

class PriorityMandiTarget {
  const PriorityMandiTarget({
    required this.city,
    required this.district,
    required this.province,
    required this.aliases,
    required this.priorityRank,
    required this.expectedSourceFamily,
    required this.latitude,
    required this.longitude,
    required this.enabled,
    required this.futureReady,
  });

  final String city;
  final String district;
  final String province;
  final List<String> aliases;
  final int priorityRank;
  final String expectedSourceFamily;
  final double latitude;
  final double longitude;
  final bool enabled;
  final bool futureReady;
}

class PakistanMandiPriorityRegistry {
  const PakistanMandiPriorityRegistry._();

  static const List<PriorityMandiTarget> top25 = <PriorityMandiTarget>[
    PriorityMandiTarget(city: 'Lahore', district: 'Lahore', province: 'Punjab', aliases: <String>['Lahore', 'lahore', 'لاہور'], priorityRank: 1, expectedSourceFamily: 'official_city_market_source', latitude: 31.5204, longitude: 74.3587, enabled: true, futureReady: false),
    PriorityMandiTarget(city: 'Faisalabad', district: 'Faisalabad', province: 'Punjab', aliases: <String>['Faisalabad', 'faisalabad', 'فیصل آباد'], priorityRank: 2, expectedSourceFamily: 'future_city_committee_source', latitude: 31.4504, longitude: 73.135, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Rawalpindi', district: 'Rawalpindi', province: 'Punjab', aliases: <String>['Rawalpindi', 'rawalpindi', 'راولپنڈی'], priorityRank: 3, expectedSourceFamily: 'future_city_committee_source', latitude: 33.5651, longitude: 73.0169, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Multan', district: 'Multan', province: 'Punjab', aliases: <String>['Multan', 'multan', 'ملتان'], priorityRank: 4, expectedSourceFamily: 'future_city_committee_source', latitude: 30.1575, longitude: 71.5249, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Bahawalpur', district: 'Bahawalpur', province: 'Punjab', aliases: <String>['Bahawalpur', 'bahawalpur', 'بہاولپور'], priorityRank: 5, expectedSourceFamily: 'future_city_committee_source', latitude: 29.3956, longitude: 71.6836, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Gujranwala', district: 'Gujranwala', province: 'Punjab', aliases: <String>['Gujranwala', 'gujranwala', 'گوجرانوالہ'], priorityRank: 6, expectedSourceFamily: 'future_city_committee_source', latitude: 32.1877, longitude: 74.1945, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Sargodha', district: 'Sargodha', province: 'Punjab', aliases: <String>['Sargodha', 'sargodha', 'سرگودھا'], priorityRank: 7, expectedSourceFamily: 'future_city_committee_source', latitude: 32.0836, longitude: 72.6711, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Gujrat', district: 'Gujrat', province: 'Punjab', aliases: <String>['Gujrat', 'gujrat', 'گجرات'], priorityRank: 8, expectedSourceFamily: 'future_city_committee_source', latitude: 32.5711, longitude: 74.075, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'D.G. Khan', district: 'Dera Ghazi Khan', province: 'Punjab', aliases: <String>['D.G. Khan', 'DG Khan', 'Dera Ghazi Khan', 'ڈیرہ غازی خان'], priorityRank: 9, expectedSourceFamily: 'future_city_committee_source', latitude: 30.0452, longitude: 70.6402, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Sahiwal', district: 'Sahiwal', province: 'Punjab', aliases: <String>['Sahiwal', 'sahiwal', 'ساہیوال'], priorityRank: 10, expectedSourceFamily: 'future_city_committee_source', latitude: 30.6706, longitude: 73.1069, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Okara', district: 'Okara', province: 'Punjab', aliases: <String>['Okara', 'okara', 'اوکاڑہ'], priorityRank: 11, expectedSourceFamily: 'future_city_committee_source', latitude: 30.8103, longitude: 73.4516, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Vehari', district: 'Vehari', province: 'Punjab', aliases: <String>['Vehari', 'vehari', 'وہاڑی'], priorityRank: 12, expectedSourceFamily: 'future_city_committee_source', latitude: 30.0445, longitude: 72.3556, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Rahim Yar Khan', district: 'Rahim Yar Khan', province: 'Punjab', aliases: <String>['Rahim Yar Khan', 'rahim yar khan', 'رحیم یار خان'], priorityRank: 13, expectedSourceFamily: 'future_city_committee_source', latitude: 28.4212, longitude: 70.2989, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Bhakkar', district: 'Bhakkar', province: 'Punjab', aliases: <String>['Bhakkar', 'bhakkar', 'بھکر'], priorityRank: 14, expectedSourceFamily: 'future_city_committee_source', latitude: 31.6269, longitude: 71.0654, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Layyah', district: 'Layyah', province: 'Punjab', aliases: <String>['Layyah', 'layyah', 'لیہ'], priorityRank: 15, expectedSourceFamily: 'future_city_committee_source', latitude: 30.9693, longitude: 70.9428, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Khanewal', district: 'Khanewal', province: 'Punjab', aliases: <String>['Khanewal', 'khanewal', 'خانیوال'], priorityRank: 16, expectedSourceFamily: 'future_city_committee_source', latitude: 30.3004, longitude: 71.932, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Muzaffargarh', district: 'Muzaffargarh', province: 'Punjab', aliases: <String>['Muzaffargarh', 'muzaffargarh', 'مظفرگڑھ'], priorityRank: 17, expectedSourceFamily: 'future_city_committee_source', latitude: 30.0726, longitude: 71.1938, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Toba Tek Singh', district: 'Toba Tek Singh', province: 'Punjab', aliases: <String>['Toba Tek Singh', 'toba tek singh', 'ٹوبہ ٹیک سنگھ'], priorityRank: 18, expectedSourceFamily: 'future_city_committee_source', latitude: 30.9744, longitude: 72.4829, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Kabirwala', district: 'Khanewal', province: 'Punjab', aliases: <String>['Kabirwala', 'kabirwala', 'کبیروالا'], priorityRank: 19, expectedSourceFamily: 'future_city_committee_source', latitude: 30.4055, longitude: 71.8657, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Lodhran', district: 'Lodhran', province: 'Punjab', aliases: <String>['Lodhran', 'lodhran', 'لودھراں'], priorityRank: 20, expectedSourceFamily: 'future_city_committee_source', latitude: 29.5339, longitude: 71.6324, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Chichawatni', district: 'Sahiwal', province: 'Punjab', aliases: <String>['Chichawatni', 'chichawatni', 'چیچہ وطنی'], priorityRank: 21, expectedSourceFamily: 'future_city_committee_source', latitude: 30.5301, longitude: 72.6916, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Jhelum', district: 'Jhelum', province: 'Punjab', aliases: <String>['Jhelum', 'jhelum', 'جہلم'], priorityRank: 22, expectedSourceFamily: 'future_city_committee_source', latitude: 32.9405, longitude: 73.7276, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Mianwali', district: 'Mianwali', province: 'Punjab', aliases: <String>['Mianwali', 'mianwali', 'میانوالی'], priorityRank: 23, expectedSourceFamily: 'future_city_committee_source', latitude: 32.5862, longitude: 71.5436, enabled: true, futureReady: true),
    PriorityMandiTarget(city: 'Karachi', district: 'Karachi', province: 'Sindh', aliases: <String>['Karachi', 'karachi', 'کراچی'], priorityRank: 24, expectedSourceFamily: 'official_commissioner_source', latitude: 24.8607, longitude: 67.0011, enabled: true, futureReady: false),
    PriorityMandiTarget(city: 'Hyderabad', district: 'Hyderabad', province: 'Sindh', aliases: <String>['Hyderabad', 'hyderabad', 'حیدرآباد'], priorityRank: 25, expectedSourceFamily: 'future_city_committee_source', latitude: 25.396, longitude: 68.3578, enabled: true, futureReady: true),
  ];

  static List<PriorityMandiTarget> enabledTargets() {
    return top25.where((item) => item.enabled).toList(growable: false);
  }

  static String normalizeCity(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return '';
    for (final target in top25) {
      for (final alias in target.aliases) {
        if (alias.trim().toLowerCase() == value) {
          return target.city.toLowerCase();
        }
      }
    }
    return value
        .replaceAll(' district', '')
        .replaceAll(' city', '')
        .replaceAll(' tehsil', '')
        .trim();
  }

  static List<String> nearestCityCandidates({
    required double latitude,
    required double longitude,
    String? excludeCity,
    int limit = 6,
  }) {
    final exclude = normalizeCity(excludeCity ?? '');
    final ranked = enabledTargets()
        .map((item) {
          final km = Geolocator.distanceBetween(
                latitude,
                longitude,
                item.latitude,
                item.longitude,
              ) /
              1000;
          return (item, km);
        })
        .toList(growable: false)
      ..sort((a, b) {
        final distanceCompare = a.$2.compareTo(b.$2);
        if (distanceCompare != 0) return distanceCompare;
        return a.$1.priorityRank.compareTo(b.$1.priorityRank);
      });

    final out = <String>[];
    for (final row in ranked) {
      final cityNorm = normalizeCity(row.$1.city);
      if (exclude.isNotEmpty && cityNorm == exclude) continue;
      if (out.contains(row.$1.city)) continue;
      out.add(row.$1.city);
      if (out.length >= limit) break;
    }
    return out;
  }
}
