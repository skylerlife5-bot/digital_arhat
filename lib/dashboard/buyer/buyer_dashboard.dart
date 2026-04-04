import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../auth/master_sign_up_screen.dart';
import '../../core/widgets/premium_ui_kit.dart';
import '../../routes.dart';
import '../../services/auth_service.dart';
import '../../theme/app_colors.dart';
import '../../profile/verification_status_widget.dart';
import 'buyer_dashboard_screen.dart';
import 'buyer_home_screen.dart';
import 'buyer_trust_widget.dart';
import '../export/export_screen.dart';

class BuyerDashboard extends StatefulWidget {
  const BuyerDashboard({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<BuyerDashboard> createState() => _BuyerDashboardState();
}

class _BuyerDashboardState extends State<BuyerDashboard> {
  int _currentIndex = 0;

  static const Color _deepGreen = AppColors.background;
  static const Color _gold = AppColors.accentGold;

  Future<void> _onTabTapped(int index) async {
    if (index == 2) {
      await _handlePostTap();
      return;
    }
    setState(() => _currentIndex = index);
  }

  Future<void> _handlePostTap() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      await _showGuestPostPrompt();
      return;
    }

    Map<String, dynamic> latestUserData = <String, dynamic>{...widget.userData};
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final remote = snap.data();
      if (remote != null) {
        latestUserData = <String, dynamic>{...latestUserData, ...remote};
      }
    } catch (_) {
      // Keep local data fallback only; no flow break on transient read failure.
    }

    final role = _resolveRole(latestUserData);
    if (!mounted) return;

    if (role == 'seller') {
      Navigator.of(context).pushNamed(
        Routes.postListingOption,
        arguments: <String, dynamic>{'userData': latestUserData},
      );
      return;
    }

    await _showSellerRequiredPrompt();
  }

  String _resolveRole(Map<String, dynamic> data) {
    return (data['role'] ?? data['userRole'] ?? data['userType'] ?? 'buyer')
        .toString()
        .trim()
        .toLowerCase();
  }

  Future<void> _showGuestPostPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.softGlassBorder),
          ),
          title: const Text(
            'Post Listing / لسٹنگ پوسٹ کریں',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'Login required to post a listing / لسٹنگ پوسٹ کرنے کے لیے لاگ اِن ضروری ہے',
            style: TextStyle(color: AppColors.secondaryText, height: 1.25),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close / بند کریں'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamed(Routes.createAccount);
              },
              child: const Text('Create Account / اکاؤنٹ بنائیں'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pushNamed(Routes.login);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _deepGreen,
              ),
              child: const Text('Login / لاگ اِن'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSellerRequiredPrompt() async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppColors.cardSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: AppColors.softGlassBorder),
          ),
          title: const Text(
            'Seller account required / فروخت کنندہ اکاؤنٹ ضروری ہے',
            style: TextStyle(
              color: AppColors.primaryText,
              fontWeight: FontWeight.w700,
            ),
          ),
          content: const Text(
            'To post a listing, switch to or create a seller account / لسٹنگ پوسٹ کرنے کے لیے سیلر اکاؤنٹ درکار ہے',
            style: TextStyle(color: AppColors.secondaryText, height: 1.25),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close / بند کریں'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        const MasterSignUpScreen(selectedRole: 'seller'),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: _deepGreen,
              ),
              child: const Text('Become Seller / سیلر بنیں'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      BuyerHomeScreen(userData: widget.userData),
      BuyerDashboardScreen(userData: widget.userData),
      const SizedBox.shrink(),
      const ExportScreen(),
      _BuyerAccountTab(userData: widget.userData),
    ];

    return Scaffold(
      backgroundColor: _deepGreen,
      // Keep content above the nav rail and avoid card/chip overlap.
      extendBody: false,
      body: IndexedStack(index: _currentIndex, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: AppColors.cardSurface,
                indicatorColor: AppColors.accentGold.withValues(alpha: 0.20),
                surfaceTintColor: Colors.transparent,
                shadowColor: Colors.transparent,
                height: 60,
                iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((
                  states,
                ) {
                  final active = states.contains(WidgetState.selected);
                  return IconThemeData(
                    color: active ? _gold : AppColors.secondaryText,
                    size: active ? 22 : 21,
                  );
                }),
                labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
                  states,
                ) {
                  final active = states.contains(WidgetState.selected);
                  return TextStyle(
                    color: active ? _gold : AppColors.secondaryText,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  );
                }),
              ),
              child: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: _onTabTapped,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                animationDuration: const Duration(milliseconds: 180),
                elevation: 0,
                destinations: <NavigationDestination>[
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_outlined, color: _gold),
                    label: 'Home',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront_outlined, color: _gold),
                    label: 'Mandi',
                  ),
                  NavigationDestination(
                    icon: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.accentGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF072415),
                        size: 19,
                      ),
                    ),
                    selectedIcon: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.accentGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_rounded,
                        color: Color(0xFF072415),
                        size: 19,
                      ),
                    ),
                    label: 'Post',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.public),
                    selectedIcon: Icon(
                      Icons.public,
                      color: _gold,
                    ),
                    label: 'Export',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline_rounded),
                    selectedIcon: Icon(
                      Icons.person_outline_rounded,
                      color: _gold,
                    ),
                    label: 'Account',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BuyerNotificationsTab extends StatelessWidget {
  const BuyerNotificationsTab({super.key, required this.userData});

  final Map<String, dynamic> userData;

  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (uid.isEmpty) {
      return const _AlertsGuestLockedView();
    }

    return Scaffold(
      backgroundColor: _deepGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Notifications / اطلاعات',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('toUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(60)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _gold));
          }

          if (snapshot.hasError) {
            return const _ShellNoticeCard(
              title:
                  'Alerts are not available right now / اطلاعات عارضی طور پر دستیاب نہیں',
              subtitle:
                  'Please check again shortly / براہِ کرم تھوڑی دیر بعد دوبارہ چیک کریں',
            );
          }

          final docs =
              snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
          final buyerDocs = docs
              .where((doc) {
                final data = doc.data();
                final role = (data['targetRole'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase();
                return role.isEmpty || role == 'buyer';
              })
              .toList(growable: false);
          debugPrint('[NotifReadBuyer] count=${buyerDocs.length}');
          if (buyerDocs.isEmpty) {
            return const _ShellNoticeCard(
              title: 'No new alerts / نئی اطلاعات موجود نہیں',
              subtitle:
                  'Bid, outbid, and listing alerts will appear here / بولی اور مارکیٹ اپڈیٹس یہاں نظر آئیں گی',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
            itemBuilder: (context, index) {
              final data = buyerDocs[index].data();
              final type = (data['type'] ?? '').toString().toUpperCase();
              final isOutbid = type == 'OUTBID';
              final title = (data['titleEn'] ?? data['title'] ?? 'Update')
                  .toString()
                  .trim();
              final body = (data['bodyEn'] ?? data['body'] ?? '')
                  .toString()
                  .trim();
              final listingId = (data['listingId'] ?? data['entityId'] ?? '')
                  .toString()
                  .trim();
              final tapAction = (data['tapAction'] ?? '').toString().trim();
              final routeName = (data['routeName'] ?? '').toString().trim();

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await buyerDocs[index].reference.set({
                      'isRead': true,
                    }, SetOptions(merge: true));

                    String resolvedRoute = routeName;
                    if (resolvedRoute.isEmpty && listingId.isNotEmpty) {
                      resolvedRoute = Routes.listingDetails;
                    }

                    debugPrint(
                      '[NotifRoute] tapAction=$tapAction route=$resolvedRoute',
                    );

                    if (resolvedRoute.isNotEmpty && listingId.isNotEmpty) {
                      if (!context.mounted) return;
                      Navigator.of(context).pushNamed(
                        resolvedRoute,
                        arguments: <String, dynamic>{
                          'listingId': listingId,
                          'userData': userData,
                        },
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isOutbid
                          ? AppColors.urgencyRed.withValues(alpha: 0.18)
                          : AppColors.primaryText.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isOutbid
                            ? AppColors.urgencyRed.withValues(alpha: 0.7)
                            : _gold.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          isOutbid
                              ? Icons.trending_up_rounded
                              : Icons.notifications_active_rounded,
                          color: isOutbid ? AppColors.urgencyRed : _gold,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (isOutbid)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.urgencyRed.withValues(
                                      alpha: 0.22,
                                    ),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: AppColors.urgencyRed.withValues(
                                        alpha: 0.62,
                                      ),
                                    ),
                                  ),
                                  child: const Text(
                                    'OUTBID',
                                    style: TextStyle(
                                      color: AppColors.primaryText,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.primaryText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemCount: buyerDocs.length,
          );
        },
      ),
    );
  }
}

class _BuyerAccountTab extends StatelessWidget {
  const _BuyerAccountTab({required this.userData});

  final Map<String, dynamic> userData;

  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final name = (userData['fullName'] ?? userData['name'] ?? 'خریدار')
        .toString()
        .trim();
    final phone = (userData['phone'] ?? '').toString().trim();
    final city = (userData['city'] ?? userData['village'] ?? '').toString().trim();
    final district = (userData['district'] ?? '').toString().trim();
    final province = (userData['province'] ?? '').toString().trim();
    final role = (userData['role'] ?? userData['userRole'] ?? userData['userType'] ?? 'buyer')
        .toString()
        .trim()
        .toLowerCase();
    final bool verified = userData['isVerified'] == true || userData['isApproved'] == true;
    final bool isGuest = uid.isEmpty;
    final String roleLabel = role == 'admin'
        ? 'Admin'
        : (role == 'seller' || role == 'arhat')
            ? 'Seller'
            : 'Buyer';

    return Scaffold(
      backgroundColor: _deepGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'اکاؤنٹ / Account',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          PremiumSpacing.screenHorizontal,
          PremiumSpacing.s1,
          PremiumSpacing.screenHorizontal,
          PremiumSpacing.s3,
        ),
        children: [
          PremiumSectionHeader(
            titleUr: isGuest ? 'گیسٹ موڈ' : 'آپ کا اکاؤنٹ',
            titleEn: isGuest ? 'Guest mode' : 'Your account overview',
          ),
          const SizedBox(height: PremiumSpacing.s2),
          Container(
            padding: const EdgeInsets.all(PremiumSpacing.s2),
            decoration: BoxDecoration(
              color: AppColors.primaryText10,
              borderRadius: BorderRadius.circular(PremiumSpacing.cardRadius),
              border: Border.all(color: AppColors.softGlassBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded, color: _gold),
                ),
                const SizedBox(width: PremiumSpacing.s1_5),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGuest ? 'Guest User / مہمان صارف' : (name.isEmpty ? 'خریدار' : name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isGuest
                            ? 'Limited access enabled'
                            : '${phone.isEmpty ? 'Phone not set' : phone} · ${city.isEmpty ? district : city}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.primaryText60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _gold.withValues(alpha: 0.58)),
                  ),
                  child: Text(
                    isGuest ? 'Guest' : roleLabel,
                    style: const TextStyle(
                      color: AppColors.accentGold,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PremiumSpacing.s2),
          if (isGuest)
            const PremiumStatusCard(
              badgeText: 'GUEST MODE',
              badgeColor: AppColors.accentGold,
              titleUr: 'ابھی آپ مہمان کے طور پر براؤز کر رہے ہیں',
              titleEn: 'You are currently browsing as a guest',
              descriptionUr: 'لاگ اِن کے بعد آپ بولی لگا سکتے ہیں، الرٹس لے سکتے ہیں اور اپنی سرگرمی محفوظ کر سکتے ہیں۔',
              descriptionEn: 'After login you can place bids, receive alerts, and save your activity.',
            )
          else
            PremiumStatusCard(
              badgeText: verified ? 'VERIFIED' : 'UNDER REVIEW',
              badgeColor: verified ? const Color(0xFF59C686) : AppColors.accentGold,
              titleUr: verified ? 'آپ کا اکاؤنٹ تصدیق شدہ ہے' : 'آپ کا اکاؤنٹ جائزے میں ہے',
              titleEn: verified ? 'Your account is verified' : 'Your account is under review',
              descriptionUr: verified
                  ? 'آپ کی شناخت اور پروفائل معلومات درست پائی گئی ہیں۔'
                  : 'کچھ فیچرز محدود ہو سکتے ہیں جب تک جائزہ مکمل نہیں ہو جاتا۔',
              descriptionEn: verified
                  ? 'Your identity and profile details have been verified.'
                  : 'Some features may remain limited until review is complete.',
            ),
          const SizedBox(height: PremiumSpacing.s2),
          _AccountInfoTile(
            label: 'Phone',
            value: phone.isEmpty ? (isGuest ? 'Guest session' : 'Not set') : phone,
          ),
          _AccountInfoTile(
            label: 'Location',
            value:
                '${district.isEmpty ? 'Pakistan' : district}${province.isEmpty ? '' : ', $province'}',
          ),
          const SizedBox(height: PremiumSpacing.s1),
          const VerificationStatusWidget(),
          if (!isGuest) ...[
            const SizedBox(height: PremiumSpacing.s2),
            BuyerTrustWidget(userData: userData),
          ],
          if (isGuest) ...[
            const SizedBox(height: PremiumSpacing.s1_5),
            const _AccountBenefitRow(
              icon: Icons.gavel_rounded,
              text: 'بولی لگائیں اور نتائج ٹریک کریں\nPlace bids and track outcomes',
            ),
            const _AccountBenefitRow(
              icon: Icons.notifications_active_outlined,
              text: 'فوری الرٹس حاصل کریں\nReceive instant activity alerts',
            ),
            const _AccountBenefitRow(
              icon: Icons.post_add_rounded,
              text: 'اپنی لسٹنگز پوسٹ کریں\nPost your own listings',
            ),
          ],
          const SizedBox(height: PremiumSpacing.s2),
          if (isGuest) ...[
            PremiumPrimaryButton(
              label: 'لاگ اِن کریں / Login',
              icon: Icons.login_rounded,
              onPressed: () => Navigator.of(context).pushNamed(Routes.login),
            ),
            const SizedBox(height: PremiumSpacing.s1),
            PremiumSecondaryButton(
              label: 'اکاؤنٹ بنائیں / Create Account',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: () =>
                  Navigator.of(context).pushNamed(Routes.createAccount),
            ),
          ] else ...[
            PremiumSecondaryButton(
              label: 'لاگ آؤٹ / Logout',
              icon: Icons.logout_rounded,
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                await AuthService().clearPersistedSessionUid();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                  Routes.welcome,
                  (route) => false,
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountInfoTile extends StatelessWidget {
  const _AccountInfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryText24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountBenefitRow extends StatelessWidget {
  const _AccountBenefitRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: _BuyerAccountTab._gold, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11.7,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertsGuestLockedView extends StatelessWidget {
  const _AlertsGuestLockedView();

  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepGreen,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Alerts / اطلاعات',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 22),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primaryText.withValues(alpha: 0.11),
                  AppColors.primaryText.withValues(alpha: 0.06),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _gold.withValues(alpha: 0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: _gold,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sign in to unlock live alerts / لائیو الرٹس کے لیے لاگ اِن کریں',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Stay updated with your bids, listing approvals, outbid updates, and auction reminders.\nاپنی بولی، منظوری، آؤٹ بِڈ اور آکشن ریمائنڈرز ایک جگہ دیکھیں۔',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 12.2,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _AlertBenefitTile(
            icon: Icons.gavel_rounded,
            title: 'Bid updates / بولی اپڈیٹس',
          ),
          const _AlertBenefitTile(
            icon: Icons.trending_up_rounded,
            title: 'Outbid warnings / آؤٹ بِڈ تنبیہ',
          ),
          const _AlertBenefitTile(
            icon: Icons.verified_rounded,
            title: 'Listing approvals / منظوری اطلاعات',
          ),
          const _AlertBenefitTile(
            icon: Icons.schedule_rounded,
            title: 'Auction reminders / آکشن یاد دہانی',
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pushNamed(Routes.login),
            style: FilledButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: _deepGreen,
              minimumSize: const Size.fromHeight(46),
            ),
            icon: const Icon(Icons.login_rounded),
            label: const Text('Login / لاگ اِن'),
          ),
        ],
      ),
    );
  }
}

class _AlertBenefitTile extends StatelessWidget {
  const _AlertBenefitTile({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primaryText.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primaryText24),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _AlertsGuestLockedView._gold),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShellNoticeCard extends StatelessWidget {
  const _ShellNoticeCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  static const Color _deepGreen = Color(0xFF062517);
  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _deepGreen,
      body: Center(
        child: Container(
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryText.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _gold.withValues(alpha: 0.28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline_rounded, color: _gold, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.secondaryText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
