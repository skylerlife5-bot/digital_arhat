import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location_display_helper.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';

class BakraMandiDetailScreen extends StatefulWidget {
  const BakraMandiDetailScreen({
    super.key,
    required this.listingId,
    this.initialData,
  });

  final String listingId;
  final Map<String, dynamic>? initialData;

  @override
  State<BakraMandiDetailScreen> createState() => _BakraMandiDetailScreenState();
}

class _BakraMandiDetailScreenState extends State<BakraMandiDetailScreen> {
  final AnalyticsService _analytics = AnalyticsService();
  final PageController _pageController = PageController();
  int _activeImage = 0;

  String _seasonalAssetFromText(String text) {
    final normalized = text.toLowerCase();
    if (normalized.contains('camel') || normalized.contains('oont') || normalized.contains('اونٹ')) {
      return 'assets/bakra_mandi/oont.png';
    }
    if (normalized.contains('dumba') || normalized.contains('sheep') || normalized.contains('دنب')) {
      return 'assets/bakra_mandi/dumba.png';
    }
    if (normalized.contains('cow') || normalized.contains('gaye') || normalized.contains('گائے')) {
      return 'assets/bakra_mandi/gaye.png';
    }
    return 'assets/bakra_mandi/bakray.png';
  }

  bool _isFlagOn(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      _analytics.logEvent(
        event: 'bakra_mandi_detail_open',
        data: <String, dynamic>{'listingId': widget.listingId},
      );
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _openDialer(String phone) async {
    final normalized = phone.trim();
    if (normalized.isEmpty) return;
    final uri = Uri.parse('tel:$normalized');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsApp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'بکرا منڈی',
          style: TextStyle(color: AppColors.primaryText),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('listings')
            .doc(widget.listingId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? widget.initialData;
          if (data == null) {
            return const Center(
              child: Text(
                'تفصیل دستیاب نہیں',
                style: TextStyle(color: AppColors.primaryText),
              ),
            );
          }

          final String title = (data['product'] ?? 'جانور').toString();
          final String breed = (data['breed'] ?? '').toString();
          final String age = (data['age'] ?? '').toString();
          final String weight = (data['weight'] ?? '').toString();
            final String locationDisplay =
              LocationDisplayHelper.locationDisplayFromData(data);
          final String sellerName = (data['sellerName'] ?? '').toString();
          final double price =
              ((data['price'] is num) ? data['price'] as num : num.tryParse((data['price'] ?? '').toString()) ?? 0)
                  .toDouble();
          final String phone =
              (data['sellerPhone'] ?? data['contactPhone'] ?? '').toString();
          final String whatsapp =
              (data['sellerWhatsapp'] ?? phone).toString().trim();
          final bool isFeatured = _isFlagOn(data, 'isFeatured') || _isFlagOn(data, 'featured');
          final bool isUrgent = _isFlagOn(data, 'isUrgent');
          final bool isDealer = _isFlagOn(data, 'isDealer');
          final String fallbackAsset = _seasonalAssetFromText(
            '${data['animalType'] ?? ''} ${data['product'] ?? ''} ${data['subcategoryLabel'] ?? ''} ${data['description'] ?? ''}',
          );

          final List<dynamic> images =
              (data['imageUrls'] as List?) ?? (data['images'] as List?) ?? const <dynamic>[];

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 22),
            children: [
              if (images.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 250,
                    child: Stack(
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: images.length,
                          onPageChanged: (value) {
                            setState(() => _activeImage = value);
                          },
                          itemBuilder: (context, index) {
                            return Image.network(
                              images[index].toString(),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  _imagePlaceholder(
                                    assetPath: fallbackAsset,
                                    label: title,
                                  ),
                            );
                          },
                        ),
                        Positioned(
                          bottom: 8,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (index) {
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                width: _activeImage == index ? 16 : 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: _activeImage == index
                                      ? AppColors.accentGold
                                      : Colors.white.withValues(alpha: 0.7),
                                ),
                              );
                            }),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 250,
                    child: _imagePlaceholder(
                      assetPath: fallbackAsset,
                      label: title,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.primaryText,
                  fontWeight: FontWeight.w800,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (isFeatured) _hookBadge('Featured Listing', const Color(0xFFE8C766)),
                  if (isUrgent) _hookBadge('Urgent Sale', const Color(0xFFFF8A65)),
                  if (isDealer) _hookBadge('Dealer Plan', const Color(0xFF81C784)),
                ],
              ),
              const SizedBox(height: 8),
              _line('📍 مقام', locationDisplay.isEmpty ? 'نامعلوم' : locationDisplay),
              if (weight.isNotEmpty) _line('⚖ وزن', weight),
              _line('💰 قیمت', 'Rs. ${price.toStringAsFixed(0)}'),
              if (sellerName.trim().isNotEmpty) _line('فروخت کنندہ', sellerName.trim()),
              if (breed.trim().isNotEmpty) _line('Breed', breed.trim()),
              if (age.trim().isNotEmpty) _line('Age', age.trim()),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Text(
                  '⚠ ادائیگی سے پہلے جانور خود دیکھ لیں',
                  style: TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: phone.trim().isEmpty
                          ? null
                          : () async {
                              await _analytics.logEvent(
                                event: 'bakra_mandi_call_tap',
                                data: <String, dynamic>{'listingId': widget.listingId},
                              );
                              await _openDialer(phone);
                            },
                      icon: const Icon(Icons.phone),
                      label: Text(phone.trim().isEmpty ? '📞 نمبر نہیں' : '📞 کال کریں'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: whatsapp.isEmpty
                          ? null
                          : () async {
                              await _analytics.logEvent(
                                event: 'bakra_mandi_whatsapp_tap',
                                data: <String, dynamic>{'listingId': widget.listingId},
                              );
                              await _openWhatsApp(whatsapp);
                            },
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(whatsapp.isEmpty ? '💬 نمبر نہیں' : '💬 واٹس ایپ'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _imagePlaceholder({required String assetPath, required String label}) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            color: AppColors.cardSurface,
            alignment: Alignment.center,
            child: const Icon(
              Icons.pets_rounded,
              size: 60,
              color: AppColors.accentGold,
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.58),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 14,
          right: 14,
          bottom: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'موسمی بکرا منڈی',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(color: AppColors.secondaryText),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: AppColors.primaryText, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hookBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
