import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../routes.dart';

class LivenessDetectionScreen extends StatefulWidget {
  const LivenessDetectionScreen({super.key});

  @override
  State<LivenessDetectionScreen> createState() => _LivenessDetectionScreenState();
}

class _LivenessDetectionScreenState extends State<LivenessDetectionScreen> {
  CameraController? _controller;
  bool _isBusy = false;
  bool _hasBlinked = false;
  String _instruction = "براہ کر�& اپ� �R آ� کھ�Rں جھپکائ�Rں (Blink your eyes)";
  
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, 
      enableTracking: true,
    ),
  );

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  void _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    _controller = CameraController(
      frontCamera, 
      ResolutionPreset.medium, 
      enableAudio: false,
      imageFormatGroup: Platform.isIOS 
          ? ImageFormatGroup.bgra8888 
          : ImageFormatGroup.yuv420,
    );

    await _controller?.initialize();
    
    _controller?.startImageStream((image) {
      if (_isBusy || _hasBlinked) return;
      _processImage(image);
    });
    
    if (mounted) setState(() {});
  }

  Future<void> _processImage(CameraImage image) async {
    _isBusy = true;
    
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      final cameras = await availableCameras();
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front);
      
      final imageRotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation) 
          ?? InputImageRotation.rotation0deg;
      
      final inputImageFormat = InputImageFormatValue.fromRawValue(image.format.raw) 
          ?? InputImageFormat.yuv420;

      final inputImageData = InputImageMetadata(
        size: imageSize,
        rotation: imageRotation,
        format: inputImageFormat,
        bytesPerRow: image.planes[0].bytesPerRow,
      );

      final inputImage = InputImage.fromBytes(bytes: bytes, metadata: inputImageData);
      final faces = await _faceDetector.processImage(inputImage);

      for (Face face in faces) {
        if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
          // Blink logic: if eyes are more than 70% closed
          if (face.leftEyeOpenProbability! < 0.3 && face.rightEyeOpenProbability! < 0.3) {
            
            if (mounted) {
              setState(() {
                _hasBlinked = true;
                _instruction = "تصد�R� �&ک�&� ہ�� گئ�R! �S&";
              });
            }
            
            // �S& Fix: Guarding the async gap
            await Future.delayed(const Duration(seconds: 2));
            if (!mounted) return; // BuildContext check after await

            await _controller?.stopImageStream();
            if (!mounted) return; // BuildContext check after stopImageStream

            Navigator.pushReplacementNamed(context, Routes.setPassword);
          }
        }
      }
    } catch (e) {
      debugPrint("AI Processing Error: $e");
    } finally {
      _isBusy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF011A0A), 
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFFD700)))
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF011A0A),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_instruction, 
              style: const TextStyle(
                color: Color(0xFFFFD700), 
                fontSize: 22, 
                fontFamily: 'Jameel Noori'
              ),
              textAlign: TextAlign.center,
            ).animate().fadeIn(),
            const SizedBox(height: 40),
            
            Center(
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _hasBlinked ? Colors.green : const Color(0xFFFFD700), 
                    width: 5
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    )
                  ],
                ),
                child: ClipOval(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),
            ),
            
            const SizedBox(height: 50),
            if (_hasBlinked) 
              const Icon(Icons.check_circle, color: Colors.green, size: 80)
                  .animate()
                  .scale(duration: 400.ms)
                  .then()
                  .shake(),
            
            const SizedBox(height: 20),
            const Text(
              "Security Check: System is verifying your identity",
              style: TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _faceDetector.close();
    super.dispose();
  }
}
