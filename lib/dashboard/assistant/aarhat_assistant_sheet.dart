import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../routes.dart';
import '../../services/ai_generative_service.dart';
import '../../theme/app_colors.dart';
import 'assistant_mandi_icon.dart';
import 'assistant_prefs_service.dart';
import 'assistant_quick_action_card.dart';
import 'assistant_role_resolver.dart';

enum _AssistantAction {
  createListing,
  auctionVsFixed,
  mandiRate,
  improveListing,
  featuredBenefit,
  sellingTips,
  findItem,
  bidExplained,
  betterOffer,
  nearbyListings,
  contactSeller,
  appTutorial,
  buyerOrSeller,
  marketplaceExplore,
  bidSystem,
}

class _QuickActionDef {
  const _QuickActionDef({
    required this.action,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
  });

  final _AssistantAction action;
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
}

class AarhatAssistantSheet extends StatefulWidget {
  const AarhatAssistantSheet({super.key, required this.userData});

  final Map<String, dynamic> userData;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> userData,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => AarhatAssistantSheet(userData: userData),
    );
  }

  @override
  State<AarhatAssistantSheet> createState() => _AarhatAssistantSheetState();
}

class _AarhatAssistantSheetState extends State<AarhatAssistantSheet>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const List<String> _punjabProvinceQueryValues = <String>[
    'Punjab',
    'punjab',
    'پنجاب',
  ];

  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final List<Animation<double>> _cardFadeAnims;
  late final List<Animation<Offset>> _cardSlideAnims;

  final TextEditingController _chatCtrl = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  final MandiIntelligenceService _aiService = MandiIntelligenceService();

  late final AssistantUserRole _role;
  late final List<_QuickActionDef> _actions;

  _AssistantAction? _activeAction;
  final List<_AssistantChatMessage> _chatMessages = <_AssistantChatMessage>[];
  bool _isChatLoading = false;
  Timer? _typingTimer;
  int _typingPhase = 0;

  static const Duration _liveContextTtl = Duration(minutes: 3);
  static String? _cachedLiveMarketContext;
  static DateTime? _cachedLiveMarketContextAt;
  static Future<String>? _liveMarketContextInFlight;

  static const String _madadgarSystemInstruction =
      "System Instruction: 'You are Madadgar, an expert, respectful, and highly experienced Agricultural Broker (Arhti) from Punjab, Pakistan. You speak in a warm, professional Roman Urdu tone. You address the user as Bhai jaan or Kisan bhai. You never sound like a robot; you sound like a seasoned trader giving insider advice.'";
  static const String _liveContextUsageInstruction =
      "Always use the provided Live Market Context to answer rate queries. If the requested rate is not in the context, tell the user you don't have today's rate for that item. Use the market trend context to explicitly mention whether market is Tezi (📈) or Mandi (📉).";

  int _auctionStep = 0;
  String? _auctionItemType;
  String? _auctionRecommendation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _role = AssistantRoleResolver.resolveRole(widget.userData);
    _actions = _buildQuickActionsByRole(_role);

    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.075),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);

    // Staggered card entrance: each card fades + slides up with a small delay.
    _cardFadeAnims = List.generate(
      _actions.length,
      (i) => CurvedAnimation(
        parent: _animCtrl,
        curve: Interval(
          0.06 + i * 0.06,
          (0.42 + i * 0.06).clamp(0.0, 1.0),
          curve: Curves.easeOut,
        ),
      ),
    );
    _cardSlideAnims = List.generate(
      _actions.length,
      (i) =>
          Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
            CurvedAnimation(
              parent: _animCtrl,
              curve: Interval(
                0.06 + i * 0.06,
                (0.40 + i * 0.06).clamp(0.0, 1.0),
                curve: Curves.easeOutCubic,
              ),
            ),
          ),
    );

    _animCtrl.forward();

    // Warm cache in background so first user query is fast.
    unawaited(_getLiveMarketContext());

    AssistantPrefsService.markUsed();
    _markRoleTipSeen();
  }

  Future<void> _markRoleTipSeen() async {
    if (AssistantRoleResolver.isSeller(_role)) {
      await AssistantPrefsService.markSellerAssistantTipSeen();
      return;
    }
    if (AssistantRoleResolver.isBuyer(_role)) {
      await AssistantPrefsService.markBuyerAssistantTipSeen();
      return;
    }
    await AssistantPrefsService.markGuestAssistantTipSeen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animCtrl.dispose();
    _chatCtrl.dispose();
    _chatScrollController.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollChatToBottom();
    });
  }

  List<_QuickActionDef> _buildQuickActionsByRole(AssistantUserRole role) {
    return const [
      _QuickActionDef(
        action: _AssistantAction.appTutorial,
        icon: Icons.menu_book_rounded,
        title: 'ایپ کیسے کام کرتی ہے؟',
        subtitle: 'ایپ کو آسانی سے سمجھیں',
        badge: 'پہلے یہ دیکھیں',
      ),
      _QuickActionDef(
        action: _AssistantAction.buyerOrSeller,
        icon: Icons.people_alt_rounded,
        title: 'خریدار یا فروخت کنندہ؟',
        subtitle: 'اپنے لیے درست راستہ چنیں',
      ),
      _QuickActionDef(
        action: _AssistantAction.marketplaceExplore,
        icon: Icons.storefront_rounded,
        title: 'منڈی دیکھیں',
        subtitle: 'موجودہ لسٹنگ اور قیمتیں دیکھیں',
      ),
      _QuickActionDef(
        action: _AssistantAction.bidSystem,
        icon: Icons.gavel_rounded,
        title: 'بولی کیسے لگتی ہے؟',
        subtitle: 'بولی لگانے کا آسان طریقہ جانیں',
      ),
      _QuickActionDef(
        action: _AssistantAction.mandiRate,
        icon: Icons.bar_chart_rounded,
        title: 'منڈی ریٹ دیکھیں',
        subtitle: 'تازہ نرخ اور منڈی کی جھلک دیکھیں',
      ),
      _QuickActionDef(
        action: _AssistantAction.createListing,
        icon: Icons.post_add_rounded,
        title: 'لسٹنگ کیسے پوسٹ ہوتی ہے؟',
        subtitle: 'اپنا مال شامل کرنے کا سیدھا طریقہ سمجھیں',
      ),
    ];
  }

  void _selectAction(_AssistantAction action) {
    setState(() {
      _activeAction = _activeAction == action ? null : action;
      if (action == _AssistantAction.auctionVsFixed) {
        _auctionStep = 0;
        _auctionItemType = null;
        _auctionRecommendation = null;
      }
    });

    if (action == _AssistantAction.auctionVsFixed) {
      AssistantPrefsService.markAuctionTipSeen();
    }
    if (action == _AssistantAction.featuredBenefit) {
      AssistantPrefsService.markFeaturedTipSeen();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Get strict dimensions once — no Scaffold, no resizeToAvoidBottomInset.
    final double screenHeight = MediaQuery.of(context).size.height;
    final double keyboardHeight = MediaQuery.of(context).viewInsets.bottom;

    // 2. Return a strict Container — breaks the unbounded measurement cycle.
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          height: screenHeight * 0.85,
          // Handle keyboard manually instead of relying on Scaffold.
          padding: EdgeInsets.only(bottom: keyboardHeight),
          decoration: const BoxDecoration(
            color: Color(0xFF0E3B2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              children: [
                const _DragHandle(),
                // Top area is Flexible so it never expands unboundedly.
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 14),
                        _buildSuggestionChips(),
                        if (_activeAction != null) ...[
                          const SizedBox(height: 14),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            child: KeyedSubtree(
                              key: ValueKey(_activeAction),
                              child: _buildActionResult(),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Divider(color: Color(0x26FFFFFF), height: 1),
                const SizedBox(height: 10),
                // Chat list — bounded solely by this Expanded, no shrinkWrap.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildChatSection(),
                  ),
                ),
                const SizedBox(height: 10),
                // FAQ chips (horizontal scroll).
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: _buildFaqChips(),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Input area.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _chatCtrl,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            hintText: 'اپنا سوال یہاں لکھیں',
                            hintStyle: const TextStyle(
                              color: AppColors.secondaryText,
                              fontSize: 12,
                            ),
                            filled: true,
                            fillColor: AppColors.cardSurface,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 11,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.divider),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                                  const BorderSide(color: AppColors.divider),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.accentGold,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _submitChat(),
                          textInputAction: TextInputAction.send,
                          enabled: !_isChatLoading,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Material(
                        color: _isChatLoading
                            ? AppColors.accentGold.withValues(alpha: 0.5)
                            : AppColors.accentGold,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: _isChatLoading ? null : _submitChat,
                          borderRadius: BorderRadius.circular(12),
                          child: const Padding(
                            padding: EdgeInsets.all(11),
                            child: Icon(
                              Icons.send_rounded,
                              color: AppColors.ctaTextDark,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AssistantMandiIcon(size: 24, padding: const EdgeInsets.all(10)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مددگار',
                    style: TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w900,
                      fontSize: 18.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'کھیتی، بولی اور منڈی میں مکمل رہنمائی',
                    style: TextStyle(
                      color: AppColors.secondaryText.withValues(alpha: 0.88),
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'جو سمجھ نہ آئے، یہاں سے آسانی سے دیکھیں',
                    style: TextStyle(
                      color: AppColors.secondaryText.withValues(alpha: 0.82),
                      fontSize: 11.8,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 20),
              color: AppColors.secondaryText,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSmartRecommendation(),
      ],
    );
  }

  Widget _buildSmartRecommendation() {
    String recommendation;
    IconData icon;

    if (AssistantRoleResolver.isSeller(_role)) {
      recommendation = 'پہلے منڈی ریٹ دیکھیں، پھر قیمت یا بولی کا فیصلہ کریں';
      icon = Icons.local_offer_rounded;
    } else if (AssistantRoleResolver.isBuyer(_role)) {
      recommendation = 'پہلے قریبی لسٹنگ دیکھیں تاکہ لین دین آسان رہے';
      icon = Icons.location_on_rounded;
    } else {
      recommendation = 'پہلے منڈی سمجھیں، پھر اپنا راستہ چنیں';
      icon = Icons.explore_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.accentGold.withValues(alpha: 0.24),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentGold, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              recommendation,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'فوری رہنمائی',
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(_actions.length, (i) {
          final def = _actions[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: FadeTransition(
              opacity: _cardFadeAnims[i],
              child: SlideTransition(
                position: _cardSlideAnims[i],
                child: AssistantQuickActionCard(
                  icon: def.icon,
                  title: def.title,
                  subtitle: def.subtitle,
                  badge: def.badge,
                  isActive: _activeAction == def.action,
                  onTap: () => _selectAction(def.action),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSuggestionChips() {
    final List<(String, _AssistantAction)> chips = const [
      ('اپنے علاقے کی منڈی دیکھیں', _AssistantAction.appTutorial),
      ('خریدار یا فروخت کنندہ', _AssistantAction.buyerOrSeller),
      ('بولی کا طریقہ', _AssistantAction.bidSystem),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: chips
          .map(
            (chip) =>
                _chipBtn(label: chip.$1, onTap: () => _selectAction(chip.$2)),
          )
          .toList(growable: false),
    );
  }

  Widget _buildActionResult() {
    switch (_activeAction) {
      case _AssistantAction.createListing:
        return _buildCreateListingResult();
      case _AssistantAction.auctionVsFixed:
        return _buildAuctionVsFixedResult();
      case _AssistantAction.mandiRate:
        return _buildMandiRateResult();
      case _AssistantAction.improveListing:
        return _buildImproveListingResult();
      case _AssistantAction.featuredBenefit:
        return _buildFeaturedBenefitResult();
      case _AssistantAction.sellingTips:
        return _buildSellingTipsResult();
      case _AssistantAction.findItem:
        return _buildFindItemResult();
      case _AssistantAction.bidExplained:
      case _AssistantAction.bidSystem:
        return _buildBidExplainedResult();
      case _AssistantAction.betterOffer:
        return _buildBetterOfferResult();
      case _AssistantAction.nearbyListings:
        return _buildNearbyListingsResult();
      case _AssistantAction.contactSeller:
        return _buildContactSellerResult();
      case _AssistantAction.appTutorial:
        return _buildAppTutorialResult();
      case _AssistantAction.buyerOrSeller:
        return _buildBuyerOrSellerResult();
      case _AssistantAction.marketplaceExplore:
        return _buildMarketplaceExploreResult();
      case null:
        return const SizedBox.shrink();
    }
  }

  Widget _resultCard({required Widget child, Color? borderColor}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A4D38), Color(0xFF0F3225)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: borderColor ?? AppColors.accentGold.withValues(alpha: 0.38),
        ),
      ),
      child: child,
    );
  }

  Widget _resultTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.primaryText,
      fontWeight: FontWeight.w800,
      fontSize: 13.5,
    ),
  );

  Widget _resultBody(String text) => Text(
    text,
    style: const TextStyle(
      color: AppColors.secondaryText,
      fontSize: 12.2,
      height: 1.42,
    ),
  );

  Widget _primaryBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accentGold,
          foregroundColor: AppColors.ctaTextDark,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _secondaryBtn({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primaryText,
          side: BorderSide(
            color: AppColors.primaryText.withValues(alpha: 0.28),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _chipBtn({required String label, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.34),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildCreateListingResult() {
    if (AssistantRoleResolver.isGuest(_role)) {
      return _resultCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultTitle('لسٹنگ کیسے پوسٹ ہوتی ہے؟'),
            const SizedBox(height: 8),
            _resultBody(
              'لسٹنگ پوسٹ کرنے کے لیے اکاؤنٹ بنائیں، پھر فروخت کنندہ حصے میں جا کر تصویر، قیمت اور تفصیل درج کریں۔',
            ),
            const SizedBox(height: 12),
            _primaryBtn(
              label: 'اکاؤنٹ بنائیں',
              icon: Icons.person_add_alt_1_rounded,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(Routes.masterSignUp);
              },
            ),
          ],
        ),
      );
    }

    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('لسٹنگ کیسے پوسٹ ہوتی ہے؟'),
          const SizedBox(height: 8),
          _resultBody(
            'آواز سے لسٹنگ بنائیں یا دستی فارم سے تفصیل دیں۔ اگر تصویر اور لوکیشن واضح ہوں تو خریدار جلدی ملتے ہیں۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'آواز سے آغاز',
            icon: Icons.mic_rounded,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(Routes.sellerDashboard);
            },
          ),
          const SizedBox(height: 8),
          _secondaryBtn(
            label: 'لسٹنگ فارم کھولیں',
            icon: Icons.edit_note_rounded,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(
                Routes.sellerAddListing,
                arguments: <String, dynamic>{'userData': widget.userData},
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMandiRateResult() {
    return _resultCard(
      borderColor: const Color(0xFF2A8A63).withValues(alpha: 0.55),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('منڈی ریٹ دیکھیں'),
          const SizedBox(height: 8),
          _resultBody(
            'کسی بھی آئٹم کے لئے پہلے علاقہ اور منڈی ریٹ دیکھیں، پھر قیمت لگائیں یا بولی دیں۔ اگر لائیو ریٹ دستیاب نہ ہو تو قریبی منڈی کے تازہ ریٹس دیکھ کر محفوظ اندازہ لگائیں۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'ریٹ دیکھیں',
            icon: Icons.bar_chart_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildAuctionVsFixedResult() {
    if (_auctionRecommendation != null) {
      return _resultCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultTitle('تجویز'),
            const SizedBox(height: 10),
            _resultBody(_auctionRecommendation!),
            const SizedBox(height: 14),
            _primaryBtn(
              label: 'اب لسٹنگ کریں',
              icon: Icons.add_circle_outline_rounded,
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(
                  Routes.sellerAddListing,
                  arguments: <String, dynamic>{'userData': widget.userData},
                );
              },
            ),
          ],
        ),
      );
    }

    if (_auctionStep == 0) {
      return _resultCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _resultTitle('بولی یا سیدھی قیمت؟'),
            const SizedBox(height: 6),
            _resultBody('آپ کیا بیچ رہے ہیں؟'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['فصل', 'مویشی', 'دیگر']
                  .map(
                    (label) => _chipBtn(
                      label: label,
                      onTap: () => setState(() {
                        _auctionItemType = label;
                        _auctionStep = 1;
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ),
      );
    }

    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('فروخت کی رفتار'),
          const SizedBox(height: 6),
          _resultBody('کیا آپ کو جلدی فروخت کرنی ہے؟'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _chipBtn(
                label: 'جی ہاں',
                onTap: () => setState(() {
                  _auctionRecommendation = _computeAuctionRecommendation(
                    itemType: _auctionItemType ?? 'دیگر',
                    urgent: true,
                  );
                }),
              ),
              _chipBtn(
                label: 'نہیں',
                onTap: () => setState(() {
                  _auctionRecommendation = _computeAuctionRecommendation(
                    itemType: _auctionItemType ?? 'دیگر',
                    urgent: false,
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _computeAuctionRecommendation({
    required String itemType,
    required bool urgent,
  }) {
    if (urgent) {
      return 'بولی بہتر رہے گی کیونکہ جلدی خریدار آ جاتے ہیں، اور مقابلے کی وجہ سے قیمت بھی اوپر جا سکتی ہے۔';
    }
    if (itemType.toLowerCase().contains('livestock') ||
        itemType.contains('مویشی')) {
      return 'مویشی کے لیے اکثر بولی بہتر رہتی ہے، خاص طور پر موسمی منڈی میں۔ اس طرح زیادہ بولیاں مل سکتی ہیں۔';
    }
    return 'اگر وقت ہو تو سیدھی قیمت رکھیں تاکہ اپنی مطلوبہ قیمت کے قریب سودا ہو سکے۔';
  }

  Widget _buildImproveListingResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('لسٹنگ بہتر کیسے بنے؟'),
          const SizedBox(height: 10),
          _resultBody(
            '1) واضح تصویر اور درست مقام شامل کریں\n2) صاف عنوان لکھیں\n3) منڈی ریٹ کے قریب قیمت رکھیں\n4) ضرورت ہو تو نمایاں لسٹنگ منتخب کریں',
          ),
          const SizedBox(height: 12),
          _secondaryBtn(
            label: 'لسٹنگ کھولیں',
            icon: Icons.edit_note_rounded,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(
                Routes.sellerAddListing,
                arguments: <String, dynamic>{'userData': widget.userData},
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedBenefitResult() {
    return _resultCard(
      borderColor: AppColors.accentGold.withValues(alpha: 0.45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('نمایاں لسٹنگ کا فائدہ'),
          const SizedBox(height: 10),
          _resultBody(
            'نمایاں لسٹنگ اوپر دکھتی ہے، زیادہ خریدار دیکھتے ہیں، اور جلد فروخت کے امکانات بہتر ہوتے ہیں۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'فروخت کنندہ صفحہ',
            icon: Icons.star_rounded,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(Routes.sellerDashboard);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSellingTipsResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('آج کیا بیچنا بہتر ہے؟'),
          const SizedBox(height: 8),
          _resultBody(
            'آج وہ چیز بیچیں جس کی مقامی طلب زیادہ ہے اور سپلائی کم۔ پہلے منڈی ریٹ اور پچھلی بولیوں کا رجحان دیکھیں۔',
          ),
        ],
      ),
    );
  }

  Widget _buildFindItemResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('منڈی دیکھیں'),
          const SizedBox(height: 8),
          _resultBody(
            'ہوم سکرین میں سرچ اور فلٹر استعمال کریں: آئٹم، علاقہ، قیمت اور قسم کے مطابق نتائج جلدی ملیں گے۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'منڈی دیکھیں',
            icon: Icons.search_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildBidExplainedResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('بولی کیسے لگتی ہے؟'),
          const SizedBox(height: 8),
          _resultBody(
            '1) لسٹنگ کھولیں\n2) بولی کی موجودہ قیمت دیکھیں\n3) اپنی مناسب بولی دیں\n4) وقت ختم ہونے سے پہلے بہترین بولی جیتتی ہے۔',
          ),
        ],
      ),
    );
  }

  Widget _buildBetterOfferResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('بہتر سودا کیسے ملے؟'),
          const SizedBox(height: 8),
          _resultBody(
            'منڈی ریٹ دیکھیں، فروخت کنندہ کی ساکھ دیکھیں، اور ایک سے زیادہ لسٹنگ کا موازنہ کریں۔ مناسب اور حقیقت پسند بولی دیں۔',
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyListingsResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('قریبی لسٹنگ دیکھیں'),
          const SizedBox(height: 8),
          _resultBody(
            'اپنے قریب موجود لسٹنگ سے نقل و حمل کم رہتی ہے اور سودا جلدی ممکن ہوتا ہے۔ ہوم میں قریبی حصے کو دیکھیں۔',
          ),
        ],
      ),
    );
  }

  Widget _buildContactSellerResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('فروخت کنندہ سے رابطہ'),
          const SizedBox(height: 8),
          _resultBody(
            'ہمیشہ محفوظ رابطے کے ذریعے بات کریں، پیشگی ادائیگی احتیاط سے کریں، اور مشکوک سودے کی اطلاع دیں۔',
          ),
        ],
      ),
    );
  }

  Widget _buildAppTutorialResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('یہ ایپ کیسے کام کرتی ہے؟'),
          const SizedBox(height: 8),
          _resultBody(
            'یہاں آپ خرید و فروخت دونوں کر سکتے ہیں۔ پہلے منڈی دیکھیں، پھر ضرورت کے مطابق خریدار یا فروخت کنندہ پروفائل بنائیں۔',
          ),
        ],
      ),
    );
  }

  Widget _buildBuyerOrSellerResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('خریدار یا فروخت کنندہ؟'),
          const SizedBox(height: 8),
          _resultBody(
            'اگر آپ مال بیچنا چاہتے ہیں تو فروخت کنندہ بنیں۔ اگر خریدنا چاہتے ہیں تو خریدار بنیں۔ بعد میں کردار تبدیل بھی کیا جا سکتا ہے۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'اکاؤنٹ بنانے کی رہنمائی',
            icon: Icons.person_add_rounded,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(Routes.masterSignUp);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMarketplaceExploreResult() {
    return _resultCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultTitle('منڈی دیکھیں'),
          const SizedBox(height: 8),
          _resultBody(
            'مارکیٹ میں نئی لسٹنگز، فیچرڈ آئٹمز اور قریبی منڈی ریٹ دیکھیں۔ پھر مناسب قدم منتخب کریں۔',
          ),
          const SizedBox(height: 12),
          _primaryBtn(
            label: 'منڈی کھولیں',
            icon: Icons.explore_rounded,
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // Chat message list only — bounded by the Expanded in build().
  Widget _buildChatSection() {
    return ListView.builder(
      controller: _chatScrollController,
      itemCount: _chatMessages.length + (_isChatLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (_isChatLoading && index == _chatMessages.length) {
          return Align(
            alignment: Alignment.centerLeft,
            child: _buildTypingIndicator(),
          );
        }

        final item = _chatMessages[index];
        final isUser = item.isUser;

        return Align(
          alignment:
              isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color(0xFF1B8F4F)
                  : const Color(0xFFE9EDF0),
              borderRadius: BorderRadius.circular(14).copyWith(
                bottomRight: isUser
                    ? const Radius.circular(4)
                    : const Radius.circular(14),
                bottomLeft: isUser
                    ? const Radius.circular(14)
                    : const Radius.circular(4),
              ),
              border: Border.all(
                color: isUser
                    ? const Color(0xFF239E5A).withValues(alpha: 0.85)
                    : const Color(0xFFD2D9DE),
              ),
            ),
            child: isUser
                ? Text(
                    item.text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.8,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : MarkdownBody(
                    data: item.text,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: const TextStyle(
                        color: Color(0xFF1C252E),
                        fontSize: 12.6,
                        height: 1.35,
                      ),
                      strong: const TextStyle(
                        color: Color(0xFF11161C),
                        fontWeight: FontWeight.w800,
                      ),
                      listBullet: const TextStyle(
                        color: Color(0xFF1C252E),
                        fontSize: 12.6,
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }

  List<Widget> _buildFaqChips() {
    return _actions
        .take(8)
        .map(
          (action) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              backgroundColor: const Color(0xFF1B4D38).withValues(alpha: 0.85),
              side: BorderSide(
                color: AppColors.accentGold.withValues(alpha: 0.45),
              ),
              label: Text(
                action.title,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _selectAction(action.action),
            ),
          ),
        )
        .toList(growable: false);
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxWidth: 220),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF0),
        borderRadius: BorderRadius.circular(
          14,
        ).copyWith(bottomLeft: const Radius.circular(4)),
        border: Border.all(color: const Color(0xFFD2D9DE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Typing...',
            style: TextStyle(
              color: Color(0xFF55616C),
              fontSize: 11.8,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List<Widget>.generate(3, (int i) {
              final bool active = _typingPhase == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.only(right: 6),
                width: active ? 9 : 7,
                height: active ? 9 : 7,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.accentGold
                      : const Color(0xFF8A949E),
                  shape: BoxShape.circle,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  void _appendMessage({required String text, required bool isUser}) {
    setState(() {
      _chatMessages.add(_AssistantChatMessage(text: text, isUser: isUser));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollChatToBottom();
    });
  }

  void _scrollChatToBottom() {
    if (!_chatScrollController.hasClients) return;
    _chatScrollController.animateTo(
      _chatScrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
    );
  }

  String _normalizeToken(String input) {
    return input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _hasRateIntent(String text) {
    final q = _normalizeToken(text);
    return q.contains('rate') ||
        q.contains('price') ||
        q.contains('mandi') ||
        q.contains('bhao') ||
        text.contains('ریٹ') ||
        text.contains('قیمت') ||
        text.contains('بھاؤ') ||
        text.contains('منڈی');
  }

        bool _hasSmartBidIntent(String text) {
          final q = _normalizeToken(text);
          return q.contains('boli') ||
          q.contains('bid') ||
          q.contains('khareedna') ||
          q.contains('kharidna') ||
          q.contains('mashwara') ||
          text.contains('بولی') ||
          text.contains('خریدنا') ||
          text.contains('مشورہ');
        }

        Set<String> _queryTokens(String text) {
          return _normalizeToken(text)
          .split(' ')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
        }

  Set<String> _commodityAliases(Map<String, dynamic> data) {
    final aliases = <String>{
      _pickFirstNonEmptyString(data, const <String>['commodityNameUr']),
      _pickFirstNonEmptyString(data, const <String>['commodityNameEn']),
      _pickFirstNonEmptyString(data, const <String>['commodityName']),
      _pickFirstNonEmptyString(data, const <String>['commodity']),
      _pickFirstNonEmptyString(data, const <String>['cropType']),
      _pickFirstNonEmptyString(data, const <String>['itemName']),
      _pickFirstNonEmptyString(data, const <String>['product']),
      _pickFirstNonEmptyString(data, const <String>['name']),
    };

    return aliases
        .map(_normalizeToken)
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  String? _matchCommodityAlias(String query, Set<String> aliases) {
    final normalizedQuery = _normalizeToken(query);
    final queryTokens = _queryTokens(query);
    String? bestAlias;
    int bestScore = 0;

    for (final alias in aliases) {
      if (alias.isEmpty) continue;

      int score = 0;
      if (normalizedQuery == alias) {
        score += 100;
      }
      if (normalizedQuery.contains(alias) || alias.contains(normalizedQuery)) {
        score += 60;
      }

      final aliasTokens = alias.split(' ').where((e) => e.isNotEmpty).toSet();
      final overlap = aliasTokens.intersection(queryTokens).length;
      score += overlap * 20;

      if (score > bestScore) {
        bestScore = score;
        bestAlias = alias;
      }
    }

    return bestScore > 0 ? bestAlias : null;
  }

  double? _readRawQuintalRate(Map<String, dynamic> data) {
    return _toDouble(data['price']) ??
        _toDouble(data['averagePrice']) ??
        _toDouble(data['rate']) ??
        _toDouble(data['pricePerUnit']) ??
        _toDouble(data['fqp']);
  }

  double _convertQuintalToMann(double quintalPrice) {
    return (quintalPrice / 100) * 40;
  }

  double? _readPreviousQuintalRate(Map<String, dynamic> data) {
    return _toDouble(data['previousPrice']) ??
        _toDouble(data['previousRate']) ??
        _toDouble(data['lastPrice']) ??
        _toDouble(data['yesterdayPrice']) ??
        _toDouble(data['prevPrice']) ??
        _toDouble(data['prevRate']);
  }

  String _trendLineForRate({
    required double currentQuintalRate,
    required Map<String, dynamic> data,
  }) {
    final previous = _readPreviousQuintalRate(data);
    if (previous != null && previous > 0) {
      final deltaPct = ((currentQuintalRate - previous) / previous) * 100;
      if (deltaPct <= -2.0) {
        return 'Market aaj thori Naram (Mandi) hai 📉';
      }
      return 'Market mein aaj Tezi hai 📈';
    }

    final avg = _toDouble(data['averagePrice']) ?? _toDouble(data['avgPrice']);
    final low = _toDouble(data['minPrice']) ?? _toDouble(data['lowPrice']);
    final high = _toDouble(data['maxPrice']) ?? _toDouble(data['highPrice']);

    if (avg != null && avg > 0) {
      return currentQuintalRate >= avg
          ? 'Market mein aaj Tezi hai 📈'
          : 'Market aaj thori Naram (Mandi) hai 📉';
    }

    if (low != null && low > 0 && high != null && high > low) {
      final midpoint = (low + high) / 2;
      return currentQuintalRate >= midpoint
          ? 'Market mein aaj Tezi hai 📈'
          : 'Market aaj thori Naram (Mandi) hai 📉';
    }

    return 'Market mein aaj Tezi hai 📈';
  }

  DateTime? _readRateTimestamp(Map<String, dynamic> data) {
    final dynamic value =
        data['syncedAt'] ?? data['rateDate'] ?? data['updatedAt'] ?? data['createdAt'];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    return null;
  }

  String _formatFreshnessLabel(DateTime? value) {
    if (value == null) return 'date unavailable';
    final local = value.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(local.year, local.month, local.day);
    final difference = target.difference(today).inDays;
    final dateText =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';

    if (difference == 0) {
      return 'Aaj ka synced rate ($dateText)';
    }
    if (difference == -1) {
      return 'Kal ka synced rate ($dateText)';
    }
    return 'Synced date: $dateText';
  }

  String _formatCommodityRateMessage(_CommodityRateMatch chosen) {
    final freshness = _formatFreshnessLabel(chosen.rateDate);
    final locationText = chosen.locationLabel.isEmpty
        ? ''
        : ' ${chosen.locationLabel} mandi se';

    return 'Punjab Mandi Board ke mutabiq ${chosen.commodityLabel} ka rate '
        '${_formatRate(chosen.mannRate)} rupaye fi 40 kilo (Mann) hai. '
        'Ye rate 40kg (Mann) ka hai. '
        'Formula: (${_formatRate(chosen.rawQuintalRate)} / 100) * 40 = ${_formatRate(chosen.mannRate)}. '
        '$freshness.$locationText\n'
        '${chosen.trendLine}';
  }

  String _formatSmartBidAdvice(_CommodityRateMatch chosen) {
    final suggestedBid = chosen.mannRate * 0.95;
    return '${chosen.commodityLabel} ka market rate ${_formatRate(chosen.mannRate)} hai. '
        'Mera mashwara hai ke aap apni boli ${_formatRate(suggestedBid)} rupaye se shuru karein taake apko faida ho. '
        '${chosen.trendLine}';
  }

  String _buildGeneralFallbackReply(String query) {
    final usesUrdu = _containsUrduScript(query);
    if (usesUrdu) {
      return 'جی، میں سن رہا ہوں۔ اگر آپ کسی فصل کا ریٹ پوچھنا چاہتے ہیں تو فصل کا نام لکھ دیں، مثلاً چاول، مکئی، کپاس یا مونگ۔';
    }
    return 'Ji, main sun raha hoon. Agar aap kisi fasal ka rate poochna chahte hain to fasal ka naam likh dein, misal ke taur par rice, maize, kapas ya mong.';
  }

  Future<String?> _safeAiReply({
    required String query,
    required String liveMarketContext,
  }) async {
    try {
      final languageHint = _containsUrduScript(query)
          ? 'User input uses Urdu script. Reply naturally in Urdu script.'
          : 'User input uses Roman/English script. Reply naturally in polite Roman Urdu.';
      final prompt =
          '$_madadgarSystemInstruction\n$_liveContextUsageInstruction\n$languageHint\n$liveMarketContext\n\nUser query:\n$query';

      final response = await _aiService
          .getAIResponse(prompt)
          .timeout(const Duration(milliseconds: 4500));
      final text = response.trim();
      return text.isEmpty ? null : text;
    } catch (error) {
      debugPrint('[Madadgar] ai_reply_failed query=$query error=$error');
      return null;
    }
  }

  int _locationMatchScore(Map<String, dynamic> data, Set<String> localTokens) {
    if (localTokens.isEmpty) return 0;
    final places = <String>{
      _normalizeToken((data['district'] ?? '').toString()),
      _normalizeToken((data['city'] ?? '').toString()),
      _normalizeToken((data['tehsil'] ?? '').toString()),
      _normalizeToken((data['marketName'] ?? '').toString()),
      _normalizeToken((data['mandiName'] ?? '').toString()),
    }..removeWhere((e) => e.isEmpty);

    return places.where(localTokens.contains).length;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchAssistantRateSnapshot() async {
    final col = FirebaseFirestore.instance.collection('mandi_rates');
    try {
      return await col
          .orderBy('syncedAt', descending: true)
          .limit(180)
          .get()
          .timeout(const Duration(milliseconds: 1600));
    } catch (_) {
      try {
        return await col
            .orderBy('rateDate', descending: true)
            .limit(180)
            .get()
            .timeout(const Duration(milliseconds: 1600));
      } catch (_) {
        return await col
            .limit(180)
            .get()
            .timeout(const Duration(milliseconds: 1600));
      }
    }
  }

  Future<String?> _buildCommodityRateReply(String query) async {
    final snapshot = await _fetchAssistantRateSnapshot();
    if (snapshot.docs.isEmpty) {
      return null;
    }

    final hasRateIntent = _hasRateIntent(query);
    final hasSmartBidIntent = _hasSmartBidIntent(query);
    final localTokens = <String>{
      _normalizeToken((widget.userData['district'] ?? '').toString()),
      _normalizeToken((widget.userData['city'] ?? '').toString()),
      _normalizeToken((widget.userData['tehsil'] ?? '').toString()),
      _normalizeToken((widget.userData['marketName'] ?? '').toString()),
    }..removeWhere((e) => e.isEmpty);

    _CommodityRateMatch? bestLocal;
    _CommodityRateMatch? bestOverall;

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final aliases = _commodityAliases(data);
      if (aliases.isEmpty) {
        continue;
      }

      final matchedAlias = _matchCommodityAlias(query, aliases);
      if (matchedAlias == null) {
        continue;
      }

      final rawQuintalRate = _readRawQuintalRate(data);
      if (rawQuintalRate == null || rawQuintalRate <= 0) {
        continue;
      }

      final commodityLabel = _pickFirstNonEmptyString(data, const <String>[
        'commodityNameUr',
        'commodityNameEn',
        'commodityName',
        'commodity',
        'cropType',
        'itemName',
        'product',
        'name',
      ]);
      final locationLabel = _pickFirstNonEmptyString(data, const <String>[
        'marketName',
        'mandiName',
        'city',
        'district',
      ]);
      final rateDate = _readRateTimestamp(data);
      final locationScore = _locationMatchScore(data, localTokens);
      final match = _CommodityRateMatch(
        commodityLabel: commodityLabel,
        matchedAlias: matchedAlias,
        locationLabel: locationLabel,
        rawQuintalRate: rawQuintalRate,
        mannRate: _convertQuintalToMann(rawQuintalRate),
        rateDate: rateDate,
        locationScore: locationScore,
        trendLine: _trendLineForRate(
          currentQuintalRate: rawQuintalRate,
          data: data,
        ),
      );

      if (locationScore > 0 &&
          (bestLocal == null || match.isBetterThan(bestLocal))) {
        bestLocal = match;
      }
      if (bestOverall == null || match.isBetterThan(bestOverall)) {
        bestOverall = match;
      }
    }

    if (!hasRateIntent && !hasSmartBidIntent && bestOverall == null) {
      return null;
    }

    final chosen = bestLocal ?? bestOverall;
    if (chosen == null) {
      return null;
    }

    if (hasSmartBidIntent) {
      return _formatSmartBidAdvice(chosen);
    }

    return _formatCommodityRateMessage(chosen);
  }

  bool _containsUrduScript(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  bool _liveContextCacheFresh() {
    final at = _cachedLiveMarketContextAt;
    if (at == null) return false;
    return DateTime.now().difference(at) <= _liveContextTtl;
  }

  String _pickFirstNonEmptyString(
    Map<String, dynamic> data,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) {
        return value;
      }
    }
    return '';
  }

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final cleaned = value.toString().replaceAll(',', '').trim();
    return double.tryParse(cleaned);
  }

  String _formatRate(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchRateSnapshot() async {
    final col = FirebaseFirestore.instance
        .collection('mandi_rates')
        .where('province', whereIn: _punjabProvinceQueryValues);
    try {
      return await col
          .orderBy('rateDate', descending: true)
          .limit(14)
          .get()
          .timeout(const Duration(milliseconds: 1300));
    } catch (_) {
      try {
        return await col
            .orderBy('updatedAt', descending: true)
            .limit(14)
            .get()
            .timeout(const Duration(milliseconds: 1300));
      } catch (_) {
        return await col
            .limit(14)
            .get()
            .timeout(const Duration(milliseconds: 1300));
      }
    }
  }

  Future<String> _fetchLiveMarketContextFromFirestore() async {
    try {
      final snapshot = await _fetchRateSnapshot();
      final entries = <String>[];

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final normalizedCity = (data['city'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (normalizedCity == 'karachi' || normalizedCity == 'کراچی') {
          continue;
        }
        final commodity = _pickFirstNonEmptyString(data, const <String>[
          'commodityNameUr',
          'commodityNameEn',
          'commodityName',
          'cropType',
          'itemName',
          'product',
          'commodity',
          'name',
        ]);
        final city = _pickFirstNonEmptyString(data, const <String>[
          'city',
          'district',
          'marketName',
          'mandiName',
        ]);
        final rawRate = _readRawQuintalRate(data);
        final rate = rawRate == null || rawRate <= 0
            ? null
            : _convertQuintalToMann(rawRate);
        final freshness = _formatFreshnessLabel(_readRateTimestamp(data));

        if (commodity.isEmpty || city.isEmpty || rate == null || rate <= 0) {
          continue;
        }

        final trendContext = (rawRate ?? 0) > 5000
            ? 'Market trend is Tezi (High).'
            : 'Market trend is Naram/Mandi (Low).';
        entries.add(
          '$city $commodity ${_formatRate(rate)} Rs per 40kg (Mann), $freshness, $trendContext',
        );
        if (entries.length >= 8) break;
      }

      if (entries.isEmpty) {
        return _cachedLiveMarketContext ?? 'Live Market Context: unavailable.';
      }
      return 'Live Market Context: ${entries.join(', ')}.';
    } catch (error) {
      debugPrint('[Madadgar] live_context_fetch_failed error=$error');
      return _cachedLiveMarketContext ?? 'Live Market Context: unavailable.';
    }
  }

  Future<String> _getLiveMarketContext() async {
    if (_liveContextCacheFresh() &&
        (_cachedLiveMarketContext ?? '').trim().isNotEmpty) {
      return _cachedLiveMarketContext!;
    }

    if (_liveMarketContextInFlight != null) {
      return _liveMarketContextInFlight!;
    }

    _liveMarketContextInFlight = (() async {
      try {
        final context = await _fetchLiveMarketContextFromFirestore();
        _cachedLiveMarketContext = context;
        _cachedLiveMarketContextAt = DateTime.now();
        return context;
      } catch (_) {
        return _cachedLiveMarketContext ?? 'Live Market Context: unavailable.';
      } finally {
        _liveMarketContextInFlight = null;
      }
    })();

    return _liveMarketContextInFlight!;
  }

  void _setChatLoading(bool value) {
    if (!mounted) return;
    if (value) {
      _typingTimer?.cancel();
      _typingPhase = 0;
      _typingTimer = Timer.periodic(const Duration(milliseconds: 340), (_) {
        if (!mounted) return;
        setState(() {
          _typingPhase = (_typingPhase + 1) % 3;
        });
      });
      setState(() {
        _isChatLoading = true;
      });
      return;
    }

    _typingTimer?.cancel();
    _typingTimer = null;
    setState(() {
      _isChatLoading = false;
      _typingPhase = 0;
    });
  }

  Future<void> _submitChat() async {
    final q = _chatCtrl.text.trim();
    if (q.isEmpty || _isChatLoading) return;
    _chatCtrl.clear();
    _appendMessage(text: q, isUser: true);
    FocusScope.of(context).unfocus();

    _setChatLoading(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollChatToBottom();
    });

    String safeText = _buildGeneralFallbackReply(q);

    try {
      String? text;

      try {
        text = await _buildCommodityRateReply(q);
      } catch (error) {
        debugPrint('[Madadgar] commodity_reply_failed query=$q error=$error');
      }

      if ((text ?? '').trim().isEmpty) {
        String liveMarketContext;
        try {
          liveMarketContext = await _getLiveMarketContext().timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () =>
                _cachedLiveMarketContext ?? 'Live Market Context: unavailable.',
          );
        } catch (error) {
          debugPrint('[Madadgar] get_live_context_failed query=$q error=$error');
          liveMarketContext =
              _cachedLiveMarketContext ?? 'Live Market Context: unavailable.';
        }

        text = await _safeAiReply(
          query: q,
          liveMarketContext: liveMarketContext,
        );
      }

      if ((text ?? '').trim().isNotEmpty) {
        safeText = text!.trim();
      }
    } catch (error) {
      debugPrint('[Madadgar] submit_chat_failed query=$q error=$error');
    } finally {
      if (mounted) {
        _appendMessage(text: safeText, isUser: false);
      }
      _setChatLoading(false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollChatToBottom();
      });
    }
  }
}

class _CommodityRateMatch {
  const _CommodityRateMatch({
    required this.commodityLabel,
    required this.matchedAlias,
    required this.locationLabel,
    required this.rawQuintalRate,
    required this.mannRate,
    required this.rateDate,
    required this.locationScore,
    required this.trendLine,
  });

  final String commodityLabel;
  final String matchedAlias;
  final String locationLabel;
  final double rawQuintalRate;
  final double mannRate;
  final DateTime? rateDate;
  final int locationScore;
  final String trendLine;

  bool isBetterThan(_CommodityRateMatch other) {
    if (locationScore != other.locationScore) {
      return locationScore > other.locationScore;
    }

    final thisDate = rateDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final otherDate = other.rateDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    return thisDate.isAfter(otherDate);
  }
}

class _AssistantChatMessage {
  const _AssistantChatMessage({required this.text, required this.isUser});

  final String text;
  final bool isUser;
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Container(
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.secondaryText.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}
