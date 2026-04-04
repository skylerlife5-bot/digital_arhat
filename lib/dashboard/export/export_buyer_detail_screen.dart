import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'export_inquiry_form.dart';
import 'models/export_buyer_profile.dart';

class ExportBuyerDetailScreen extends StatelessWidget {
  const ExportBuyerDetailScreen({
    super.key,
    required this.profile,
  });

  final ExportBuyerProfile profile;

  String _commoditySummary() {
    return profile.commodities.join(', ');
  }

  String _certificationSummary() {
    if (profile.certificationsPreferred.isEmpty) {
      return 'Buyer-specific certifications';
    }
    return profile.certificationsPreferred.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Buyer Details',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.softGlassBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          profile.companyName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.primaryText,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                        ),
                        if (profile.verified)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A4A33).withValues(alpha: 0.50),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Verified',
                              style: TextStyle(
                                color: AppColors.accentGold,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${profile.country}, ${profile.city}',
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _MetaPill(label: profile.buyerType),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Buyer Summary',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SummaryLine(label: 'Imports', value: _commoditySummary()),
                    _SummaryLine(label: 'MOQ', value: profile.minOrder),
                    _SummaryLine(
                      label: 'Preferred countries',
                      value: profile.country,
                    ),
                    _SummaryLine(
                      label: 'Certifications required',
                      value: _certificationSummary(),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      profile.summary,
                      style: const TextStyle(
                        color: AppColors.secondaryText,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Trust',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const _TrustRow(text: 'Verified Buyer'),
                    const SizedBox(height: 6),
                    _TrustRow(text: 'Active ${profile.lastActiveHours} hours ago'),
                    const SizedBox(height: 6),
                    const _TrustRow(text: 'Only verified buyers are shown here'),
                    const SizedBox(height: 6),
                    const _TrustRow(
                      text: 'Your contact will only be shared with this buyer',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: AppColors.background,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  onPressed: () async {
                    final result = await Navigator.of(context).push<bool>(
                      MaterialPageRoute<bool>(
                        builder: (_) => ExportInquiryForm(
                          buyer: profile,
                          initialCommodity: profile.commodities.isNotEmpty
                              ? profile.commodities.first
                              : null,
                        ),
                      ),
                    );

                    if (result == true && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Your inquiry has been sent')),
                      );
                    }
                  },
                  child: const Text('Send Inquiry'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.cardSurface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.softGlassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              color: AppColors.primaryText,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.primaryText,
          fontSize: 12,
          height: 1.3,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(
            Icons.check_circle,
            size: 14,
            color: AppColors.accentGold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppColors.secondaryText,
              fontSize: 12,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}
