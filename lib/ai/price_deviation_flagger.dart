import 'package:flutter/material.dart';
import '../services/market_rate_service.dart';

/// �S& Digital Arhat - Unified AI Engine
/// Ye file Seller ki price aur Buyer ki bid dono ko analyze karti hai.
class PriceDeviationFlagger {
  // Instance of service to fetch live rates
  final MarketRateService _rateService = MarketRateService();

  // ---------------------------------------------------------
  // �x�} SELLER LOGIC: Price Deviation Analysis
  // ---------------------------------------------------------
  
  /// Ye function seller ki price ko Mandi rates se compare karta hai.
  Map<String, dynamic> analyzePrice(String product, double sellerPrice) {
    final List<MarketRate> rates = _rateService.getLatestRates();
    
    final marketData = rates.firstWhere(
      (r) => r.cropName.toLowerCase().trim() == product.toLowerCase().trim(),
      orElse: () => MarketRate(cropName: "", currentPrice: 0, change: 0, trend: "stable"),
    );

    if (marketData.currentPrice <= 0) {
      return {
        'status': 'active',
        'isSuspicious': false,
        'message': 'Market data filhal dastyab nahi hai. Aap apne mutabiq rate lagayein.',
        'reason': 'No market data available',
        'color': Colors.grey,
        'icon': Icons.help_outline,
        'deviation': 0.0,
      };
    }

    double aiMarketPrice = marketData.currentPrice;
    
    // Formula for Price Deviation:
    // $$ \text{diffPercent} = \frac{\text{sellerPrice} - \text{aiMarketPrice}}{\text{aiMarketPrice}} \times 100 $$
    double diffPercent = ((sellerPrice - aiMarketPrice) / aiMarketPrice) * 100;

    // A. Extreme Deviation (�xa� Suspicious: > 40%)
    if (diffPercent.abs() > 40) {
      String direction = sellerPrice > aiMarketPrice ? "bohot zyada (Overpriced)" : "bohot kam (Underpriced)";
      return {
        'status': 'under_review',
        'isSuspicious': true,
        'message': "�xa� Tawajjo! Aaj ka market rate Rs. ${aiMarketPrice.toInt()} hai. Aapka rate $direction hai.",
        'reason': 'Extreme deviation (>40%)',
        'color': Colors.red[900],
        'icon': Icons.report_problem,
        'deviation': diffPercent,
      };
    }

    // B. High Price Warning (�a�️ > 15%)
    if (diffPercent > 15) {
      return {
        'status': 'active',
        'isSuspicious': false,
        'message': '�a�️ Rate market (Rs. ${aiMarketPrice.toInt()}) se kafi zyada hai! Shayad kharidar na miley.',
        'reason': 'High pricing',
        'color': Colors.orange[800],
        'icon': Icons.arrow_upward,
        'deviation': diffPercent,
      };
    }

    // C. Underpriced Warning (�x0 < -15%)
    if (diffPercent < -15) {
      return {
        'status': 'active',
        'isSuspicious': false,
        'message': '�xa� Aapka rate market (Rs. ${aiMarketPrice.toInt()}) se bohot kam hai. Kahin koi ghalti to nahi?',
        'reason': 'Significant underpricing',
        'color': Colors.blueAccent,
        'icon': Icons.arrow_downward,
        'deviation': diffPercent,
      };
    }

    // D. Fair Price (�S& Perfect Range)
    return {
      'status': 'active',
      'isSuspicious': false,
      'message': '�S& Behtareen! Aapka rate market ke bilkul mutabiq hai.',
      'reason': 'Fair market value',
      'color': Colors.green[700],
      'icon': Icons.check_circle_outline,
      'deviation': diffPercent,
    };
  }

  // ---------------------------------------------------------
  // �x�� BUYER LOGIC: Psychology & Nudges
  // ---------------------------------------------------------

  /// Dekhta hai ke kya buyer thora sa mazeed barha kar jeet sakta hai.
  static Map<String, dynamic> getSmartNudge(double currentBid, double highestBid, double marketPrice) {
    double gap = highestBid - currentBid;
    double nudgeAmount = 50.0; // Standard incremental jump

    // Case 1: Close Competition (Gap 0 to 200)
    if (gap > 0 && gap <= 200) {
      return {
        "shouldNudge": true,
        "nudgeMessage": "AI Suggestion: Sirf Rs. ${gap + nudgeAmount} mazeed barhane se aap is deal ke sab se mazboot umeedwar ban sakte hain.",
        "suggestedAmount": highestBid + nudgeAmount
      };
    }
    
    // Case 2: Low Activity / Bargain Opportunity
    if (currentBid < (marketPrice * 0.9) && gap <= 0) {
      return {
        "shouldNudge": true,
        "nudgeMessage": "Is waqt competition kam hai aur rate market se kam hai, behtareen mauka hai!",
      };
    }

    return {"shouldNudge": false};
  }

  /// Weekly Trend logic for UI
  static Map<String, dynamic> getWeeklyTrend(String crop, double currentChange) {
    return {
      "trend": currentChange >= 0 ? "up" : "down",
      "percentage": "${currentChange.abs().toStringAsFixed(1)}%",
      "message": "Pichle kuch dino mein $crop ka rate ${currentChange.abs().toStringAsFixed(1)}% ${currentChange >= 0 ? 'uper' : 'neeche'} gaya hai."
    };
  }
}
