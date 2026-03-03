import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/constants.dart';

class ValidationResult {
  final bool isSuspicious;
  final int riskScore;
  final String warningMessage;
  final double sellerPrice;
  final double? marketRate;
  final double deviationPercent;
  final String? errorCode;

  const ValidationResult({
    required this.isSuspicious,
    required this.riskScore,
    required this.warningMessage,
    required this.sellerPrice,
    required this.marketRate,
    required this.deviationPercent,
    this.errorCode,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'isSuspicious': isSuspicious,
      'riskScore': riskScore,
      'warningMessage': warningMessage,
      'sellerPrice': sellerPrice,
      'marketRate': marketRate,
      'deviationPercent': deviationPercent,
      'errorCode': errorCode,
    };
  }
}

class MandiValidationService {
  final FirebaseFirestore _db;

  static const double _suspiciousThresholdPercent = 20.0;

  MandiValidationService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  Future<ValidationResult> validateSellerPrice({
    required String cropType,
    required double sellerPrice,
  }) async {
    final normalizedCrop = cropType.trim();

    if (normalizedCrop.isEmpty) {
      return _errorResult(
        sellerPrice: sellerPrice,
        errorCode: 'INVALID_CROP',
        warningMessage: 'فص� ک�R �س�& درست فراہ�& کر�Rں�',
      );
    }

    if (sellerPrice <= 0) {
      return _errorResult(
        sellerPrice: sellerPrice,
        errorCode: 'INVALID_PRICE',
        warningMessage: '��R�&ت صفر س� ز�Rادہ ہ��� �R � اہ�R��',
      );
    }

    try {
      final marketRate = await _fetchLatestMarketRate(
        normalizedCrop,
      ).timeout(const Duration(seconds: 8));

      if (marketRate == null || marketRate <= 0) {
        return _errorResult(
          sellerPrice: sellerPrice,
          errorCode: 'MARKET_RATE_NOT_FOUND',
          warningMessage:
              'اس فص� کا تازہ �&� ���R ر�Rٹ دست�Rاب � ہ�Rں� براہِ کر�& بعد �&�Rں د��بارہ ک��شش کر�Rں�',
        );
      }

      final deviationPercent = _calculateDeviationPercent(
        sellerPrice: sellerPrice,
        marketRate: marketRate,
      );
      final absoluteDeviation = deviationPercent.abs();
      final isSuspicious = absoluteDeviation > _suspiciousThresholdPercent;
      final riskScore = _calculateRiskScore(absoluteDeviation);

      return ValidationResult(
        isSuspicious: isSuspicious,
        riskScore: riskScore,
        warningMessage: _buildUrduMessage(
          cropType: normalizedCrop,
          sellerPrice: sellerPrice,
          marketRate: marketRate,
          deviationPercent: deviationPercent,
          isSuspicious: isSuspicious,
          riskScore: riskScore,
        ),
        sellerPrice: sellerPrice,
        marketRate: marketRate,
        deviationPercent: deviationPercent,
      );
    } on TimeoutException {
      return _errorResult(
        sellerPrice: sellerPrice,
        errorCode: 'RATE_FETCH_TIMEOUT',
        warningMessage:
            '�&� ���R ر�Rٹ حاص� کر� � �&�Rں تاخ�Rر ہ�� رہ�R ہ�� براہِ کر�& د��بارہ ک��شش کر�Rں�',
      );
    } on FirebaseException {
      return _errorResult(
        sellerPrice: sellerPrice,
        errorCode: 'FIRESTORE_ERROR',
        warningMessage:
            '�&� ���R ر�Rٹ سر��س �&�Rں �&سئ�ہ پ�Rش آ�Rا ہ�� ک� ھ د�Rر بعد د��بارہ ک��شش کر�Rں�',
      );
    } catch (_) {
      return _errorResult(
        sellerPrice: sellerPrice,
        errorCode: 'UNKNOWN_ERROR',
        warningMessage:
            '��R�&ت ک�R جا� �  �&ک�&� � ہ ہ�� سک�R� براہِ کر�& د��بارہ ک��شش کر�Rں�',
      );
    }
  }

  Future<double?> _fetchLatestMarketRate(String cropType) async {
    final fromDailyRates = await _fetchFromMandiRatesCollection(cropType);
    if (fromDailyRates != null && fromDailyRates > 0) {
      return fromDailyRates;
    }

    return _fetchFromPakistanMandiRatesCollection(cropType);
  }

  Future<double?> _fetchFromMandiRatesCollection(String cropType) async {
    final normalized = cropType.trim().toLowerCase();

    final query = await _db
        .collection(AppConstants.mandiRatesCollection)
        .orderBy('rateDate', descending: true)
        .limit(100)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      final crop = (data['cropType'] ?? data['cropName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (crop != normalized) continue;

      final averagePrice = _toDouble(data['averagePrice']);
      if (averagePrice != null && averagePrice > 0) {
        return averagePrice;
      }
    }

    return null;
  }

  Future<double?> _fetchFromPakistanMandiRatesCollection(
    String cropType,
  ) async {
    final normalized = cropType.trim().toLowerCase();

    final query = await _db
        .collection(AppConstants.pakistanMandiRatesCollection)
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      final crop = (data['cropName'] ?? data['itemName'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (crop != normalized) continue;

      final averagePrice = _toDouble(data['average'] ?? data['currentRate']);
      if (averagePrice != null && averagePrice > 0) {
        return averagePrice;
      }
    }

    return null;
  }

  double _calculateDeviationPercent({
    required double sellerPrice,
    required double marketRate,
  }) {
    return ((sellerPrice - marketRate) / marketRate) * 100;
  }

  int _calculateRiskScore(double absoluteDeviation) {
    if (absoluteDeviation <= _suspiciousThresholdPercent) {
      final lowBandScore =
          (absoluteDeviation / _suspiciousThresholdPercent) * 59;
      return lowBandScore.round().clamp(0, 59);
    }

    final severeBand =
        ((absoluteDeviation - _suspiciousThresholdPercent) / 80) * 40;
    final score = 60 + severeBand;
    return score.round().clamp(60, 100);
  }

  String _buildUrduMessage({
    required String cropType,
    required double sellerPrice,
    required double marketRate,
    required double deviationPercent,
    required bool isSuspicious,
    required int riskScore,
  }) {
    final direction = deviationPercent >= 0 ? 'ز�Rادہ' : 'ک�&';
    final diff = deviationPercent.abs().toStringAsFixed(1);
    final seller = sellerPrice.toStringAsFixed(0);
    final market = marketRate.toStringAsFixed(0);

    if (isSuspicious) {
      return '�a�️ ت� ب�Rہ: $cropType ک�R آپ ک�R ��R�&ت (Rs. $seller) �&� ���R ر�Rٹ (Rs. $market) س� $diff% $direction ہ�� '
          '�Rہ 20% حد س� ز�Rادہ ا� حراف ہ�� رسک اسک��ر: $riskScore/100�';
    }

    return '�S& $cropType ک�R ��R�&ت �اب�ِ �ب��� حد �&�Rں ہ�� آپ ک�R ��R�&ت (Rs. $seller) �&� ���R ر�Rٹ (Rs. $market) س� $diff% $direction ہ�� '
        'رسک اسک��ر: $riskScore/100�';
  }

  ValidationResult _errorResult({
    required double sellerPrice,
    required String errorCode,
    required String warningMessage,
  }) {
    return ValidationResult(
      isSuspicious: false,
      riskScore: 0,
      warningMessage: warningMessage,
      sellerPrice: sellerPrice,
      marketRate: null,
      deviationPercent: 0,
      errorCode: errorCode,
    );
  }

  double? _toDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }
}

