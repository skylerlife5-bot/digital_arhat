import 'package:geolocator/geolocator.dart';

class MandiLocationContext {
  const MandiLocationContext({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.district,
    required this.province,
    required this.permissionDenied,
    required this.permissionPermanentlyDenied,
    required this.locationServiceDisabled,
    required this.usedFallback,
  });

  final double? latitude;
  final double? longitude;
  final String city;
  final String district;
  final String province;
  final bool permissionDenied;
  final bool permissionPermanentlyDenied;
  final bool locationServiceDisabled;
  final bool usedFallback;

  bool get permissionGranted =>
      !permissionDenied && !permissionPermanentlyDenied;

  bool get locationAvailable => latitude != null && longitude != null;

  static const MandiLocationContext empty = MandiLocationContext(
    latitude: null,
    longitude: null,
    city: '',
    district: '',
    province: '',
    permissionDenied: false,
    permissionPermanentlyDenied: false,
    locationServiceDisabled: false,
    usedFallback: true,
  );
}

class MandiRateLocationService {
  const MandiRateLocationService();

  Future<MandiLocationContext> resolve({
    String? fallbackCity,
    String? fallbackDistrict,
    String? fallbackProvince,
  }) async {
    final safeCity = (fallbackCity ?? '').trim();
    final safeDistrict = (fallbackDistrict ?? '').trim();
    final safeProvince = (fallbackProvince ?? '').trim();

    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return MandiLocationContext(
        latitude: null,
        longitude: null,
        city: safeCity,
        district: safeDistrict,
        province: safeProvince,
        permissionDenied: false,
        permissionPermanentlyDenied: false,
        locationServiceDisabled: true,
        usedFallback: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return MandiLocationContext(
        latitude: null,
        longitude: null,
        city: safeCity,
        district: safeDistrict,
        province: safeProvince,
        permissionDenied: true,
        permissionPermanentlyDenied: false,
        locationServiceDisabled: false,
        usedFallback: true,
      );
    }

    if (permission == LocationPermission.deniedForever) {
      return MandiLocationContext(
        latitude: null,
        longitude: null,
        city: safeCity,
        district: safeDistrict,
        province: safeProvince,
        permissionDenied: false,
        permissionPermanentlyDenied: true,
        locationServiceDisabled: false,
        usedFallback: true,
      );
    }

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) {
      return MandiLocationContext(
        latitude: null,
        longitude: null,
        city: safeCity,
        district: safeDistrict,
        province: safeProvince,
        permissionDenied: false,
        permissionPermanentlyDenied: false,
        locationServiceDisabled: false,
        usedFallback: true,
      );
    }

    return MandiLocationContext(
      latitude: position.latitude,
      longitude: position.longitude,
      city: safeCity,
      district: safeDistrict,
      province: safeProvince,
      permissionDenied: false,
      permissionPermanentlyDenied: false,
      locationServiceDisabled: false,
      usedFallback: safeCity.isNotEmpty || safeDistrict.isNotEmpty || safeProvince.isNotEmpty,
    );
  }
}
