import 'package:flutter/material.dart';

import '../../routes.dart';
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
  const AarhatAssistantSheet({
    super.key,
    required this.userData,
  });

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  late final List<Animation<double>> _cardFadeAnims;
  late final List<Animation<Offset>> _cardSlideAnims;

  final TextEditingController _chatCtrl = TextEditingController();

  late final AssistantUserRole _role;
  late final List<_QuickActionDef> _actions;

  _AssistantAction? _activeAction;
  String? _chatResponse;

  int _auctionStep = 0;
  String? _auctionItemType;
  String? _auctionRecommendation;

  @override
  void initState() {
    super.initState();
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
      (i) => Tween<Offset>(
        begin: const Offset(0, 0.12),
        end: Offset.zero,
      ).animate(
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
    _animCtrl.dispose();
    _chatCtrl.dispose();
    super.dispose();
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
      _chatResponse = null;
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
    final double topPadding = MediaQuery.of(context).viewPadding.top + 56;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: EdgeInsets.only(top: topPadding),
          decoration: const BoxDecoration(
            color: Color(0xFF0E3B2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DragHandle(),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 4,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 14),
                      _buildQuickActionList(),
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 16),
                      _buildChatSection(),
                    ],
                  ),
                ),
              ),
            ],
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
            (chip) => _chipBtn(
              label: chip.$1,
              onTap: () => _selectAction(chip.$2),
            ),
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
              children: [
                'فصل',
                'مویشی',
                'دیگر',
              ]
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
          _resultBody('1) واضح تصویر اور درست مقام شامل کریں\n2) صاف عنوان لکھیں\n3) منڈی ریٹ کے قریب قیمت رکھیں\n4) ضرورت ہو تو نمایاں لسٹنگ منتخب کریں'),
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
          _resultBody('اپنے قریب موجود لسٹنگ سے نقل و حمل کم رہتی ہے اور سودا جلدی ممکن ہوتا ہے۔ ہوم میں قریبی حصے کو دیکھیں۔'),
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
          _resultBody('ہمیشہ محفوظ رابطے کے ذریعے بات کریں، پیشگی ادائیگی احتیاط سے کریں، اور مشکوک سودے کی اطلاع دیں۔'),
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
          _resultBody('یہاں آپ خرید و فروخت دونوں کر سکتے ہیں۔ پہلے منڈی دیکھیں، پھر ضرورت کے مطابق خریدار یا فروخت کنندہ پروفائل بنائیں۔'),
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
          _resultBody('اگر آپ مال بیچنا چاہتے ہیں تو فروخت کنندہ بنیں۔ اگر خریدنا چاہتے ہیں تو خریدار بنیں۔ بعد میں کردار تبدیل بھی کیا جا سکتا ہے۔'),
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
          _resultBody('مارکیٹ میں نئی لسٹنگز، فیچرڈ آئٹمز اور قریبی منڈی ریٹ دیکھیں۔ پھر مناسب قدم منتخب کریں۔'),
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

  Widget _buildChatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0x26FFFFFF), height: 1),
        const SizedBox(height: 12),
        const Text(
          'کوئی سوال ہے؟',
          style: TextStyle(
            color: AppColors.secondaryText,
            fontSize: 11.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        if (_chatResponse != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.softGlassBorder),
            ),
            child: Text(
              _chatResponse!,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontSize: 12.4,
                height: 1.35,
              ),
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _chatCtrl,
                style: const TextStyle(color: AppColors.primaryText, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'اپنا سوال یہاں لکھیں',
                  hintStyle: const TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12,
                  ),
                  filled: true,
                  fillColor: AppColors.cardSurface,
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.accentGold),
                  ),
                ),
                onSubmitted: (_) => _submitChat(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: AppColors.accentGold,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: _submitChat,
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
      ],
    );
  }

  void _submitChat() {
    final q = _chatCtrl.text.trim();
    if (q.isEmpty) return;
    _chatCtrl.clear();
    FocusScope.of(context).unfocus();

    final lower = q.toLowerCase();
    String response;
    if (lower.contains('rate') || lower.contains('ریٹ') || lower.contains('قیمت')) {
      response = 'پہلے منڈی ریٹ دیکھیں، پھر قیمت یا بولی طے کریں۔ اوپر "منڈی ریٹ دیکھیں" سے فوری رہنمائی ملے گی۔';
    } else if (lower.contains('boli') || lower.contains('bid') || lower.contains('auction') || lower.contains('بولی')) {
      response = 'بولی میں وقت ختم ہونے سے پہلے مناسب قیمت دیں۔ اوپر "بولی کیسے لگتی ہے؟" سے آسان طریقہ دیکھیں۔';
    } else if (lower.contains('listing') || lower.contains('sell') || lower.contains('لسٹنگ')) {
      response = 'اپنا مال شامل کرنے کے لیے اوپر "لسٹنگ کیسے پوسٹ ہوتی ہے؟" کھولیں، مرحلہ وار رہنمائی مل جائے گی۔';
    } else {
      response = 'آپ کا سوال موصول ہوا۔ اوپر موجود رہنمائی کارڈز سے متعلقہ معلومات فوراً دیکھیں۔';
    }

    setState(() => _chatResponse = response);
  }
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
