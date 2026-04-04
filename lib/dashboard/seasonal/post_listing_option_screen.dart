import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/seasonal_bakra_mandi_config.dart';
import '../../routes.dart';
import '../../theme/app_colors.dart';

class PostListingOptionScreen extends StatefulWidget {
  const PostListingOptionScreen({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<PostListingOptionScreen> createState() =>
      _PostListingOptionScreenState();
}

class _PostListingOptionScreenState extends State<PostListingOptionScreen> {
  late final Future<bool> _bakraVisibilityFuture;

  String _resolveVerificationStatus(Map<String, dynamic> data) {
    final status =
        (data['verificationStatus'] ?? '').toString().trim().toLowerCase();
    if (status == 'approved' || status == 'verified') return 'approved';
    if (status == 'rejected') return 'rejected';
    return 'pending';
  }

  bool _isSellerApproved(Map<String, dynamic> data) {
    final status = _resolveVerificationStatus(data);
    return status == 'approved' || data['isApproved'] == true;
  }

  Future<Map<String, dynamic>> _loadSellerProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return widget.userData;
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return doc.data() ?? widget.userData;
  }

  Future<bool> _ensureApprovedOrInform() async {
    final profile = await _loadSellerProfile();
    final approved = _isSellerApproved(profile);
    if (!mounted) return false;
    if (approved) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'آپ کی تصدیق ابھی جاری ہے۔ منظوری کے بعد آپ لسٹنگ پوسٹ کر سکیں گے۔',
        ),
      ),
    );
    return false;
  }

  Future<void> _openRegularMandi() async {
    final allowed = await _ensureApprovedOrInform();
    if (!allowed || !mounted) return;
    Navigator.of(context).pushNamed(
      Routes.sellerAddListing,
      arguments: <String, dynamic>{'userData': widget.userData},
    );
  }

  Future<void> _openBakraPost() async {
    final allowed = await _ensureApprovedOrInform();
    if (!allowed || !mounted) return;
    Navigator.of(context).pushNamed(
      Routes.bakraMandiPost,
      arguments: <String, dynamic>{'userData': widget.userData},
    );
  }

  @override
  void initState() {
    super.initState();
    _bakraVisibilityFuture = SeasonalBakraMandiConfig.loadRuntimeVisibility();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _bakraVisibilityFuture,
      builder: (context, snapshot) {
        final bool bakraEnabled = SeasonalBakraMandiConfig.isEnabled(
          snapshot.data,
        );
        final bool bakraPostingAllowed =
            bakraEnabled && SeasonalBakraMandiConfig.allowPosting;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text(
              'پوسٹ کی قسم / Choose Post Type',
              style: TextStyle(color: AppColors.primaryText),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              _OptionCard(
                title: 'عام منڈی پوسٹ / Regular Mandi',
                subtitle: 'Auction flow (existing rules)',
                icon: Icons.storefront_outlined,
                onTap: _openRegularMandi,
              ),
              const SizedBox(height: 12),
              _OptionCard(
                title: 'عید بکرا منڈی / Eid Bakra Mandi',
                subtitle: bakraPostingAllowed
                    ? 'Fixed-price post with direct contact'
                    : 'موسمی بکرا منڈی پوسٹ بند ہے',
                icon: Icons.pets_rounded,
                disabled: !bakraPostingAllowed,
                onTap: bakraPostingAllowed ? _openBakraPost : null,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
    this.disabled = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: disabled ? AppColors.divider : AppColors.softGlassBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: disabled ? AppColors.secondaryText : AppColors.accentGold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: disabled
                          ? AppColors.secondaryText
                          : AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
