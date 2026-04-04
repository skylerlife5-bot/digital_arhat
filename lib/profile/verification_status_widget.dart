// Digital Arhat - placeholder
import 'package:flutter/material.dart';

import '../core/widgets/premium_ui_kit.dart';
import '../theme/app_colors.dart';

class VerificationStatusWidget extends StatelessWidget {
  const VerificationStatusWidget({
    super.key,
    this.isVerified = false,
    this.isPending = true,
  });

  final bool isVerified;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final bool pending = !isVerified && isPending;
    final String badge = isVerified
        ? 'VERIFIED'
        : (pending ? 'PENDING REVIEW' : 'ACTION REQUIRED');

    final Color badgeColor = isVerified
        ? const Color(0xFF59C686)
        : (pending ? AppColors.accentGold : AppColors.urgencyRed);

    final String titleUr = isVerified
        ? 'تصدیق مکمل'
        : (pending ? 'تصدیق زیرِ جائزہ' : 'تصدیق درکار');
    final String titleEn = isVerified
        ? 'Verification complete'
        : (pending ? 'Verification under review' : 'Verification required');

    final String helperUr = isVerified
        ? 'آپ کا اکاؤنٹ تصدیق شدہ ہے، آپ بلا رکاوٹ مارکیٹ فیچرز استعمال کر سکتے ہیں۔'
        : (pending
            ? 'ہم آپ کی معلومات کا جائزہ لے رہے ہیں۔ مکمل ہونے پر آپ کو اطلاع ملے گی۔'
            : 'اپنی پروفائل معلومات مکمل کریں تاکہ مکمل مارکیٹ رسائی مل سکے۔');
    final String helperEn = isVerified
        ? 'Your account is verified. You can use all marketplace features smoothly.'
        : (pending
            ? 'Your details are being reviewed. You will be notified once completed.'
            : 'Complete your profile details to unlock full marketplace access.');

    return PremiumStatusCard(
      badgeText: badge,
      badgeColor: badgeColor,
      titleUr: titleUr,
      titleEn: titleEn,
      descriptionUr: helperUr,
      descriptionEn: helperEn,
    );
  }
}

