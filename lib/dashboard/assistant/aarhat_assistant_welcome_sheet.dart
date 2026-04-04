import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'aarhat_assistant_sheet.dart';
import 'assistant_mandi_icon.dart';
import 'assistant_prefs_service.dart';

/// Premium welcome bottom sheet for Aarhat Assistant.
/// Shown only once per device using SharedPreferences flag.
/// Simple, clean, Urdu-first introduction to assistant capabilities.
class AarhatAssistantWelcomeSheet extends StatefulWidget {
  const AarhatAssistantWelcomeSheet({
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
      builder: (_) => AarhatAssistantWelcomeSheet(userData: userData),
    );
  }

  @override
  State<AarhatAssistantWelcomeSheet> createState() =>
      _AarhatAssistantWelcomeSheetState();
}

class _AarhatAssistantWelcomeSheetState
    extends State<AarhatAssistantWelcomeSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 290),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fadeAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    AssistantPrefsService.markWelcomeSeen();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _handleTryNow() {
    final navigator = Navigator.of(context);
    final userData = widget.userData;
    navigator.pop();
    Future.delayed(
      const Duration(milliseconds: 200),
      () {
        if (!mounted) return;
        AarhatAssistantSheet.show(context, userData: userData);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).viewPadding.top + 24;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Container(
          margin: EdgeInsets.only(top: topPadding),
          decoration: const BoxDecoration(
            color: Color(0xFF0E3B2E),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _DragHandle(),
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  children: [
                    // Icon badge (mandi wheat icon)
                    const SizedBox(height: 8),
                    AssistantMandiIcon(size: 28, padding: const EdgeInsets.all(16)),
                    const SizedBox(height: 18),

                    // Title (Urdu first)
                    const Text(
                      'مددگار میں خوش آمدید',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.primaryText,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Body text
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.accentGold.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.accentGold.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'مددگار آپ کے ساتھ ہے:',
                            style: TextStyle(
                              color: AppColors.secondaryText,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildFeature('جلدی لسٹنگ بنانے میں'),
                          const SizedBox(height: 7),
                          _buildFeature('بہتر قیمت سمجھنے میں'),
                          const SizedBox(height: 7),
                          _buildFeature('بولی اور منڈی ریٹ میں'),
                          const SizedBox(height: 7),
                          _buildFeature('بہتر خرید و فروخت میں'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Buttons
                    Column(
                      children: [
                        FilledButton(
                          onPressed: _handleTryNow,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentGold,
                            foregroundColor: AppColors.ctaTextDark,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 3,
                          ),
                          child: const Text(
                            'شروع کریں',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.secondaryText,
                            minimumSize: const Size(double.infinity, 46),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'بعد میں',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeature(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 2, right: 8),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFD4A937), Color(0xFFA3832A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: Icon(Icons.check_rounded, color: Colors.white, size: 10),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.secondaryText.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
