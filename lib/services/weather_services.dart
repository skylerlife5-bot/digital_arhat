import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../firebase_options.dart';
import 'ai_generative_service.dart';

class WeatherService {
  static const String _fallbackDistrict = 'Punjab';

  String get _projectId {
    try {
      return DefaultFirebaseOptions.currentPlatform.projectId;
    } catch (_) {
      return DefaultFirebaseOptions.android.projectId;
    }
  }

  String get _functionsBaseUrl =>
      'https://asia-south1-$_projectId.cloudfunctions.net';

  final MandiIntelligenceService _aiService = MandiIntelligenceService();

  Future<Map<String, dynamic>> getWeatherData(String district) async {
    final normalizedDistrict = district.trim().isEmpty
        ? _fallbackDistrict
        : district.trim();

    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

    try {
      final response = await http
          .post(
            Uri.parse('$_functionsBaseUrl/weatherCurrentHttp'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              if (idToken != null && idToken.trim().isNotEmpty)
                'Authorization': 'Bearer $idToken',
            },
            body: jsonEncode(<String, dynamic>{'district': normalizedDistrict}),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return _weatherUnavailableResponse(
          'موسمی سروس عارضی طور پر دستیاب نہیں۔',
        );
      }

      final Map<String, dynamic> decoded = response.body.trim().isEmpty
          ? <String, dynamic>{}
          : (jsonDecode(response.body) as Map<String, dynamic>);

      final double temp = _parseTemperature(decoded['temp']);
      final String condition = _sanitizeWeatherText(
        '${decoded['condition'] ?? 'Clear'}',
        fallback: 'Clear',
      );
      final String description = _sanitizeWeatherText(
        '${decoded['description'] ?? condition}',
        fallback: condition,
      );
      final String conditionUr = _conditionToUrdu(condition);

      if (temp == 0.0 && condition.trim().isEmpty) {
        return _weatherUnavailableResponse('موسمی معلومات مکمل نہیں ہیں۔');
      }

      return {
        'success': true,
        'temp': temp,
        'condition': _sanitizeWeatherText(condition, fallback: 'Clear'),
        'conditionUr': conditionUr,
        'description': _sanitizeWeatherText(description, fallback: condition),
        'humidity': _parseInt(decoded['humidity']),
        'windSpeed': _parseTemperature(decoded['windSpeed']),
        'isRainLikely':
            decoded['isRainLikely'] == true || _checkRain(condition),
      };
    } catch (_) {
      return _weatherUnavailableResponse('موسمی معلومات دستیاب نہیں۔');
    }
  }

  Future<String> getAIAdvisory(
    String condition,
    dynamic tempValue,
    String crop, {
    String? category,
    String? subcategory,
    String? district,
  }) async {
    final double temp = _parseTemperature(tempValue);
    final cropUr = _toUrduCropLabel(subcategory ?? category ?? crop);
    final districtUr = _normalizeDistrict(district);
    final conditionUr = _conditionToUrdu(condition);

    try {
      final String aiAdvice = await _aiService.getWeatherAlert(
        condition: condition,
        temperature: temp,
        crop: cropUr,
      );

      final clean = _normalizeAdvisory(aiAdvice);
      if (clean.isEmpty || _containsLatin(clean) || _looksTechnical(clean)) {
        return _getRuleBasedAdvisory(
          condition: conditionUr,
          temp: temp,
          crop: cropUr,
          district: districtUr,
        );
      }

      return clean;
    } catch (_) {
      return _getRuleBasedAdvisory(
        condition: conditionUr,
        temp: temp,
        crop: cropUr,
        district: districtUr,
      );
    }
  }

  bool _checkRain(String condition) {
    final rainTerms = ['rain', 'drizzle', 'thunderstorm', 'shower'];
    return rainTerms.any((term) => condition.toLowerCase().contains(term));
  }

  double _parseTemperature(dynamic tempValue) {
    if (tempValue is num) return tempValue.toDouble();
    if (tempValue is String) return double.tryParse(tempValue) ?? 0.0;
    return 0.0;
  }

  int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> _weatherUnavailableResponse(String msg) {
    return {
      'success': false,
      'temp': 0.0,
      'condition': 'Unavailable',
      'conditionUr': 'موسم دستیاب نہیں',
      'description': 'موسم دستیاب نہیں',
      'humidity': 0,
      'windSpeed': 0.0,
      'isRainLikely': false,
      'error': msg,
    };
  }

  String _sanitizeWeatherText(String text, {required String fallback}) {
    final String normalized = text.trim();
    if (normalized.isEmpty) return fallback;

    final String lower = normalized.toLowerCase();
    const List<String> localDialectTerms = [
      'vadhiya',
      'vadiya',
      'pya',
      'pai',
      'kani',
      'phuhar',
      'sona mausam',
      'sard hawa',
    ];

    if (localDialectTerms.any((term) => lower.contains(term))) {
      return fallback;
    }

    return _toTitleCase(normalized);
  }

  String _toTitleCase(String value) {
    final words = value
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .toList();
    if (words.isEmpty) return value;
    return words.join(' ');
  }

  String _getRuleBasedAdvisory({
    required String condition,
    required double temp,
    required String crop,
    required String district,
  }) {
    final cond = condition.toLowerCase();
    final districtLabel = _normalizeDistrict(district).trim().isEmpty
        ? 'آپ کے علاقے'
        : _normalizeDistrict(district);

    if (_checkRain(cond)) {
      return 'آج $districtLabel میں بارش کا امکان ہے۔ $crop کو نمی اور کھلے ذخیرے سے محفوظ رکھیں۔';
    }
    if (temp > 38) {
      return 'آج $districtLabel میں درجہ حرارت زیادہ ہے۔ $crop کے لیے آبپاشی کا وقفہ کم رکھیں اور سایہ کا انتظام کریں۔';
    }
    if (temp < 10 && temp != 0.0) {
      return 'آج $districtLabel میں سردی میں اضافہ ہے۔ $crop کو ٹھنڈی ہوا اور کہر سے بچانے کے لیے حفاظتی ڈھانپ استعمال کریں۔';
    }

    return 'آج $districtLabel میں موسم نسبتاً سازگار ہے۔ $crop کے لیے معمول کے مطابق آبپاشی اور ذخیرہ کاری جاری رکھیں۔';
  }

  String _normalizeAdvisory(String raw) {
    final cleaned = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll('*', '')
        .trim();
    if (cleaned.isEmpty) return '';
    return cleaned;
  }

  bool _containsLatin(String text) {
    return RegExp(r'[A-Za-z]').hasMatch(text);
  }

  bool _looksTechnical(String text) {
    final lower = text.toLowerCase();
    return lower.contains('debug') ||
        lower.contains('error') ||
        lower.contains('stack') ||
        lower.contains('exception');
  }

  String _normalizeDistrict(String? district) {
    final value = (district ?? '').trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    const urduMap = <String, String>{
      'lahore': 'لاہور',
      'kasur': 'قصور',
      'multan': 'ملتان',
      'faisalabad': 'فیصل آباد',
      'islamabad': 'اسلام آباد',
      'karachi': 'کراچی',
      'peshawar': 'پشاور',
      'quetta': 'کوئٹہ',
      'punjab': 'پنجاب',
      'sindh': 'سندھ',
    };
    if (urduMap.containsKey(lower)) {
      return urduMap[lower]!;
    }
    return value;
  }

  String _toUrduCropLabel(String value) {
    final v = value.trim().toLowerCase();
    if (v.isEmpty) return 'عمومی فصل';

    if (v.contains('wheat') || v.contains('گندم')) return 'گندم';
    if (v.contains('rice') || v.contains('چاول') || v.contains('دھان')) {
      return 'چاول';
    }
    if (v.contains('cotton') || v.contains('کپاس')) return 'کپاس';
    if (v.contains('maize') || v.contains('corn') || v.contains('مکئی')) {
      return 'مکئی';
    }
    if (v.contains('sugarcane') || v.contains('گنا')) return 'گنا';
    if (v.contains('vegetable') || v.contains('سبزی')) return 'سبزیاں';
    if (v.contains('fruit') || v.contains('پھل')) return 'پھل';
    if (v.contains('livestock') || v.contains('مویشی')) return 'مویشی';
    if (v.contains('milk') || v.contains('دودھ')) return 'دودھ';
    if (v.contains('seed') || v.contains('بیج')) return 'بیج';
    if (v.contains('fertilizer') || v.contains('کھاد')) return 'کھاد';

    if (_containsLatin(v)) return 'عمومی فصل';
    return value;
  }

  String _conditionToUrdu(String condition) {
    final c = condition.trim().toLowerCase();
    if (c.isEmpty) return 'صاف موسم';
    if (c.contains('thunder')) return 'گرج چمک کے ساتھ بارش';
    if (c.contains('drizzle')) return 'ہلکی بارش';
    if (c.contains('rain') || c.contains('shower')) return 'بارش';
    if (c.contains('cloud')) return 'ابر آلود';
    if (c.contains('mist') || c.contains('fog') || c.contains('haze')) {
      return 'دھند';
    }
    if (c.contains('wind')) return 'تیز ہوا';
    if (c.contains('sun') || c.contains('clear')) return 'صاف موسم';
    return _containsLatin(condition) ? 'موسمی صورتحال' : condition;
  }
}
