import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/location_display_helper.dart';
import '../../core/pakistan_location_service.dart';
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

  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;
  String _animalType = 'all';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _animalType = (widget.initialAnimalType ?? 'all').trim().toLowerCase();
    _query = (widget.initialQuery ?? '').trim().toLowerCase();
    PakistanLocationService.instance.loadIfNeeded().then((_) {
      if (!mounted) return;
      setState(() {});
    });
    Future<void>.microtask(() {
      _analytics.logEvent(
        event: 'bakra_mandi_list_open',
        data: <String, dynamic>{
          'animalType': _animalType,
          'hasQuery': _query.isNotEmpty,
        },
      );
    });
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

  bool _isArchived(Map<String, dynamic> data) {
    final status = (data['status'] ?? data['listingStatus'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final archivedFlag = data['isArchived'] == true;
    return archivedFlag || status == 'archived' || status == 'expired_archived';
  }

  bool _isFlagOn(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = (value ?? '').toString().trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }

  int _rankingTier(Map<String, dynamic> data) {
    final isFeatured = _isFlagOn(data, 'isFeatured') || _isFlagOn(data, 'featured');
    final isUrgent = _isFlagOn(data, 'isUrgent');

    if (isFeatured && isUrgent) return 0;
    if (isFeatured) return 1;
    if (isUrgent) return 2;
    return 3;
  }

  DateTime _createdAtOf(Map<String, dynamic> data) {
    return _readDate(data['createdAt']) ??
        _readDate(data['timestamp']) ??
        _readDate(data['updatedAt']) ??
        DateTime.fromMillisecondsSinceEpoch(0);
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

  String _seasonalAssetFor(Map<String, dynamic> data) {
    final text =
        '${data['animalType'] ?? ''} ${data['product'] ?? ''} ${data['subcategoryLabel'] ?? ''} ${data['description'] ?? ''}';
    return _seasonalAssetFromText(text);
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
      event: 'bakra_mandi_call_tap',
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
      event: 'bakra_mandi_whatsapp_tap',
      data: <String, dynamic>{'listingId': listingId},
    );
    final uri = Uri.parse('https://wa.me/$digits');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = SeasonalBakraMandiConfig.isEnabled();
    final PakistanLocationService locationService =
      PakistanLocationService.instance;
    final List<String> provinceOptions = locationService.provinces;
    final List<String> districtOptions = _selectedProvince == null
      ? const <String>[]
      : locationService.districtsForProvince(_selectedProvince!);
    final List<String> tehsilOptions = _selectedDistrict == null
      ? const <String>[]
      : locationService.tehsilsForDistrict(_selectedDistrict!);
    final List<String> cityOptions =
      (_selectedDistrict == null || _selectedTehsil == null)
      ? const <String>[]
      : locationService.cityOptions(
        district: _selectedDistrict!,
        tehsil: _selectedTehsil!,
        );

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
                              label: 'صوبہ / Province',
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: _selectedProvince,
                                  dropdownColor: AppColors.cardSurface,
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...provinceOptions.map(
                                      (String p) => DropdownMenuItem<String?>(
                                        value: p,
                                        child: Text(
                                          LocationDisplayHelper.bilingualLabel(p),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedProvince = value;
                                      _selectedDistrict = null;
                                      _selectedTehsil = null;
                                      _selectedCity = null;
                                    });
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
                                onChanged: (_) => setState(() {}),
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
                                onChanged: (_) => setState(() {}),
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
                                onChanged: (_) => setState(() {}),
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
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.location_city_outlined,
                              label: 'ضلع / District',
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: _selectedDistrict,
                                  dropdownColor: AppColors.cardSurface,
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...districtOptions.map(
                                      (String d) => DropdownMenuItem<String?>(
                                        value: d,
                                        child: Text(
                                          LocationDisplayHelper.bilingualLabel(d),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: _selectedProvince == null
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedDistrict = value;
                                            _selectedTehsil = null;
                                            _selectedCity = null;
                                          });
                                        },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _FilterInput(
                              icon: Icons.alt_route_rounded,
                              label: 'تحصیل / Tehsil',
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  isExpanded: true,
                                  value: _selectedTehsil,
                                  dropdownColor: AppColors.cardSurface,
                                  items: <DropdownMenuItem<String?>>[
                                    const DropdownMenuItem<String?>(
                                      value: null,
                                      child: Text('All / سب'),
                                    ),
                                    ...tehsilOptions.map(
                                      (String t) => DropdownMenuItem<String?>(
                                        value: t,
                                        child: Text(
                                          LocationDisplayHelper.bilingualLabel(t),
                                        ),
                                      ),
                                    ),
                                  ],
                                  onChanged: _selectedDistrict == null
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _selectedTehsil = value;
                                            _selectedCity = null;
                                          });
                                        },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _FilterInput(
                        icon: Icons.pin_drop_outlined,
                        label: 'شہر / City',
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            isExpanded: true,
                            value: _selectedCity,
                            dropdownColor: AppColors.cardSurface,
                            items: <DropdownMenuItem<String?>>[
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All / سب'),
                              ),
                              ...cityOptions.map(
                                (String c) => DropdownMenuItem<String?>(
                                  value: c,
                                  child: Text(
                                    LocationDisplayHelper.bilingualLabel(c),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: _selectedTehsil == null
                                ? null
                                : (value) {
                                    setState(() => _selectedCity = value);
                                  },
                          ),
                        ),
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
                        if (_isArchived(data)) return false;
                        if (_isExpired(data)) return false;
                        if (!_isAnimalMatch(data)) return false;

                        final String locationHaystack =
                            LocationDisplayHelper.searchTextFromData(data);

                        if ((_selectedProvince ?? '').trim().isNotEmpty &&
                            !locationHaystack.contains(
                              (_selectedProvince ?? '').toLowerCase(),
                            )) {
                          return false;
                        }
                        if ((_selectedDistrict ?? '').trim().isNotEmpty &&
                            !locationHaystack.contains(
                              (_selectedDistrict ?? '').toLowerCase(),
                            )) {
                          return false;
                        }
                        if ((_selectedTehsil ?? '').trim().isNotEmpty &&
                            !locationHaystack.contains(
                              (_selectedTehsil ?? '').toLowerCase(),
                            )) {
                          return false;
                        }
                        if ((_selectedCity ?? '').trim().isNotEmpty &&
                            !locationHaystack.contains(
                              (_selectedCity ?? '').toLowerCase(),
                            )) {
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
                      }).toList(growable: true)
                        ..sort((a, b) {
                          final aData = a.data();
                          final bData = b.data();
                          final tierCompare = _rankingTier(aData).compareTo(_rankingTier(bData));
                          if (tierCompare != 0) return tierCompare;
                          return _createdAtOf(bData).compareTo(_createdAtOf(aData));
                        });

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
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = filtered[index];
                          final data = doc.data();
                          final title = (data['product'] ?? 'جانور').toString();
                          final animalType = (data['animalType'] ?? '').toString().trim();
                            final String locationDisplay =
                              LocationDisplayHelper.locationDisplayFromData(data);
                          final priceValue = (data['price'] is num)
                              ? data['price'] as num
                              : num.tryParse((data['price'] ?? '').toString()) ?? 0;
                          final weight = (data['weight'] ?? '').toString().trim();
                          final isFeatured = _isFlagOn(data, 'isFeatured') || _isFlagOn(data, 'featured');
                          final isUrgent = _isFlagOn(data, 'isUrgent');
                          final isDealer = _isFlagOn(data, 'isDealer');
                          final phone = (data['sellerPhone'] ?? data['contactPhone'] ?? '').toString().trim();
                          final whatsapp = (data['sellerWhatsapp'] ?? phone).toString().trim();
                          final images = (data['imageUrls'] as List?) ?? (data['images'] as List?) ?? const <dynamic>[];
                          final fallbackAsset = _seasonalAssetFor(data);

                          return GestureDetector(
                            onTap: () {
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
                                              errorBuilder: (context, error, stackTrace) =>
                                                  _imagePlaceholder(
                                                    assetPath: fallbackAsset,
                                                    label: title,
                                                  ),
                                            )
                                          : _imagePlaceholder(
                                              assetPath: fallbackAsset,
                                              label: title,
                                            ),
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
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: [
                                            if (isFeatured)
                                              _hookBadge('Featured Listing', const Color(0xFFE8C766)),
                                            if (isUrgent)
                                              _hookBadge('Urgent Sale', const Color(0xFFFF8A65)),
                                            if (isDealer)
                                              _hookBadge('Dealer Plan', const Color(0xFF81C784)),
                                          ],
                                        ),
                                        if (animalType.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            animalType,
                                            style: const TextStyle(
                                              color: AppColors.secondaryText,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
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
                                          '📍 ${locationDisplay.isEmpty ? 'نامعلوم' : locationDisplay}',
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
              size: 54,
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
                  Colors.black.withValues(alpha: 0.08),
                  Colors.black.withValues(alpha: 0.52),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'قربانی جانور',
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
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
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
