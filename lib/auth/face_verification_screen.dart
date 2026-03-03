import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../routes.dart';

class FaceVerificationScreen extends StatefulWidget {
  const FaceVerificationScreen({super.key});

  @override
  State<FaceVerificationScreen> createState() => _FaceVerificationScreenState();
}

class _FaceVerificationScreenState extends State<FaceVerificationScreen> {
  CameraController? _controller;
  bool _isProcessing = false;
  String _instruction = 'Apna chehra daire ke andar rakhein';

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('Camera Error: $error');
    }
  }

  Future<void> _takeSelfie() async {
    if (_isProcessing || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _isProcessing = true;
      _instruction = 'Tasdeeq ho rahi hai, barah-e-karam intezar karein...';
    });

    try {
      await _controller!.takePicture();
      await Future<void>.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          Routes.verificationPending,
          (route) => false,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _instruction = 'Masla aya. Dobara koshish karein.';
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFFD700)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      body: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: _controller!.value.aspectRatio,
              child: CameraPreview(_controller!),
            ),
          ),
          _buildOverlay(),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 30),
                _buildHeader(),
                const Spacer(),
                _buildInstructionBox(),
                const SizedBox(height: 30),
                _buildCaptureButton(),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          'FACE VERIFICATION',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
            letterSpacing: 3,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 5),
        const Text(
          'Chehre Ki Tasdeeq',
          style: TextStyle(
            color: Color(0xFFFFD700),
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.2, end: 0),
      ],
    );
  }

  Widget _buildInstructionBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 40),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: const Color(0xFFFFD700).withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        _instruction,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white, fontSize: 17),
      ),
    ).animate().fadeIn();
  }

  Widget _buildCaptureButton() {
    return GestureDetector(
      onTap: _takeSelfie,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: 90,
            width: 90,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFFD700).withValues(alpha: 0.5),
                width: 2,
              ),
            ),
          ).animate(onPlay: (controller) => controller.repeat()).scale(
                begin: const Offset(1, 1),
                end: const Offset(1.1, 1.1),
                duration: 1.seconds,
                curve: Curves.easeInOut,
              ),
          Container(
            height: 70,
            width: 70,
            decoration: const BoxDecoration(
              color: Color(0xFFFFD700),
              shape: BoxShape.circle,
            ),
            child: _isProcessing
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(
                      color: Color(0xFF011A0A),
                      strokeWidth: 3,
                    ),
                  )
                : const Icon(Icons.camera_alt, color: Color(0xFF011A0A), size: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        Colors.black.withValues(alpha: 0.8),
        BlendMode.srcOut,
      ),
      child: Stack(
        children: [
          Container(color: Colors.transparent),
          Align(
            alignment: Alignment.center,
            child: Container(
              margin: const EdgeInsets.only(bottom: 50),
              height: 320,
              width: 260,
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.all(Radius.elliptical(130, 160)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}