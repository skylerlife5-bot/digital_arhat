import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'assistant_mandi_icon.dart';
import 'assistant_prefs_service.dart';

/// First-time welcome popup for the Aarhat Assistant.
/// Shown once using SharedPreferences flag.
class AarhatAssistantWelcomeDialog extends StatefulWidget {
  const AarhatAssistantWelcomeDialog({
    super.key,
    required this.onTryAssistant,
  });

  final VoidCallback onTryAssistant;

  @override
  State<AarhatAssistantWelcomeDialog> createState() =>
      _AarhatAssistantWelcomeDialogState();
}

class _AarhatAssistantWelcomeDialogState
    extends State<AarhatAssistantWelcomeDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _scaleAnim = Tween<double>(begin: 0.86, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );
    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.forward();
    AssistantPrefsService.markWelcomeSeen();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 22,
            vertical: 60,
          ),
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A5A40), Color(0xFF0E3B2E)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: AppColors.accentGold.withValues(alpha: 0.45),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.40),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(),
                _buildBody(),
                _buildActions(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accentGold.withValues(alpha: 0.16),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          AssistantMandiIcon(size: 28, padding: const EdgeInsets.all(14)),
          const SizedBox(height: 12),
          const Text(
            'آڑھت اسسٹنٹ میں خوش آمدید',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w800,
              fontSize: 18.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Aarhat Assistant mein khush aamdeed',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    const items = [
      'لسٹنگ جلدی بنانے میں',
      'منڈی ریٹ سمجھنے میں',
      'Auction یا Fixed Price چننے میں',
      'بہتر خرید و فروخت میں',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'میں آپ کی مدد کر سکتا ہوں:',
            style: TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 5, right: 10),
                    decoration: const BoxDecoration(
                      color: AppColors.accentGold,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      text,
                      style: const TextStyle(
                        color: AppColors.primaryText,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onTryAssistant();
              },
              icon: const Icon(Icons.grain_rounded, size: 18),
              label: const Text(
                'Abhi Dekhein / Try Assistant',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accentGold,
                foregroundColor: AppColors.ctaTextDark,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.secondaryText,
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              child: const Text('Baad Mein / Maybe Later'),
            ),
          ),
        ],
      ),
    );
  }
}
