import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../config/promotion_payment_config.dart';
import '../../../theme/app_colors.dart';

class FeaturedListingPaymentData {
  FeaturedListingPaymentData({
    required this.paymentMethod,
    required this.paymentRef,
    required this.proofImage,
  });

  final String paymentMethod;
  final String paymentRef;
  final XFile? proofImage;

  bool get isComplete =>
      paymentMethod.trim().isNotEmpty &&
      paymentRef.trim().isNotEmpty &&
      proofImage != null;
}

class FeaturedListingPaymentModal extends StatefulWidget {
  const FeaturedListingPaymentModal({super.key});

  @override
  State<FeaturedListingPaymentModal> createState() =>
      _FeaturedListingPaymentModalState();
}

class _FeaturedListingPaymentModalState
    extends State<FeaturedListingPaymentModal> {
  static const Color _gold = AppColors.accentGold;
  static const Color _darkGreen = AppColors.background;

  final TextEditingController _paymentRefController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _selectedPaymentMethod = 'bank_transfer';
  XFile? _proofImage;
  bool _isImageUploading = false;

  final List<Map<String, String>> _paymentMethods = const [
    {
      'id': 'bank_transfer',
      'label': 'Bank Transfer / بینک منتقلی',
    },
    {
      'id': 'mobile_payment',
      'label': 'Mobile Payment (JazzCash/Easypaisa) / موبائل ادائیگی',
    },
    {
      'id': 'cheque',
      'label': 'Cheque / چیک',
    },
  ];

  @override
  void dispose() {
    _paymentRefController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      setState(() => _isImageUploading = true);
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2000,
        maxHeight: 2000,
      );
      if (image != null) {
        setState(() => _proofImage = image);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Image pick failed: ${e.toString()}'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isImageUploading = false);
      }
    }
  }

  bool _validateForm() {
    if (_selectedPaymentMethod.trim().isEmpty) {
      _showError('Payment method is required / ادائیگی کا طریقہ منتخب کریں');
      return false;
    }
    if (_paymentRefController.text.trim().length < 3) {
      _showError(
        'Payment reference must be at least 3 characters / ادائیگی حوالہ کم از کم 3 حروف ہونا چاہیے',
      );
      return false;
    }
    if (_proofImage == null) {
      _showError(
        'Payment proof screenshot is required / ادائیگی کے ثبوت کی تصویر لازمی ہے',
      );
      return false;
    }
    return true;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _submitPayment() {
    if (!_validateForm()) {
      return;
    }

    final data = FeaturedListingPaymentData(
      paymentMethod: _selectedPaymentMethod,
      paymentRef: _paymentRefController.text.trim(),
      proofImage: _proofImage,
    );

    Navigator.pop(context, data);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _darkGreen,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Featured Listing Payment',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'نمایاں لسٹنگ کی ادائیگی',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 20),

              // Fee Display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  border: Border.all(color: _gold, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Featured Listing Fee',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rs ${PromotionPaymentConfig.featuredListingFee}',
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${PromotionPaymentConfig.featuredListingFee} روپے',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Bank Details Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transfer To / منتقل کریں',
                      style: TextStyle(
                        color: _gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildBankDetail('Bank', PromotionPaymentConfig.bankName),
                    _buildBankDetail('Account Title', PromotionPaymentConfig.bankAccountTitle),
                    _buildBankDetail('Account #', PromotionPaymentConfig.accountNumber),
                    _buildBankDetail('IBAN', PromotionPaymentConfig.iban),
                    _buildBankDetail('Branch', PromotionPaymentConfig.branchName),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Payment Method Dropdown
              const Text(
                'Payment Method / ادائیگی کا طریقہ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: DropdownButton<String>(
                  value: _selectedPaymentMethod,
                  isExpanded: true,
                  underline: const SizedBox(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                  dropdownColor: AppColors.cardSurface,
                  items: _paymentMethods.map((method) {
                    return DropdownMenuItem(
                      value: method['id'],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(method['label'] ?? ''),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedPaymentMethod = value);
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Payment Reference Input
              const Text(
                'Payment Reference / ادائیگی حوالہ',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _paymentRefController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Transaction ID or Reference / لین دین ID',
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                  ),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _gold, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Proof Upload
              const Text(
                'Payment Proof / ادائیگی کا ثبوت',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_proofImage == null)
                GestureDetector(
                  onTap: _isImageUploading ? null : _pickImage,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      border: Border.all(
                        color: _gold.withValues(alpha: 0.4),
                        width: 2,
                        style: BorderStyle.solid,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_upload_outlined,
                          color: _gold.withValues(alpha: 0.7),
                          size: 32,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isImageUploading
                              ? 'Uploading... / اپ لوڈ ہو رہا ہے'
                              : 'Tap to upload proof screenshot / ثبوت اپ لوڈ کریں',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _gold.withValues(alpha: 0.8),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Proof Uploaded',
                              style: TextStyle(
                                color: Colors.green,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _proofImage!.name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.green.withValues(alpha: 0.7),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.green),
                        onPressed: () {
                          setState(() => _proofImage = null);
                        },
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: Colors.transparent,
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Cancel / منسوخ',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isImageUploading ? null : _submitPayment,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: _gold,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        disabledBackgroundColor:
                            _gold.withValues(alpha: 0.3),
                      ),
                      child: Text(
                        'Confirm Payment / تصدیق کریں',
                        style: TextStyle(
                          color: _darkGreen,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBankDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: _gold,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 16, color: _gold),
            onPressed: () {
              // In a real app, copy to clipboard
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
