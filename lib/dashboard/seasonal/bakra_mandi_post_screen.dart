import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _whatsAppController = TextEditingController();

  static const List<String> _animalTypes = <String>['بکرے', 'گائے', 'دنبہ', 'اونٹ'];

  String _selectedAnimal = _animalTypes.first;
  List<XFile> _images = <XFile>[];
  XFile? _video;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _phoneController.text =
        (widget.userData['phone'] ?? widget.userData['phoneNumber'] ?? '')
            .toString()
            .trim();
    _whatsAppController.text = _phoneController.text;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _breedController.dispose();
    _ageController.dispose();
    _weightController.dispose();
    _priceController.dispose();
    _cityController.dispose();
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
    if (!SeasonalBakraMandiConfig.isEnabled ||
        !SeasonalBakraMandiConfig.allowPosting) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('موسمی بکرا منڈی پوسٹنگ بند ہے')),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
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
      'province': '',
      'district': '',
      'tehsil': '',
      'city': _cityController.text.trim(),
      'village': _cityController.text.trim(),
      'location': _cityController.text.trim(),
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
      'archiveAfter': expiresAt.toIso8601String(),
      'status': 'pending_review',
      'isVerifiedSource': true,
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
        event: 'bakra_post_created',
        data: <String, dynamic>{
          'category': 'bakra_mandi',
          'status': status,
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
              'قیمت (PKR)',
              keyboardType: TextInputType.number,
              required: true,
            ),
            _field(_cityController, 'شہر', required: true),
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
            _sectionTitle('اختیاری معلومات'),
            const SizedBox(height: 8),
            _field(_breedController, 'نسل (Breed)'),
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
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
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
            onSelected: (_) => setState(() => _selectedAnimal = type),
          );
        }).toList(growable: false),
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
