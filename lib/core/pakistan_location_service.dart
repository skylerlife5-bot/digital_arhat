// Shared Pakistan location service – single source of truth for Province /
// District / Tehsil data across Add Listing, Seller Sign-Up, and Buyer Sign-Up.
//
// Loads assets/data/pakistan_locations.json once (the same JSON used by
// add_listing_screen.dart) and falls back to PakistanLocationHierarchy static
// constants when the asset cannot be loaded.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'market_hierarchy.dart';

// ---------------------------------------------------------------------------
// Internal node types (lightweight – English name only, matching Add Listing)
// ---------------------------------------------------------------------------

class _Leaf {
  const _Leaf({required this.nameEn});
  final String nameEn;
}

class _District {
  const _District({required this.nameEn, required this.tehsils});
  final String nameEn;
  final List<_Leaf> tehsils;
}

class _Province {
  const _Province({required this.nameEn, required this.districts});
  final String nameEn;
  final List<_District> districts;
}

// ---------------------------------------------------------------------------
// Public service singleton
// ---------------------------------------------------------------------------

class PakistanLocationService {
  PakistanLocationService._();
  static final PakistanLocationService instance = PakistanLocationService._();

  List<_Province> _provinces = const <_Province>[];
  bool _loaded = false;

  /// Call once from initState; safe to call multiple times (no-op if loaded).
  Future<void> loadIfNeeded() async {
    if (_loaded) return;
    try {
      final rawJson = await rootBundle.loadString(
        'assets/data/pakistan_locations.json',
      );
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map<String, dynamic>) return;

      final provincesRaw = decoded['provinces'];
      if (provincesRaw is! List) return;

      final provinces = <_Province>[];
      for (final pItem in provincesRaw) {
        if (pItem is! Map) continue;
        final pMap = pItem.cast<String, dynamic>();
        final pEn = (pMap['name_en'] ?? '').toString().trim();
        if (pEn.isEmpty) continue;

        final districts = <_District>[];
        final districtsRaw = pMap['districts'];
        if (districtsRaw is List) {
          for (final dItem in districtsRaw) {
            if (dItem is! Map) continue;
            final dMap = dItem.cast<String, dynamic>();
            final dEn = (dMap['name_en'] ?? '').toString().trim();
            if (dEn.isEmpty) continue;

            final tehsils = <_Leaf>[];
            final tehsilsRaw = dMap['tehsils'];
            if (tehsilsRaw is List) {
              for (final tItem in tehsilsRaw) {
                if (tItem is! Map) continue;
                final tMap = tItem.cast<String, dynamic>();
                final tEn = (tMap['name_en'] ?? '').toString().trim();
                if (tEn.isNotEmpty) tehsils.add(_Leaf(nameEn: tEn));
              }
            }
            districts.add(_District(nameEn: dEn, tehsils: tehsils));
          }
        }
        provinces.add(_Province(nameEn: pEn, districts: districts));
      }

      if (provinces.isNotEmpty) {
        _provinces = provinces;
        _loaded = true;
      }
    } catch (_) {
      // Fall through – _loaded stays false and callers use static fallback.
    }
  }

  // -------------------------------------------------------------------------
  // Location accessors (mirror the private getters in add_listing_screen.dart)
  // -------------------------------------------------------------------------

  List<String> get provinces {
    if (_loaded && _provinces.isNotEmpty) {
      return _provinces.map((p) => p.nameEn).toList(growable: false);
    }
    return PakistanLocationHierarchy.provinces;
  }

  List<String> districtsForProvince(String province) {
    if (_loaded && _provinces.isNotEmpty) {
      final match = _provinces.where(
        (p) => p.nameEn.toLowerCase() == province.toLowerCase(),
      );
      if (match.isNotEmpty) {
        return match.first.districts
            .map((d) => d.nameEn)
            .toList(growable: false);
      }
    }
    return PakistanLocationHierarchy.districtsForProvince(province);
  }

  List<String> tehsilsForDistrict(String district) {
    if (_loaded && _provinces.isNotEmpty) {
      for (final province in _provinces) {
        for (final d in province.districts) {
          if (d.nameEn.toLowerCase() == district.toLowerCase()) {
            return d.tehsils.map((t) => t.nameEn).toList(growable: false);
          }
        }
      }
    }
    return PakistanLocationHierarchy.tehsilsForDistrict(district);
  }

  /// Returns city/area options for a given district+tehsil.
  /// Mirrors Add Listing's _cityOptions getter:
  ///   – if the JSON asset is loaded → [tehsil, district] (same as Add Listing)
  ///   – otherwise → PakistanLocationHierarchy fallback
  List<String> cityOptions({
    required String district,
    required String tehsil,
  }) {
    if (_loaded && _provinces.isNotEmpty) {
      if (district.isNotEmpty && tehsil.isNotEmpty) {
        return <String>[tehsil, district];
      }
      return const <String>[];
    }
    return PakistanLocationHierarchy.citiesForTehsil(
      district: district,
      tehsil: tehsil,
    );
  }
}
