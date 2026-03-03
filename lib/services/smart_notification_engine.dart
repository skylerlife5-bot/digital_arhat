import '../ai/price_deviation_flagger.dart';

class SmartNotificationEngine {
  
  // �xa� Trigger: AI Nudge (Jab buyer outbid ho jaye)
  static void sendSmartNudge(String buyerToken, double userBid, double currentHighest, double marketPrice) {
    final nudgeData = PriceDeviationFlagger.getSmartNudge(userBid, currentHighest, marketPrice);

    if (nudgeData['shouldNudge']) {
      _sendFCM(
        token: buyerToken,
        title: "�x� AI Mashwara",
        body: nudgeData['nudgeMessage'],
      );
    }
  }

  // �x0 Trigger: Low Activity (1 ghante se khamoshi)
  static void sendLowActivityAlert(List<String> buyerTokens, String cropName) {
    _sendFCM(
      tokens: buyerTokens, // Multiple buyers
      title: "�x� Mauka hath se na janay dein!",
      body: "$cropName par is waqt competition kam hai, behtareen rate milne ka mauka hai!",
    );
  }

  static void _sendFCM({String? token, List<String>? tokens, required String title, required String body}) {
    // Firebase Cloud Messaging logic yahan aayegi
  }
}
