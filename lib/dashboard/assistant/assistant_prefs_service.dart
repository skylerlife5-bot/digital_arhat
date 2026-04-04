import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight local-state store for the Aarhat Assistant feature.
/// All keys are prefixed with 'assistant_' to avoid collisions.
class AssistantPrefsService {
  AssistantPrefsService._();

  static const String _keyWelcomeSeen = 'assistant_welcome_seen';
  static const String _keyHasUsed = 'assistant_has_used';
  static const String _keySellerTipSeen = 'assistant_seller_tip_seen';
  static const String _keyBuyerTipSeen = 'assistant_buyer_tip_seen';
  static const String _keyGuestTipSeen = 'assistant_guest_tip_seen';
  static const String _keyAuctionTipSeen = 'assistant_auction_tip_seen';
  static const String _keyFeaturedTipSeen = 'assistant_featured_tip_seen';

  static Future<bool> hasSeenWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyWelcomeSeen) ?? false;
  }

  static Future<void> markWelcomeSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWelcomeSeen, true);
  }

  static Future<void> markUsed() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyHasUsed, true);
  }

  static Future<bool> hasUsedAssistant() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyHasUsed) ?? false;
  }

  static Future<bool> hasSeenSellerAssistantTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySellerTipSeen) ?? false;
  }

  static Future<void> markSellerAssistantTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySellerTipSeen, true);
  }

  static Future<bool> hasSeenBuyerAssistantTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyBuyerTipSeen) ?? false;
  }

  static Future<void> markBuyerAssistantTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyBuyerTipSeen, true);
  }

  static Future<bool> hasSeenGuestAssistantTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyGuestTipSeen) ?? false;
  }

  static Future<void> markGuestAssistantTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyGuestTipSeen, true);
  }

  static Future<bool> hasSeenAuctionTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAuctionTipSeen) ?? false;
  }

  static Future<void> markAuctionTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAuctionTipSeen, true);
  }

  static Future<bool> hasSeenFeaturedTip() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyFeaturedTipSeen) ?? false;
  }

  static Future<void> markFeaturedTipSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFeaturedTipSeen, true);
  }
}
