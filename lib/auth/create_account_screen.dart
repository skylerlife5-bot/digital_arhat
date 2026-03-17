import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
// ignore_for_file: avoid_print

import 'auth_state.dart';
import 'buyer_sign_up_screen.dart';
import 'master_sign_up_screen.dart';

class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  String? _selectedRole;

  void _goNext() {
    final String? selectedRole = _selectedRole;
    if (selectedRole == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Please select Buyer or Seller / خریدار یا فروخت کنندہ منتخب کریں',
            ),
          ),
        );
      return;
    }

    AuthState.setSelectedRole(selectedRole);
    print('CreateAccount selectedRole = $selectedRole');
    if (selectedRole == 'buyer') {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => const BuyerSignUpScreen()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const MasterSignUpScreen(selectedRole: 'seller'),
      ),
    );
  }

  Widget _roleCard({
    required String value,
    required String title,
    required String urdu,
    required String detail,
    required String detailUrdu,
    required IconData icon,
  }) {
    final selected = _selectedRole == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selectedRole = value),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.softOverlayGold
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppColors.accentGold
                    : AppColors.accentGold.withValues(alpha: 0.5),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? <BoxShadow>[
                      BoxShadow(
                        color: AppColors.accentGold.withValues(alpha: 0.22),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ]
                  : const <BoxShadow>[],
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 136),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: AppColors.accentGold, size: 23),
                  const SizedBox(height: 7),
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    urdu,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 14,
                      fontFamily: 'JameelNoori',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 11.2,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    detailUrdu,
                    style: const TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12.5,
                      fontFamily: 'JameelNoori',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Create Account / اکاؤنٹ بنائیں'),
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _AuthBackground())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.accentGold.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose your role in Digital Arhat / اپنا کردار منتخب کریں',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Pakistan digital mandi for trusted trading',
                          style: TextStyle(color: AppColors.secondaryText, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _roleCard(
                              value: 'buyer',
                              title: 'Buyer',
                              urdu: 'خریدار',
                              detail:
                                  'Browse listings, place bids, track offers',
                              detailUrdu:
                                  'لسٹنگ دیکھیں، بولی لگائیں، آفر ٹریک کریں',
                              icon: Icons.shopping_bag_outlined,
                            ),
                            const SizedBox(width: 10),
                            _roleCard(
                              value: 'seller',
                              title: 'Seller',
                              urdu: 'فروخت کنندہ',
                              detail:
                                  'Post listings, receive bids, sell faster',
                              detailUrdu:
                                  'لسٹنگ پوسٹ کریں، بولی لیں، جلد فروخت کریں',
                              icon: Icons.storefront_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.accentGold.withValues(alpha: 0.35),
                      ),
                    ),
                    child: const Text(
                      'Trusted environment with verified profiles, bid flow transparency, and mandi-focused buyer-seller matching.\nتصدیق شدہ پروفائلز، شفاف بولی عمل اور منڈی فوکسڈ میچنگ کے ساتھ محفوظ تجارت۔',
                      style: TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 11.8,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _selectedRole == null ? null : _goNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.background,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue / جاری رکھیں',
                      style: TextStyle(fontWeight: FontWeight.w700),
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
}

class _AuthBackground extends StatelessWidget {
  const _AuthBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.background, AppColors.cardSurface, AppColors.background],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.softOverlayWhite, Colors.transparent],
            ),
          ),
          child: SizedBox.expand(),
        ),
      ],
    );
  }
}

