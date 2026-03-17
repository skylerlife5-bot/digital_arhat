import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/seasonal_bakra_mandi_config.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import 'bakra_mandi_detail_screen.dart';

class BakraMandiListScreen extends StatefulWidget {
  const BakraMandiListScreen({
    super.key,
    this.initialAnimalType,
    this.initialQuery,
  });

  final String? initialAnimalType;
  final String? initialQuery;

  @override
  State<BakraMandiListScreen> createState() => _BakraMandiListScreenState();
}

class _BakraMandiListScreenState extends State<BakraMandiListScreen> {
  final AnalyticsService _analytics = AnalyticsService();
  final TextEditingController _priceMinController = TextEditingController();
  final TextEditingController _priceMaxController = TextEditingController();
  final TextEditingController _weightMinController = TextEditingController();

  String _selectedCity = 'all';
  String _animalType = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _animalType = (widget.initialAnimalType ?? 'all').trim().toLowerCase();
    _query = (widget.initialQuery ?? '').trim().toLowerCase();
  }

  @override
  void dispose() {
    _priceMinController.dispose();
    _priceMaxController.dispose();
    _weightMinController.dispose();
    super.dispose();
  }

  bool _isBakra(Map<String, dynamic> data) {
    final category = (data['category'] ?? '').toString().toLowerCase();
    if (category == 'bakra_mandi') return true;

    final tags = (data['seasonalTags'] as List?) ?? const <dynamic>[];
    for (final tag in tags) {
      final key = tag.toString().toLowerCase().trim();
      if (key == 'bakra_mandi' || key == 'qurbani') return true;
    }
    return data['isSeasonalQurbani'] == true;
  }

  DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  DateTime? _resolveExpiry(Map<String, dynamic> data) {
    return _readDate(data['bakraExpiresAt']) ??
        _readDate(data['archiveAfter']) ??
        (() {
          final createdAt = _readDate(data['createdAt']);
          if (createdAt == null) return null;
          return createdAt.add(SeasonalBakraMandiConfig.listingLifetime);
        })();
  }

  bool _isExpired(Map<String, dynamic> data) {
    final expiry = _resolveExpiry(data);
    if (expiry == null) return false;
    return DateTime.now().isAfter(expiry);
  }

  bool _isAnimalMatch(Map<String, dynamic> data) {
    if (_animalType == 'all') return true;
    final text =
        '${data['product'] ?? ''} ${data['subcategoryLabel'] ?? ''} ${data['description'] ?? ''}'
            .toString()
            .toLowerCase();
    if (_animalType == 'bakray') {
      return text.contains('bakra') || text.contains('goat') || text.contains('بکر');
    }
    if (_animalType == 'gaye') {
      return text.contains('gaye') || text.contains('cow') || text.contains('گائے');
    }
    if (_animalType == 'dumba') {
      return text.contains('dumba') || text.contains('sheep') || text.contains('دنب');
    }
    if (_animalType == 'oont') {
      return text.contains('oont') || text.contains('camel') || text.contains('اونٹ');
    }
    return true;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  Future<void> _callSeller(BuildContext context, String phone, String listingId) async {
    if (phone.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فون نمبر دستیاب نہیں / Phone not available')),
      );
      return;
    }
    await _analytics.logEvent(
      event: 'bakra_call_tap',
      data: <String, dynamic>{'listingId': listingId},
    );
    final uri = Uri.parse('tel:${phone.trim()}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWhatsapp(BuildContext context, String whatsapp, String listingId) async {
    final digits = whatsapp.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('واٹس ایپ نمبر دستیاب نہیں / WhatsApp not available')),
      );
      return;
    }
    await _analytics.logEvent(
      event: 'bakra_whatsapp_tap',
      data: <String, dynamic>{'listingId': listingId},
    );
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = SeasonalBakraMandiConfig.isEnabled;

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
      body: !enabled
          ? const Center(
              child: Text(
                'موسمی بکرا منڈی بند ہے',
                style: TextStyle(color: AppColors.primaryText),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.location_on_outlined,
                              label: 'شہر / City',
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _selectedCity,
                                  dropdownColor: AppColors.cardSurface,
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('سب شہر')),
                                    DropdownMenuItem(value: 'lahore', child: Text('Lahore')),
                                    DropdownMenuItem(value: 'karachi', child: Text('Karachi')),
                                    DropdownMenuItem(value: 'multan', child: Text('Multan')),
                                    DropdownMenuItem(value: 'faisalabad', child: Text('Faisalabad')),
                                    DropdownMenuItem(value: 'islamabad', child: Text('Islamabad')),
                                  ],
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _selectedCity = value);
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.monitor_weight_outlined,
                              label: '⚖ وزن',
                              child: TextField(
                                controller: _weightMinController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'کم از کم',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.currency_rupee_rounded,
                              label: '💰 قیمت (کم)',
                              child: TextField(
                                controller: _priceMinController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Min',
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.currency_rupee_rounded,
                              label: '💰 قیمت (زیادہ)',
                              child: TextField(
                                controller: _priceMaxController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: InputBorder.none,
                                  hintText: 'Max',
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('listings')
                        .where('isApproved', isEqualTo: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(
                          child: CircularProgressIndicator(color: AppColors.accentGold),
                        );
                      }

                      if (snapshot.hasError) {
                        return const Center(
                          child: Text(
                            'لسٹنگ لوڈ نہیں ہو سکی / Try again',
                            style: TextStyle(color: AppColors.primaryText),
                          ),
                        );
                      }

                      final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                      final filtered = docs.where((doc) {
                        final data = doc.data();
                        if (!_isBakra(data)) return false;
                        if (_isExpired(data)) return false;
                        if (!_isAnimalMatch(data)) return false;

                        final city = (data['city'] ?? data['location'] ?? '').toString().trim().toLowerCase();
                        if (_selectedCity != 'all' && !city.contains(_selectedCity)) {
                          return false;
                        }

                        final price = _toDouble(data['price']);
                        final minPrice = _toDouble(_priceMinController.text);
                        final maxPrice = _toDouble(_priceMaxController.text);
                        if (minPrice > 0 && price < minPrice) return false;
                        if (maxPrice > 0 && price > maxPrice) return false;

                        final minWeight = _toDouble(_weightMinController.text);
                        final weight = _toDouble(data['weight']);
                        if (minWeight > 0 && weight > 0 && weight < minWeight) return false;

                        if (_query.isNotEmpty) {
                          final text =
                              '${data['product'] ?? ''} ${data['description'] ?? ''} ${data['city'] ?? ''}'
                                  .toString()
                                  .toLowerCase();
                          if (!text.contains(_query)) return false;
                        }

                        return true;
                      }).toList(growable: false);

                      if (filtered.isEmpty) {
                        return const Center(
                          child: Text(
                            'کوئی جانور دستیاب نہیں\nNo animals found',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.primaryText),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final data = doc.data();
                          final title = (data['product'] ?? 'جانور').toString();
                          final city = (data['city'] ?? data['location'] ?? '').toString();
                          final priceValue = (data['price'] is num)
                              ? data['price'] as num
                              : num.tryParse((data['price'] ?? '').toString()) ?? 0;
                          final weight = (data['weight'] ?? '').toString().trim();
                          final phone = (data['sellerPhone'] ?? data['contactPhone'] ?? '').toString().trim();
                          final whatsapp = (data['sellerWhatsapp'] ?? phone).toString().trim();
                          final images = (data['imageUrls'] as List?) ?? (data['images'] as List?) ?? const <dynamic>[];

                          return GestureDetector(
                            onTap: () async {
                              await _analytics.logEvent(
                                event: 'bakra_listing_open',
                                data: <String, dynamic>{'listingId': doc.id},
                              );
                              if (!context.mounted) return;
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => BakraMandiDetailScreen(
                                    listingId: doc.id,
                                    initialData: data,
                                  ),
                                ),
                              );
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.cardSurface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                    child: SizedBox(
                                      height: 180,
                                      width: double.infinity,
                                      child: images.isNotEmpty
                                          ? Image.network(
                                              images.first.toString(),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _imagePlaceholder(),
                                            )
                                          : _imagePlaceholder(),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          title,
                                          style: const TextStyle(
                                            color: AppColors.primaryText,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '💰 قیمت: Rs. ${priceValue.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: AppColors.primaryText,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '📍 شہر: ${city.isEmpty ? 'نامعلوم' : city}',
                                          style: const TextStyle(color: AppColors.secondaryText),
                                        ),
                                        if (weight.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            '⚖ وزن: $weight',
                                            style: const TextStyle(color: AppColors.secondaryText),
                                          ),
                                        ],
                                        const SizedBox(height: 10),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: () => _callSeller(context, phone, doc.id),
                                                icon: const Icon(Icons.phone_rounded, size: 17),
                                                label: const Text('📞 کال کریں'),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: () => _openWhatsapp(context, whatsapp, doc.id),
                                                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                                                label: const Text('💬 واٹس ایپ'),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      color: AppColors.softGlassTintedSurface,
      alignment: Alignment.center,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, color: AppColors.secondaryText, size: 26),
          SizedBox(height: 6),
          Text('تصویر دستیاب نہیں', style: TextStyle(color: AppColors.secondaryText)),
        ],
      ),
    );
  }
}

class _FilterInput extends StatelessWidget {
  const _FilterInput({
    required this.icon,
    required this.label,
    required this.child,
  });

  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.accentGold),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(color: AppColors.secondaryText, fontSize: 12),
              ),
            ],
          ),
          child,
        ],
      ),
    );
  }
}
