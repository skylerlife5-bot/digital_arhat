import 'dart:io';
import 'package:weather/weather.dart';
import 'ai_generative_service.dart';

class WeatherService {
  // API Configuration
  static const String _apiKey = "5b51e91b66ec10b88380f02540a3423f";
  static final WeatherFactory _weatherFactory = WeatherFactory(_apiKey);

  final MandiIntelligenceService _aiService = MandiIntelligenceService();

  /// �S& Professional Weather Fetching with Detailed Response
  Future<Map<String, dynamic>> getWeatherData(String district) async {
    final String cityName = '$district,PK';

    try {
      final weather = await _weatherFactory
          .currentWeatherByCityName(cityName)
          .timeout(const Duration(seconds: 12));

      final double temp = weather.temperature?.celsius ?? 0.0;
      final String condition = (weather.weatherMain ?? 'Clear').toString();
      final String description =
          (weather.weatherDescription ?? condition).toString();

      if (temp == 0.0 && condition.trim().isEmpty) {
        return _weatherUnavailableResponse('Weather payload invalid hai.');
      }

      return {
        'success': true,
        'temp': temp,
        'condition': _sanitizeWeatherText(condition, fallback: 'Clear'),
        'description': _sanitizeWeatherText(description, fallback: condition),
        'humidity': _parseInt(weather.humidity),
        'windSpeed': _parseTemperature(weather.windSpeed),
        'isRainLikely': _checkRain(condition),
      };
    } on SocketException {
      return _weatherUnavailableResponse("Internet connection ka masla hai.");
    } catch (e) {
      return _weatherUnavailableResponse("Weather data dastyab nahi hai.");
    }
  }

  /// �x� AI Advisory Logic (Professional Integration)
  Future<String> getAIAdvisory(
    String condition,
    dynamic tempValue,
    String crop,
  ) async {
    final double temp = _parseTemperature(tempValue);

    try {
      // 1. Trying Gemini for Smart Advisory
      final String advice = await _aiService.getWeatherAlert(
        condition: condition,
        temperature: temp,
        crop: crop,
      );

      // Agar AI koi error ya empty response de to fallback use karein
      if (advice.isEmpty || advice.contains("error")) {
        return _getRuleBasedAdvisory(condition, temp, crop);
      }

      return advice;
    } catch (e) {
      return _getRuleBasedAdvisory(condition, temp, crop);
    }
  }

  /// --- Helper Methods ---

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
      'condition': 'Weather Unavailable',
      'description': 'Weather Unavailable',
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

  /// �S& Rule-Based Fallback (Safe Mode)
  String _getRuleBasedAdvisory(String condition, double temp, String crop) {
    String cond = condition.toLowerCase();

    if (_checkRain(cond)) {
      return "آئ�R ا�رٹ: بارش کا ا�&کا�  ہ�� $crop ک�R کٹائ�R ر��ک د�Rں ا��ر � کاس�R آب کا ا� تظا�& کر�Rں�";
    }
    if (temp > 38) {
      return "شد�Rد گر�&�R ($temp°C)� $crop ک�� ��� س� ب� ا� � ک� ��R� ہ�کا پا� �R �گائ�Rں�";
    }
    if (temp < 10 && temp != 0.0) {
      return "سرد�R ا��ر ک��ر� کا خطرہ� $crop ک�R حفاظت ک� ��R� دھ��اں �Rا ہ�کا پا� �R استع�&ا� کر�Rں�";
    }

    return "�&��س�& $crop ک� ��R� سازگار ہ�� زرع�R �&اہر�R�  ک� �&طاب� �&ع�&��� ک� کا�& جار�R رکھ�Rں�";
  }
}

