import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/location_display_helper.dart';
import '../../core/pakistan_location_service.dart';
import '../../core/seasonal_bakra_mandi_config.dart';
import '../../services/analytics_service.dart';
import '../../services/marketplace_service.dart';
import '../../theme/app_colors.dart';

class BakraMandiPostScreen extends StatefulWidget {
  const BakraMandiPostScreen({super.key, required this.userData});

  final Map<String, dynamic> userData;

  @override
  State<BakraMandiPostScreen> createState() => _BakraMandiPostScreenState();
}

class _BakraMandiPostScreenState extends State<BakraMandiPostScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final MarketplaceService _marketplaceService = MarketplaceService();
  final AnalyticsService _analytics = AnalyticsService();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();

  static const List<String> _animalTypes = <String>['بکرے', 'گائے', 'دنبہ', 'اونٹ'];

  String _selectedAnimal = _animalTypes.first;
  List<XFile> _images = <XFile>[];
  XFile? _video;
  bool _isSubmitting = false;
  bool _wantsFeatured = false;
  bool _wantsUrgent = false;
  bool _wantsDealer = false;
  String? _selectedProvince;
  String? _selectedDistrict;
  String? _selectedTehsil;
  String? _selectedCity;

  @override
  void initState() {
    super.initState();
    _phoneController.text =
        (widget.userData['phone'] ?? widget.userData['phoneNumber'] ?? '')
            .toString()
            .trim();
    _whatsAppController.text = _phoneController.text;
    PakistanLocationService.instance.loadIfNeeded().then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _phoneController.dispose();
    _whatsAppController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _images = picked.take(6).toList(growable: false);
    });
  }

  Future<void> _pickVideo() async {
    final picked = await _picker.pickVideo(source: ImageSource.gallery);
    if (!mounted || picked == null) return;
    setState(() => _video = picked);
  }

  Future<void> _submit() async {
    if (!SeasonalBakraMandiConfig.isEnabled() ||
        !SeasonalBakraMandiConfig.allowPosting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('موسمی بکرا منڈی پوسٹنگ بند ہے')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if ((_selectedProvince ?? '').trim().isEmpty ||
        (_selectedDistrict ?? '').trim().isEmpty ||
        (_selectedTehsil ?? '').trim().isEmpty ||
        (_selectedCity ?? '').trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Province, district, tehsil aur city منتخب کریں / Select province, district, tehsil, and city',
          ),
        ),
      );
      return;
    }
    if (_images.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('کم از کم ایک تصویر لازمی ہے')),
      );
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Login required / لاگ اِن ضروری ہے')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final String province = (_selectedProvince ?? '').trim();
    final String district = (_selectedDistrict ?? '').trim();
    final String tehsil = (_selectedTehsil ?? '').trim();
    final String city = (_selectedCity ?? '').trim();
    final String locationUr = <String>[
      LocationDisplayHelper.urduFor(city),
      LocationDisplayHelper.urduFor(tehsil),
      LocationDisplayHelper.urduFor(district),
      LocationDisplayHelper.urduFor(province),
    ].where((String e) => e.trim().isNotEmpty).join('، ');
    final String locationDisplay = LocationDisplayHelper.locationDisplayFromData(
      <String, dynamic>{
        'province': province,
        'district': district,
        'tehsil': tehsil,
        'city': city,
      },
    );

    final now = DateTime.now().toUtc();
    final expiresAt = now.add(SeasonalBakraMandiConfig.listingLifetime);
    final listingData = <String, dynamic>{
      'sellerId': user.uid,
      'sellerName':
          (widget.userData['name'] ?? widget.userData['fullName'] ?? '')
              .toString(),
      'mandiType': 'LIVESTOCK',
      'category': 'bakra_mandi',
        'categoryLabel': 'بکرا منڈی / Bakra Mandi',
      'subcategory': 'bakra_classified',
      'subcategoryLabel': 'Bakra Classified',
      'product': _titleController.text.trim(),
      'quantity': 1,
      'unit': 'Per Head',
      'price': double.tryParse(_priceController.text.trim()) ?? 0,
      'description': _descriptionController.text.trim(),
      'country': 'Pakistan',
      'province': province,
      'district': district,
      'tehsil': tehsil,
      'city': city,
      'village': city,
      'location': '$city, $tehsil, $district',
      'locationUr': locationUr,
      'locationDisplay': locationDisplay,
      'locationNodes': <String, dynamic>{
        'province': <String, String>{
          'name_en': province,
          'name_ur': LocationDisplayHelper.urduFor(province),
        },
        'district': <String, String>{
          'name_en': district,
          'name_ur': LocationDisplayHelper.urduFor(district),
        },
        'tehsil': <String, String>{
          'name_en': tehsil,
          'name_ur': LocationDisplayHelper.urduFor(tehsil),
        },
        'city': <String, String>{
          'name_en': city,
          'name_ur': LocationDisplayHelper.urduFor(city),
        },
      },
      'locationData': <String, dynamic>{
        'country': 'Pakistan',
        'province': province,
        'district': district,
        'tehsil': tehsil,
        'city': city,
        'village': city,
        'provinceObj': <String, String>{
          'name_en': province,
          'name_ur': LocationDisplayHelper.urduFor(province),
        },
        'districtObj': <String, String>{
          'name_en': district,
          'name_ur': LocationDisplayHelper.urduFor(district),
        },
        'tehsilObj': <String, String>{
          'name_en': tehsil,
          'name_ur': LocationDisplayHelper.urduFor(tehsil),
        },
        'cityObj': <String, String>{
          'name_en': city,
          'name_ur': LocationDisplayHelper.urduFor(city),
        },
      },
      'saleType': 'fixed',
      'featured': false,
      'featuredAuction': false,
      'priorityScore': 'normal',
      'isSeasonalQurbani': true,
      'seasonalTags': const <String>['qurbani', 'bakra_mandi'],
      'directContactEnabled': true,
      'sellerPhone': _phoneController.text.trim(),
      'sellerWhatsapp': _whatsAppController.text.trim(),
      'animalType': _selectedAnimal,
      'breed': _breedController.text.trim(),
      'age': _ageController.text.trim(),
      'weight': _weightController.text.trim(),
      'bakraExpiresAt': expiresAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'archiveAfter': expiresAt.toIso8601String(),
      'isArchived': false,
      'status': 'pending_review',
      'isVerifiedSource': true,

      // Manual/admin flags only (no payment flow in V1).
      'isFeatured': false,
      'isUrgent': false,
      'isDealer': false,

      // Seller interest hooks for manual follow-up.
      'featuredHookRequested': _wantsFeatured,
      'urgentHookRequested': _wantsUrgent,
      'dealerHookRequested': _wantsDealer,
      'featuredHookPriceDisplay': 'PKR 300',
      'urgentHookPriceDisplay': 'PKR 200',
      'dealerHookPriceDisplay': 'PKR 3000',
    };

    final mediaFiles = <String, dynamic>{
      'images': _images,
      'video': _video,
      'audioPath': '',
    };

    try {
      final status = await _marketplaceService.createListingSecure(
        listingData,
        mediaFiles,
      );
      await _analytics.logEvent(
        event: 'bakra_mandi_post_created',
        data: <String, dynamic>{
          'category': 'bakra_mandi',
          'status': status,
          'featuredHookRequested': _wantsFeatured,
          'urgentHookRequested': _wantsUrgent,
          'dealerHookRequested': _wantsDealer,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('بکرا منڈی پوسٹ جمع ہوگئی۔ اسٹیٹس: $status')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('فی الحال پوسٹ جمع نہیں ہو سکی')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'بکرا منڈی پوسٹ',
          style: TextStyle(color: AppColors.primaryText),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _sectionTitle('ضروری معلومات'),
            const SizedBox(height: 8),
            _animalTypeSelector(),
            const SizedBox(height: 10),
            _field(_titleController, 'جانور کا نام/عنوان', required: true),
            _field(
              _priceController,
              'قیمت (روپے)',
              keyboardType: TextInputType.number,
              required: true,
            ),
            Builder(
              builder: (BuildContext context) {
                final PakistanLocationService locationService =
                    PakistanLocationService.instance;
                final List<BilingualLocationOption> provinces =
                  locationService.provinceOptions;
                final List<BilingualLocationOption> districts =
                  _selectedProvince == null
                  ? const <BilingualLocationOption>[]
                  : locationService.districtOptions(_selectedProvince!);
                final List<BilingualLocationOption> tehsils =
                  _selectedDistrict == null
                  ? const <BilingualLocationOption>[]
                  : locationService.tehsilOptions(_selectedDistrict!);
                final List<BilingualLocationOption> cities =
                    (_selectedDistrict == null || _selectedTehsil == null)
                  ? const <BilingualLocationOption>[]
                  : locationService.cityOptionsLocalized(
                        district: _selectedDistrict!,
                        tehsil: _selectedTehsil!,
                      );

                return Column(
                  children: <Widget>[
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedProvince,
                      dropdownColor: AppColors.cardSurface,
                      style: const TextStyle(color: AppColors.primaryText),
                      decoration: const InputDecoration(
                        labelText: 'Province / صوبہ',
                      ),
                      items: provinces
                          .map(
                            (BilingualLocationOption item) => DropdownMenuItem<String>(
                              value: item.labelEn,
                              child: Text(item.bilingualLabel),
                            ),
                          )
                          .toList(),
                      onChanged: (String? value) {
                        setState(() {
                          _selectedProvince = value;
                          _selectedDistrict = null;
                          _selectedTehsil = null;
                          _selectedCity = null;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedDistrict,
                      dropdownColor: AppColors.cardSurface,
                      style: const TextStyle(color: AppColors.primaryText),
                      decoration: const InputDecoration(
                        labelText: 'District / ضلع',
                      ),
                      items: districts
                          .map(
                            (BilingualLocationOption item) => DropdownMenuItem<String>(
                              value: item.labelEn,
                              child: Text(item.bilingualLabel),
                            ),
                          )
                          .toList(),
                      onChanged: _selectedProvince == null
                          ? null
                          : (String? value) {
                              setState(() {
                                _selectedDistrict = value;
                                _selectedTehsil = null;
                                _selectedCity = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedTehsil,
                      dropdownColor: AppColors.cardSurface,
                      style: const TextStyle(color: AppColors.primaryText),
                      decoration: const InputDecoration(
                        labelText: 'Tehsil / تحصیل',
                      ),
                      items: tehsils
                          .map(
                            (BilingualLocationOption item) => DropdownMenuItem<String>(
                              value: item.labelEn,
                              child: Text(item.bilingualLabel),
                            ),
                          )
                          .toList(),
                      onChanged: _selectedDistrict == null
                          ? null
                          : (String? value) {
                              setState(() {
                                _selectedTehsil = value;
                                _selectedCity = null;
                              });
                            },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _selectedCity,
                      dropdownColor: AppColors.cardSurface,
                      style: const TextStyle(color: AppColors.primaryText),
                      decoration: const InputDecoration(
                        labelText: 'City / شہر',
                      ),
                      items: cities
                          .map(
                            (BilingualLocationOption item) => DropdownMenuItem<String>(
                              value: item.labelEn,
                              child: Text(item.bilingualLabel),
                            ),
                          )
                          .toList(),
                      onChanged: _selectedTehsil == null
                          ? null
                          : (String? value) {
                              setState(() => _selectedCity = value);
                            },
                    ),
                  ],
                );
              },
            ),
            _field(
              _phoneController,
              'فون نمبر',
              keyboardType: TextInputType.phone,
              required: true,
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text('تصاویر منتخب کریں (${_images.length}/6)'),
            ),
            const SizedBox(height: 10),
            _sectionTitle('نمایاں اختیارات (اختیاری)'),
            const SizedBox(height: 8),
            _hookTile(
              label: 'نمایاں لسٹنگ / Featured Listing',
              price: 'PKR 300',
              note: 'زیادہ نمایاں جگہ',
              selected: _wantsFeatured,
              onTap: () {
                setState(() => _wantsFeatured = !_wantsFeatured);
                if (_wantsFeatured) {
                  _analytics.logEvent(event: 'bakra_mandi_featured_interest');
                }
              },
            ),
            const SizedBox(height: 8),
            _hookTile(
              label: 'فوری فروخت / Urgent Sale',
              price: 'PKR 200',
              note: 'فوری بیج اور ترجیحی جگہ',
              selected: _wantsUrgent,
              onTap: () {
                setState(() => _wantsUrgent = !_wantsUrgent);
                if (_wantsUrgent) {
                  _analytics.logEvent(event: 'bakra_mandi_urgent_interest');
                }
              },
            ),
            const SizedBox(height: 8),
            _hookTile(
              label: 'ڈیلر پلان / Dealer Plan',
              price: 'PKR 3000',
              note: 'ڈیلر بیج اور اضافی ترجیح',
              selected: _wantsDealer,
              onTap: () {
                setState(() => _wantsDealer = !_wantsDealer);
                if (_wantsDealer) {
                  _analytics.logEvent(event: 'bakra_mandi_dealer_interest');
                }
              },
            ),
            const SizedBox(height: 10),
            _sectionTitle('اختیاری معلومات'),
            const SizedBox(height: 8),
            _field(_breedController, 'نسل'),
            _field(_ageController, 'عمر (مہینے)'),
            _field(_weightController, 'وزن (کلوگرام)'),
            _field(
              _whatsAppController,
              'واٹس ایپ نمبر',
              keyboardType: TextInputType.phone,
            ),
            _field(_descriptionController, 'مزید تفصیل', maxLines: 4),
            OutlinedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.videocam_outlined),
              label: Text(_video == null ? 'ویڈیو شامل کریں (اختیاری)' : 'ویڈیو منتخب ہو گئی'),
            ),
            if (_video != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _video!.name,
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ),
            if (_images.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 74,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  separatorBuilder: (context, index) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(_images[index].path),
                        width: 74,
                        height: 74,
                        fit: BoxFit.cover,
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Text(
                '⚠ ادائیگی سے پہلے خریدار کو جانور دکھائیں',
                style: TextStyle(color: AppColors.secondaryText, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_rounded),
              label: Text(_isSubmitting ? 'جمع ہو رہی ہے...' : 'پوسٹ جمع کریں'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primaryText,
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    );
  }

  Widget _animalTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _animalTypes.map((type) {
          final bool selected = _selectedAnimal == type;
          return ChoiceChip(
            label: Text(type),
            selected: selected,
            onSelected: (selectedValue) => setState(() => _selectedAnimal = type),
          );
        }).toList(growable: false),
      ),
    );
  }

  Widget _hookTile({
    required String label,
    required String price,
    required String note,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: _isSubmitting ? null : onTap,
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.accentGold : AppColors.divider,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.accentGold : AppColors.secondaryText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$label - $price',
                    style: const TextStyle(
                      color: AppColors.primaryText,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note,
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

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(color: AppColors.primaryText),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.secondaryText),
          helperText: required ? 'لازمی' : 'اختیاری',
          filled: true,
          fillColor: AppColors.cardSurface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
        ),
        validator: (value) {
          if (required && (value ?? '').trim().isEmpty) {
            return 'یہ فیلڈ لازمی ہے';
          }
          return null;
        },
      ),
    );
  }
}
