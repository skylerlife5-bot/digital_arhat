import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import 'export_inquiry_model.dart';
import 'models/export_buyer_profile.dart';

class ExportInquiryForm extends StatefulWidget {
  const ExportInquiryForm({
    super.key,
    required this.buyer,
    this.initialCommodity,
  });

  final ExportBuyerProfile buyer;
  final String? initialCommodity;

  @override
  State<ExportInquiryForm> createState() => _ExportInquiryFormState();
}

class _ExportInquiryFormState extends State<ExportInquiryForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commodityController = TextEditingController();
  final _quantityController = TextEditingController();
  final _messageController = TextEditingController();
  final _nameFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _commodityFocus = FocusNode();
  final _quantityFocus = FocusNode();
  final _messageFocus = FocusNode();

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _commodityController.text = widget.initialCommodity?.trim().isNotEmpty == true
        ? widget.initialCommodity!.trim()
        : (widget.buyer.commodities.isNotEmpty ? widget.buyer.commodities.first : '');
    _messageController.text =
        'Assalam o Alaikum, we can supply 100 tons ${_commodityController.text.isEmpty ? 'commodity' : _commodityController.text} from Punjab with export-ready packaging and documentation.';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commodityController.dispose();
    _quantityController.dispose();
    _messageController.dispose();
    _nameFocus.dispose();
    _phoneFocus.dispose();
    _commodityFocus.dispose();
    _quantityFocus.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  String _fallbackMessage(String commodity) {
    final normalizedCommodity = commodity.trim().isEmpty
        ? 'commodity'
        : commodity.trim();
    return 'Assalam o Alaikum, I am interested in supplying $normalizedCommodity. Please share details.';
  }

  Future<void> _submitInquiry() async {
    if (_isSubmitting) return;
    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    FocusScope.of(context).unfocus();

    setState(() => _isSubmitting = true);

    final commodity = _commodityController.text.trim();
    final message = _messageController.text.trim().isEmpty
        ? _fallbackMessage(commodity)
        : _messageController.text.trim();

    final inquiry = ExportInquiry(
      buyerId: widget.buyer.id,
      commodity: commodity,
      quantity: _quantityController.text.trim(),
      userName: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      message: message,
      timestamp: DateTime.now(),
    );

    try {
      await FirebaseFirestore.instance.collection('export_inquiries').add(
        <String, dynamic>{
          ...inquiry.toMap(),
          'timestamp': FieldValue.serverTimestamp(),
          'buyerCompanyName': widget.buyer.companyName,
          'buyerCountry': widget.buyer.country,
          'buyerCity': widget.buyer.city,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on SocketException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send inquiry. Please try again.'),
        ),
      );
    } on FirebaseException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send inquiry. Please try again.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send inquiry. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  String? _nameValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return 'Name is required';
    if (normalized.length < 2) return 'Name must be at least 2 characters';
    return null;
  }

  String? _phoneValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^\d+$').hasMatch(normalized)) {
      return 'Phone number must contain digits only';
    }
    if (normalized.length < 10) return 'Phone number must be at least 10 digits';
    return null;
  }

  String? _commodityValidator(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Commodity is required';
    return null;
  }

  String? _quantityValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return 'Quantity is required';
    final parsed = num.tryParse(normalized);
    if (parsed == null) return 'Quantity must be numeric';
    if (parsed <= 0) return 'Quantity must be greater than 0';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Send Inquiry',
          style: TextStyle(
            color: AppColors.primaryText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.cardSurface.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.softGlassBorder),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Only verified buyers are shown here',
                        style: TextStyle(
                          color: AppColors.primaryText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Your contact will only be shared with this verified buyer',
                        style: TextStyle(
                          color: AppColors.secondaryText,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _InputLabel('Your Name'),
                const SizedBox(height: 6),
                _buildInput(
                  controller: _nameController,
                  hintText: 'Enter your name',
                  validator: _nameValidator,
                  focusNode: _nameFocus,
                  nextFocus: _phoneFocus,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _InputLabel('Phone Number'),
                const SizedBox(height: 6),
                _buildInput(
                  controller: _phoneController,
                  hintText: '03xx-xxxxxxx',
                  validator: _phoneValidator,
                  keyboardType: TextInputType.number,
                  focusNode: _phoneFocus,
                  nextFocus: _commodityFocus,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _InputLabel('Commodity'),
                const SizedBox(height: 6),
                _buildInput(
                  controller: _commodityController,
                  hintText: 'Commodity name',
                  validator: _commodityValidator,
                  focusNode: _commodityFocus,
                  nextFocus: _quantityFocus,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _InputLabel('Quantity (tons)'),
                const SizedBox(height: 6),
                _buildInput(
                  controller: _quantityController,
                  hintText: 'e.g. 100',
                  validator: _quantityValidator,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  focusNode: _quantityFocus,
                  nextFocus: _messageFocus,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _InputLabel('Message (optional)'),
                const SizedBox(height: 6),
                _buildInput(
                  controller: _messageController,
                  hintText:
                      'Assalam o Alaikum, we can supply 100 tons wheat from Punjab...',
                  focusNode: _messageFocus,
                  minLines: 4,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentGold,
                      foregroundColor: AppColors.background,
                      disabledBackgroundColor:
                          AppColors.accentGold.withValues(alpha: 0.45),
                      disabledForegroundColor:
                          AppColors.background.withValues(alpha: 0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: _isSubmitting ? null : _submitInquiry,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.background,
                              ),
                            ),
                          )
                        : const Text('Submit Inquiry'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInput({
    required TextEditingController controller,
    required String hintText,
    FormFieldValidator<String>? validator,
    FocusNode? focusNode,
    FocusNode? nextFocus,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      minLines: minLines,
      maxLines: maxLines,
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        }
      },
      style: const TextStyle(
        color: AppColors.primaryText,
        fontSize: 13,
      ),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: AppColors.secondaryText,
          fontSize: 12,
        ),
        filled: true,
        fillColor: AppColors.cardSurface.withValues(alpha: 0.94),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.softGlassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.softGlassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accentGold),
        ),
      ),
    );
  }
}

class _InputLabel extends StatelessWidget {
  const _InputLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.primaryText,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
