import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

enum _CnicSide { front, back }
enum _AccountType { buyer, seller, driver }

extension _AccountTypeX on _AccountType {
  String get label {
    switch (this) {
      case _AccountType.buyer:
        return 'Buyer';
      case _AccountType.seller:
        return 'Seller';
      case _AccountType.driver:
        return 'Driver';
    }
  }

  IconData get icon {
    switch (this) {
      case _AccountType.buyer:
        return Icons.shopping_bag_rounded;
      case _AccountType.seller:
        return Icons.storefront_rounded;
      case _AccountType.driver:
        return Icons.local_shipping_rounded;
    }
  }

  String get verificationLabel {
    switch (this) {
      case _AccountType.buyer:
        return 'Business Photo (Optional)';
      case _AccountType.seller:
        return 'Shop Photo (Required)';
      case _AccountType.driver:
        return 'Vehicle Photo (Required)';
    }
  }
}

class MasterSignUpScreen extends StatefulWidget {
  const MasterSignUpScreen({super.key});

  @override
  State<MasterSignUpScreen> createState() => _MasterSignUpScreenState();
}

class _MasterSignUpScreenState extends State<MasterSignUpScreen>
    with SingleTickerProviderStateMixin {
  static const Color _deepGreen = Color(0xFF1B5E20);
  static const Color _gold = Color(0xFFFFD700);
  static const int _totalSteps = 5;

  static const Map<String, List<String>> _districtsByProvince = <String, List<String>>{
    'Punjab': <String>[
      'Lahore',
      'Kasur',
      'Nankana Sahib',
      'Sheikhupura',
      'Faisalabad',
      'Chiniot',
      'Toba Tek Singh',
      'Jhang',
      'Sargodha',
      'Khushab',
      'Mianwali',
      'Bhakkar',
      'Gujranwala',
      'Gujrat',
      'Mandi Bahauddin',
      'Sialkot',
      'Narowal',
      'Rawalpindi',
      'Attock',
      'Jhelum',
      'Chakwal',
      'Multan',
      'Khanewal',
      'Lodhran',
      'Vehari',
      'Sahiwal',
      'Okara',
      'Pakpattan',
      'Bahawalpur',
      'Bahawalnagar',
      'Rahim Yar Khan',
      'Dera Ghazi Khan',
      'Layyah',
      'Muzaffargarh',
      'Rajanpur',
      'Taunsa',
    ],
    'Sindh': <String>[
      'Karachi Central',
      'Karachi East',
      'Karachi South',
      'Karachi West',
      'Korangi',
      'Kemari',
      'Malir',
      'Hyderabad',
      'Jamshoro',
      'Tando Allahyar',
      'Tando Muhammad Khan',
      'Matiari',
      'Badin',
      'Thatta',
      'Sujawal',
      'Dadu',
      'Larkana',
      'Qambar Shahdadkot',
      'Shikarpur',
      'Jacobabad',
      'Kashmore',
      'Sukkur',
      'Khairpur',
      'Ghotki',
      'Naushehro Feroze',
      'Shaheed Benazirabad',
      'Sanghar',
      'Mirpurkhas',
      'Umerkot',
      'Tharparkar',
    ],
    'Khyber Pakhtunkhwa': <String>[
      'Peshawar',
      'Mardan',
      'Swabi',
      'Nowshera',
      'Charsadda',
      'Kohat',
      'Hangu',
      'Karak',
      'Bannu',
      'Lakki Marwat',
      'Dera Ismail Khan',
      'Tank',
      'Abbottabad',
      'Haripur',
      'Mansehra',
      'Battagram',
      'Tor Ghar',
      'Kolai Palas Kohistan',
      'Lower Kohistan',
      'Upper Kohistan',
      'Swat',
      'Shangla',
      'Buner',
      'Malakand',
      'Lower Dir',
      'Upper Dir',
      'Chitral Lower',
      'Chitral Upper',
      'Bajaur',
      'Mohmand',
      'Khyber',
      'Orakzai',
      'Kurram',
      'North Waziristan',
      'South Waziristan Lower',
      'South Waziristan Upper',
      'Bannu Frontier Region',
      'Peshawar Frontier Region',
    ],
    'Balochistan': <String>[
      'Quetta',
      'Pishin',
      'Killa Abdullah',
      'Chaman',
      'Nushki',
      'Chagai',
      'Kharan',
      'Washuk',
      'Khuzdar',
      'Awaran',
      'Lasbela',
      'Hub',
      'Gwadar',
      'Kech',
      'Panjgur',
      'Mastung',
      'Kalat',
      'Surab',
      'Sibi',
      'Harnai',
      'Ziarat',
      'Duki',
      'Loralai',
      'Musakhel',
      'Barkhan',
      'Kohlu',
      'Dera Bugti',
      'Nasirabad',
      'Jafarabad',
      'Sohbatpur',
      'Usta Muhammad',
      'Jhal Magsi',
      'Kachhi',
      'Sherani',
      'Zhob',
      'Killa Saifullah',
    ],
    'Azad Jammu & Kashmir': <String>[
      'Muzaffarabad',
      'Hattian Bala',
      'Neelum',
      'Mirpur',
      'Bhimber',
      'Kotli',
      'Poonch',
      'Bagh',
      'Haveli',
      'Sudhnoti',
    ],
    'Gilgit Baltistan': <String>[
      'Gilgit',
      'Skardu',
      'Shigar',
      'Kharmang',
      'Ghanche',
      'Khaplu',
      'Nagar',
      'Hunza',
      'Ghizer',
      'Gupis Yasin',
      'Diamer',
      'Astore',
      'Darel',
      'Tangir',
    ],
    'Islamabad Capital Territory': <String>['Islamabad'],
  };

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _cnicController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _gpsController = TextEditingController();
  final TextEditingController _shopVehicleNameController = TextEditingController();

  late final AnimationController _laserController;

  XFile? _cnicFront;
  XFile? _cnicBack;
  XFile? _businessProof;

  bool _isScanning = false;
  bool _isSubmitting = false;
  int _currentStep = 0;

  _AccountType _selectedAccountType = _AccountType.buyer;
  String? _selectedGender;
  String? _selectedProvince;
  String? _selectedDistrict;

  @override
  void initState() {
    super.initState();
    _laserController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _laserController.dispose();
    _nameController.dispose();
    _cnicController.dispose();
    _dobController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _gpsController.dispose();
    _shopVehicleNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          _buildMeshBackground(),
          SafeArea(
            child: Form(
              key: _formKey,
              child: Column(
                children: <Widget>[
                  _buildHeader(),
                  _StepProgressBar(
                    currentStep: _currentStep,
                    totalSteps: _totalSteps,
                    deepGreen: _deepGreen,
                    gold: _gold,
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: _buildCurrentStep(),
                      ),
                    ),
                  ),
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMeshBackground() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _deepGreen,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            _deepGreen,
            const Color(0xFF184D1A),
            const Color(0xFF123F15),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -80,
            left: -80,
            child: _meshBlob(const Size(250, 250), _gold.withValues(alpha: 0.08)),
          ),
          Positioned(
            right: -60,
            top: 120,
            child: _meshBlob(const Size(210, 210), Colors.white.withValues(alpha: 0.05)),
          ),
          Positioned(
            left: 40,
            bottom: -90,
            child: _meshBlob(const Size(280, 280), _gold.withValues(alpha: 0.06)),
          ),
        ],
      ),
    );
  }

  Widget _meshBlob(Size size, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          ),
          Expanded(
            child: Text(
              'Master Sign Up',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildStepOne();
      case 1:
        return _buildStepTwo();
      case 2:
        return _buildStepThree();
      case 3:
        return _buildStepFour();
      case 4:
      default:
        return _buildStepFive();
    }
  }

  Widget _buildBottomControls() {
    final bool isLast = _currentStep == _totalSteps - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        border: Border(
          top: BorderSide(color: _gold.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _isSubmitting ? null : _previousStep,
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _gold.withValues(alpha: 0.7)),
                  foregroundColor: _gold,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('Back', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[Color(0xFFFFB300), Color(0xFFFFD700)],
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: (_isSubmitting || _isScanning)
                    ? null
                    : isLast
                        ? _register
                        : _nextStep,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: _deepGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        isLast ? 'Register' : 'Continue',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepOne() {
    return KeyedSubtree(
      key: const ValueKey<String>('step1'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _VerseTopBanner(),
          const SizedBox(height: 14),
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step 1: AI Smart Scan (CNIC)',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _buildCnicSlotCard(
                        title: 'Front Side',
                        file: _cnicFront,
                        side: _CnicSide.front,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCnicSlotCard(
                        title: 'Back Side',
                        file: _cnicBack,
                        side: _CnicSide.back,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _isScanning
                      ? 'AI reading CNIC...'
                      : 'Front image se Name/CNIC auto-fill ho jayega.',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCnicSlotCard({
    required String title,
    required XFile? file,
    required _CnicSide side,
  }) {
    final bool showLaser = side == _CnicSide.front && _isScanning && file != null;

    return _DottedGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _gold,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          AspectRatio(
            aspectRatio: 1.55,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.white.withValues(alpha: 0.08),
                child: file == null
                    ? Center(
                        child: Icon(
                          Icons.badge_rounded,
                          size: 42,
                          color: Colors.white.withValues(alpha: 0.65),
                        ),
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Image.file(File(file.path), fit: BoxFit.cover),
                          if (showLaser)
                            _ScanningLaserOverlay(
                              animation: _laserController,
                              glowColor: _gold,
                            ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _miniActionButton(
                  icon: Icons.camera_alt_rounded,
                  text: 'Camera',
                  onTap: () => _pickCnicImage(side, ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniActionButton(
                  icon: Icons.photo_library_rounded,
                  text: 'Gallery',
                  onTap: () => _pickCnicImage(side, ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniActionButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      onPressed: _isScanning ? null : onTap,
      icon: Icon(icon, size: 16),
      label: Text(
        text,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _gold,
        side: BorderSide(color: _gold.withValues(alpha: 0.65)),
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildStepTwo() {
    return KeyedSubtree(
      key: const ValueKey<String>('step2'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _VerseTopBanner(),
          const SizedBox(height: 14),
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step 2: Account Type',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _AccountType.values.map(((_AccountType type) {
                    final bool selected = _selectedAccountType == type;
                    return InkWell(
                      onTap: () => setState(() => _selectedAccountType = type),
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: 150,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: selected
                              ? _gold.withValues(alpha: 0.15)
                              : Colors.white.withValues(alpha: 0.06),
                          border: Border.all(
                            color: selected
                                ? _gold
                                : _gold.withValues(alpha: 0.45),
                            width: selected ? 1.6 : 1,
                          ),
                          boxShadow: selected
                              ? <BoxShadow>[
                                  BoxShadow(
                                    color: _gold.withValues(alpha: 0.28),
                                    blurRadius: 14,
                                    offset: const Offset(0, 5),
                                  ),
                                ]
                              : <BoxShadow>[],
                        ),
                        child: Column(
                          children: <Widget>[
                            Icon(type.icon, size: 32, color: selected ? _gold : Colors.white),
                            const SizedBox(height: 8),
                            Text(
                              type.label,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  })).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepThree() {
    return KeyedSubtree(
      key: const ValueKey<String>('step3'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _VerseTopBanner(),
          const SizedBox(height: 14),
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step 3: User Data',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_rounded,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _cnicController,
                  label: 'CNIC Number',
                  icon: Icons.badge_rounded,
                  hint: 'xxxxx-xxxxxxx-x',
                ),
                const SizedBox(height: 12),
                _buildDateField(),
                const SizedBox(height: 12),
                _buildGenderField(),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _phoneController,
                  label: 'Phone Number',
                  icon: Icons.phone_rounded,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  icon: Icons.lock_rounded,
                  obscureText: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFour() {
    final List<String> provinces = _districtsByProvince.keys.toList()..sort();
    final List<String> districts = _selectedProvince == null
        ? <String>[]
        : (_districtsByProvince[_selectedProvince] ?? <String>[]);

    return KeyedSubtree(
      key: const ValueKey<String>('step4'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _VerseTopBanner(),
          const SizedBox(height: 14),
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step 4: Geographic Mapping',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSearchPickerField(
                  label: 'Province',
                  value: _selectedProvince,
                  icon: Icons.map_rounded,
                  onTap: () async {
                    final String? selected = await _showSearchPicker(
                      title: 'Select Province',
                      options: provinces,
                      initialValue: _selectedProvince,
                    );
                    if (!mounted || selected == null) return;
                    setState(() {
                      _selectedProvince = selected;
                      _selectedDistrict = null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildSearchPickerField(
                  label: 'District',
                  value: _selectedDistrict,
                  icon: Icons.location_city_rounded,
                  onTap: _selectedProvince == null
                      ? null
                      : () async {
                          final String? selected = await _showSearchPicker(
                            title: 'Select District',
                            options: districts,
                            initialValue: _selectedDistrict,
                          );
                          if (!mounted || selected == null) return;
                          setState(() => _selectedDistrict = selected);
                        },
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _gpsController,
                  label: 'Detected Coordinates',
                  icon: Icons.gps_fixed_rounded,
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _detectLocation,
                        icon: const Icon(Icons.my_location_rounded),
                        label: Text(
                          'Detect My Location',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: BorderSide(color: _gold.withValues(alpha: 0.72)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _openMapPin,
                        icon: const Icon(Icons.pin_drop_rounded),
                        label: Text(
                          'Open Map Pin',
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _gold,
                          side: BorderSide(color: _gold.withValues(alpha: 0.72)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepFive() {
    final bool proofRequired = _selectedAccountType != _AccountType.buyer;

    return KeyedSubtree(
      key: const ValueKey<String>('step5'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const _VerseTopBanner(),
          const SizedBox(height: 14),
          _GlassPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Step 5: Business Verification',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  controller: _shopVehicleNameController,
                  label: _selectedAccountType == _AccountType.driver
                      ? 'Vehicle / Fleet Name'
                      : 'Shop / Business Name',
                  icon: _selectedAccountType == _AccountType.driver
                      ? Icons.directions_car_rounded
                      : Icons.store_rounded,
                ),
                const SizedBox(height: 12),
                _DottedGlassCard(
                  child: Column(
                    children: <Widget>[
                      Text(
                        _selectedAccountType.verificationLabel,
                        style: GoogleFonts.poppins(
                          color: _gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      AspectRatio(
                        aspectRatio: 1.8,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            color: Colors.white.withValues(alpha: 0.08),
                            child: _businessProof == null
                                ? Center(
                                    child: Icon(
                                      Icons.camera_alt_rounded,
                                      size: 36,
                                      color: Colors.white.withValues(alpha: 0.65),
                                    ),
                                  )
                                : Image.file(File(_businessProof!.path), fit: BoxFit.cover),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: _miniActionButton(
                              icon: Icons.camera_rounded,
                              text: 'Camera',
                              onTap: () => _pickBusinessProof(ImageSource.camera),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _miniActionButton(
                              icon: Icons.photo_library_rounded,
                              text: 'Gallery',
                              onTap: () => _pickBusinessProof(ImageSource.gallery),
                            ),
                          ),
                        ],
                      ),
                      if (proofRequired)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Seller/Driver ke liye upload required hai.',
                            style: GoogleFonts.poppins(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 11,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildSummaryCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _gold.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Final Review',
            style: GoogleFonts.poppins(
              color: _gold,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _summaryRow('Account Type', _selectedAccountType.label),
          _summaryRow('Name', _nameController.text.trim().isEmpty ? '-' : _nameController.text.trim()),
          _summaryRow('CNIC', _cnicController.text.trim().isEmpty ? '-' : _cnicController.text.trim()),
          _summaryRow('Date of Birth', _dobController.text.trim().isEmpty ? '-' : _dobController.text.trim()),
          _summaryRow('Gender', _selectedGender ?? '-'),
          _summaryRow('Province', _selectedProvince ?? '-'),
          _summaryRow('District', _selectedDistrict ?? '-'),
          _summaryRow(
            'Verification Image',
            _businessProof == null ? 'Not uploaded' : 'Uploaded',
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 4,
            child: Text(
              '$key:',
              style: GoogleFonts.poppins(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return TextFormField(
      controller: _dobController,
      readOnly: true,
      onTap: _pickDob,
      style: GoogleFonts.poppins(color: Colors.white),
      decoration: _fieldDecoration(
        label: 'Date of Birth',
        icon: Icons.calendar_month_rounded,
      ),
    );
  }

  Widget _buildGenderField() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedGender,
      dropdownColor: const Color(0xFF215F28),
      style: GoogleFonts.poppins(color: Colors.white),
      decoration: _fieldDecoration(label: 'Gender', icon: Icons.wc_rounded),
      items: const <String>['Male', 'Female', 'Other']
          .map(
            (String gender) => DropdownMenuItem<String>(
              value: gender,
              child: Text(gender, style: GoogleFonts.poppins()),
            ),
          )
          .toList(),
      onChanged: (String? value) => setState(() => _selectedGender = value),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    bool obscureText = false,
    bool readOnly = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: Colors.white),
      decoration: _fieldDecoration(label: label, icon: icon, hint: hint),
    );
  }

  Widget _buildSearchPickerField({
    required String label,
    required String? value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final bool enabled = onTap != null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _fieldDecoration(label: label, icon: icon),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                value ?? (enabled ? 'Tap to select' : 'Select province first'),
                style: GoogleFonts.poppins(
                  color: value == null ? Colors.white70 : Colors.white,
                ),
              ),
            ),
            Icon(Icons.search_rounded, color: _gold),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: Colors.white54),
      labelStyle: GoogleFonts.poppins(color: Colors.white70, fontWeight: FontWeight.w500),
      prefixIcon: Icon(icon, color: _gold),
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.09),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.5)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: _gold.withValues(alpha: 0.5)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
    );
  }

  Future<void> _pickCnicImage(_CnicSide side, ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 2300,
    );
    if (picked == null) return;

    setState(() {
      if (side == _CnicSide.front) {
        _cnicFront = picked;
      } else {
        _cnicBack = picked;
      }
    });

    if (side == _CnicSide.front) {
      await _extractCnicWithGemini(picked);
    }
  }

  Future<void> _pickBusinessProof(ImageSource source) async {
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2200,
    );
    if (picked == null) return;
    setState(() => _businessProof = picked);
  }

  Future<void> _extractCnicWithGemini(XFile frontImage) async {
    setState(() => _isScanning = true);
    _laserController.repeat();

    try {
      final String apiKey = const String.fromEnvironment('GEMINI_API_KEY').trim();
      if (apiKey.isEmpty) {
        _showSnack('Tasveer saaf nahi hai, dobara koshish karein.');
        return;
      }

      final Uint8List bytes = await frontImage.readAsBytes();
      final String mimeType = _guessMimeType(frontImage.path);

      final GenerativeModel model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: apiKey,
      );

      const String prompt =
          'Extract Name and CNIC number from this Pakistani CNIC. '
          'Format: JSON {name: "string", cnic: "string"}. '
          'If DOB and gender are visible, include them as dob and gender fields too.';

      final Content request = Content.multi(<Part>[
        TextPart(prompt),
        DataPart(mimeType, bytes),
      ]);

      final GenerateContentResponse response = await model.generateContent(<Content>[request]);
      final String rawText = response.text?.trim() ?? '';
      final Map<String, dynamic>? data = _parseGeminiJson(rawText);

      if (data == null) {
        _showSnack('Tasveer saaf nahi hai, dobara koshish karein.');
        return;
      }

      final String name = (data['name'] ?? '').toString().trim();
      final String cnic = (data['cnic'] ?? '').toString().trim();
      final String dob = (data['dob'] ?? data['dateOfBirth'] ?? '').toString().trim();
      final String gender = (data['gender'] ?? '').toString().trim();

      if (name.isNotEmpty) {
        _nameController.text = name;
      }
      if (cnic.isNotEmpty) {
        _cnicController.text = cnic;
      }
      if (dob.isNotEmpty) {
        _dobController.text = dob;
      }
      if (gender.isNotEmpty) {
        final String normalized = _normalizeGender(gender);
        if (normalized.isNotEmpty) {
          _selectedGender = normalized;
        }
      }

      if (!mounted) return;
      setState(() {});
      _showSnack('Shabash! Data fetch ho gaya.');
    } catch (_) {
      _showSnack('Tasveer saaf nahi hai, dobara koshish karein.');
    } finally {
      _laserController.stop();
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  String _normalizeGender(String value) {
    final String lower = value.toLowerCase();
    if (lower.contains('male')) return 'Male';
    if (lower.contains('female')) return 'Female';
    if (lower.contains('other')) return 'Other';
    return '';
  }

  Map<String, dynamic>? _parseGeminiJson(String text) {
    if (text.isEmpty) return null;

    String candidate = text;
    final RegExp fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
    final Match? fencedMatch = fenced.firstMatch(text);
    if (fencedMatch != null) {
      candidate = fencedMatch.group(1)?.trim() ?? text;
    }

    final int start = candidate.indexOf('{');
    final int end = candidate.lastIndexOf('}');
    if (start >= 0 && end > start) {
      candidate = candidate.substring(start, end + 1);
    }

    try {
      final Object? decoded = jsonDecode(candidate);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((Object? key, Object? value) => MapEntry(key.toString(), value));
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String _guessMimeType(String path) {
    final String lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _pickDob() async {
    final DateTime now = DateTime.now();
    final DateTime initial = DateTime(now.year - 23, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 15),
    );
    if (picked == null) return;
    final String formatted =
        '${picked.day.toString().padLeft(2, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.year}';
    _dobController.text = formatted;
    if (mounted) setState(() {});
  }

  Future<void> _detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Location service band hai. On karein.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showSnack('Location permission nahi mili.');
        return;
      }

      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );

      _gpsController.text = '${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}';
      if (mounted) setState(() {});
    } catch (_) {
      _showSnack('Location detect nahi ho saki.');
    }
  }

  Future<void> _openMapPin() async {
    String query;
    if (_gpsController.text.trim().isNotEmpty) {
      query = _gpsController.text.trim();
    } else {
      final String province = _selectedProvince ?? 'Pakistan';
      final String district = _selectedDistrict ?? '';
      query = '$district $province Pakistan'.trim();
    }

    final Uri uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );

    final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _showSnack('Google Maps open nahi ho saka.');
    }
  }

  Future<String?> _showSearchPicker({
    required String title,
    required List<String> options,
    required String? initialValue,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        String query = '';
        final List<String> sorted = List<String>.from(options)..sort();

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final List<String> filtered = sorted
                .where((String item) => item.toLowerCase().contains(query.toLowerCase()))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              decoration: BoxDecoration(
                color: const Color(0xFF144517),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: _gold.withValues(alpha: 0.45)),
              ),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: 48,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white54,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      onChanged: (String value) => setModalState(() => query = value),
                      style: GoogleFonts.poppins(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: GoogleFonts.poppins(color: Colors.white60),
                        prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.08),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: _gold.withValues(alpha: 0.45)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _gold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No match found',
                              style: GoogleFonts.poppins(color: Colors.white70),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                            itemBuilder: (BuildContext context, int index) {
                              final String item = filtered[index];
                              final bool selected = item == initialValue;
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: selected
                                        ? _gold
                                        : _gold.withValues(alpha: 0.18),
                                  ),
                                ),
                                tileColor: Colors.white.withValues(alpha: selected ? 0.14 : 0.05),
                                title: Text(
                                  item,
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                                  ),
                                ),
                                onTap: () => Navigator.of(context).pop(item),
                              );
                            },
                            separatorBuilder: (_, _) => const SizedBox(height: 8),
                            itemCount: filtered.length,
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _nextStep() {
    if (!_validateStep(_currentStep)) return;
    if (_currentStep < _totalSteps - 1) {
      setState(() => _currentStep += 1);
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    }
  }

  bool _validateStep(int step) {
    switch (step) {
      case 0:
        if (_cnicFront == null || _cnicBack == null) {
          _showSnack('Front aur Back dono upload karein.');
          return false;
        }
        return true;
      case 1:
        return true;
      case 2:
        if (_nameController.text.trim().isEmpty ||
            _cnicController.text.trim().isEmpty ||
            _dobController.text.trim().isEmpty ||
            (_selectedGender ?? '').isEmpty ||
            _phoneController.text.trim().length < 10 ||
            _passwordController.text.trim().length < 6) {
          _showSnack('Step 3 ke tamam fields complete karein.');
          return false;
        }
        return true;
      case 3:
        if (_selectedProvince == null || _selectedDistrict == null) {
          _showSnack('Province aur District select karein.');
          return false;
        }
        return true;
      case 4:
        final bool proofRequired = _selectedAccountType != _AccountType.buyer;
        if (proofRequired && _businessProof == null) {
          _showSnack('Seller/Driver ke liye photo upload zaroori hai.');
          return false;
        }
        return true;
      default:
        return true;
    }
  }

  Future<void> _register() async {
    if (!_validateStep(4)) return;

    setState(() => _isSubmitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 900));

    if (!mounted) return;
    setState(() => _isSubmitting = false);
    _showSnack('Registration complete ho gayi.');
    Navigator.of(context).pop();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.black87,
        content: Text(
          message,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
      ),
    );
  }
}

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
    required this.deepGreen,
    required this.gold,
  });

  final int currentStep;
  final int totalSteps;
  final Color deepGreen;
  final Color gold;

  @override
  Widget build(BuildContext context) {
    final double progress = totalSteps <= 1
        ? 0
        : (currentStep / (totalSteps - 1)).clamp(0, 1).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
      child: SizedBox(
        height: 52,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double lineLeft = 18;
            final double lineRight = constraints.maxWidth - 18;
            final double lineWidth = math.max(0, lineRight - lineLeft);

            return Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Positioned(
                  left: lineLeft,
                  right: 18,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned(
                  left: lineLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: lineWidth * progress,
                    height: 5,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: <Color>[Color(0xFFFFE082), Color(0xFFFFD700)],
                      ),
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: gold.withValues(alpha: 0.45),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List<Widget>.generate(totalSteps, (int index) {
                    final bool completed = index <= currentStep;
                    final bool active = index == currentStep;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      width: active ? 36 : 32,
                      height: active ? 36 : 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: completed
                            ? const LinearGradient(
                                colors: <Color>[Color(0xFFFFF59D), Color(0xFFFFD700)],
                              )
                            : null,
                        color: completed ? null : deepGreen.withValues(alpha: 0.78),
                        border: Border.all(color: gold, width: active ? 2 : 1.3),
                        boxShadow: completed
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: gold.withValues(alpha: active ? 0.65 : 0.38),
                                  blurRadius: active ? 16 : 10,
                                  spreadRadius: active ? 0.6 : 0,
                                ),
                              ]
                            : <BoxShadow>[],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${index + 1}',
                        style: GoogleFonts.poppins(
                          color: completed ? deepGreen : Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  const _GlassPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.45)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DottedGlassCard extends StatelessWidget {
  const _DottedGlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: const Color(0xFFFFD700).withValues(alpha: 0.8),
            strokeWidth: 1.2,
            dashLength: 7,
            gapLength: 5,
            radius: 16,
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({
    required this.color,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
    required this.radius,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final RRect rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    final Path path = Path()..addRRect(rrect);
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = math.min(distance + dashLength, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dashLength + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return color != oldDelegate.color ||
        strokeWidth != oldDelegate.strokeWidth ||
        dashLength != oldDelegate.dashLength ||
        gapLength != oldDelegate.gapLength ||
        radius != oldDelegate.radius;
  }
}

class _ScanningLaserOverlay extends StatelessWidget {
  const _ScanningLaserOverlay({
    required this.animation,
    required this.glowColor,
  });

  final Animation<double> animation;
  final Color glowColor;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (BuildContext context, Widget? child) {
        final double y = animation.value;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.02),
                    ],
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment(0, y * 2 - 1),
              child: Container(
                height: 2.5,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      glowColor.withValues(alpha: 0.0),
                      glowColor,
                      glowColor.withValues(alpha: 0.0),
                    ],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: glowColor.withValues(alpha: 0.7),
                      blurRadius: 10,
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VerseTopBanner extends StatelessWidget {
  const _VerseTopBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.75)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'وَتَرْزُقُ مَن تَشَاءُ بِغَيْرِ حِسَابٍ',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoNastaliqUrdu(
              color: const Color(0xFFFFD700),
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Aur tu jisay chahay be-hisab rizq deta hai',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
