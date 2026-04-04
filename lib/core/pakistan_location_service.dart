// Shared Pakistan location service – single source of truth for Province /
// District / Tehsil data across Add Listing, Seller Sign-Up, and Buyer Sign-Up.
//
// Loads assets/data/pakistan_locations.json once (the same JSON used by
// add_listing_screen.dart) and falls back to PakistanLocationHierarchy static
// constants when the asset cannot be loaded.

import 'dart:convert';

import 'package:flutter/services.dart';

import 'location_display_helper.dart';
import 'market_hierarchy.dart';

class BilingualLocationOption {
  const BilingualLocationOption({
    required this.code,
    required this.labelEn,
    required this.labelUr,
  });

  final String code;
  final String labelEn;
  final String labelUr;

  String get bilingualLabel => LocationDisplayHelper.bilingualLabelFromParts(
    labelEn,
    candidateUrdu: labelUr,
  );
}

// ---------------------------------------------------------------------------
// Internal node types (lightweight – English name only, matching Add Listing)
// ---------------------------------------------------------------------------

class _Leaf {
  const _Leaf({required this.nameEn, required this.nameUr});
  final String nameEn;
  final String nameUr;
}

class _District {
  const _District({
    required this.nameEn,
    required this.nameUr,
    required this.tehsils,
  });
  final String nameEn;
  final String nameUr;
  final List<_Tehsil> tehsils;
}

class _Tehsil {
  const _Tehsil({
    required this.nameEn,
    required this.nameUr,
    required this.cities,
  });

  final String nameEn;
  final String nameUr;
  final List<_Leaf> cities;
}

class _Province {
  const _Province({
    required this.nameEn,
    required this.nameUr,
    required this.districts,
  });
  final String nameEn;
  final String nameUr;
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
        final pUr = (pMap['name_ur'] ?? '').toString().trim();

        final districts = <_District>[];
        final districtsRaw = pMap['districts'];
        if (districtsRaw is List) {
          for (final dItem in districtsRaw) {
            if (dItem is! Map) continue;
            final dMap = dItem.cast<String, dynamic>();
            final dEn = (dMap['name_en'] ?? '').toString().trim();
            if (dEn.isEmpty) continue;
            final dUr = (dMap['name_ur'] ?? '').toString().trim();

            final tehsils = <_Tehsil>[];
            final tehsilsRaw = dMap['tehsils'];
            if (tehsilsRaw is List) {
              for (final tItem in tehsilsRaw) {
                if (tItem is! Map) continue;
                final tMap = tItem.cast<String, dynamic>();
                final tEn = (tMap['name_en'] ?? '').toString().trim();
                if (tEn.isEmpty) continue;

                final tUr = (tMap['name_ur'] ?? '').toString().trim();
                final cities = <_Leaf>[];
                final citiesRaw = tMap['cities'];
                if (citiesRaw is List) {
                  for (final cItem in citiesRaw) {
                    if (cItem is! Map) continue;
                    final cMap = cItem.cast<String, dynamic>();
                    final cEn = (cMap['name_en'] ?? '').toString().trim();
                    if (cEn.isEmpty) continue;
                    final cUr = (cMap['name_ur'] ?? '').toString().trim();
                    cities.add(_Leaf(nameEn: cEn, nameUr: cUr));
                  }
                }

                tehsils.add(_Tehsil(nameEn: tEn, nameUr: tUr, cities: cities));
              }
            }
            districts.add(
              _District(nameEn: dEn, nameUr: dUr, tehsils: tehsils),
            );
          }
        }
        provinces.add(
          _Province(nameEn: pEn, nameUr: pUr, districts: districts),
        );
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

  List<BilingualLocationOption> get provinceOptions {
    if (_loaded && _provinces.isNotEmpty) {
      return _provinces
          .map(
            (p) => BilingualLocationOption(
              code: _stableCode(p.nameEn),
              labelEn: p.nameEn,
              labelUr: LocationDisplayHelper.resolvedUrduLabel(
                p.nameEn,
                candidateUrdu: p.nameUr,
              ),
            ),
          )
          .toList(growable: false);
    }

    return PakistanLocationHierarchy.provinces
        .map(
          (name) => BilingualLocationOption(
            code: _stableCode(name),
            labelEn: name,
            labelUr: LocationDisplayHelper.resolvedUrduLabel(name),
          ),
        )
        .toList(growable: false);
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

  List<BilingualLocationOption> districtOptions(String province) {
    if (_loaded && _provinces.isNotEmpty) {
      final String provinceLower = province.trim().toLowerCase();
      final Iterable<_Province> match = _provinces.where(
        (p) => p.nameEn.toLowerCase() == provinceLower,
      );
      if (match.isNotEmpty) {
        return match.first.districts
            .map(
              (d) => BilingualLocationOption(
                code: _stableCode(d.nameEn),
                labelEn: d.nameEn,
                labelUr: LocationDisplayHelper.resolvedUrduLabel(
                  d.nameEn,
                  candidateUrdu: d.nameUr,
                ),
              ),
            )
            .toList(growable: false);
      }
    }

    final List<String> districts = districtsForProvince(province);
    return districts
        .map(
          (name) => BilingualLocationOption(
            code: _stableCode(name),
            labelEn: name,
            labelUr: LocationDisplayHelper.resolvedUrduLabel(name),
          ),
        )
        .toList(growable: false);
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

  List<BilingualLocationOption> tehsilOptions(String district) {
    if (_loaded && _provinces.isNotEmpty) {
      final String districtLower = district.trim().toLowerCase();
      for (final province in _provinces) {
        for (final d in province.districts) {
          if (d.nameEn.toLowerCase() != districtLower) continue;
          return d.tehsils
              .map(
                (t) => BilingualLocationOption(
                  code: _stableCode(t.nameEn),
                  labelEn: t.nameEn,
                  labelUr: LocationDisplayHelper.resolvedUrduLabel(
                    t.nameEn,
                    candidateUrdu: t.nameUr,
                  ),
                ),
              )
              .toList(growable: false);
        }
      }
    }

    final List<String> tehsils = tehsilsForDistrict(district);
    return tehsils
        .map(
          (name) => BilingualLocationOption(
            code: _stableCode(name),
            labelEn: name,
            labelUr: LocationDisplayHelper.resolvedUrduLabel(name),
          ),
        )
        .toList(growable: false);
  }

  /// Returns city/area options for a given district+tehsil.
  /// Suggestions are optional and never required for writable city input.
  List<String> cityOptions({required String district, required String tehsil}) {
    if (_loaded && _provinces.isNotEmpty) {
      final districtClean = district.trim().toLowerCase();
      final tehsilClean = tehsil.trim().toLowerCase();
      if (districtClean.isNotEmpty && tehsilClean.isNotEmpty) {
        for (final province in _provinces) {
          for (final d in province.districts) {
            if (d.nameEn.toLowerCase() != districtClean) continue;
            for (final t in d.tehsils) {
              if (t.nameEn.toLowerCase() != tehsilClean) continue;
              final cities = t.cities
                  .map((c) => c.nameEn)
                  .where((c) => c.trim().isNotEmpty)
                  .toList(growable: false);
              if (cities.isNotEmpty) return cities;
            }
          }
        }
      }
      return const <String>[];
    }
    return const <String>[];
  }

  List<BilingualLocationOption> cityOptionsLocalized({
    required String district,
    required String tehsil,
  }) {
    if (_loaded && _provinces.isNotEmpty) {
      final String districtLower = district.trim().toLowerCase();
      final String tehsilLower = tehsil.trim().toLowerCase();

      for (final province in _provinces) {
        for (final d in province.districts) {
          if (d.nameEn.toLowerCase() != districtLower) continue;
          for (final t in d.tehsils) {
            if (t.nameEn.toLowerCase() != tehsilLower) continue;
            final List<BilingualLocationOption> localized = t.cities
                .map(
                  (c) => BilingualLocationOption(
                    code: _stableCode(c.nameEn),
                    labelEn: c.nameEn,
                    labelUr: LocationDisplayHelper.resolvedUrduLabel(
                      c.nameEn,
                      candidateUrdu: c.nameUr,
                    ),
                  ),
                )
                .where((c) => c.labelEn.trim().isNotEmpty)
                .toList(growable: false);
            if (localized.isNotEmpty) {
              return localized;
            }
            return const <BilingualLocationOption>[];
          }
        }
      }
    }

    final List<String> cities = cityOptions(district: district, tehsil: tehsil);
    return cities
        .map(
          (name) => BilingualLocationOption(
            code: _stableCode(name),
            labelEn: name,
            labelUr: LocationDisplayHelper.urduFor(name),
          ),
        )
        .toList(growable: false);
  }

  String _stableCode(String input) {
    final String normalized = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'loc_unknown' : normalized;
  }
}
